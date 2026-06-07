import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/route_point.dart';
import '../repositories/attempt_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/navigation_fusion_service.dart';
import '../services/settings_service.dart';
import '../services/attempt_validator_service.dart';
import '../utils/geo_math.dart';

enum AttemptRecordingState {
  idle,
  waitingToStart,
  recording,
  paused,
  finished,
  aborted,
}

class AttemptRecordingSnapshot {
  const AttemptRecordingSnapshot({
    required this.state,
    required this.elapsed,
    required this.distanceMeters,
    required this.pointCount,
    this.attemptId,
    this.speedMps = 0,
    this.headingDegrees = 0,
    this.gpsAccuracyMeters = 0,
    this.distanceToStart = double.infinity,
    this.distanceToFinish = double.infinity,
    this.errorMessage,
  });

  final AttemptRecordingState state;
  final String? attemptId;
  final Duration elapsed;
  final double distanceMeters;
  final int pointCount;
  final double speedMps;
  final double headingDegrees;
  final double gpsAccuracyMeters;
  final double distanceToStart;
  final double distanceToFinish;
  final String? errorMessage;

  AttemptRecordingSnapshot copyWith({
    AttemptRecordingState? state,
    String? attemptId,
    Duration? elapsed,
    double? distanceMeters,
    int? pointCount,
    double? speedMps,
    double? headingDegrees,
    double? gpsAccuracyMeters,
    double? distanceToStart,
    double? distanceToFinish,
    String? errorMessage,
  }) {
    return AttemptRecordingSnapshot(
      state: state ?? this.state,
      attemptId: attemptId ?? this.attemptId,
      elapsed: elapsed ?? this.elapsed,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      pointCount: pointCount ?? this.pointCount,
      speedMps: speedMps ?? this.speedMps,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      gpsAccuracyMeters: gpsAccuracyMeters ?? this.gpsAccuracyMeters,
      distanceToStart: distanceToStart ?? this.distanceToStart,
      distanceToFinish: distanceToFinish ?? this.distanceToFinish,
      errorMessage: errorMessage,
    );
  }
}

class AttemptRecordingController extends ChangeNotifier {
  AttemptRecordingController({
    required this.segmentId,
    required List<RoutePoint> segmentPoints,
    required AttemptRepository attemptRepository,
    required AttemptValidatorService validatorService,
    required SettingsService settings,
  })  : _attemptRepository = attemptRepository,
        _validatorService = validatorService,
        _segmentPoints = segmentPoints,
        _fusionService = NavigationFusionService(
          routePoints: segmentPoints,
          settings: settings,
        );

  final String segmentId;
  final List<RoutePoint> _segmentPoints;
  final AttemptRepository _attemptRepository;
  final AttemptValidatorService _validatorService;
  final NavigationFusionService _fusionService;
  final List<TripRecordingPoint> _pendingPoints = [];

  AttemptRecordingSnapshot _snapshot = const AttemptRecordingSnapshot(
    state: AttemptRecordingState.idle,
    elapsed: Duration.zero,
    distanceMeters: 0,
    pointCount: 0,
  );

  DateTime? _startedAt;
  DateTime? _lastPointAt;
  double? _lastLat;
  double? _lastLon;
  bool _flushing = false;

  AttemptRecordingSnapshot get snapshot => _snapshot;

  void start() {
    if (_snapshot.state != AttemptRecordingState.idle) return;
    _snapshot = _snapshot.copyWith(state: AttemptRecordingState.waitingToStart);
    _fusionService.addListener(_onFusionUpdate);
    _fusionService.start();
    notifyListeners();
  }

  @override
  void dispose() {
    _fusionService.removeListener(_onFusionUpdate);
    _fusionService.stop();
    super.dispose();
  }

