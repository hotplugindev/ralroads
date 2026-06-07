import 'package:drift/drift.dart';

import '../database/app_database.dart';

class GroupRepository {
  GroupRepository(this.database);

  final AppDatabase database;

  Future<List<Group>> listCachedGroups() {
    return (database.select(
      database.groups,
    )..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).get();
  }

  Stream<List<Group>> watchCachedGroups() {
    return (database.select(
      database.groups,
    )..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).watch();
  }

  Future<Group> createLocalDraftGroup({
    required String id,
    required String name,
    String? description,
  }) async {
    final now = DateTime.now();
    final roomId = 'local-room-$id';
    await database.transaction(() async {
      await database
          .into(database.rooms)
          .insertOnConflictUpdate(
            RoomsCompanion(
              id: Value(roomId),
              matrixRoomId: Value(roomId),
              type: const Value('local_group'),
              name: Value(name),
              encrypted: const Value(false),
              updatedAt: Value(now),
            ),
          );
      await database
          .into(database.groups)
          .insertOnConflictUpdate(
            GroupsCompanion(
              id: Value(id),
              roomId: Value(roomId),
              name: Value(name),
              description: Value(description),
              visibility: const Value('private'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });
    return (database.select(
      database.groups,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<Group> upsertMatrixGroup({
    required String id,
    required String roomId,
    required String name,
    String? description,
    String visibility = 'private',
    bool encrypted = false,
  }) async {
    final now = DateTime.now();
    await database.transaction(() async {
      await database
          .into(database.rooms)
          .insertOnConflictUpdate(
            RoomsCompanion(
              id: Value(roomId),
              matrixRoomId: Value(roomId),
              type: const Value('group'),
              name: Value(name),
              encrypted: Value(encrypted),
              updatedAt: Value(now),
            ),
          );
      await database
          .into(database.groups)
          .insertOnConflictUpdate(
            GroupsCompanion(
              id: Value(id),
              roomId: Value(roomId),
              name: Value(name),
              description: Value(description),
              visibility: Value(visibility),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });
    return (database.select(
      database.groups,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<void> updateCachedGroupMetadata({
    required String id,
    String? name,
    String? description,
    String? visibility,
  }) {
    return (database.update(
      database.groups,
    )..where((row) => row.id.equals(id))).write(
      GroupsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        description: description == null
            ? const Value.absent()
            : Value(description),
        visibility: visibility == null
            ? const Value.absent()
            : Value(visibility),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<GroupMember>> listMembers(String groupId) {
    return (database.select(
      database.groupMembers,
    )..where((row) => row.groupId.equals(groupId))).get();
  }
}
