import '../database/app_database.dart';
import '../repositories/notification_repository.dart';

class BadgeService {
  BadgeService({required this.database, required this.notifications});

  final AppDatabase database;
  final NotificationRepository notifications;

  /// Reviews attempts for the profile and awards gamification badges if they meet the rules.
  Future<void> checkAndAwardBadges(String profileId) async {
    final attempts = await (database.select(
      database.segmentAttempts,
    )..where((row) => row.profileId.equals(profileId))).get();

    final cleanAttempts = attempts
        .where((a) => a.status == 'validClean' || a.status == 'valid_clean')
        .toList();

    // 1. Check "First Clean Run" badge
    if (cleanAttempts.isNotEmpty) {
      await _awardBadge(
        id: 'badge_first_clean',
        title: 'First Clean Run',
        body:
            'Congratulations! You completed your first clean segment attempt.',
      );
    }

    // 2. Check "Frequent Flyer" badge (5 or more attempts)
    if (attempts.length >= 5) {
      await _awardBadge(
        id: 'badge_frequent_flyer',
        title: 'Frequent Flyer',
        body: 'Awesome! You have completed 5 or more segment attempts.',
      );
    }
  }

  Future<void> _awardBadge({
    required String id,
    required String title,
    required String body,
  }) async {
    final exists = await (database.select(
      database.localNotifications,
    )..where((row) => row.id.equals(id))).getSingleOrNull();

    if (exists == null) {
      await notifications.createNotification(
        id: id,
        type: 'badge_earned',
        title: title,
        body: body,
      );
    }
  }
}
