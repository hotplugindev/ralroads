import 'dart:async';
import '../models/route_point.dart';
import '../repositories/trip_repository.dart';
import '../utils/geo_math.dart';

class TripCaptureController {
  TripCaptureController({
    required TripRepository tripRepository,
  }) : _tripRepository = tripRepository;

  final TripRepository _tripRepository;

  final List<TripRecordingPoint> _pendingTripPoints = [];
  bool _flushingTrip = false;

  double _distanceMeters = 0.0;
  double get distanceMeters => _distanceMeters;

  double? _lastLat;
  double? _lastLon;
  DateTime? _lastPointAt;

  void reset(double? initialLat, double? initialLon) {
    _pendingTripPoints.clear();
    _flushingTrip = false;
    _distanceMeters = 0.0;
    _lastLat = initialLat;
    _lastLon = initialLon;
    _lastPointAt = null;
  }

  Future<void> startTrip({
    required String tripId,
    required DateTime startedAt,
    required String name,
  }) async {
    await _tripRepository.startTrip(
      id: tripId,
      startedAt: startedAt,
      name: name,
    );
  }

  Future<void> pauseTrip(String tripId) async {
    await _tripRepository.pauseTrip(tripId);
  }

  Future<void> resumeTrip(String tripId) async {
    await _tripRepository.resumeTrip(tripId);
  }

  Future<void> deleteTrip(String tripId) async {
    await _tripRepository.deleteTrip(tripId);
  }

  void trackLocation({
    required String tripId,
    required DateTime timestamp,
    required double lat,
    required double lon,
    required double gpsAccuracyMeters,
    required double rawSpeedMps,
    required double headingDegrees,
    required int? speedLimitKmh,
    required bool isPaused,
  }) {
    // 1. Accumulate distance
    if (_lastLat != null && _lastLon != null) {
      final delta = haversineDistanceMeters(
        _lastLat!,
        _lastLon!,
        lat,
        lon,
      );
      if (delta.isFinite && delta < 120.0) {
        _distanceMeters += delta;
      }
    }
    _lastLat = lat;
    _lastLon = lon;

    final now = DateTime.now();
    if (_lastPointAt == null ||
        now.difference(_lastPointAt!).inMilliseconds >= 700) {
      _lastPointAt = now;
      final speedKmh = rawSpeedMps * 3.6;
      final speedCompliant = speedLimitKmh == null || speedKmh <= speedLimitKmh + 8;

      _pendingTripPoints.add(
        TripRecordingPoint(
          recordedAt: timestamp,
          lat: lat,
          lon: lon,
          accuracyMeters: gpsAccuracyMeters,
          speedMps: rawSpeedMps,
          headingDegrees: headingDegrees,
          distanceFromStart: _distanceMeters,
          speedLimitKmh: speedLimitKmh,
          speedCompliant: speedCompliant,
        ),
      );

      if (_pendingTripPoints.length >= 5) {
        _flushTripPoints(tripId, isPaused);
      }
    }
  }

  Future<void> flushAndFinish({
    required String tripId,
    required DateTime endedAt,
    required bool cleanEligible,
  }) async {
    await _flushTripPoints(tripId, false);
    await _tripRepository.finishTrip(
      tripId: tripId,
      endedAt: endedAt,
      distanceMeters: _distanceMeters,
      cleanEligible: cleanEligible,
    );
  }

  Future<void> _flushTripPoints(String tripId, bool isPaused) async {
    if (_pendingTripPoints.isEmpty || _flushingTrip) return;
    _flushingTrip = true;
    final batch = List<TripRecordingPoint>.from(_pendingTripPoints);
    _pendingTripPoints.clear();
    try {
      await _tripRepository.appendTripPoints(tripId, batch);
      await _tripRepository.updateTripProgress(
        tripId: tripId,
        distanceMeters: _distanceMeters,
        cleanEligible: true,
        status: isPaused ? 'paused' : 'recording',
      );
    } finally {
      _flushingTrip = false;
      if (_pendingTripPoints.length >= 5) {
        // recursively flush if more accumulated
        _flushTripPoints(tripId, isPaused);
      }
    }
  }
}
