import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/repositories/app_repositories.dart';
import 'package:ralroads/repositories/profile_repository.dart';
import 'package:ralroads/repositories/segment_repository.dart';
import 'package:ralroads/services/route_storage_service.dart';

void main() {
  late AppDatabase database;
  late AppRepositories repositories;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repositories = AppRepositories(
      routeStorage: RouteStorageService(),
      database: database,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'stores local profile, social data, segment, challenge and sync event',
    () async {
      final profile = await repositories.profiles.createOrUpdateLocalProfile(
        const LocalProfileInput(id: 'profile-1', displayName: 'Local driver'),
      );
      await repositories.groups.createLocalDraftGroup(
        id: 'group-1',
        name: 'Local group',
      );
      final social = await repositories.social.loadLocalSnapshot();

      expect(profile.displayName, 'Local driver');
      expect(social.profile?.id, 'profile-1');
      expect(social.groups, hasLength(1));

      final segment = await repositories.segments.createLocalSegment(
        const LocalSegmentInput(
          id: 'segment-1',
          versionId: 'segment-version-1',
          name: 'Local segment',
          distanceMeters: 1200,
          safetyStatus: 'suitable',
          contentHash: 'hash-1',
          geometry: [
            RoutePoint(lat: 46, lon: 11, distanceFromStart: 0),
            RoutePoint(lat: 46.01, lon: 11.01, distanceFromStart: 1200),
          ],
        ),
      );
      final challenge = await repositories.challenges.createLocalChallenge(
        id: 'challenge-1',
        segmentId: segment.id,
        name: 'Local challenge',
      );

      await repositories.sync.enqueueOutgoingEvent(
        id: 'event-1',
        eventType: 'org.ralroads.segment.created.v1',
        entityId: segment.id,
        payloadJson: '{}',
      );
      final dueEvents = await repositories.sync.listDueEvents(DateTime.now());

      expect(challenge.segmentId, segment.id);
      expect(dueEvents.single.id, 'event-1');
    },
  );
}
