import 'dart:math' as math;
import 'package:drift/drift.dart';

import '../database/app_database.dart';

class TripRecordingPoint {
  const TripRecordingPoint({
    required this.recordedAt,
    required this.lat,
    required this.lon,
    this.altitudeMeters,
    this.accuracyMeters,
    this.speedMps,
    this.headingDegrees,
    this.matchedEdgeId,
    this.speedLimitKmh,
    this.speedCompliant,
    this.mockLocation,
    this.distanceFromStart,
  });

  final DateTime recordedAt;
  final double lat;
  final double lon;
  final double? altitudeMeters;
  final double? accuracyMeters;
  final double? speedMps;
  final double? headingDegrees;
  final String? matchedEdgeId;
  final int? speedLimitKmh;
  final bool? speedCompliant;
  final bool? mockLocation;
  final double? distanceFromStart;
}

class TripSummary {
  const TripSummary({
    required this.id,
    required this.startedAt,
    required this.distanceMeters,
    required this.status,
    required this.cleanEligible,
    this.name,
    this.endedAt,
  });

  final String id;
  final String? name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceMeters;
  final String status;
  final bool cleanEligible;
}

class TripStats {
  const TripStats({
    required this.totalTrips,
    required this.totalDistanceMeters,
    required this.cleanEligibleTrips,
  });

  final int totalTrips;
  final double totalDistanceMeters;
  final int cleanEligibleTrips;
}

class TripPointStats {
  const TripPointStats({
    required this.pointCount,
    required this.averageGpsAccuracyMeters,
    required this.speedLimitCoverage,
  });

  final int pointCount;
  final double? averageGpsAccuracyMeters;
  final double speedLimitCoverage;
}

class TripRepository {
  TripRepository(this.database);

  final AppDatabase database;

