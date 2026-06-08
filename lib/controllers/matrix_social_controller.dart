import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart' as drift;

import '../database/app_database.dart';
import '../models/route_point.dart';
import '../online/matrix/matrix_client_service.dart';
import '../online/matrix/matrix_encryption_helper.dart';
import '../online/matrix/matrix_sync_service.dart';
import '../repositories/app_repositories.dart';
import '../repositories/friend_repository.dart';
import '../repositories/profile_repository.dart';

class MatrixSocialController extends ChangeNotifier {
  MatrixSocialController({
    required AppRepositories repositories,
    required MatrixClientService clientService,
    MatrixSyncService? syncService,
  }) : _repositories = repositories,
       _clientService = clientService,
       _syncService = syncService;

  final AppRepositories _repositories;
  final MatrixClientService _clientService;
  final MatrixSyncService? _syncService;

  bool _busy = false;
  String? _message;

  bool get busy => _busy;
  String? get message => _message;

  Client get _client => _clientService.client;

  void _setBusy(bool val, {String? msg}) {
    _busy = val;
    _message = msg;
    notifyListeners();
  }

  String _profileIdForMatrix(String matrixUserId) {
    return 'matrix-${matrixUserId.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')}';
  }

  Future<void> _ensureProfileExists(String matrixUserId) async {
    final profileId = _profileIdForMatrix(matrixUserId);
    final existing = await (_repositories.profiles.database.select(
      _repositories.profiles.database.profiles,
    )..where((row) => row.id.equals(profileId))).getSingleOrNull();

    if (existing == null) {
      await _repositories.profiles.createOrUpdateLocalProfile(
        LocalProfileInput(
          id: profileId,
          matrixUserId: matrixUserId,
          displayName: matrixUserId,
          visibility: 'friends',
        ),
      );
    }
  }

  void _requireEncryptedRoom(String roomId) {
    if (!_clientService.isRoomEncrypted(roomId)) {
      throw Exception('Private Matrix sharing requires an encrypted room.');
    }
  }

  // ─── Friend Requests ────────────────────────────────────────────────────────

  Future<void> sendFriendRequest(String targetMatrixUserId) async {
    if (_client.userID == null) {
      throw Exception('Matrix is not connected.');
    }
    _setBusy(true);
    try {
      final myUserId = _client.userID!;
      if (targetMatrixUserId == myUserId) {
        throw Exception('Cannot send a friend request to yourself.');
      }

      // 1. Create DM room
      final roomId = await _client.createRoom(
        isDirect: true,
        invite: [targetMatrixUserId],
        visibility: Visibility.private,
      );

      // 2. Local profiles and request upsert
      final myProfileId = _profileIdForMatrix(myUserId);
      final targetProfileId = _profileIdForMatrix(targetMatrixUserId);

      await _ensureProfileExists(myUserId);
      await _ensureProfileExists(targetMatrixUserId);

      final requestId = 'friend-$myProfileId-$targetProfileId';
      await _repositories.friends.upsertRequest(
        CachedFriendRequestInput(
          id: requestId,
          fromProfileId: myProfileId,
          toProfileId: targetProfileId,
          state: 'pending',
          roomId: roomId,
        ),
      );

      // 3. Queue outgoing event to the room
      final payload = {
        'id': requestId,
        'fromMatrixId': myUserId,
        'toMatrixId': targetMatrixUserId,
        'roomId': roomId,
      };

      await _repositories.sync.enqueueOutgoingEvent(
        id: requestId,
        eventType: 'org.ralroads.friend.request.v1',
        entityId: requestId,
        payloadJson: jsonEncode(payload),
        roomId: roomId,
      );

      _syncService?.processOutbox();

      _setBusy(false, msg: 'Friend request sent.');
    } catch (e) {
      _setBusy(false, msg: 'Failed to send request: $e');
      rethrow;
    }
  }

  Future<void> acceptFriendRequest(FriendRequest request) async {
    if (_client.userID == null) {
      throw Exception('Matrix is not connected.');
    }
    _setBusy(true);
    try {
      final myUserId = _client.userID!;
      final roomId = request.roomId;
      if (roomId == null) {
        throw Exception('Invalid request room.');
      }

      // 1. Join room
      await _client.joinRoom(roomId);

      // 2. Resolve target matrix user ID from request profile IDs
      final fromProfile =
          await (_repositories.profiles.database.select(
                _repositories.profiles.database.profiles,
              )..where((row) => row.id.equals(request.fromProfileId)))
              .getSingleOrNull();
      final targetMatrixId =
          fromProfile?.matrixUserId ??
          request.fromProfileId.replaceFirst('matrix-', '');

      // 3. Upsert friendship locally
      await _repositories.friends.upsertFriend(
        id: 'friendship-${request.fromProfileId}-${request.toProfileId}',
        profileId: request.fromProfileId,
        friendProfileId: request.toProfileId,
        state: 'accepted',
      );

      // 4. Update request status locally
      await _repositories.friends.upsertRequest(
        CachedFriendRequestInput(
          id: request.id,
          fromProfileId: request.fromProfileId,
          toProfileId: request.toProfileId,
          state: 'accepted',
          roomId: roomId,
        ),
      );

      // 5. Queue accepted event
      final acceptEventId = 'friend-accepted-${request.id}';
      final payload = {
        'id': acceptEventId,
        'fromMatrixId': myUserId,
        'toMatrixId': targetMatrixId,
        'roomId': roomId,
      };

      await _repositories.sync.enqueueOutgoingEvent(
        id: acceptEventId,
        eventType: 'org.ralroads.friend.accepted.v1',
        entityId: acceptEventId,
        payloadJson: jsonEncode(payload),
        roomId: roomId,
      );

      _syncService?.processOutbox();

      _setBusy(false, msg: 'Friend request accepted.');
    } catch (e) {
      _setBusy(false, msg: 'Failed to accept: $e');
      rethrow;
    }
  }

  Future<void> rejectFriendRequest(FriendRequest request) async {
    if (_client.userID == null) {
      throw Exception('Matrix is not connected.');
    }
    _setBusy(true);
    try {
      final myUserId = _client.userID!;
      final roomId = request.roomId;

      // Update local request status
      await _repositories.friends.upsertRequest(
        CachedFriendRequestInput(
          id: request.id,
          fromProfileId: request.fromProfileId,
          toProfileId: request.toProfileId,
          state: 'rejected',
          roomId: roomId,
        ),
      );

      if (roomId != null) {
        final fromProfile =
            await (_repositories.profiles.database.select(
                  _repositories.profiles.database.profiles,
                )..where((row) => row.id.equals(request.fromProfileId)))
                .getSingleOrNull();
        final targetMatrixId =
            fromProfile?.matrixUserId ??
            request.fromProfileId.replaceFirst('matrix-', '');

        final rejectEventId = 'friend-rejected-${request.id}';
        final payload = {
          'id': rejectEventId,
          'fromMatrixId': myUserId,
          'toMatrixId': targetMatrixId,
          'roomId': roomId,
        };

        await _repositories.sync.enqueueOutgoingEvent(
          id: rejectEventId,
          eventType: 'org.ralroads.friend.rejected.v1',
          entityId: rejectEventId,
          payloadJson: jsonEncode(payload),
          roomId: roomId,
        );

        _syncService?.processOutbox();
      }

      _setBusy(false, msg: 'Friend request rejected.');
    } catch (e) {
      _setBusy(false, msg: 'Failed to reject: $e');
      rethrow;
    }
  }

  // ─── Group Management ───────────────────────────────────────────────────────

  Future<void> createGroup(
    String name,
    String? description,
    bool encrypted,
  ) async {
    if (_client.userID == null) {
      throw Exception('Matrix is not connected.');
    }
    _setBusy(true);
    try {
      // 1. Create Matrix room
      final roomId = await _client.createRoom(
        name: name,
        topic: description,
        visibility: Visibility.private,
      );

      // 2. Set encryption if requested
      if (encrypted) {
        await _client.setRoomStateWithKey(roomId, 'm.room.encryption', '', {
          'algorithm': 'm.megolm.v1.aes-sha2',
        });
      }

      // 3. Upsert Group locally
      final groupId = 'group-$roomId';
      await _repositories.groups.upsertMatrixGroup(
        id: groupId,
        roomId: roomId,
        name: name,
        description: description,
        visibility: 'private',
        encrypted: encrypted,
      );

      // 4. Enqueue profile state event to room
      final profileEventId = 'group-profile-$roomId';
      final payload = {
        'id': groupId,
        'name': name,
        'description': description,
        'visibility': 'private',
        'encrypted': encrypted,
      };

      await _repositories.sync.enqueueOutgoingEvent(
        id: profileEventId,
        eventType: 'org.ralroads.group.profile.v1',
        entityId: groupId,
        payloadJson: jsonEncode(payload),
        roomId: roomId,
      );

      _syncService?.processOutbox();

      _setBusy(false, msg: 'Group created successfully.');
    } catch (e) {
      _setBusy(false, msg: 'Failed to create group: $e');
      rethrow;
    }
  }

  Future<void> joinGroup(String roomIdOrAlias) async {
    if (_client.userID == null) {
      throw Exception('Matrix is not connected.');
    }
    _setBusy(true);
    try {
      final roomId = await _client.joinRoom(roomIdOrAlias);

      // Upsert room/group basic info (will be fully synced by ingestor/versions)
      final groupId = 'group-$roomId';
      await _repositories.groups.upsertMatrixGroup(
        id: groupId,
        roomId: roomId,
        name: 'Joined Group',
        description: 'Syncing details...',
      );

      _setBusy(false, msg: 'Joined group successfully.');
    } catch (e) {
      _setBusy(false, msg: 'Failed to join group: $e');
      rethrow;
    }
  }

  Future<void> inviteToGroup(String roomId, String targetUserId) async {
    if (_client.userID == null) {
      throw Exception('Matrix is not connected.');
    }
    _setBusy(true);
    try {
      await _client.inviteUser(roomId, targetUserId);
      _setBusy(false, msg: 'User invited.');
    } catch (e) {
      _setBusy(false, msg: 'Failed to invite user: $e');
      rethrow;
    }
  }

  // ─── Moderation ────────────────────────────────────────────────────────────

  Future<void> blockUser(String matrixUserId, {String? reason}) async {
    _setBusy(true);
    try {
      final id = 'block-${DateTime.now().microsecondsSinceEpoch}';
      await _repositories.moderation.blockUser(
        id: id,
        matrixUserId: matrixUserId,
        reason: reason,
      );
      _setBusy(false, msg: 'User blocked.');
    } catch (e) {
      _setBusy(false, msg: 'Failed to block user: $e');
      rethrow;
    }
  }

  Future<void> unblockUser(String matrixUserId) async {
    _setBusy(true);
    try {
      await _repositories.moderation.unblockUser(matrixUserId);
      _setBusy(false, msg: 'User unblocked.');
    } catch (e) {
      _setBusy(false, msg: 'Failed to unblock user: $e');
      rethrow;
    }
  }

  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    _setBusy(true);
    try {
      final id = 'report-${DateTime.now().microsecondsSinceEpoch}';
      final myProfile = await _repositories.profiles.getCurrentLocalProfile();

      await _repositories.moderation.reportContent(
        id: id,
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        reporterProfileId: myProfile?.id,
      );
      _setBusy(false, msg: 'Content reported.');
    } catch (e) {
      _setBusy(false, msg: 'Failed to report content: $e');
      rethrow;
    }
  }

  // ─── Privacy-Safe Sharing ───────────────────────────────────────────────────

  Future<void> shareSegment(String roomId, String segmentId) async {
    if (_client.userID == null) {
      throw Exception('Matrix is not connected.');
    }
    _setBusy(true);
    try {
      // 1. Load data from DB
      _requireEncryptedRoom(roomId);
      final segment = await _repositories.segments.getSegment(segmentId);
      if (segment == null) throw Exception('Segment not found.');
      final versionId = segment.currentVersionId;
      if (versionId == null) throw Exception('Segment version not found.');

      final version = await (_repositories.segments.database.select(
        _repositories.segments.database.segmentVersions,
      )..where((row) => row.id.equals(versionId))).getSingle();

      final geomList =
          await (_repositories.segments.database.select(
                  _repositories.segments.database.segmentGeometry,
                )
                ..where((row) => row.versionId.equals(versionId))
                ..orderBy([(row) => drift.OrderingTerm.asc(row.pointIndex)]))
              .get();

      final geometry = geomList
          .map(
            (g) => RoutePoint(
              lat: g.lat,
              lon: g.lon,
              distanceFromStart: g.distanceFromStart,
            ),
          )
          .toList();

      final rules = await _repositories.segments.getRulesForVersion(versionId);

      // 2. Build JSON package
      final package = {
        'id': segment.id,
        'currentVersionId': version.id,
        'name': segment.name,
        'visibility': segment.visibility,
        'distanceMeters': version.distanceMeters,
        'safetyStatus': version.safetyStatus,
        'contentHash': version.contentHash,
        'signature': version.signature,
        'rules': {
          'policyVersion': rules?.policyVersion ?? 'local-v1',
          'hardSpeedToleranceKmh': rules?.hardSpeedToleranceKmh ?? 8,
          'hardSpeedDurationSeconds': rules?.hardSpeedDurationSeconds ?? 2,
          'minRouteMatchScore': rules?.minRouteMatchScore ?? 0.85,
          'minGpsQualityScore': rules?.minGpsQualityScore ?? 0.7,
        },
        'geometry': [
          for (final pt in geometry)
            {
              'lat': pt.lat,
              'lon': pt.lon,
              'distanceFromStart': pt.distanceFromStart,
            },
        ],
      };

      // 3. Encrypt payload
      final key = MatrixEncryptionHelper.generateRandomKey();
      final encryptedBytes = await MatrixEncryptionHelper.encryptPayload(
        jsonEncode(package),
        key,
      );

      // 4. Write to temp file
      final tempDir = await getTemporaryDirectory();
      final fileId = 'temp-upload-${DateTime.now().microsecondsSinceEpoch}';
      final tempFile = File('${tempDir.path}/$fileId');
      await tempFile.writeAsBytes(encryptedBytes);

      // 5. Enqueue media upload
      await _repositories.sync.enqueuePendingMediaUpload(
        id: fileId,
        localPath: tempFile.path,
        sha256: sha256.convert(encryptedBytes).toString(),
        sizeBytes: encryptedBytes.length,
      );

      // 6. Enqueue shared package event
      final eventId = 'share-segment-${DateTime.now().microsecondsSinceEpoch}';
      final payload = {
        'mxc_uri': fileId, // Placeholder
        'key_base64': base64.encode(key),
        'package_type': 'segment',
      };

      await _repositories.sync.enqueueOutgoingEvent(
        id: eventId,
        eventType: 'org.ralroads.shared_package.v1',
        entityId: segmentId,
        payloadJson: jsonEncode(payload),
        roomId: roomId,
      );

      _syncService?.processOutbox();

      _setBusy(false, msg: 'Segment sharing queued.');
    } catch (e) {
      _setBusy(false, msg: 'Sharing failed: $e');
      rethrow;
    }
  }

  Future<void> shareAttempt(String roomId, String attemptId) async {
    if (_client.userID == null) {
      throw Exception('Matrix is not connected.');
    }
    _setBusy(true);
    try {
      // 1. Load attempt details
      _requireEncryptedRoom(roomId);
      final attempt = await (_repositories.attempts.database.select(
        _repositories.attempts.database.segmentAttempts,
      )..where((row) => row.id.equals(attemptId))).getSingleOrNull();
      if (attempt == null) throw Exception('Attempt not found.');

      final pointsList =
          await (_repositories.attempts.database.select(
                  _repositories.attempts.database.attemptPoints,
                )
                ..where((row) => row.attemptId.equals(attemptId))
                ..orderBy([(row) => drift.OrderingTerm.asc(row.pointIndex)]))
              .get();

      final validation = await (_repositories.attempts.database.select(
        _repositories.attempts.database.localValidationResults,
      )..where((row) => row.attemptId.equals(attemptId))).getSingleOrNull();

      // 2. Build JSON package
      final package = {
        'id': attempt.id,
        'segmentId': attempt.segmentId,
        'profileId': attempt.profileId,
        'startedAt': attempt.startedAt.toIso8601String(),
        'finishedAt': attempt.finishedAt?.toIso8601String(),
        'status': attempt.status,
        'officialEligible': attempt.officialEligible,
        'durationSeconds': validation?.durationSeconds,
        'routeMatchScore': validation?.routeMatchScore,
        'gpsQualityScore': validation?.gpsQualityScore,
        'resultHash': validation?.resultHash ?? '',
        'reasonsJson': validation?.reasonsJson,
        'points': [
          for (final pt in pointsList)
            {
              'recordedAt': pt.recordedAt.toIso8601String(),
              'lat': pt.lat,
              'lon': pt.lon,
              'accuracyMeters': pt.accuracyMeters,
              'speedMps': pt.speedMps,
              'speedLimitKmh': pt.speedLimitKmh,
              'speedCompliant': pt.speedCompliant,
            },
        ],
      };

      // 3. Encrypt payload
      final key = MatrixEncryptionHelper.generateRandomKey();
      final encryptedBytes = await MatrixEncryptionHelper.encryptPayload(
        jsonEncode(package),
        key,
      );

      // 4. Write to temp file
      final tempDir = await getTemporaryDirectory();
      final fileId = 'temp-upload-${DateTime.now().microsecondsSinceEpoch}';
      final tempFile = File('${tempDir.path}/$fileId');
      await tempFile.writeAsBytes(encryptedBytes);

      // 5. Enqueue media upload
      await _repositories.sync.enqueuePendingMediaUpload(
        id: fileId,
        localPath: tempFile.path,
        sha256: sha256.convert(encryptedBytes).toString(),
        sizeBytes: encryptedBytes.length,
      );

      // 6. Enqueue shared package event
      final eventId = 'share-attempt-${DateTime.now().microsecondsSinceEpoch}';
      final payload = {
        'mxc_uri': fileId, // Placeholder
        'key_base64': base64.encode(key),
        'package_type': 'attempt',
      };

      await _repositories.sync.enqueueOutgoingEvent(
        id: eventId,
        eventType: 'org.ralroads.shared_package.v1',
        entityId: attemptId,
        payloadJson: jsonEncode(payload),
        roomId: roomId,
      );

      _syncService?.processOutbox();

      _setBusy(false, msg: 'Attempt sharing queued.');
    } catch (e) {
      _setBusy(false, msg: 'Sharing failed: $e');
      rethrow;
    }
  }
}
