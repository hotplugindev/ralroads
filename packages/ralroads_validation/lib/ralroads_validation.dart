import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

enum AttemptStatus {
  validClean,
  invalidSpeedLimit,
  invalidRouteMismatch,
  invalidGpsQuality,
  suspicious,
  rejected,
  dnf,
}

class ValidationReason {
  const ValidationReason(this.code, this.message);

  final String code;
  final String message;

  Map<String, Object?> toJson() => {'code': code, 'message': message};
}

class ValidationPoint {
  const ValidationPoint({
    required this.timestamp,
    required this.lat,
    required this.lon,
    this.speedMps,
    this.accuracyMeters,
    this.speedLimitKmh,
  });

  final DateTime timestamp;
  final double lat;
  final double lon;
  final double? speedMps;
  final double? accuracyMeters;
  final int? speedLimitKmh;
}

class SegmentPoint {
  const SegmentPoint({
    required this.lat,
    required this.lon,
    required this.distanceFromStart,
  });

  final double lat;
  final double lon;
  final double distanceFromStart;
}

class ValidationPolicy {
  const ValidationPolicy({
    this.corridorMeters = 35,
    this.startFinishRadiusMeters = 35,
    this.minRouteMatchScore = 0.85,
    this.maxAverageGpsAccuracyMeters = 30,
    this.maxJumpSpeedMps = 80,
    this.hardSpeedToleranceKmh = 8,
    this.hardSpeedDuration = const Duration(seconds: 2),
  });

  final double corridorMeters;
  final double startFinishRadiusMeters;
  final double minRouteMatchScore;
  final double maxAverageGpsAccuracyMeters;
  final double maxJumpSpeedMps;
  final int hardSpeedToleranceKmh;
  final Duration hardSpeedDuration;
}

class AttemptValidationResult {
  const AttemptValidationResult({
    required this.status,
    required this.duration,
    required this.routeMatchScore,
    required this.gpsQualityScore,
    required this.speedLimitCoverage,
    required this.reasons,
    required this.resultHash,
  });

  final AttemptStatus status;
  final Duration? duration;
  final double routeMatchScore;
  final double gpsQualityScore;
  final double speedLimitCoverage;
  final List<ValidationReason> reasons;
  final String resultHash;
}

class AttemptValidator {
  const AttemptValidator();

  AttemptValidationResult validate({
    required List<SegmentPoint> segment,
    required List<ValidationPoint> trace,
    ValidationPolicy policy = const ValidationPolicy(),
  }) {
    final reasons = <ValidationReason>[];
    if (segment.length < 2 || trace.length < 2) {
      reasons.add(
        const ValidationReason('too_short', 'Segment or trace is too short.'),
      );
      return _result(
        status: AttemptStatus.dnf,
        duration: null,
        routeMatchScore: 0,
        gpsQualityScore: 0,
        speedLimitCoverage: 0,
        reasons: reasons,
        segment: segment,
        trace: trace,
      );
    }

    var monotonic = true;
    var impossibleJump = false;
    var matched = 0;
    var speedLimitPoints = 0;
    var hardViolationSeconds = 0.0;
    var accuracySum = 0.0;
    var accuracyCount = 0;
    var lastProgress = 0.0;
    var routeOrderBacktracks = 0;

    for (var i = 0; i < trace.length; i++) {
      final point = trace[i];
      if (point.accuracyMeters != null) {
        accuracySum += point.accuracyMeters!;
        accuracyCount++;
      }
      final match = _nearestSegmentDistance(point, segment);
      if (match.distanceMeters <= policy.corridorMeters) {
        matched++;
      }
      if (i > 0) {
        final previous = trace[i - 1];
        final dt =
            point.timestamp.difference(previous.timestamp).inMilliseconds /
            1000.0;
        if (dt <= 0) {
          monotonic = false;
        } else {
          final jumpSpeed =
              _distanceMeters(
                previous.lat,
                previous.lon,
                point.lat,
                point.lon,
              ) /
              dt;
          if (jumpSpeed > policy.maxJumpSpeedMps) {
            impossibleJump = true;
          }
        }
        if (match.distanceFromStart + 25 < lastProgress) {
          routeOrderBacktracks++;
        }
      }
      lastProgress = math.max(lastProgress, match.distanceFromStart);

      final limit = point.speedLimitKmh;
      final speed = point.speedMps;
      if (limit != null) {
        speedLimitPoints++;
        if (speed != null &&
            speed * 3.6 > limit + policy.hardSpeedToleranceKmh) {
          hardViolationSeconds += i == 0
              ? 0
              : point.timestamp
                        .difference(trace[i - 1].timestamp)
                        .inMilliseconds /
                    1000.0;
        }
      }
    }

    final avgAccuracy = accuracyCount == 0
        ? double.infinity
        : accuracySum / accuracyCount;
    final routeMatchScore = matched / trace.length;
    final gpsQualityScore = accuracyCount == 0
        ? 0.0
        : (1.0 - (avgAccuracy / policy.maxAverageGpsAccuracyMeters)).clamp(
            0.0,
            1.0,
          );
    final speedLimitCoverage = speedLimitPoints / trace.length;

    final startDistance = _distanceMeters(
      trace.first.lat,
      trace.first.lon,
      segment.first.lat,
      segment.first.lon,
    );
    final finishDistance = _distanceMeters(
      trace.last.lat,
      trace.last.lon,
      segment.last.lat,
      segment.last.lon,
    );

    if (startDistance > policy.startFinishRadiusMeters) {
      reasons.add(
        const ValidationReason(
          'missing_start',
          'Trace did not start in the segment start zone.',
        ),
      );
    }
    if (finishDistance > policy.startFinishRadiusMeters) {
      reasons.add(
        const ValidationReason(
          'missing_finish',
          'Trace did not finish in the segment finish zone.',
        ),
      );
    }
    if (!monotonic) {
      reasons.add(
        const ValidationReason(
          'time_order',
          'Trace timestamps are not monotonic.',
        ),
      );
    }
    if (impossibleJump) {
      reasons.add(
        const ValidationReason(
          'impossible_jump',
          'Trace contains an impossible GPS jump.',
        ),
      );
    }
    if (routeOrderBacktracks > 2 ||
        routeMatchScore < policy.minRouteMatchScore) {
      reasons.add(
        const ValidationReason(
          'route_mismatch',
          'Trace did not follow enough of the segment corridor in order.',
        ),
      );
    }
    if (avgAccuracy > policy.maxAverageGpsAccuracyMeters) {
      reasons.add(
        const ValidationReason(
          'gps_quality',
          'Average GPS accuracy is too weak for a clean result.',
        ),
      );
    }
    if (hardViolationSeconds >= policy.hardSpeedDuration.inSeconds) {
      reasons.add(
        const ValidationReason(
          'speed_limit',
          'Sustained speed-limit violation detected.',
        ),
      );
    }

    final status = _statusForReasons(reasons);
    return _result(
      status: status,
      duration: trace.last.timestamp.difference(trace.first.timestamp),
      routeMatchScore: routeMatchScore,
      gpsQualityScore: gpsQualityScore,
      speedLimitCoverage: speedLimitCoverage,
      reasons: reasons,
      segment: segment,
      trace: trace,
    );
  }

