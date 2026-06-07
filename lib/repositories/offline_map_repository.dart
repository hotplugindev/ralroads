import 'package:drift/drift.dart';

import '../database/app_database.dart';

class OfflineMapRepository {
  OfflineMapRepository(this.database);

  final AppDatabase database;

  Future<List<OfflineMapRegion>> listRegions() {
    return (database.select(
      database.offlineMapRegions,
    )..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).get();
  }

  Future<void> upsertRegion({
    required String id,
    required String name,
    required String provider,
    required String status,
    String? uri,
    int sizeBytes = 0,
  }) {
    return database
        .into(database.offlineMapRegions)
        .insertOnConflictUpdate(
          OfflineMapRegionsCompanion(
            id: Value(id),
            name: Value(name),
            provider: Value(provider),
            uri: Value(uri),
            sizeBytes: Value(sizeBytes),
            status: Value(status),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
