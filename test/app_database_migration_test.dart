import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/models/pace_note.dart';
import 'package:ralroads/models/road_warning.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/models/saved_route.dart';
import 'package:ralroads/models/speed_limit_segment.dart';
import 'package:ralroads/services/saved_route_migration_service.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('creates the versioned Drift schema', () async {
    expect(database.schemaVersion, 1);
    expect(await database.savedRouteCount(), 0);
  });

  test(
    'migrates saved routes idempotently without duplicate child rows',
    () async {
      final route = SavedRoute(
        id: 'route-1',
        name: 'Morning loop',
        createdAt: DateTime.utc(2026, 6, 7, 8),
        totalDistance: 1200,
        startName: 'Start',
        destinationName: 'Finish',
        points: const [
          RoutePoint(lat: 46.0, lon: 11.0, distanceFromStart: 0, heading: 90),
          RoutePoint(
            lat: 46.001,
            lon: 11.002,
            distanceFromStart: 1200,
            heading: 110,
            elevation: 500,
          ),
        ],
        pacenotes: const [
          PaceNote(
            id: 'note-1',
            distanceFromStart: 300,
            direction: 'right',
            severity: 3,
            text: 'Right 3',
            type: PaceNoteType.right,
          ),
        ],
        roadWarnings: const [
          RoadWarning(
            id: 'warning-1',
            type: RoadWarningType.speedBump,
            lat: 46.0005,
            lon: 11.001,
            distanceFromStart: 600,
            text: 'Speed bump',
          ),
        ],
        speedLimitSegments: const [
          SpeedLimitSegment(
            id: 'limit-1',
            startDistance: 0,
            endDistance: 1200,
            rawMaxspeed: '50',
            parsedKmh: 50,
          ),
        ],
      );

      final migration = SavedRouteMigrationService(database);

      expect(await migration.migrateSavedRoutes([route]), 1);
      expect(await migration.migrateSavedRoutes([route]), 1);

      expect(await database.savedRouteCount(), 1);
      expect(
        await database.select(database.savedRoutePoints).get(),
        hasLength(2),
      );
      expect(await database.select(database.pacenoteRows).get(), hasLength(1));
      expect(
        await database.select(database.roadWarningRows).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.speedLimitSegmentRows).get(),
        hasLength(1),
      );
    },
  );
}
