import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:ralroads_validation/ralroads_validation.dart';
import '../repositories/attempt_repository.dart';
import '../repositories/segment_repository.dart';

class AttemptValidatorService {
  AttemptValidatorService({
    required this.attemptRepository,
    required this.segmentRepository,
  });

  final AttemptRepository attemptRepository;
  final SegmentRepository segmentRepository;
  final AttemptValidator _validator = const AttemptValidator();

  Future<AttemptValidationResult> validateAndPersist(String attemptId) async {
    // 1. Load attempt
    final attempt = await (attemptRepository.database.select(attemptRepository.database.segmentAttempts)
          ..where((row) => row.id.equals(attemptId)))
        .getSingle();

    // 2. Load segment geometry
    final segment = await (segmentRepository.database.select(segmentRepository.database.challengeSegments)
          ..where((row) => row.id.equals(attempt.segmentId)))
        .getSingle();
    final versionId = segment.currentVersionId;
    if (versionId == null) {
      throw Exception('Segment currentVersionId is null.');
    }

    final segmentGeomList = await (segmentRepository.database.select(segmentRepository.database.segmentGeometry)
          ..where((row) => row.versionId.equals(versionId))
          ..orderBy([(row) => OrderingTerm.asc(row.pointIndex)]))
        .get();

    final segmentPoints = segmentGeomList.map((g) => SegmentPoint(
      lat: g.lat,
      lon: g.lon,
      distanceFromStart: g.distanceFromStart,
    )).toList();

    // 3. Load attempt points
    final attemptPointsList = await (attemptRepository.database.select(attemptRepository.database.attemptPoints)
          ..where((row) => row.attemptId.equals(attemptId))
          ..orderBy([(row) => OrderingTerm.asc(row.pointIndex)]))
        .get();

    final trace = attemptPointsList.map((p) => ValidationPoint(
      timestamp: p.recordedAt,
      lat: p.lat,
      lon: p.lon,
      speedMps: p.speedMps,
      accuracyMeters: p.accuracyMeters,
      speedLimitKmh: p.speedLimitKmh,
    )).toList();

    // 4. Run validator
    final result = _validator.validate(
      segment: segmentPoints,
      trace: trace,
    );

    // 5. Mapping status enum to string
    final statusString = switch (result.status) {
      AttemptStatus.validClean => 'valid_clean',
      AttemptStatus.invalidSpeedLimit => 'invalid_speed_limit',
      AttemptStatus.invalidRouteMismatch => 'invalid_route_mismatch',
      AttemptStatus.invalidGpsQuality => 'invalid_gps_quality',
      AttemptStatus.suspicious => 'suspicious',
      AttemptStatus.rejected => 'rejected',
      AttemptStatus.dnf => 'dnf',
    };

    // 6. Persist results
    await attemptRepository.persistValidationResult(
      AttemptValidationInput(
        id: 'val-$attemptId',
        attemptId: attemptId,
        engineVersion: '1.0.0',
        status: statusString,
        resultHash: result.resultHash,
        durationSeconds: result.duration != null
            ? result.duration!.inMilliseconds.toDouble() / 1000.0
            : null,
        routeMatchScore: result.routeMatchScore,
        gpsQualityScore: result.gpsQualityScore,
        reasonsJson: jsonEncode(result.reasons.map((r) => r.toJson()).toList()),
      ),
    );

    // 7. Update segment attempt status
    await attemptRepository.finishAttempt(
      attemptId: attemptId,
      finishedAt: DateTime.now(),
      status: statusString,
      officialEligible: result.status == AttemptStatus.validClean,
    );

    return result;
  }
}
