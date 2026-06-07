import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../models/route_point.dart';
import '../../repositories/app_repositories.dart';
import '../../repositories/friend_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../repositories/segment_repository.dart';
import '../../repositories/attempt_repository.dart';
import '../../repositories/trip_repository.dart';
import 'matrix_encryption_helper.dart';

class MatrixEventIngestor {
  MatrixEventIngestor({
    required this.repositories,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final AppRepositories repositories;
  final Dio _dio;

  Future<void> ingestEvent({
    required String eventId,
    required String roomId,
    required String eventType,
    required Map<String, dynamic> content,
    required int originServerTs,
    required String? sender,
    required String currentUserId,
    required String homeserverUrl,
    required String accessToken,
  }) async {
    // 1. Check if already processed
    final exists = await (repositories.sync.database.select(
      repositories.sync.database.cachedDirectoryEvents,
    )..where((row) => row.id.equals(eventId))).getSingleOrNull();
    if (exists != null) return;

    // 2. Process based on eventType
    if (eventType == 'org.ralroads.profile.v1') {
      await importProfileEvent(content, sender: sender);
    } else if (eventType == 'org.ralroads.friend.request.v1') {
      await importFriendEvent(
        content,
        currentUserId: currentUserId,
        state: 'pending',
      );
    } else if (eventType == 'org.ralroads.friend.accepted.v1') {
      await importFriendEvent(
        content,
        currentUserId: currentUserId,
        state: 'accepted',
      );
    } else if (eventType == 'org.ralroads.friend.rejected.v1' ||
        eventType == 'org.ralroads.friend.removed.v1') {
      await importFriendEvent(
        content,
        currentUserId: currentUserId,
        state: 'removed',
      );
    } else if (eventType == 'org.ralroads.group.profile.v1') {
      await importGroupEvent(content, roomId: roomId);
    } else if (eventType == 'org.ralroads.directory.segment.published.v1') {
      await repositories.directories.cacheDirectoryEvent(
        id: eventId,
        roomId: roomId,
        eventType: eventType,
        entityId: content['segmentId'] as String? ??
            content['id'] as String? ??
            eventId,
        payloadJson: jsonEncode(content),
        originTimestamp: DateTime.fromMillisecondsSinceEpoch(originServerTs),
      );
    } else if (eventType == 'org.ralroads.shared_package.v1') {
      await _handleSharedPackage(
        content: content,
        homeserverUrl: homeserverUrl,
        accessToken: accessToken,
      );
    } else if (eventType == 'org.ralroads.segment.v1') {
      await _handlePlainSegment(content);
    } else if (eventType == 'org.ralroads.attempt.result.v1') {
      await _handlePlainAttempt(content);
    } else if (eventType == 'm.room.name') {
      final name = content['name'] as String?;
      if (name != null) {
        await (repositories.sync.database.update(
          repositories.sync.database.rooms,
        )..where((row) => row.id.equals(roomId))).write(
          RoomsCompanion(
            name: Value(name),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }

    // 3. Cache the event
    await repositories.sync.database
        .into(repositories.sync.database.cachedDirectoryEvents)
        .insertOnConflictUpdate(
          CachedDirectoryEventsCompanion(
            id: Value(eventId),
            roomId: Value(roomId),
            eventType: Value(eventType),
            entityId: Value(
              content['id'] as String? ??
                  content['segmentId'] as String? ??
                  'unknown',
            ),
            payloadJson: Value(jsonEncode(content)),
            originTimestamp: Value(
              DateTime.fromMillisecondsSinceEpoch(originServerTs),
            ),
            ingestedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> _handlePlainSegment(Map<String, dynamic> content) async {
    try {
      await importSegment(content);
    } catch (_) {}
  }

  Future<void> _handlePlainAttempt(Map<String, dynamic> content) async {
    try {
      await importAttempt(content);
    } catch (_) {}
  }

  Future<void> importProfileEvent(
    Map<String, dynamic> content, {
    String? sender,
  }) async {
    if (!_payloadAllowed(content)) return;
    final payload = _payload(content);
    final matrixUserId = payload['matrixUserId'] as String? ??
        payload['matrix_user_id'] as String? ??
        payload['authorMatrixId'] as String? ??
        sender;
    if (matrixUserId == null || !_isMatrixId(matrixUserId)) return;
    final displayName = payload['displayName'] as String? ??
        payload['display_name'] as String? ??
        matrixUserId;
    await repositories.profiles.createOrUpdateLocalProfile(
      LocalProfileInput(
        id: _profileIdForMatrix(matrixUserId),
        matrixUserId: matrixUserId,
        displayName: displayName,
        avatarUri: payload['avatarUri'] as String?,
        homeRegion: payload['homeRegion'] as String?,
        visibility: payload['visibility'] as String? ?? 'friends',
      ),
    );
  }

  Future<void> importFriendEvent(
    Map<String, dynamic> content, {
    String? currentUserId,
    MatrixSession? session,
    required String state,
  }) async {
    final activeUserId = currentUserId ?? session?.matrixUserId;
    if (activeUserId == null) return;
    if (!_payloadAllowed(content)) return;
    final payload = _payload(content);
    final fromMatrixId = payload['fromMatrixId'] as String? ??
        payload['from'] as String? ??
        payload['authorMatrixId'] as String?;
    final toMatrixId = payload['toMatrixId'] as String? ??
        payload['to'] as String? ??
        payload['targetMatrixId'] as String?;
    if (!_isMatrixId(fromMatrixId) || !_isMatrixId(toMatrixId)) return;
    final fromId = fromMatrixId!;
    final toId = toMatrixId!;

    final localProfile = await repositories.profiles.getCurrentLocalProfile();
    final fromProfileId = fromId == activeUserId
        ? localProfile?.id ?? _profileIdForMatrix(fromId)
        : _profileIdForMatrix(fromId);
    final toProfileId = toId == activeUserId
        ? localProfile?.id ?? _profileIdForMatrix(toId)
        : _profileIdForMatrix(toId);

    await _ensureMatrixProfile(fromId, fromProfileId);
    await _ensureMatrixProfile(toId, toProfileId);

    final requestId = payload['id'] as String? ??
        payload['requestId'] as String? ??
        'friend-$fromProfileId-$toProfileId';
    if (state == 'pending') {
      await repositories.friends.upsertRequest(
        CachedFriendRequestInput(
          id: requestId,
          fromProfileId: fromProfileId,
          toProfileId: toProfileId,
          state: 'pending',
          roomId: payload['roomId'] as String?,
        ),
      );
      return;
    }

    await repositories.friends.upsertFriend(
      id: 'friendship-$fromProfileId-$toProfileId',
      profileId: fromProfileId,
      friendProfileId: toProfileId,
      state: state,
    );
  }

  Future<void> importGroupEvent(
    Map<String, dynamic> content, {
    required String roomId,
  }) async {
    if (!_payloadAllowed(content)) return;
    final payload = _payload(content);
    final groupId = payload['id'] as String? ??
        payload['groupId'] as String? ??
        'group-$roomId';
    final name = payload['name'] as String? ??
        payload['displayName'] as String? ??
        'Matrix group';
    await repositories.groups.upsertMatrixGroup(
      id: groupId,
      roomId: roomId,
      name: name,
      description: payload['description'] as String?,
      visibility: payload['visibility'] as String? ?? 'private',
      encrypted: payload['encrypted'] as bool? ?? false,
    );
  }

  Future<void> _ensureMatrixProfile(String matrixUserId, String id) async {
    final existing = await (repositories.profiles.database.select(
      repositories.profiles.database.profiles,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (existing != null) return;
    await repositories.profiles.createOrUpdateLocalProfile(
      LocalProfileInput(
        id: id,
        matrixUserId: matrixUserId,
        displayName: matrixUserId,
        visibility: 'friends',
      ),
    );
  }

  Map<String, dynamic> _payload(Map<String, dynamic> content) {
    final payload = content['payload'];
    if (payload is Map<String, dynamic>) return payload;
    return content;
  }

  bool _payloadAllowed(Map<String, dynamic> content) {
    return jsonEncode(content).length <= 64 * 1024;
  }

  bool _isMatrixId(String? value) {
    if (value == null) return false;
    return value.startsWith('@') && value.contains(':');
  }

  String _profileIdForMatrix(String matrixUserId) {
    return 'matrix-${matrixUserId.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')}';
  }

  Future<void> _handleSharedPackage({
    required Map<String, dynamic> content,
    required String homeserverUrl,
    required String accessToken,
  }) async {
    final mxcUri = content['mxc_uri'] as String?;
    final keyBase64 = content['key_base64'] as String?;
    final packageType = content['package_type'] as String?;

    if (mxcUri == null || keyBase64 == null || packageType == null) return;

    try {
      final parsed = Uri.parse(mxcUri);
      if (parsed.scheme != 'mxc') return;
      final serverName = parsed.host;
      final mediaId = parsed.path.replaceFirst('/', '');

      final downloadUrl =
          '$homeserverUrl/_matrix/media/v3/download/$serverName/$mediaId';
      final response = await _dio.get<List<int>>(
        downloadUrl,
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          responseType: ResponseType.bytes,
        ),
      );

      final combinedBytes = Uint8List.fromList(response.data!);
      final keyBytes = base64.decode(keyBase64);

      final jsonStr = MatrixEncryptionHelper.decryptPayload(
        combinedBytes,
        keyBytes,
      );
      final package = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (packageType == 'segment') {
        await importSegment(package);
      } else if (packageType == 'attempt') {
        await importAttempt(package);
      }
    } catch (_) {}
  }

  Future<void> importSegment(Map<String, dynamic> package) async {
    final segmentId = package['id'] as String;
    final versionId = package['currentVersionId'] as String;
    final name = package['name'] as String;
    final visibility = package['visibility'] as String? ?? 'private';

    final distanceMeters =
        (package['distanceMeters'] as num?)?.toDouble() ?? 0.0;
    final safetyStatus = package['safetyStatus'] as String? ?? 'suitable';
    final contentHash = package['contentHash'] as String? ?? '';
    final signature = package['signature'] as String?;

    final rulesData = package['rules'] as Map<String, dynamic>?;
    final rules = SegmentRuleInput(
      policyVersion: rulesData?['policyVersion'] as String? ?? 'local-v1',
      hardSpeedToleranceKmh: rulesData?['hardSpeedToleranceKmh'] as int? ?? 8,
      hardSpeedDurationSeconds:
          rulesData?['hardSpeedDurationSeconds'] as int? ?? 2,
      minRouteMatchScore:
          (rulesData?['minRouteMatchScore'] as num?)?.toDouble() ?? 0.85,
      minGpsQualityScore:
          (rulesData?['minGpsQualityScore'] as num?)?.toDouble() ?? 0.7,
    );

    final geomData = package['geometry'] as List<dynamic>? ?? [];
    final geometry = geomData.map((g) {
      final map = g as Map<String, dynamic>;
      return RoutePoint(
        lat: (map['lat'] as num).toDouble(),
        lon: (map['lon'] as num).toDouble(),
        distanceFromStart: (map['distanceFromStart'] as num).toDouble(),
      );
    }).toList();

    final existing = await repositories.segments.getSegment(segmentId);
    if (existing == null) {
      await repositories.segments.createLocalSegment(
        LocalSegmentInput(
          id: segmentId,
          versionId: versionId,
          name: name,
          geometry: geometry,
          distanceMeters: distanceMeters,
          visibility: visibility,
          safetyStatus: safetyStatus,
          contentHash: contentHash,
          signature: signature,
          rules: rules,
        ),
      );
    }
  }

  Future<void> importAttempt(Map<String, dynamic> package) async {
    final attemptId = package['id'] as String;
    final segmentId = package['segmentId'] as String;
    final profileId = package['profileId'] as String?;
    final startedAt = DateTime.parse(package['startedAt'] as String);
    final finishedAt = package['finishedAt'] != null
        ? DateTime.parse(package['finishedAt'] as String)
        : null;
    final status = package['status'] as String? ?? 'dnf';
    final officialEligible = package['officialEligible'] as bool? ?? false;

    final existing = await (repositories.attempts.database.select(
      repositories.attempts.database.segmentAttempts,
    )..where((row) => row.id.equals(attemptId))).getSingleOrNull();

    if (existing == null) {
      await repositories.attempts.createAttempt(
        id: attemptId,
        segmentId: segmentId,
        startedAt: startedAt,
        profileId: profileId,
      );

      if (finishedAt != null) {
        final pointsData = package['points'] as List<dynamic>? ?? [];
        final points = pointsData.map<TripRecordingPoint>((p) {
          final map = p as Map<String, dynamic>;
          return TripRecordingPoint(
            recordedAt: DateTime.parse(map['recordedAt'] as String),
            lat: (map['lat'] as num).toDouble(),
            lon: (map['lon'] as num).toDouble(),
            accuracyMeters: (map['accuracyMeters'] as num?)?.toDouble(),
            speedMps: (map['speedMps'] as num?)?.toDouble(),
            headingDegrees: (map['headingDegrees'] as num?)?.toDouble(),
            distanceFromStart:
                (map['distanceFromStart'] as num?)?.toDouble() ?? 0.0,
            speedLimitKmh: map['speedLimitKmh'] as int?,
            speedCompliant: map['speedCompliant'] as bool?,
          );
        }).toList();

        if (points.isNotEmpty) {
          await repositories.attempts.appendAttemptPoints(attemptId, points);
        }

        final durationSeconds = (package['durationSeconds'] as num?)
            ?.toDouble();
        final routeMatchScore = (package['routeMatchScore'] as num?)
            ?.toDouble();
        final gpsQualityScore = (package['gpsQualityScore'] as num?)
            ?.toDouble();
        final resultHash = package['resultHash'] as String? ?? '';
        final reasonsJson = package['reasonsJson'] as String?;

        await repositories.attempts.persistValidationResult(
          AttemptValidationInput(
            id: 'val-$attemptId',
            attemptId: attemptId,
            engineVersion: '1.0.0',
            status: status,
            resultHash: resultHash,
            durationSeconds: durationSeconds,
            routeMatchScore: routeMatchScore,
            gpsQualityScore: gpsQualityScore,
            reasonsJson: reasonsJson,
          ),
        );

        await repositories.attempts.finishAttempt(
          attemptId: attemptId,
          finishedAt: finishedAt,
          status: status,
          officialEligible: officialEligible,
        );
      }
    }
  }
}
