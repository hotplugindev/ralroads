import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/online/matrix/matrix_account_service.dart';
import 'package:ralroads/online/matrix/matrix_sync_service.dart';
import 'package:ralroads/online/matrix/matrix_encryption_helper.dart';
import 'package:ralroads/repositories/app_repositories.dart';
import 'package:ralroads/repositories/profile_repository.dart';
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
    test('encrypts and decrypts segment/attempt JSON payloads', () {
      final keyBytes = MatrixEncryptionHelper.generateRandomKey();
      const payload = '{"id":"seg-123","points":[{"lat":45.0,"lon":10.0}]}';

      final encrypted = MatrixEncryptionHelper.encryptPayload(
        payload,
        keyBytes,
      );
      final decrypted = MatrixEncryptionHelper.decryptPayload(
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

      var putCalled = false;
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.path.contains('!room-abc') &&
            options.path.contains('evt-out-1')) {
          putCalled = true;
          final data = options.data as Map<String, dynamic>;
          expect(data['id'], 'seg-1');
          expect(options.headers['Authorization'], 'Bearer test-access-token');
        }
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

      await syncService.processOutbox();

      expect(putCalled, isTrue);

      final event = await (database.select(
        database.outgoingMatrixEvents,
      )..where((row) => row.id.equals('evt-out-1'))).getSingleOrNull();
      expect(event!.state, 'sent');
    });
  });
}
