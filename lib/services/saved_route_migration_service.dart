import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/saved_route.dart';

class SavedRouteMigrationService {
  SavedRouteMigrationService(this.database);

  final AppDatabase database;

  Future<int> migrateSavedRoutes(Iterable<SavedRoute> routes) async {
    var migrated = 0;
    final now = DateTime.now();

    await database.transaction(() async {
      for (final route in routes) {
        await database
            .into(database.savedRouteRecords)
            .insertOnConflictUpdate(
              SavedRouteRecordsCompanion(
                id: Value(route.id),
                name: Value(route.name),
                createdAt: Value(route.createdAt),
                totalDistance: Value(route.totalDistance),
                startName: Value(route.startName),
                destinationName: Value(route.destinationName),
                migratedAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        await _replaceRouteDetails(route);
        migrated++;
      }
    });

    return migrated;
  }

  Future<void> _replaceRouteDetails(SavedRoute route) async {
    await (database.delete(
      database.speedLimitSegmentRows,
    )..where((row) => row.routeId.equals(route.id))).go();
    await (database.delete(
      database.roadWarningRows,
    )..where((row) => row.routeId.equals(route.id))).go();
    await (database.delete(
      database.pacenoteRows,
    )..where((row) => row.routeId.equals(route.id))).go();
    await (database.delete(
      database.savedRoutePoints,
    )..where((row) => row.routeId.equals(route.id))).go();

    await database.batch((batch) {
      batch.insertAll(database.savedRoutePoints, [
        for (final entry in route.points.indexed)
          SavedRoutePointsCompanion.insert(
            routeId: route.id,
            pointIndex: entry.$1,
            lat: entry.$2.lat,
            lon: entry.$2.lon,
            elevation: Value(entry.$2.elevation),
            distanceFromStart: entry.$2.distanceFromStart,
            heading: entry.$2.heading,
            curvature: 0,
          ),
      ]);

      batch.insertAll(database.pacenoteRows, [
        for (final note in route.pacenotes)
          PacenoteRowsCompanion.insert(
            id: note.id,
            routeId: route.id,
            distanceFromStart: note.distanceFromStart,
            direction: note.direction,
            severity: note.severity,
            type: note.type.name,
            textValue: note.text,
            tightens: Value(note.tightens),
            opens: Value(note.opens),
            recommendedSpeedKmh: Value(note.recommendedSpeedKmh),
            isShort: Value(note.isShort),
            isLong: Value(note.isLong),
            distanceMeters: Value(note.distanceMeters),
            intoNoteId: Value(note.intoNoteId),
            startDistance: Value(note.startDistance),
            endDistance: Value(note.endDistance),
          ),
      ]);

      batch.insertAll(database.roadWarningRows, [
        for (final warning in route.roadWarnings)
          RoadWarningRowsCompanion.insert(
            id: warning.id,
            routeId: route.id,
            distanceFromStart: warning.distanceFromStart,
            lat: warning.lat,
            lon: warning.lon,
            type: warning.type.name,
            textValue: warning.text,
            tagsJson: Value(jsonEncode(warning.tags)),
          ),
      ]);

      batch.insertAll(database.speedLimitSegmentRows, [
        for (final segment in route.speedLimitSegments)
          SpeedLimitSegmentRowsCompanion.insert(
            id: segment.id,
            routeId: route.id,
            startDistance: segment.startDistance,
            endDistance: segment.endDistance,
            rawMaxspeed: segment.rawMaxspeed,
            parsedKmh: Value(segment.parsedKmh),
            tagsJson: Value(jsonEncode(segment.tags)),
          ),
      ]);
    });
  }
}
