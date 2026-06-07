import 'dart:math' as math;
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../services/device_identity_service.dart';
import 'trip_repository.dart';

class ValidatorAttestationInput {
  const ValidatorAttestationInput({
    required this.id,
    required this.attemptId,
    required this.validatorId,
    required this.validatorPublicKey,
    required this.status,
    required this.engineVersion,
    required this.resultHash,
    required this.signature,
  });

  final String id;
  final String attemptId;
  final String validatorId;
  final String validatorPublicKey;
  final String status;
  final String engineVersion;
  final String resultHash;
  final String signature;
}

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

  Future<void> saveAttestation(ValidatorAttestationInput input) async {
    await database.into(database.validatorAttestations).insertOnConflictUpdate(
      ValidatorAttestationsCompanion(
        id: Value(input.id),
        attemptId: Value(input.attemptId),
        validatorId: Value(input.validatorId),
        validatorPublicKey: Value(input.validatorPublicKey),
        status: Value(input.status),
        engineVersion: Value(input.engineVersion),
        resultHash: Value(input.resultHash),
        signature: Value(input.signature),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<ValidatorAttestation>> getAttestationsForAttempt(String attemptId) {
    return (database.select(database.validatorAttestations)
          ..where((row) => row.attemptId.equals(attemptId)))
        .get();
  }

  Future<bool> verifyAndSaveAttestation({
    required ValidatorAttestationInput input,
    required DeviceIdentityService identityService,
  }) async {
    final attempt = await (database.select(database.segmentAttempts)
          ..where((row) => row.id.equals(input.attemptId)))
        .getSingleOrNull();
    if (attempt == null) return false;

    final localResult = await (database.select(database.localValidationResults)
          ..where((row) => row.attemptId.equals(input.attemptId)))
        .getSingleOrNull();

    if (localResult != null && localResult.resultHash != input.resultHash) {
      return false;
    }

    final durationMs = localResult?.durationSeconds != null 
        ? (localResult!.durationSeconds! * 1000).toInt() 
        : 0;

    final canonicalMessage = '${input.attemptId}|${input.resultHash}|${input.status}|$durationMs|${input.engineVersion}|${input.validatorId}|${input.validatorPublicKey}';

    final isValid = await identityService.verifySignature(
      message: canonicalMessage,
      signatureHex: input.signature,
      publicKeyHex: input.validatorPublicKey,
    );

    if (!isValid) return false;

    await saveAttestation(input);

    final isClean = input.status == 'validClean' || input.status == 'valid_clean';
    if (isClean) {
      await (database.update(database.segmentAttempts)
            ..where((row) => row.id.equals(input.attemptId)))
          .write(
        SegmentAttemptsCompanion(
          officialEligible: const Value(true),
          status: Value(input.status),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    return true;
  }

  Future<void> deleteAttempt(String attemptId) async {
    await database.transaction(() async {
      await (database.delete(database.attemptPoints)
            ..where((row) => row.attemptId.equals(attemptId)))
          .go();
      await (database.delete(database.localValidationResults)
            ..where((row) => row.attemptId.equals(attemptId)))
          .go();
      await (database.delete(database.validatorAttestations)
            ..where((row) => row.attemptId.equals(attemptId)))
          .go();
      await (database.delete(database.segmentAttempts)
            ..where((row) => row.id.equals(attemptId)))
          .go();
    });
  }
}
