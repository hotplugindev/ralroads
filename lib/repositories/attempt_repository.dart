import 'dart:math' as math;
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'trip_repository.dart';

class AttemptValidationInput {
  const AttemptValidationInput({
    required this.id,
    required this.attemptId,
    required this.engineVersion,
    required this.status,
    required this.resultHash,
    this.durationSeconds,
    this.routeMatchScore,
    this.gpsQualityScore,
    this.reasonsJson,
  });

  final String id;
  final String attemptId;
  final String engineVersion;
  final String status;
  final String resultHash;
  final double? durationSeconds;
  final double? routeMatchScore;
  final double? gpsQualityScore;
  final String? reasonsJson;
}

class AttemptRepository {
  AttemptRepository(this.database);

  final AppDatabase database;

  Future<void> createAttempt({
    required String id,
    required String segmentId,
    required DateTime startedAt,
    String? tripId,
    String? profileId,
  }) {
    final now = DateTime.now();
    return database
        .into(database.segmentAttempts)
        .insertOnConflictUpdate(
          SegmentAttemptsCompanion(
            id: Value(id),
            segmentId: Value(segmentId),
            tripId: Value(tripId),
            profileId: Value(profileId),
            startedAt: Value(startedAt),
            status: const Value('recording'),
            officialEligible: const Value(false),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> appendAttemptPoints(
    String attemptId,
    List<TripRecordingPoint> points,
  ) async {
    if (points.isEmpty) return;

    final zones = await database.select(database.privateZones).get();

    bool isInZone(double lat, double lon) {
      const earthRadius = 6371000.0;
      for (final zone in zones) {
        final dLat = (zone.lat - lat) * 3.141592653589793 / 180.0;
        final dLon = (zone.lon - lon) * 3.141592653589793 / 180.0;
        final rLat1 = lat * 3.141592653589793 / 180.0;
        final rLat2 = zone.lat * 3.141592653589793 / 180.0;
        final a =
            math.sin(dLat / 2) * math.sin(dLat / 2) +
            math.cos(rLat1) *
                math.cos(rLat2) *
                math.sin(dLon / 2) *
                math.sin(dLon / 2);
        final distance =
            earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
        if (distance <= zone.radiusMeters) {
          return true;
        }
      }
      return false;
    }

    final filteredPoints = points
        .where((p) => !isInZone(p.lat, p.lon))
        .toList();
    if (filteredPoints.isEmpty) return;

    final existing = await (database.select(
      database.attemptPoints,
    )..where((row) => row.attemptId.equals(attemptId))).get();
    final startIndex = existing.length;

    await database.batch((batch) {
      batch.insertAll(database.attemptPoints, [
        for (final point in filteredPoints.indexed)
          AttemptPointsCompanion.insert(
            attemptId: attemptId,
            pointIndex: startIndex + point.$1,
            recordedAt: point.$2.recordedAt,
            lat: point.$2.lat,
            lon: point.$2.lon,
            speedMps: Value(point.$2.speedMps),
            accuracyMeters: Value(point.$2.accuracyMeters),
            speedLimitKmh: Value(point.$2.speedLimitKmh),
            speedCompliant: Value(point.$2.speedCompliant),
          ),
      ]);
    });
  }

  Future<void> finishAttempt({
    required String attemptId,
    required DateTime finishedAt,
    required String status,
    bool officialEligible = false,
  }) {
    return (database.update(
      database.segmentAttempts,
    )..where((row) => row.id.equals(attemptId))).write(
      SegmentAttemptsCompanion(
        finishedAt: Value(finishedAt),
        status: Value(status),
        officialEligible: Value(officialEligible),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> persistValidationResult(AttemptValidationInput input) {
    return database
        .into(database.localValidationResults)
        .insertOnConflictUpdate(
          LocalValidationResultsCompanion(
            id: Value(input.id),
            attemptId: Value(input.attemptId),
            engineVersion: Value(input.engineVersion),
            status: Value(input.status),
            durationSeconds: Value(input.durationSeconds),
            routeMatchScore: Value(input.routeMatchScore),
            gpsQualityScore: Value(input.gpsQualityScore),
            resultHash: Value(input.resultHash),
            reasonsJson: Value(input.reasonsJson),
            createdAt: Value(DateTime.now()),
          ),
        );
  }

  Future<List<SegmentAttempt>> listAttemptsForSegment(String segmentId) {
    return (database.select(database.segmentAttempts)
          ..where((row) => row.segmentId.equals(segmentId))
          ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
        .get();
  }

  Future<List<SegmentAttempt>> listPersonalAttempts(String profileId) {
    return (database.select(database.segmentAttempts)
          ..where((row) => row.profileId.equals(profileId))
          ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
        .get();
  }

  Future<void> deleteAttempt(String attemptId) async {
    await database.transaction(() async {
      await (database.delete(
        database.attemptPoints,
      )..where((row) => row.attemptId.equals(attemptId))).go();
      await (database.delete(
        database.localValidationResults,
      )..where((row) => row.attemptId.equals(attemptId))).go();
      await (database.delete(
        database.segmentAttempts,
      )..where((row) => row.id.equals(attemptId))).go();
    });
  }
}
