import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads_validation/ralroads_validation.dart';

void main() {
  final start = DateTime.utc(2026, 6, 7, 12);
  const segment = [
    SegmentPoint(lat: 46.0, lon: 11.0, distanceFromStart: 0),
    SegmentPoint(lat: 46.001, lon: 11.001, distanceFromStart: 150),
    SegmentPoint(lat: 46.002, lon: 11.002, distanceFromStart: 300),
  ];

  test('returns valid clean for ordered compliant trace', () {
    final result = const AttemptValidator().validate(
      segment: segment,
      trace: [
        ValidationPoint(
          timestamp: start,
          lat: 46.0,
          lon: 11.0,
          speedMps: 8,
          accuracyMeters: 5,
          speedLimitKmh: 50,
        ),
        ValidationPoint(
          timestamp: start.add(const Duration(seconds: 10)),
          lat: 46.001,
          lon: 11.001,
          speedMps: 9,
          accuracyMeters: 6,
          speedLimitKmh: 50,
        ),
        ValidationPoint(
          timestamp: start.add(const Duration(seconds: 20)),
          lat: 46.002,
          lon: 11.002,
          speedMps: 9,
          accuracyMeters: 6,
          speedLimitKmh: 50,
        ),
      ],
    );

    expect(result.status, AttemptStatus.validClean);
    expect(result.reasons, isEmpty);
    expect(result.resultHash, hasLength(64));
  });

  test('invalidates sustained hard speed-limit violations', () {
    final result = const AttemptValidator().validate(
      segment: segment,
      trace: [
        ValidationPoint(
          timestamp: start,
          lat: 46.0,
          lon: 11.0,
          speedMps: 20,
          accuracyMeters: 5,
          speedLimitKmh: 50,
        ),
        ValidationPoint(
          timestamp: start.add(const Duration(seconds: 3)),
          lat: 46.001,
          lon: 11.001,
          speedMps: 20,
          accuracyMeters: 5,
          speedLimitKmh: 50,
        ),
        ValidationPoint(
          timestamp: start.add(const Duration(seconds: 6)),
          lat: 46.002,
          lon: 11.002,
          speedMps: 20,
          accuracyMeters: 5,
          speedLimitKmh: 50,
        ),
      ],
    );

    expect(result.status, AttemptStatus.invalidSpeedLimit);
    expect(
      result.reasons.map((reason) => reason.code),
      contains('speed_limit'),
    );
  });

  test('same input produces same deterministic hash', () {
    final trace = [
      ValidationPoint(
        timestamp: start,
        lat: 46.0,
        lon: 11.0,
        accuracyMeters: 5,
        speedLimitKmh: 50,
      ),
      ValidationPoint(
        timestamp: start.add(const Duration(seconds: 10)),
        lat: 46.001,
        lon: 11.001,
        accuracyMeters: 5,
        speedLimitKmh: 50,
      ),
      ValidationPoint(
        timestamp: start.add(const Duration(seconds: 20)),
        lat: 46.002,
        lon: 11.002,
        accuracyMeters: 5,
        speedLimitKmh: 50,
      ),
    ];

    final first = const AttemptValidator().validate(
      segment: segment,
      trace: trace,
    );
    final second = const AttemptValidator().validate(
      segment: segment,
      trace: trace,
    );

    expect(first.resultHash, second.resultHash);
  });
}
