import 'package:drift/drift.dart';
import '../database/app_database.dart';

class ModerationRepository {
  ModerationRepository(this.database);

  final AppDatabase database;

  // Report content
  Future<void> reportContent({
    required String id,
    required String targetType,
    required String targetId,
    required String reason,
    String? reporterProfileId,
  }) {
    final now = DateTime.now();
    return database.into(database.reports).insertOnConflictUpdate(
      ReportsCompanion(
        id: Value(id),
        targetType: Value(targetType),
        targetId: Value(targetId),
        reason: Value(reason),
        status: const Value('pending'),
        reporterProfileId: Value(reporterProfileId),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  // Block a user
  Future<void> blockUser({
    required String id,
    required String matrixUserId,
    String? reason,
  }) {
    return database.into(database.blockedUsers).insertOnConflictUpdate(
      BlockedUsersCompanion(
        id: Value(id),
        matrixUserId: Value(matrixUserId),
        reason: Value(reason),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  // Unblock a user
  Future<void> unblockUser(String matrixUserId) {
    return (database.delete(database.blockedUsers)
          ..where((row) => row.matrixUserId.equals(matrixUserId)))
        .go();
  }

  // Check if a user is blocked
  Future<bool> isUserBlocked(String matrixUserId) async {
    final res = await (database.select(database.blockedUsers)
          ..where((row) => row.matrixUserId.equals(matrixUserId)))
        .getSingleOrNull();
    return res != null;
  }

  // Check if an entity is moderated (e.g. banned or hidden)
  Future<bool> isContentModerated(String targetType, String targetId) async {
    final res = await (database.select(database.moderationState)
          ..where((row) => row.targetType.equals(targetType) & row.targetId.equals(targetId)))
        .getSingleOrNull();
    if (res == null) return false;
    // Check expiration if set
    if (res.expiresAt != null && DateTime.now().isAfter(res.expiresAt!)) {
      return false;
    }
    return res.action == 'banned' || res.action == 'hidden';
  }

  // Apply moderation action (banned/hidden)
  Future<void> applyModerationAction({
    required String id,
    required String targetType,
    required String targetId,
    required String action,
    String? reason,
    DateTime? expiresAt,
  }) {
    return database.into(database.moderationState).insertOnConflictUpdate(
      ModerationStateCompanion(
        id: Value(id),
        targetType: Value(targetType),
        targetId: Value(targetId),
        action: Value(action),
        reason: Value(reason),
        expiresAt: Value(expiresAt),
        createdAt: Value(DateTime.now()),
      ),
    );
  }
}
