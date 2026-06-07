import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/route_point.dart';
import '../repositories/trip_repository.dart';
import '../services/navigation_fusion_service.dart';
import '../services/settings_service.dart';
import '../utils/geo_math.dart';

enum TripRecordingState {
  idle,
  starting,
  recording,
  paused,
  finishing,
  finished,
  error,
}

class TripRecordingSnapshot {
  const TripRecordingSnapshot({
    required this.state,
    required this.elapsed,
    required this.distanceMeters,
    required this.pointCount,
    required this.cleanEligible,
    this.tripId,
    this.speedMps = 0,
    this.headingDegrees = 0,
    this.gpsAccuracyMeters = 0,
    this.speedLimitKmh,
    this.errorMessage,
  });

  final TripRecordingState state;
  final String? tripId;
  final Duration elapsed;
  final double distanceMeters;
  final int pointCount;
  final bool cleanEligible;
  final double speedMps;
  final double headingDegrees;
  final double gpsAccuracyMeters;
  final int? speedLimitKmh;
  final String? errorMessage;

  TripRecordingSnapshot copyWith({
    TripRecordingState? state,
    String? tripId,
    Duration? elapsed,
    double? distanceMeters,
    int? pointCount,
    bool? cleanEligible,
    double? speedMps,
    double? headingDegrees,
    double? gpsAccuracyMeters,
    int? speedLimitKmh,
    String? errorMessage,
  }) {
    return TripRecordingSnapshot(
      state: state ?? this.state,
      tripId: tripId ?? this.tripId,
      elapsed: elapsed ?? this.elapsed,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      pointCount: pointCount ?? this.pointCount,
      cleanEligible: cleanEligible ?? this.cleanEligible,
      speedMps: speedMps ?? this.speedMps,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      gpsAccuracyMeters: gpsAccuracyMeters ?? this.gpsAccuracyMeters,
      speedLimitKmh: speedLimitKmh ?? this.speedLimitKmh,
      errorMessage: errorMessage,
    );
  }
}

class TripRecordingController extends ChangeNotifier {
  TripRecordingController({
    required TripRepository tripRepository,
    required SettingsService settings,
  }) : _tripRepository = tripRepository,
       _fusionService = NavigationFusionService(
         routePoints: const <RoutePoint>[],
         settings: settings,
       );

  final TripRepository _tripRepository;
  final NavigationFusionService _fusionService;
  final List<TripRecordingPoint> _pendingPoints = [];

  TripRecordingSnapshot _snapshot = const TripRecordingSnapshot(
    state: TripRecordingState.idle,
    elapsed: Duration.zero,
    distanceMeters: 0,
    pointCount: 0,
    cleanEligible: true,
  );
  DateTime? _startedAt;
  DateTime? _lastPointAt;
  double? _lastLat;
  double? _lastLon;
  bool _flushing = false;

  TripRecordingSnapshot get snapshot => _snapshot;

