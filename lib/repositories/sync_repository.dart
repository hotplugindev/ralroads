import 'package:drift/drift.dart';

import '../database/app_database.dart';

class SyncRepository {
  SyncRepository(this.database);

  final AppDatabase database;

  Future<void> enqueueOutgoingEvent({
    required String id,
    required String eventType,
    required String entityId,
    required String payloadJson,
    String? roomId,
  }) {
    final now = DateTime.now();
    return database
        .into(database.outgoingMatrixEvents)
        .insertOnConflictUpdate(
          OutgoingMatrixEventsCompanion(
            id: Value(id),
            eventType: Value(eventType),
            roomId: Value(roomId),
            entityId: Value(entityId),
            payloadJson: Value(payloadJson),
            state: const Value('queued'),
            attemptCount: const Value(0),
            nextAttemptAt: Value(now),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> markEventState(
    String id,
    String state, {
    DateTime? nextAttemptAt,
  }) {
    return (database.update(
      database.outgoingMatrixEvents,
    )..where((row) => row.id.equals(id))).write(
      OutgoingMatrixEventsCompanion(
        state: Value(state),
        nextAttemptAt: Value(nextAttemptAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markEventFailedWithRetry(String id, Duration delay) async {
    final event = await (database.select(
      database.outgoingMatrixEvents,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (event == null) return;
    await (database.update(
      database.outgoingMatrixEvents,
    )..where((row) => row.id.equals(id))).write(
      OutgoingMatrixEventsCompanion(
        state: const Value('failed'),
        attemptCount: Value(event.attemptCount + 1),
        nextAttemptAt: Value(DateTime.now().add(delay)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<OutgoingMatrixEvent>> listDueEvents(DateTime now) async {
    final queued =
        await (database.select(database.outgoingMatrixEvents)
              ..where(
                (row) =>
                    row.state.equals('queued') |
                    row.state.equals('failed') |
                    row.state.equals('sending'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    return [
      for (final event in queued)
        if (event.nextAttemptAt == null || !event.nextAttemptAt!.isAfter(now))
          event,
    ];
  }

  Future<void> enqueuePendingMediaUpload({
    required String id,
    required String localPath,
    required String sha256,
    required int sizeBytes,
  }) {
    final now = DateTime.now();
    return database
        .into(database.pendingMediaUploads)
        .insertOnConflictUpdate(
          PendingMediaUploadsCompanion(
            id: Value(id),
            localPath: Value(localPath),
            sha256: Value(sha256),
            sizeBytes: Value(sizeBytes),
            state: const Value('queued'),
            attemptCount: const Value(0),
            nextAttemptAt: Value(now),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<List<PendingMediaUpload>> listDueMediaUploads(DateTime now) async {
    final queued = await (database.select(database.pendingMediaUploads)
          ..where((row) =>
              row.state.equals('queued') |
              row.state.equals('failed') |
              row.state.equals('uploading'))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
    return [
      for (final media in queued)
        if (media.nextAttemptAt == null || !media.nextAttemptAt!.isAfter(now))
          media,
    ];
  }

  Future<void> markMediaState(
    String id,
    String state, {
    String? matrixUri,
    DateTime? nextAttemptAt,
  }) {
    return (database.update(database.pendingMediaUploads)
          ..where((row) => row.id.equals(id)))
        .write(
          PendingMediaUploadsCompanion(
            state: Value(state),
            matrixUri: matrixUri == null ? const Value.absent() : Value(matrixUri),
            nextAttemptAt: Value(nextAttemptAt),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> markMediaFailedWithRetry(String id, Duration delay) async {
    final media = await (database.select(database.pendingMediaUploads)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (media == null) return;
    await (database.update(database.pendingMediaUploads)
          ..where((row) => row.id.equals(id)))
        .write(
          PendingMediaUploadsCompanion(
            state: const Value('failed'),
            attemptCount: Value(media.attemptCount + 1),
            nextAttemptAt: Value(DateTime.now().add(delay)),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> saveSyncCursor(String scope, String? cursor) {
    return database.into(database.matrixSyncCursors).insertOnConflictUpdate(
      MatrixSyncCursorsCompanion(
        id: Value(scope),
        scope: Value(scope),
        cursor: Value(cursor),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<String?> getSyncCursor(String scope) async {
    final row = await (database.select(database.matrixSyncCursors)
          ..where((row) => row.scope.equals(scope)))
        .getSingleOrNull();
    return row?.cursor;
  }

  Stream<int> watchPendingSyncCount() {
    final query = database.select(database.outgoingMatrixEvents)
      ..where((row) =>
          row.state.equals('queued') |
          row.state.equals('failed') |
          row.state.equals('sending'));
    return query.watch().map((rows) => rows.length);
  }
}
