import 'package:drift/drift.dart';
import '../database/app_database.dart';

class DirectoryRepository {
  DirectoryRepository(this.database);

  final AppDatabase database;

  Future<void> cacheDirectoryEvent({
    required String id,
    required String roomId,
    required String eventType,
    required String entityId,
    required String payloadJson,
    required DateTime originTimestamp,
  }) {
    return database
        .into(database.cachedDirectoryEvents)
        .insertOnConflictUpdate(
          CachedDirectoryEventsCompanion(
            id: Value(id),
            roomId: Value(roomId),
            eventType: Value(eventType),
            entityId: Value(entityId),
            payloadJson: Value(payloadJson),
            originTimestamp: Value(originTimestamp),
            ingestedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<List<CachedDirectoryEvent>> getEventsForRoom(String roomId) {
    return (database.select(database.cachedDirectoryEvents)
          ..where((row) => row.roomId.equals(roomId))
          ..orderBy([(row) => OrderingTerm.desc(row.originTimestamp)]))
        .get();
  }
}
