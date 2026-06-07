import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/repositories/app_repositories.dart';
import 'package:ralroads/repositories/profile_repository.dart';
import 'package:ralroads/repositories/attempt_repository.dart';
import 'package:ralroads/repositories/trip_repository.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/repositories/segment_repository.dart';
import 'package:ralroads/services/route_storage_service.dart';
import 'package:ralroads/services/badge_service.dart';

void main() {
  group('Social, Moderation, Privacy Zones, and Badges', () {
    late AppDatabase database;
    late AppRepositories repositories;
    late BadgeService badgeService;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      repositories = AppRepositories(
        routeStorage: RouteStorageService(),
        database: database,
      );
      badgeService = BadgeService(
        database: database,
        notifications: repositories.notifications,
      );

      // Create a segment for foreign key constraints in attempts
      await repositories.segments.createLocalSegment(
        const LocalSegmentInput(
          id: 'seg-1',
          versionId: 'seg-version-1',
          name: 'Test Segment',
          distanceMeters: 1000,
          safetyStatus: 'suitable',
          contentHash: 'hash-1',
          geometry: [
            RoutePoint(lat: 46.0, lon: 11.0, distanceFromStart: 0),
          ],
        ),
      );

      // Create a driver profile
      await repositories.profiles.createOrUpdateLocalProfile(
        const LocalProfileInput(id: 'prof-1', displayName: 'Driver'),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('Privacy Zones: Filters out coordinates inside zone', () async {
      // 1. Create a privacy zone around Lat: 46.0, Lon: 11.0, Radius: 200m
      await repositories.privacy.createPrivateZone(
        id: 'zone-1',
        name: 'Home Zone',
        lat: 46.0,
        lon: 11.0,
        radiusMeters: 200.0,
      );

      // 2. Check points
      // Lat 46.0, Lon 11.0 is exactly the center (0m away -> inside)
      final insideCenter = await repositories.privacy.isPointInPrivacyZone(46.0, 11.0);
      // Lat 46.1, Lon 11.1 is ~13km away -> outside
      final outsideFar = await repositories.privacy.isPointInPrivacyZone(46.1, 11.1);

      expect(insideCenter, isTrue);
      expect(outsideFar, isFalse);

      // 3. Insert Trip points
      await repositories.trips.startTrip(id: 'trip-1', startedAt: DateTime.now());
      await repositories.trips.appendTripPoints('trip-1', [
        TripRecordingPoint(
          recordedAt: DateTime.now(),
          lat: 46.0,
          lon: 11.0, // inside -> should be redacted/dropped
        ),
        TripRecordingPoint(
          recordedAt: DateTime.now().add(const Duration(seconds: 1)),
          lat: 46.1,
          lon: 11.1, // outside -> should be stored
        ),
      ]);

      final tripPoints = await (database.select(database.tripPoints)
            ..where((row) => row.tripId.equals('trip-1')))
          .get();

      // Only the outside point should be stored
      expect(tripPoints, hasLength(1));
      expect(tripPoints.first.lat, 46.1);
      expect(tripPoints.first.lon, 11.1);
    });

    test('Moderation: Handles reports, user blocking, and content moderation', () async {
      // 1. Content Reporting
      await repositories.moderation.reportContent(
        id: 'rep-1',
        targetType: 'attempt',
        targetId: 'att-123',
        reason: 'Cheating',
        reporterProfileId: 'prof-1',
      );

      final reports = await database.select(database.reports).get();
      expect(reports, hasLength(1));
      expect(reports.first.targetId, 'att-123');
      expect(reports.first.reason, 'Cheating');

      // 2. User Blocking
      expect(await repositories.moderation.isUserBlocked('@baduser:matrix.org'), isFalse);

      await repositories.moderation.blockUser(
        id: 'block-1',
        matrixUserId: '@baduser:matrix.org',
        reason: 'Spamming',
      );
      expect(await repositories.moderation.isUserBlocked('@baduser:matrix.org'), isTrue);

      await repositories.moderation.unblockUser('@baduser:matrix.org');
      expect(await repositories.moderation.isUserBlocked('@baduser:matrix.org'), isFalse);

      // 3. Action State
      expect(await repositories.moderation.isContentModerated('attempt', 'att-123'), isFalse);

      await repositories.moderation.applyModerationAction(
        id: 'action-1',
        targetType: 'attempt',
        targetId: 'att-123',
        action: 'banned',
        reason: 'Confirmed GPS spoofing',
      );
      expect(await repositories.moderation.isContentModerated('attempt', 'att-123'), isTrue);
    });

    test('Notifications: CRUD local notifications', () async {
      // Create notification
      await repositories.notifications.createNotification(
        id: 'notif-1',
        type: 'friend_request',
        title: 'New Friend Request',
        body: 'User @alice:matrix.org wants to be friends.',
      );

      final unread = await repositories.notifications.getUnreadNotifications();
      expect(unread, hasLength(1));
      expect(unread.first.id, 'notif-1');

      // Mark read
      await repositories.notifications.markAsRead('notif-1');
      final unreadAfter = await repositories.notifications.getUnreadNotifications();
      expect(unreadAfter, isEmpty);
    });

    test('BadgeService: Awards badges based on achievements', () async {
      // Initially, no notifications
      expect(await repositories.notifications.getUnreadNotifications(), isEmpty);

      // 1. Create a non-clean attempt
      await repositories.attempts.createAttempt(
        id: 'att-first',
        segmentId: 'seg-1',
        startedAt: DateTime.now(),
        profileId: 'prof-1',
      );
      await badgeService.checkAndAwardBadges('prof-1');
      // No clean attempts yet -> no badges
      expect(await repositories.notifications.getUnreadNotifications(), isEmpty);

      // 2. Add a clean attempt
      await repositories.attempts.persistValidationResult(
        AttemptValidationInput(
          id: 'val-1',
          attemptId: 'att-first',
          engineVersion: '0.1.0',
          status: 'valid_clean',
          resultHash: 'hash-abc',
          durationSeconds: 120.0,
        ),
      );
      // Wait, we need the attempt status to be updated. `persistValidationResult` is normally followed by `verifyAndSaveAttestation`, or we can finish the attempt with clean status. Let's finish the attempt with 'valid_clean'.
      await repositories.attempts.finishAttempt(
        attemptId: 'att-first',
        finishedAt: DateTime.now().add(const Duration(minutes: 2)),
        status: 'valid_clean',
      );

      await badgeService.checkAndAwardBadges('prof-1');
      final unreadAfterClean = await repositories.notifications.getUnreadNotifications();
      expect(unreadAfterClean, hasLength(1));
      expect(unreadAfterClean.first.id, 'badge_first_clean');

      // Mark badge read
      await repositories.notifications.markAsRead('badge_first_clean');

      // 3. Complete 4 more attempts to reach 5 total
      for (var i = 2; i <= 5; i++) {
        await repositories.attempts.createAttempt(
          id: 'att-$i',
          segmentId: 'seg-1',
          startedAt: DateTime.now(),
          profileId: 'prof-1',
        );
        await repositories.attempts.finishAttempt(
          attemptId: 'att-$i',
          finishedAt: DateTime.now().add(const Duration(minutes: 2)),
          status: 'valid_clean',
        );
      }

      await badgeService.checkAndAwardBadges('prof-1');
      final unreadAfter5 = await repositories.notifications.getUnreadNotifications();
      expect(unreadAfter5, hasLength(1));
      expect(unreadAfter5.first.id, 'badge_frequent_flyer');
    });
  });
}