  void _onFusionUpdate() {
    final state = _fusionService.currentState;
    if (state == null) return;

    final startPoint = _segmentPoints.first;
    final finishPoint = _segmentPoints.last;

    final distanceToStart = haversineDistanceMeters(
      state.rawLat,
      state.rawLon,
      startPoint.lat,
      startPoint.lon,
    );
    final distanceToFinish = haversineDistanceMeters(
      state.rawLat,
      state.rawLon,
      finishPoint.lat,
      finishPoint.lon,
    );

    if (_snapshot.state == AttemptRecordingState.waitingToStart) {
      _snapshot = _snapshot.copyWith(
        speedMps: state.rawSpeedMps,
        headingDegrees: state.headingDegrees,
        gpsAccuracyMeters: state.gpsAccuracyMeters,
        distanceToStart: distanceToStart,
        distanceToFinish: distanceToFinish,
      );
      notifyListeners();

      if (distanceToStart <= 35.0) {
        _startAttempt(state);
      }
      return;
    }

    if (_snapshot.state != AttemptRecordingState.recording) return;

    if (_lastPointAt != null &&
        state.timestamp.difference(_lastPointAt!).inMilliseconds < 700) {
      return;
    }

    var distance = _snapshot.distanceMeters;
    if (_lastLat != null && _lastLon != null) {
      final delta = haversineDistanceMeters(
        _lastLat!,
        _lastLon!,
        state.rawLat,
        state.rawLon,
      );
      if (delta.isFinite && delta < 120) {
        distance += delta;
      }
    }
    _lastLat = state.rawLat;
    _lastLon = state.rawLon;
    _lastPointAt = state.timestamp;

    // Estimate speed limits dynamically
    int? speedLimitKmh;
    final speedKmh = state.rawSpeedMps * 3.6;
    if (speedKmh > 100) {
      speedLimitKmh = 110;
    } else if (speedKmh > 80) {
      speedLimitKmh = 90;
    } else if (speedKmh > 50) {
      speedLimitKmh = 70;
    } else {
      speedLimitKmh = 50;
    }
    final speedCompliant = speedKmh <= speedLimitKmh + 8;

    _pendingPoints.add(
      TripRecordingPoint(
        recordedAt: state.timestamp,
        lat: state.rawLat,
        lon: state.rawLon,
        accuracyMeters: state.gpsAccuracyMeters,
        speedMps: state.rawSpeedMps,
        headingDegrees: state.headingDegrees,
        distanceFromStart: distance,
        speedLimitKmh: speedLimitKmh,
        speedCompliant: speedCompliant,
      ),
    );

    final elapsed = state.timestamp.difference(_startedAt!);
    _snapshot = _snapshot.copyWith(
      elapsed: elapsed,
      distanceMeters: distance,
      pointCount: _snapshot.pointCount + 1,
      speedMps: state.rawSpeedMps,
      headingDegrees: state.headingDegrees,
      gpsAccuracyMeters: state.gpsAccuracyMeters,
      distanceToStart: distanceToStart,
      distanceToFinish: distanceToFinish,
    );
    notifyListeners();

    if (_pendingPoints.length >= 5) {
      _flushPoints();
    }

    // Auto-detect finish line gate
    if (distanceToFinish <= 35.0 && elapsed.inSeconds >= 2) {
      _finishAttempt();
    }
  }

  Future<void> _startAttempt(FusedNavigationState state) async {
    final now = DateTime.now();
    final attemptId = 'attempt-${now.microsecondsSinceEpoch}';
    _startedAt = state.timestamp;
    _lastPointAt = state.timestamp;
    _lastLat = state.rawLat;
    _lastLon = state.rawLon;

    _snapshot = _snapshot.copyWith(
      state: AttemptRecordingState.recording,
      attemptId: attemptId,
      elapsed: Duration.zero,
      distanceMeters: 0,
      pointCount: 0,
    );
    notifyListeners();

    try {
      await _attemptRepository.createAttempt(
        id: attemptId,
        segmentId: segmentId,
        startedAt: _startedAt!,
      );
    } catch (e) {
      _snapshot = _snapshot.copyWith(
        state: AttemptRecordingState.aborted,
        errorMessage: 'Failed to start attempt in database: $e',
      );
      _fusionService.stop();
      notifyListeners();
    }
  }

  Future<void> _finishAttempt() async {
    if (_snapshot.state != AttemptRecordingState.recording) return;
    _snapshot = _snapshot.copyWith(state: AttemptRecordingState.finished);
    _fusionService.stop();
    notifyListeners();

    final attemptId = _snapshot.attemptId;
    if (attemptId == null) return;

    try {
      // Flush any remaining points
      if (_pendingPoints.isNotEmpty) {
        await _flushPoints();
      }

      // Run validator
      await _validatorService.validateAndPersist(attemptId);
    } catch (e) {
      _snapshot = _snapshot.copyWith(
        errorMessage: 'Validation failed: $e',
      );
      notifyListeners();
    }
  }

  Future<void> abort() async {
    _snapshot = _snapshot.copyWith(state: AttemptRecordingState.aborted);
    _fusionService.stop();
    notifyListeners();
  }

  Future<void> _flushPoints() async {
    final attemptId = _snapshot.attemptId;
    if (attemptId == null || _pendingPoints.isEmpty || _flushing) return;
    _flushing = true;
    final batch = List<TripRecordingPoint>.from(_pendingPoints);
    _pendingPoints.clear();
    try {
      await _attemptRepository.appendAttemptPoints(attemptId, batch);
    } finally {
      _flushing = false;
      if (_pendingPoints.length >= 5) {
        _flushPoints();
      }
    }
  }
}