  Future<void> start() async {
    _snapshot = _snapshot.copyWith(state: TripRecordingState.starting);
    notifyListeners();

    final permissionReady = await _ensureLocationPermission();
    if (!permissionReady) {
      _snapshot = _snapshot.copyWith(
        state: TripRecordingState.error,
        errorMessage: 'Location permission is required to record a trip.',
      );
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final active = await _tripRepository.activeTrip();
    final tripId = active?.id ?? 'trip-${now.microsecondsSinceEpoch}';
    final startedAt = active?.startedAt ?? now;
    if (active == null) {
      await _tripRepository.startTrip(
        id: tripId,
        startedAt: now,
        name:
            'Trip ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      );
    } else {
      await _tripRepository.resumeTrip(tripId);
    }
    _startedAt = startedAt;
    _snapshot = TripRecordingSnapshot(
      state: TripRecordingState.recording,
      tripId: tripId,
      elapsed: now.difference(startedAt),
      distanceMeters: active?.distanceMeters ?? 0,
      pointCount: 0,
      cleanEligible: active?.cleanEligible ?? true,
    );
    _fusionService.addListener(_onFusionUpdate);
    _fusionService.start();
    notifyListeners();
  }

  void pause() {
    if (_snapshot.state != TripRecordingState.recording) return;
    final tripId = _snapshot.tripId;
    if (tripId != null) {
      _tripRepository.pauseTrip(tripId);
    }
    _snapshot = _snapshot.copyWith(state: TripRecordingState.paused);
    notifyListeners();
  }

  void resume() {
    if (_snapshot.state != TripRecordingState.paused) return;
    final tripId = _snapshot.tripId;
    if (tripId != null) {
      _tripRepository.resumeTrip(tripId);
    }
    _snapshot = _snapshot.copyWith(state: TripRecordingState.recording);
    notifyListeners();
  }

  Future<String?> finish() async {
    final tripId = _snapshot.tripId;
    if (tripId == null) return null;
    _snapshot = _snapshot.copyWith(state: TripRecordingState.finishing);
    notifyListeners();
    _fusionService.removeListener(_onFusionUpdate);
    _fusionService.stop();
    await _flushPoints();
    await _tripRepository.finishTrip(
      tripId: tripId,
      endedAt: DateTime.now(),
      distanceMeters: _snapshot.distanceMeters,
      cleanEligible: _snapshot.cleanEligible,
    );
    _snapshot = _snapshot.copyWith(state: TripRecordingState.finished);
    notifyListeners();
    return tripId;
  }

  Future<void> cancel() async {
    final tripId = _snapshot.tripId;
    _fusionService.removeListener(_onFusionUpdate);
    _fusionService.stop();
    if (tripId != null) {
      await _tripRepository.deleteTrip(tripId);
    }
    _pendingPoints.clear();
    _snapshot = const TripRecordingSnapshot(
      state: TripRecordingState.idle,
      elapsed: Duration.zero,
      distanceMeters: 0,
      pointCount: 0,
      cleanEligible: true,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _fusionService.removeListener(_onFusionUpdate);
    _fusionService.stop();
    super.dispose();
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  void _onFusionUpdate() {
    if (_snapshot.state != TripRecordingState.recording) return;
    final state = _fusionService.currentState;
    final tripId = _snapshot.tripId;
    final startedAt = _startedAt;
    if (state == null || tripId == null || startedAt == null) return;
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

    final cleanEligible =
        _snapshot.cleanEligible &&
        (state.gpsAccuracyMeters <= 35 || state.gpsAccuracyMeters == 0);

    // Dynamic speed limit estimation for raw trip recording
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
    _snapshot = _snapshot.copyWith(
      elapsed: state.timestamp.difference(startedAt),
      distanceMeters: distance,
      pointCount: _snapshot.pointCount + 1,
      cleanEligible: cleanEligible,
      speedMps: state.rawSpeedMps,
      headingDegrees: state.headingDegrees,
      gpsAccuracyMeters: state.gpsAccuracyMeters,
      speedLimitKmh: speedLimitKmh,
    );
    if (_pendingPoints.length >= 5) {
      _flushPoints();
    }
    notifyListeners();
  }

  Future<void> _flushPoints() async {
    final tripId = _snapshot.tripId;
    if (tripId == null || _pendingPoints.isEmpty || _flushing) return;
    _flushing = true;
    final batch = List<TripRecordingPoint>.from(_pendingPoints);
    _pendingPoints.clear();
    try {
      await _tripRepository.appendTripPoints(tripId, batch);
      await _tripRepository.updateTripProgress(
        tripId: tripId,
        distanceMeters: _snapshot.distanceMeters,
        cleanEligible: _snapshot.cleanEligible,
        status: _snapshot.state == TripRecordingState.paused
            ? 'paused'
            : 'recording',
      );
    } finally {
      _flushing = false;
      if (_pendingPoints.length >= 5) {
        _flushPoints();
      }
    }
  }
}
