import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/online/matrix/matrix_account_service.dart';
import 'package:ralroads/online/matrix/matrix_client_service.dart';
import 'package:ralroads/online/matrix/matrix_sync_service.dart';
import 'package:ralroads/online/matrix/matrix_encryption_helper.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/repositories/app_repositories.dart';
import 'package:ralroads/repositories/profile_repository.dart';
import 'package:ralroads/repositories/segment_repository.dart';
import 'package:ralroads/services/route_storage_service.dart';
import 'package:ralroads/services/secure_credential_service.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  MockHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase database;
  late AppRepositories repositories;
  late SecureCredentialService secureCredentials;
  late MatrixAccountService matrixAccount;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repositories = AppRepositories(
      routeStorage: RouteStorageService(),
      database: database,
    );
    secureCredentials = SecureCredentialService(
      store: MemorySecureCredentialStore(),
    );
    matrixAccount = MatrixAccountService(
      database: database,
      secureCredentials: secureCredentials,
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('MatrixEncryptionHelper', () {
    test('encrypts and decrypts segment/attempt JSON payloads', () async {
      final keyBytes = MatrixEncryptionHelper.generateRandomKey();
      const payload = '{"id":"seg-123","points":[{"lat":45.0,"lon":10.0}]}';

      final encrypted = await MatrixEncryptionHelper.encryptPayload(
        payload,
        keyBytes,
      );
      final decrypted = await MatrixEncryptionHelper.decryptPayload(
        encrypted,
        keyBytes,
      );

      expect(decrypted, payload);
    });
  });

  group('MatrixSyncService', () {
    test('imports segment payload correctly', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final syncService = MatrixSyncService(
        repositories: repositories,
        secureCredentials: secureCredentials,
        matrixAccount: matrixAccount,
        dio: dio,
      );

      final segmentPayload = {
        'id': 'seg-test',
        'currentVersionId': 'ver-test',
        'name': 'Rally segment 1',
        'distanceMeters': 1420.5,
        'safetyStatus': 'suitable',
        'rules': {
          'policyVersion': 'local-v1',
          'hardSpeedToleranceKmh': 10,
          'hardSpeedDurationSeconds': 3,
          'minRouteMatchScore': 0.8,
          'minGpsQualityScore': 0.6,
        },
        'geometry': [
          {'lat': 46.0, 'lon': 11.0, 'distanceFromStart': 0.0},
          {'lat': 46.01, 'lon': 11.01, 'distanceFromStart': 1420.5},
        ],
      };

      await syncService.importSegment(segmentPayload);

      final segment = await repositories.segments.getSegment('seg-test');
      expect(segment, isNotNull);
      expect(segment!.name, 'Rally segment 1');

      final rules = await repositories.segments.getRulesForVersion('ver-test');
      expect(rules, isNotNull);
      expect(rules!.hardSpeedToleranceKmh, 10);
    });

    test('imports attempt payload correctly', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final syncService = MatrixSyncService(
        repositories: repositories,
        secureCredentials: secureCredentials,
        matrixAccount: matrixAccount,
        dio: dio,
      );

      await syncService.importSegment({
        'id': 'seg-test',
        'currentVersionId': 'ver-test',
        'name': 'Rally segment 1',
        'distanceMeters': 1420.5,
        'geometry': [
          {'lat': 46.0, 'lon': 11.0, 'distanceFromStart': 0.0},
        ],
      });

      // Create test profile to satisfy foreign key constraint
      await repositories.profiles.createOrUpdateLocalProfile(
        const LocalProfileInput(id: 'prof-test', displayName: 'Test Profile'),
      );

      final attemptPayload = {
        'id': 'att-test',
        'segmentId': 'seg-test',
        'profileId': 'prof-test',
        'startedAt': '2026-06-07T12:00:00.000Z',
        'finishedAt': '2026-06-07T12:05:00.000Z',
        'status': 'valid_clean',
        'officialEligible': true,
        'durationSeconds': 300.0,
        'routeMatchScore': 0.98,
        'gpsQualityScore': 0.92,
        'resultHash': 'hash123',
        'reasonsJson': '[]',
        'points': [
          {
            'recordedAt': '2026-06-07T12:00:00.000Z',
            'lat': 46.0,
            'lon': 11.0,
            'accuracyMeters': 4.0,
            'speedMps': 12.0,
            'headingDegrees': 90.0,
            'distanceFromStart': 0.0,
            'speedLimitKmh': 50,
            'speedCompliant': true,
          },
        ],
      };

      await syncService.importAttempt(attemptPayload);

      final attempt = await (database.select(
        database.segmentAttempts,
      )..where((row) => row.id.equals('att-test'))).getSingleOrNull();

      expect(attempt, isNotNull);
      expect(attempt!.status, 'valid_clean');
      expect(attempt.officialEligible, isTrue);

      final validation = await (database.select(
        database.localValidationResults,
      )..where((row) => row.attemptId.equals('att-test'))).getSingleOrNull();
      expect(validation, isNotNull);
      expect(validation!.routeMatchScore, 0.98);
    });

    test(
      'imports Matrix profile, friend, group and directory events',
      () async {
        final syncService = MatrixSyncService(
          repositories: repositories,
          secureCredentials: secureCredentials,
          matrixAccount: matrixAccount,
          dio: Dio(),
        );

        await repositories.profiles.createOrUpdateLocalProfile(
          const LocalProfileInput(
            id: 'local-profile',
            displayName: 'Local Driver',
          ),
        );

        final session = MatrixSession(
          id: 'matrix-primary-session',
          accountId: 'matrix-primary',
          matrixUserId: '@me:matrix.org',
          homeserverUrl: 'https://matrix.org',
          deviceId: 'DEVICE',
          isActive: true,
          createdAt: DateTime(2026, 1, 1, 12),
          updatedAt: DateTime(2026, 1, 1, 12),
        );

        await syncService.importProfileEvent({
          'schemaVersion': 1,
          'payload': {
            'matrixUserId': '@friend:matrix.org',
            'displayName': 'Friend Driver',
          },
        });
        await syncService.importFriendEvent(
          {
            'schemaVersion': 1,
            'payload': {
              'id': 'friend-request-1',
              'fromMatrixId': '@friend:matrix.org',
              'toMatrixId': '@me:matrix.org',
            },
          },
          session: session,
          state: 'pending',
        );
        await syncService.importFriendEvent(
          {
            'schemaVersion': 1,
            'payload': {
              'id': 'friend-request-1',
              'fromMatrixId': '@friend:matrix.org',
              'toMatrixId': '@me:matrix.org',
            },
          },
          session: session,
          state: 'accepted',
        );
        await syncService.importGroupEvent({
          'schemaVersion': 1,
          'payload': {
            'groupId': 'group-1',
            'name': 'Sunday Roads',
            'description': 'Private group',
            'visibility': 'private',
          },
        }, roomId: '!group:matrix.org');
        await repositories.directories.cacheDirectoryEvent(
          id: 'directory-event-1',
          roomId: '!directory:matrix.org',
          eventType: 'org.ralroads.directory.segment.published.v1',
          entityId: 'seg-1',
          payloadJson: '{"segmentId":"seg-1"}',
          originTimestamp: DateTime(2026, 1, 1, 12),
        );

        final friendProfile =
            await (database.select(database.profiles)..where(
                  (row) => row.matrixUserId.equals('@friend:matrix.org'),
                ))
                .getSingleOrNull();
        expect(friendProfile?.displayName, 'Friend Driver');

        final requests = await repositories.friends.listPendingRequests(
          'local-profile',
        );
        expect(requests.single.id, 'friend-request-1');

        final friends = await repositories.friends.listCachedFriends(
          'local-profile',
        );
        expect(friends.single.state, 'accepted');

        final groups = await repositories.groups.listCachedGroups();
        expect(groups.single.name, 'Sunday Roads');

        final directoryEvents = await repositories.directories.getEventsForRoom(
          '!directory:matrix.org',
        );
        expect(directoryEvents.single.entityId, 'seg-1');
      },
    );

    test('imports Matrix challenge lifecycle events', () async {
      final syncService = MatrixSyncService(
        repositories: repositories,
        secureCredentials: secureCredentials,
        matrixAccount: matrixAccount,
        dio: Dio(),
      );
      final origin = DateTime(2026, 6, 7, 12);

      await syncService.importChallengeEvent(
        {
          'schemaVersion': 1,
          'entityId': 'challenge-remote-1',
          'revision': 1,
          'authorMatrixId': '@alice:matrix.org',
          'timestamp': origin.toIso8601String(),
          'segment': {
            'id': 'seg-challenge-1',
            'currentVersionId': 'seg-challenge-v1',
            'name': 'Hill road',
            'distanceMeters': 900.0,
            'geometry': [
              {'lat': 46.0, 'lon': 11.0, 'distanceFromStart': 0.0},
              {'lat': 46.01, 'lon': 11.01, 'distanceFromStart': 900.0},
            ],
          },
          'payload': {
            'challengeId': 'challenge-remote-1',
            'revision': 1,
            'segmentId': 'seg-challenge-1',
            'name': 'Sunday hill climb',
            'status': 'active',
            'visibility': 'group',
            'sourceRoomId': '!group:matrix.org',
            'authorMatrixId': '@alice:matrix.org',
            'startsAt': origin.toIso8601String(),
            'deadline': origin.add(const Duration(days: 7)).toIso8601String(),
          },
        },
        roomId: '!group:matrix.org',
        eventType: 'org.ralroads.challenge.created.v1',
        originTimestamp: origin,
        sender: '@alice:matrix.org',
      );

      final challenge = await repositories.challenges.getChallenge(
        'challenge-remote-1',
      );
      expect(challenge, isNotNull);
      expect(challenge!.name, 'Sunday hill climb');
      expect(challenge.status, 'active');
      expect(challenge.roomId, '!group:matrix.org');

      await syncService.importChallengeEvent(
        {
          'schemaVersion': 1,
          'entityId': 'challenge-remote-1',
          'revision': 2,
          'authorMatrixId': '@alice:matrix.org',
          'payload': {
            'challengeId': 'challenge-remote-1',
            'revision': 2,
            'segmentId': 'seg-challenge-1',
            'status': 'cancelled',
            'authorMatrixId': '@alice:matrix.org',
          },
        },
        roomId: '!group:matrix.org',
        eventType: 'org.ralroads.challenge.cancelled.v1',
        originTimestamp: origin.add(const Duration(minutes: 5)),
        sender: '@alice:matrix.org',
      );

      final cancelled = await repositories.challenges.getChallenge(
        'challenge-remote-1',
      );
      expect(cancelled!.status, 'cancelled');
    });

    test('local room-backed challenge creation queues Matrix event', () async {
      await repositories.segments.createLocalSegment(
        const LocalSegmentInput(
          id: 'seg-local-challenge',
          versionId: 'seg-local-challenge-v1',
          name: 'Local route',
          distanceMeters: 1000,
          geometry: [RoutePoint(lat: 46.0, lon: 11.0, distanceFromStart: 0.0)],
        ),
      );

      final now = DateTime(2026, 6, 7, 12);
      await repositories.challenges.createLocalChallenge(
        id: 'challenge-local-queued',
        segmentId: 'seg-local-challenge',
        name: 'Queued challenge',
        roomId: '!group:matrix.org',
        ownerMatrixId: '@me:matrix.org',
        startsAt: now,
        endsAt: now.add(const Duration(days: 1)),
      );

      final queued = await database.select(database.outgoingMatrixEvents).get();
      expect(queued, hasLength(1));
      expect(queued.single.eventType, 'org.ralroads.challenge.created.v1');
      expect(queued.single.roomId, '!group:matrix.org');
      expect(queued.single.entityId, 'challenge-local-queued');
      expect(queued.single.payloadJson, contains('Queued challenge'));
    });

    test('processes outbox events successfully', () async {
      // Setup active session
      final now = DateTime.now();
      await database
          .into(database.localAccounts)
          .insert(
            LocalAccountsCompanion(
              id: const Value('matrix-primary'),
              mode: const Value('matrix'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await database
          .into(database.matrixSessions)
          .insert(
            MatrixSessionsCompanion(
              id: const Value('matrix-primary-session'),
              accountId: const Value('matrix-primary'),
              matrixUserId: const Value('@user:matrix.org'),
              homeserverUrl: const Value('https://matrix.org'),
              deviceId: const Value('device-1'),
              isActive: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      final fakeClientService = _FakeClientService(
        database: database,
        secureCredentials: secureCredentials,
      );
      final fakeMatrixAccount = MatrixAccountService(
        database: database,
        secureCredentials: secureCredentials,
        clientService: fakeClientService,
      );
      await secureCredentials.writeString(
        SecureCredentialKey.matrixAccessToken,
        'test-access-token',
      );

      // Enqueue outbox event
      await repositories.sync.enqueueOutgoingEvent(
        id: 'evt-out-1',
        eventType: 'org.ralroads.segment.v1',
        entityId: 'seg-1',
        payloadJson: '{"id":"seg-1"}',
        roomId: '!room-abc',
      );

      final syncService = MatrixSyncService(
        repositories: repositories,
        secureCredentials: secureCredentials,
        matrixAccount: fakeMatrixAccount,
      );

      await syncService.processOutbox();

      expect(fakeClientService.fakeClient.requests, hasLength(1));
      final request = fakeClientService.fakeClient.requests.single;
      expect(request.type, RequestType.PUT);
      expect(request.action, contains(Uri.encodeComponent('!room-abc')));
      expect(request.data['id'], 'seg-1');

      final event = await (database.select(
        database.outgoingMatrixEvents,
      )..where((row) => row.id.equals('evt-out-1'))).getSingleOrNull();
      expect(event!.state, 'sent');
    });
  });
}

class _FakeClientService extends MatrixClientService {
  _FakeClientService({
    required super.database,
    required super.secureCredentials,
  });

  final fakeClient = _FakeMatrixClient();

  @override
  Client get client => fakeClient;
}

class _SdkRequest {
  const _SdkRequest({
    required this.type,
    required this.action,
    required this.data,
  });

  final RequestType type;
  final String action;
  final Map<String, dynamic> data;
}

class _FakeMatrixClient implements Client {
  final requests = <_SdkRequest>[];

  @override
  String? get userID => '@user:matrix.org';

  @override
  String? get accessToken => 'test-access-token';

  @override
  Future<Map<String, Object?>> request(
    RequestType type,
    String action, {
    dynamic data = '',
    String contentType = 'application/json',
    Map<String, Object?>? query,
  }) async {
    requests.add(
      _SdkRequest(
        type: type,
        action: action,
        data: Map<String, dynamic>.from(data as Map),
      ),
    );
    return <String, Object?>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
