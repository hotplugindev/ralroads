import 'package:drift/drift.dart';

import '../database/app_database.dart';

class CachedFriendRequestInput {
  const CachedFriendRequestInput({
    required this.id,
    required this.fromProfileId,
    required this.toProfileId,
    required this.state,
    this.roomId,
  });

  final String id;
  final String fromProfileId;
  final String toProfileId;
  final String state;
  final String? roomId;
}

class FriendRepository {
  FriendRepository(this.database);

  final AppDatabase database;

  Future<List<Friendship>> listCachedFriends(String profileId) {
    return (database.select(database.friendships)
          ..where(
            (row) =>
                (row.profileId.equals(profileId) |
                    row.friendProfileId.equals(profileId)) &
                row.state.equals('accepted'),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .get();
  }

  Future<List<FriendRequest>> listPendingRequests(String profileId) {
    return (database.select(database.friendRequests)
          ..where(
            (row) =>
                (row.fromProfileId.equals(profileId) |
                    row.toProfileId.equals(profileId)) &
                row.state.equals('pending'),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
        .get();
  }

  Stream<List<Friendship>> watchCachedFriends(String profileId) {
    return (database.select(database.friendships)
          ..where(
            (row) =>
                (row.profileId.equals(profileId) |
                    row.friendProfileId.equals(profileId)) &
                row.state.equals('accepted'),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .watch();
  }

  Stream<List<FriendRequest>> watchPendingRequests(String profileId) {
    return (database.select(database.friendRequests)
          ..where(
            (row) =>
                (row.fromProfileId.equals(profileId) |
                    row.toProfileId.equals(profileId)) &
                row.state.equals('pending'),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
        .watch();
  }

  Future<void> upsertFriend({
    required String id,
    required String profileId,
    required String friendProfileId,
    required String state,
  }) {
    final now = DateTime.now();
    return database
        .into(database.friendships)
        .insertOnConflictUpdate(
          FriendshipsCompanion(
            id: Value(id),
            profileId: Value(profileId),
            friendProfileId: Value(friendProfileId),
            state: Value(state),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> upsertRequest(CachedFriendRequestInput input) {
    final now = DateTime.now();
    return database
        .into(database.friendRequests)
        .insertOnConflictUpdate(
          FriendRequestsCompanion(
            id: Value(input.id),
            fromProfileId: Value(input.fromProfileId),
            toProfileId: Value(input.toProfileId),
            roomId: Value(input.roomId),
            state: Value(input.state),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> blockUser(String matrixUserId, {String? reason}) {
    return database
        .into(database.blockedUsers)
        .insertOnConflictUpdate(
          BlockedUsersCompanion(
            id: Value(matrixUserId),
            matrixUserId: Value(matrixUserId),
            reason: Value(reason),
            createdAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> unblockUser(String matrixUserId) {
    return (database.delete(
      database.blockedUsers,
    )..where((row) => row.matrixUserId.equals(matrixUserId))).go();
  }
}