  Future<void> startTrip({
    required String id,
    required DateTime startedAt,
    String? name,
  }) {
    return database
        .into(database.trips)
        .insert(
          TripsCompanion.insert(
            id: id,
            name: Value(name),
            startedAt: startedAt,
            updatedAt: startedAt,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> updateTripProgress({
    required String tripId,
    required double distanceMeters,
    required bool cleanEligible,
    String status = 'recording',
  }) {
    return (database.update(
      database.trips,
    )..where((row) => row.id.equals(tripId))).write(
      TripsCompanion(
        distanceMeters: Value(distanceMeters),
        cleanEligible: Value(cleanEligible),
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> pauseTrip(String tripId) {
    return updateTripStatus(tripId, 'paused');
  }

  Future<void> resumeTrip(String tripId) {
    return updateTripStatus(tripId, 'recording');
  }

  Future<void> updateTripStatus(String tripId, String status) {
    return (database.update(
      database.trips,
    )..where((row) => row.id.equals(tripId))).write(
      TripsCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> renameTrip(String tripId, String name) {
    return (database.update(
      database.trips,
    )..where((row) => row.id.equals(tripId))).write(
      TripsCompanion(name: Value(name), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> updatePrivacy(String tripId, String privacy) {
    return (database.update(
      database.trips,
    )..where((row) => row.id.equals(tripId))).write(
      TripsCompanion(privacy: Value(privacy), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> deleteTrip(String tripId) async {
    await database.transaction(() async {
      await (database.delete(
        database.tripPoints,
      )..where((row) => row.tripId.equals(tripId))).go();
      await (database.delete(
        database.trips,
      )..where((row) => row.id.equals(tripId))).go();
    });
  }


  Future<void> appendTripPoints(
    String tripId,
    List<TripRecordingPoint> points,
  ) async {
    if (points.isEmpty) {
      return;
    }

    await database.transaction(() async {
      final zones = await database.select(database.privateZones).get();

      bool isInZone(double lat, double lon) {
        const earthRadius = 6371000.0;
        for (final zone in zones) {
          final dLat = (zone.lat - lat) * 3.141592653589793 / 180.0;
          final dLon = (zone.lon - lon) * 3.141592653589793 / 180.0;
          final rLat1 = lat * 3.141592653589793 / 180.0;
          final rLat2 = zone.lat * 3.141592653589793 / 180.0;
          final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(rLat1) *
                  math.cos(rLat2) *
                  math.sin(dLon / 2) *
                  math.sin(dLon / 2);
          final distance = earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
          if (distance <= zone.radiusMeters) {
            return true;
          }
        }
        return false;
      }

      final filteredPoints = points.where((p) => !isInZone(p.lat, p.lon)).toList();
      if (filteredPoints.isEmpty) {
        return;
      }

      final existing = await (database.select(
        database.tripPoints,
      )..where((row) => row.tripId.equals(tripId))).get();
      final startIndex = existing.length;

      await database.batch((batch) {
        batch.insertAll(database.tripPoints, [
          for (final entry in filteredPoints.indexed)
            TripPointsCompanion.insert(
              tripId: tripId,
              pointIndex: startIndex + entry.$1,
              recordedAt: entry.$2.recordedAt,
              lat: entry.$2.lat,
              lon: entry.$2.lon,
              altitudeMeters: Value(entry.$2.altitudeMeters),
              accuracyMeters: Value(entry.$2.accuracyMeters),
              speedMps: Value(entry.$2.speedMps),
              headingDegrees: Value(entry.$2.headingDegrees),
              matchedEdgeId: Value(entry.$2.matchedEdgeId),
              speedLimitKmh: Value(entry.$2.speedLimitKmh),
              speedCompliant: Value(entry.$2.speedCompliant),
              mockLocation: Value(entry.$2.mockLocation),
              distanceFromStart: Value(entry.$2.distanceFromStart),
            ),
        ]);
      });
    });
  }

  Future<void> finishTrip({
    required String tripId,
    required DateTime endedAt,
    required double distanceMeters,
    required bool cleanEligible,
  }) {
    return (database.update(
      database.trips,
    )..where((row) => row.id.equals(tripId))).write(
      TripsCompanion(
        endedAt: Value(endedAt),
        distanceMeters: Value(distanceMeters),
        cleanEligible: Value(cleanEligible),
        status: const Value('finished'),
        updatedAt: Value(endedAt),
      ),
    );
  }

  Future<List<TripSummary>> recentTrips({int limit = 50}) async {
    final rows =
        await (database.select(database.trips)
              ..orderBy([
                (row) => OrderingTerm(
                  expression: row.startedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(limit))
            .get();

    return [
      for (final row in rows)
        TripSummary(
          id: row.id,
          name: row.name,
          startedAt: row.startedAt,
          endedAt: row.endedAt,
          distanceMeters: row.distanceMeters,
          status: row.status,
          cleanEligible: row.cleanEligible,
        ),
    ];
  }

  Future<TripSummary?> getTrip(String tripId) async {
    final row = await (database.select(
      database.trips,
    )..where((trip) => trip.id.equals(tripId))).getSingleOrNull();
    if (row == null) return null;
    return TripSummary(
      id: row.id,
      name: row.name,
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      distanceMeters: row.distanceMeters,
      status: row.status,
      cleanEligible: row.cleanEligible,
    );
  }

  Future<TripSummary?> activeTrip() async {
    final row =
        await (database.select(database.trips)
              ..where(
                (trip) =>
                    trip.status.equals('recording') |
                    trip.status.equals('paused'),
              )
              ..orderBy([(trip) => OrderingTerm.desc(trip.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return TripSummary(
      id: row.id,
      name: row.name,
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      distanceMeters: row.distanceMeters,
      status: row.status,
      cleanEligible: row.cleanEligible,
    );
  }

  Future<List<TripPoint>> pointsForTrip(String tripId) {
    return (database.select(database.tripPoints)
          ..where((point) => point.tripId.equals(tripId))
          ..orderBy([(point) => OrderingTerm.asc(point.pointIndex)]))
        .get();
  }

  Future<TripPointStats> pointStats(String tripId) async {
    final points = await pointsForTrip(tripId);
    final accuracyValues = points
        .map((point) => point.accuracyMeters)
        .whereType<double>()
        .toList();
    final speedLimitPoints = points
        .where((point) => point.speedLimitKmh != null)
        .length;
    return TripPointStats(
      pointCount: points.length,
      averageGpsAccuracyMeters: accuracyValues.isEmpty
          ? null
          : accuracyValues.reduce((a, b) => a + b) / accuracyValues.length,
      speedLimitCoverage: points.isEmpty ? 0 : speedLimitPoints / points.length,
    );
  }

  Future<TripStats> stats() async {
    final rows = await database.select(database.trips).get();
    return TripStats(
      totalTrips: rows.length,
      totalDistanceMeters: rows.fold<double>(
        0,
        (sum, trip) => sum + trip.distanceMeters,
      ),
      cleanEligibleTrips: rows.where((trip) => trip.cleanEligible).length,
    );
  }

  Stream<List<TripSummary>> watchTrips({int limit = 50}) {
    final query = database.select(database.trips)
      ..orderBy([
        (row) => OrderingTerm(
              expression: row.startedAt,
              mode: OrderingMode.desc,
            ),
      ])
      ..limit(limit);
    return query.watch().map((rows) => [
          for (final row in rows)
            TripSummary(
              id: row.id,
              name: row.name,
              startedAt: row.startedAt,
              endedAt: row.endedAt,
              distanceMeters: row.distanceMeters,
              status: row.status,
              cleanEligible: row.cleanEligible,
            ),
        ]);
  }

  Stream<TripSummary?> watchTrip(String tripId) {
    final query = database.select(database.trips)
      ..where((trip) => trip.id.equals(tripId));
    return query.watchSingleOrNull().map((row) {
      if (row == null) return null;
      return TripSummary(
        id: row.id,
        name: row.name,
        startedAt: row.startedAt,
        endedAt: row.endedAt,
        distanceMeters: row.distanceMeters,
        status: row.status,
        cleanEligible: row.cleanEligible,
      );
    });
  }

  Stream<TripStats> watchStats() {
    final query = database.select(database.trips);
    return query.watch().map((rows) {
      return TripStats(
        totalTrips: rows.length,
        totalDistanceMeters: rows.fold<double>(
          0,
          (sum, trip) => sum + trip.distanceMeters,
        ),
        cleanEligibleTrips: rows.where((trip) => trip.cleanEligible).length,
      );
    });
  }
}
