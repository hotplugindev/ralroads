import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:ralroads/controllers/matrix_social_controller.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/online/matrix/matrix_client_service.dart';
import 'package:ralroads/repositories/app_repositories.dart';
import 'package:ralroads/repositories/segment_repository.dart';
import 'package:ralroads/repositories/friend_repository.dart';
import 'package:ralroads/repositories/profile_repository.dart';
import 'package:ralroads/services/route_storage_service.dart';
import 'package:ralroads/services/secure_credential_service.dart';

// Fake Path Provider for temporary directory testing
class FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
  }
}

class FakeMatrixClient implements matrix_sdk.Client {
  @override
  String? get userID => '@alice:matrix.org';

  @override
  String? get deviceID => 'DEVICE_ID';

  final List<String> createdRooms = [];
  final List<String> joinedRooms = [];
  final Map<String, List<String>> invites = {};
  final Map<String, String> roomEncryptions = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #createRoom) {
      final roomId = '!room-${createdRooms.length}:matrix.org';
      createdRooms.add(roomId);
      final inviteArg =
          invocation.namedArguments[const Symbol('invite')] as List<dynamic>?;
      if (inviteArg != null) {
        invites[roomId] = inviteArg.cast<String>();
      }
      return Future.value(roomId);
    }
    if (invocation.memberName == #joinRoom) {
      final roomIdOrAlias = invocation.positionalArguments[0] as String;
      joinedRooms.add(roomIdOrAlias);
      return Future.value(roomIdOrAlias);
    }
    if (invocation.memberName == #inviteUser) {
      final roomId = invocation.positionalArguments[0] as String;
      final userId = invocation.positionalArguments[1] as String;
      invites.putIfAbsent(roomId, () => []).add(userId);
      return Future.value();
    }
    if (invocation.memberName == #setRoomStateWithKey) {
      final roomId = invocation.positionalArguments[0] as String;
      final eventType = invocation.positionalArguments[1] as String;
      final content =
          invocation.positionalArguments[3] as Map<dynamic, dynamic>;
      if (eventType == 'm.room.encryption') {
        roomEncryptions[roomId] = content['algorithm'] as String;
      }
      return Future.value('fake-event-id');
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeMatrixClientService extends MatrixClientService {
  FakeMatrixClientService({
    required super.database,
    required super.secureCredentials,
  });

  final FakeMatrixClient _fakeClient = FakeMatrixClient();

  @override
  matrix_sdk.Client get client => _fakeClient;

  @override
  Future<void> init() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = FakePathProvider();

  late AppDatabase database;
  late AppRepositories repositories;
  late SecureCredentialService secureCredentials;
  late FakeMatrixClientService clientService;
  late MatrixSocialController socialController;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repositories = AppRepositories(
      routeStorage: RouteStorageService(),
      database: database,
    );
    secureCredentials = SecureCredentialService(
      store: MemorySecureCredentialStore(),
    );
    clientService = FakeMatrixClientService(
      database: database,
      secureCredentials: secureCredentials,
    );
    socialController = MatrixSocialController(
      repositories: repositories,
      clientService: clientService,
    );

    // Set active matrix credentials
    await secureCredentials.writeString(
      SecureCredentialKey.matrixAccessToken,
      'fake_token',
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('MatrixSocialController Friend Tests', () {
    test(
      'sendFriendRequest enqueues outgoing event and upserts request locally',
      () async {
        await socialController.sendFriendRequest('@bob:matrix.org');

        expect(clientService._fakeClient.createdRooms, hasLength(1));
        final roomId = clientService._fakeClient.createdRooms.first;
        expect(
          clientService._fakeClient.invites[roomId],
          contains('@bob:matrix.org'),
        );

        // Check database FriendRequests
        final requests = await database.select(database.friendRequests).get();
        expect(requests, hasLength(1));
        expect(requests.first.toProfileId, 'matrix--bob-matrix-org');
        expect(requests.first.state, 'pending');

        // Check OutgoingMatrixEvents
        final events = await database
            .select(database.outgoingMatrixEvents)
            .get();
        expect(events, hasLength(1));
        expect(events.first.eventType, 'org.ralroads.friend.request.v1');
      },
    );

    test(
      'acceptFriendRequest updates state to accepted and enqueues event',
      () async {
        // 1. Create profiles to satisfy foreign keys
        await repositories.profiles.createOrUpdateLocalProfile(
          const LocalProfileInput(
            id: 'matrix--bob-matrix-org',
            displayName: 'Bob',
            matrixUserId: '@bob:matrix.org',
          ),
        );
        await repositories.profiles.createOrUpdateLocalProfile(
          const LocalProfileInput(
            id: 'matrix--alice-matrix-org',
            displayName: 'Alice',
            matrixUserId: '@alice:matrix.org',
          ),
        );

        // 2. Create a pending request in database
        const requestId = 'friend-request-1';
        await repositories.friends.upsertRequest(
          const CachedFriendRequestInput(
            id: requestId,
            fromProfileId: 'matrix--bob-matrix-org',
            toProfileId: 'matrix--alice-matrix-org',
            state: 'pending',
            roomId: '!room-123:matrix.org',
          ),
        );

        final req = await (database.select(
          database.friendRequests,
        )..where((row) => row.id.equals(requestId))).getSingleOrNull();
        expect(req, isNotNull);

        // 3. Accept it
        await socialController.acceptFriendRequest(req!);

        expect(
          clientService._fakeClient.joinedRooms,
          contains('!room-123:matrix.org'),
        );

        // Check request state is updated
        final updatedReq = await (database.select(
          database.friendRequests,
        )..where((row) => row.id.equals(requestId))).getSingleOrNull();
        expect(updatedReq?.state, 'accepted');

        // Check friendship is saved
        final friendship = await (database.select(
          database.friendships,
        )..limit(1)).getSingle();
        expect(friendship.state, 'accepted');

        // Check OutgoingMatrixEvents
        final events = await database
            .select(database.outgoingMatrixEvents)
            .get();
        expect(events, hasLength(1));
        expect(events.first.eventType, 'org.ralroads.friend.accepted.v1');
      },
    );
  });

  group('MatrixSocialController Group Tests', () {
    test(
      'createGroup creates room, sets E2EE, and saves local group',
      () async {
        // Create profile for E2EE room setups or visibility
        await repositories.profiles.createOrUpdateLocalProfile(
          const LocalProfileInput(
            id: 'matrix--alice-matrix-org',
            displayName: 'Alice',
            matrixUserId: '@alice:matrix.org',
          ),
        );

        await socialController.createGroup('Rally Pack', 'Desc', true);

        final roomId = clientService._fakeClient.createdRooms.first;
        expect(
          clientService._fakeClient.roomEncryptions[roomId],
          'm.megolm.v1.aes-sha2',
        );

        // Check database
        final group = await (database.select(
          database.groups,
        )..limit(1)).getSingle();
        expect(group.name, 'Rally Pack');
        expect(group.roomId, roomId);

        final events = await database
            .select(database.outgoingMatrixEvents)
            .get();
        expect(events, hasLength(1));
        expect(events.first.eventType, 'org.ralroads.group.profile.v1');
      },
    );
  });

  group('MatrixSocialController Sharing & Placeholder Resolver Tests', () {
    test('shareSegment encrypts and queue uploads', () async {
      // 1. Create local profile and segment
      await repositories.profiles.createOrUpdateLocalProfile(
        const LocalProfileInput(
          id: 'matrix--alice-matrix-org',
          displayName: 'Alice',
        ),
      );
      await repositories.segments.createLocalSegment(
        const LocalSegmentInput(
          id: 'seg-1',
          versionId: 'seg-version-1',
          name: 'Col de Turini',
          distanceMeters: 5200,
          safetyStatus: 'suitable',
          contentHash: 'hash-abc',
          geometry: [RoutePoint(lat: 44.0, lon: 7.0, distanceFromStart: 0)],
        ),
      );

      // 2. Share Segment
      await socialController.shareSegment('!room-abc:matrix.org', 'seg-1');

      // Check pendingMediaUploads is enqueued
      final uploads = await database.select(database.pendingMediaUploads).get();
      expect(uploads, hasLength(1));
      expect(uploads.first.id, startsWith('temp-upload-'));

      final events = await database.select(database.outgoingMatrixEvents).get();
      expect(events, hasLength(1));
      expect(events.first.eventType, 'org.ralroads.shared_package.v1');

      final payload =
          jsonDecode(events.first.payloadJson) as Map<String, dynamic>;
      expect(payload['mxc_uri'], uploads.first.id);
      expect(payload['package_type'], 'segment');
    });
  });
}
