import 'dart:async';
import '../repositories/attempt_repository.dart';
import '../services/attempt_validator_service.dart';
import '../repositories/trip_repository.dart'; // for TripRecordingPoint
import '../utils/geo_math.dart';

enum AttemptRecordingState {
  idle,
  waitingToStart,
  recording,
  paused,
  finished,
  aborted,
}

class AttemptRuntimeController {
  AttemptRuntimeController({
    required AttemptRepository attemptRepository,
    required AttemptValidatorService validatorService,
  }) : _attemptRepository = attemptRepository,
       _validatorService = validatorService;

  final AttemptRepository _attemptRepository;
  final AttemptValidatorService _validatorService;

  var recordingState = AttemptRecordingState.idle;

  String? _attemptId;
  String? get attemptId => _attemptId;

  DateTime? _attemptStartedAt;
  DateTime? get attemptStartedAt => _attemptStartedAt;
  DateTime? _lastAttemptPointAt;
  double? _lastAttemptLat;
  double? _lastAttemptLon;
  double _attemptDistanceMeters = 0.0;
  bool _attemptCleanEligible = true;

  final List<TripRecordingPoint> _pendingAttemptPoints = [];
  bool _flushingAttempt = false;

  void reset() {
    recordingState = AttemptRecordingState.idle;
    _attemptId = null;
    _attemptStartedAt = null;
    _lastAttemptPointAt = null;
    _lastAttemptLat = null;
    _lastAttemptLon = null;
    _attemptDistanceMeters = 0.0;
    _attemptCleanEligible = true;
    _pendingAttemptPoints.clear();
    _flushingAttempt = false;
  }

  Future<void> startAttempt({
    required String attemptId,
    required String segmentId,
    required double lat,
    required double lon,
    required DateTime timestamp,
  }) async {
    _attemptId = attemptId;
    _attemptStartedAt = timestamp;
    _lastAttemptPointAt = timestamp;
    _lastAttemptLat = lat;
    _lastAttemptLon = lon;
    _attemptDistanceMeters = 0.0;
    _attemptCleanEligible = true;
    recordingState = AttemptRecordingState.recording;

    await _attemptRepository.createAttempt(
      id: attemptId,
      segmentId: segmentId,
      startedAt: _attemptStartedAt!,
    );
  }

  Future<void> updateAttemptRecording({
    required double lat,
    required double lon,
    required double gpsAccuracyMeters,
    required double rawSpeedMps,
    required double headingDegrees,
    required int? speedLimitKmh,
    required DateTime timestamp,
  }) async {
    if (_lastAttemptPointAt != null &&
        timestamp.difference(_lastAttemptPointAt!).inMilliseconds < 700) {
      return;
    }

    if (_lastAttemptLat != null && _lastAttemptLon != null) {
      final delta = haversineDistanceMeters(
        _lastAttemptLat!,
        _lastAttemptLon!,
        lat,
        lon,
      );
      if (delta.isFinite && delta < 120.0) {
        _attemptDistanceMeters += delta;
      }
    }

    _lastAttemptLat = lat;
    _lastAttemptLon = lon;
    _lastAttemptPointAt = timestamp;

    if (gpsAccuracyMeters > 35.0) {
      _attemptCleanEligible = false;
    }

    final speedKmh = rawSpeedMps * 3.6;
    final speedCompliant =
        speedLimitKmh == null || speedKmh <= speedLimitKmh + 8;

    _pendingAttemptPoints.add(
      TripRecordingPoint(
        recordedAt: timestamp,
        lat: lat,
        lon: lon,
        accuracyMeters: gpsAccuracyMeters,
        speedMps: rawSpeedMps,
        headingDegrees: headingDegrees,
        distanceFromStart: _attemptDistanceMeters,
        speedLimitKmh: speedLimitKmh,
        speedCompliant: speedCompliant,
      ),
    );

    if (_pendingAttemptPoints.length >= 5) {
      await _flushAttemptPoints();
    }
  }

  Future<void> finishAttempt() async {
    final attId = _attemptId;
    if (attId == null) return;

    recordingState = AttemptRecordingState.finished;

    await _flushAttemptPoints();
    await _attemptRepository.finishAttempt(
      attemptId: attId,
      finishedAt: DateTime.now(),
      status: 'finished',
      officialEligible: _attemptCleanEligible,
    );
    await _validatorService.validateAndPersist(attId);
  }

  Future<void> deleteAttempt() async {
    final attId = _attemptId;
    if (attId != null) {
      await _attemptRepository.deleteAttempt(attId);
    }
    reset();
  }

  Future<void> _flushAttemptPoints() async {
    final attId = _attemptId;
    if (attId == null || _pendingAttemptPoints.isEmpty || _flushingAttempt) {
      return;
    }
    _flushingAttempt = true;
    final batch = List<TripRecordingPoint>.from(_pendingAttemptPoints);
    _pendingAttemptPoints.clear();
    try {
      await _attemptRepository.appendAttemptPoints(attId, batch);
    } finally {
      _flushingAttempt = false;
      if (_pendingAttemptPoints.length >= 5) {
        await _flushAttemptPoints();
      }
    }
  }
}