  AttemptStatus _statusForReasons(List<ValidationReason> reasons) {
    if (reasons.isEmpty) return AttemptStatus.validClean;
    if (reasons.any((reason) => reason.code == 'speed_limit')) {
      return AttemptStatus.invalidSpeedLimit;
    }
    if (reasons.any((reason) => reason.code == 'gps_quality')) {
      return AttemptStatus.invalidGpsQuality;
    }
    if (reasons.any((reason) => reason.code == 'route_mismatch')) {
      return AttemptStatus.invalidRouteMismatch;
    }
    if (reasons.any(
      (reason) =>
          reason.code == 'missing_finish' || reason.code == 'missing_start',
    )) {
      return AttemptStatus.dnf;
    }
    return AttemptStatus.suspicious;
  }

  AttemptValidationResult _result({
    required AttemptStatus status,
    required Duration? duration,
    required double routeMatchScore,
    required double gpsQualityScore,
    required double speedLimitCoverage,
    required List<ValidationReason> reasons,
    required List<SegmentPoint> segment,
    required List<ValidationPoint> trace,
  }) {
    final payload = jsonEncode({
      'status': status.name,
      'durationMs': duration?.inMilliseconds,
      'routeMatchScore': routeMatchScore.toStringAsFixed(6),
      'gpsQualityScore': gpsQualityScore.toStringAsFixed(6),
      'speedLimitCoverage': speedLimitCoverage.toStringAsFixed(6),
      'reasons': reasons.map((reason) => reason.toJson()).toList(),
      'segment': [
        for (final point in segment)
          [point.lat, point.lon, point.distanceFromStart],
      ],
      'trace': [
        for (final point in trace)
          [
            point.timestamp.toUtc().toIso8601String(),
            point.lat,
            point.lon,
            point.speedMps,
            point.accuracyMeters,
            point.speedLimitKmh,
          ],
      ],
    });
    return AttemptValidationResult(
      status: status,
      duration: duration,
      routeMatchScore: routeMatchScore,
      gpsQualityScore: gpsQualityScore,
      speedLimitCoverage: speedLimitCoverage,
      reasons: List.unmodifiable(reasons),
      resultHash: sha256.convert(utf8.encode(payload)).toString(),
    );
  }
}

({double distanceMeters, double distanceFromStart}) _nearestSegmentDistance(
  ValidationPoint tracePoint,
  List<SegmentPoint> segment,
) {
  var bestDistance = double.infinity;
  var bestProgress = 0.0;
  for (final point in segment) {
    final distance = _distanceMeters(
      tracePoint.lat,
      tracePoint.lon,
      point.lat,
      point.lon,
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      bestProgress = point.distanceFromStart;
    }
  }
  return (distanceMeters: bestDistance, distanceFromStart: bestProgress);
}

double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);
  final rLat1 = _degToRad(lat1);
  final rLat2 = _degToRad(lat2);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rLat1) *
          math.cos(rLat2) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _degToRad(double degrees) => degrees * math.pi / 180.0;
