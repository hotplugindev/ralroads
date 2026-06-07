import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../repositories/trip_repository.dart';
import '../repositories/attempt_repository.dart';
import '../services/settings_service.dart';
import '../services/navigation_fusion_service.dart';
import '../services/attempt_validator_service.dart';
import '../services/callout_speech_service.dart';
import '../services/callout_scheduler.dart';
import '../services/ors_service.dart';
import '../services/pacenote_generator.dart';
import '../services/overpass_service.dart';
import '../utils/geo_math.dart';
import '../utils/ui_helpers.dart';

enum DrivingSessionState {
  idle,
  preparing,
  active,
  paused,
  finishing,
  finished,
  cancelled,
  error,
}

enum AttemptRecordingState {
  idle,
  waitingToStart,
  recording,
  paused,
  finished,
  aborted,
}

class DrivingSessionConfig {
  const DrivingSessionConfig({
    required this.routePoints,
    this.pacenotes = const [],
    this.roadWarnings = const [],
    this.speedLimitSegments = const [],
    this.routeId,
    this.segmentId,
    this.segmentName,
    this.challengeId,
    this.recordTrip = true,
    this.attemptMode = false,
  });

  final List<RoutePoint> routePoints;
  final List<PaceNote> pacenotes;
  final List<RoadWarning> roadWarnings;
  final List<SpeedLimitSegment> speedLimitSegments;
  final String? routeId;
  final String? segmentId;
  final String? segmentName;
  final String? challengeId;
  final bool recordTrip;
  final bool attemptMode;
}

class DrivingSessionSnapshot {
  const DrivingSessionSnapshot({
    required this.state,
    required this.startedAt,
    required this.elapsed,
    required this.distanceMeters,
    required this.recording,
    required this.attemptRecordingState,
    this.config,
    this.tripId,
    this.attemptId,
    this.speedMps = 0.0,
    this.headingDegrees = 0.0,
    this.gpsAccuracyMeters = 0.0,
    this.speedLimitKmh,
    this.distanceToStart = double.infinity,
    this.distanceToFinish = double.infinity,
    this.nextNote,
    this.distanceToNote,
    this.nextWarning,
    this.distanceToWarning,
    this.currentLimit,
    this.offRoute = false,
    this.gpsWeak = false,
    required this.progressPercentage,
    required this.remainingDistanceMeters,
    required this.remainingDurationSeconds,
    required this.etaString,
    this.errorMessage,
  });

  final DrivingSessionState state;
  final DrivingSessionConfig? config;
  final DateTime? startedAt;
  final Duration elapsed;
  final double distanceMeters;
  final bool recording;
  final AttemptRecordingState attemptRecordingState;
  final String? tripId;
  final String? attemptId;
  final double speedMps;
  final double headingDegrees;
  final double gpsAccuracyMeters;
  final int? speedLimitKmh;
  final double distanceToStart;
  final double distanceToFinish;
  final PaceNote? nextNote;
  final double? distanceToNote;
  final RoadWarning? nextWarning;
  final double? distanceToWarning;
  final SpeedLimitSegment? currentLimit;
  final bool offRoute;
  final bool gpsWeak;
  final double progressPercentage;
  final double remainingDistanceMeters;
  final double remainingDurationSeconds;
  final String etaString;
  final String? errorMessage;

  DrivingSessionSnapshot copyWith({
    DrivingSessionState? state,
    DrivingSessionConfig? config,
    DateTime? startedAt,
    Duration? elapsed,
    double? distanceMeters,
    bool? recording,
    AttemptRecordingState? attemptRecordingState,
    String? tripId,
    bool clearTripId = false,
    String? attemptId,
    bool clearAttemptId = false,
    double? speedMps,
    double? headingDegrees,
    double? gpsAccuracyMeters,
    int? speedLimitKmh,
    double? distanceToStart,
    double? distanceToFinish,
    PaceNote? nextNote,
    double? distanceToNote,
    RoadWarning? nextWarning,
    double? distanceToWarning,
    SpeedLimitSegment? currentLimit,
    bool? offRoute,
    bool? gpsWeak,
    double? progressPercentage,
    double? remainingDistanceMeters,
    double? remainingDurationSeconds,
    String? etaString,
    String? errorMessage,
  }) {
    return DrivingSessionSnapshot(
      state: state ?? this.state,
      config: config ?? this.config,
      startedAt: startedAt ?? this.startedAt,
      elapsed: elapsed ?? this.elapsed,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      recording: recording ?? this.recording,
      attemptRecordingState:
          attemptRecordingState ?? this.attemptRecordingState,
      tripId: clearTripId ? null : (tripId ?? this.tripId),
      attemptId: clearAttemptId ? null : (attemptId ?? this.attemptId),
      speedMps: speedMps ?? this.speedMps,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      gpsAccuracyMeters: gpsAccuracyMeters ?? this.gpsAccuracyMeters,
      speedLimitKmh: speedLimitKmh ?? this.speedLimitKmh,
      distanceToStart: distanceToStart ?? this.distanceToStart,
      distanceToFinish: distanceToFinish ?? this.distanceToFinish,
      nextNote: nextNote ?? this.nextNote,
      distanceToNote: distanceToNote ?? this.distanceToNote,
      nextWarning: nextWarning ?? this.nextWarning,
      distanceToWarning: distanceToWarning ?? this.distanceToWarning,
      currentLimit: currentLimit ?? this.currentLimit,
      offRoute: offRoute ?? this.offRoute,
      gpsWeak: gpsWeak ?? this.gpsWeak,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      remainingDistanceMeters:
          remainingDistanceMeters ?? this.remainingDistanceMeters,
      remainingDurationSeconds:
          remainingDurationSeconds ?? this.remainingDurationSeconds,
      etaString: etaString ?? this.etaString,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class DrivingSessionController extends ChangeNotifier {
  DrivingSessionController({
    required TripRepository tripRepository,
    required AttemptRepository attemptRepository,
    required AttemptValidatorService validatorService,
    required SettingsService settings,
  }) : _tripRepository = tripRepository,
       _attemptRepository = attemptRepository,
       _validatorService = validatorService,
       _settings = settings {
    _speechService = CalloutSpeechService();
    _speechService.init().then((_) {
      _speechService.setEnabled(true);
    });
    _scheduler = CalloutScheduler(
      speechService: _speechService,
      settings: _settings,
    );
  }

  final TripRepository _tripRepository;
  final AttemptRepository _attemptRepository;
  final AttemptValidatorService _validatorService;
  final SettingsService _settings;

  late final CalloutSpeechService _speechService;
  late final CalloutScheduler _scheduler;
  NavigationFusionService? _fusionService;

  DrivingSessionSnapshot _snapshot = const DrivingSessionSnapshot(
    state: DrivingSessionState.idle,
    startedAt: null,
    elapsed: Duration.zero,
    distanceMeters: 0.0,
    recording: false,
    attemptRecordingState: AttemptRecordingState.idle,
    progressPercentage: 0.0,
    remainingDistanceMeters: 0.0,
    remainingDurationSeconds: 0.0,
    etaString: '--:--',
  );

  DrivingSessionSnapshot get snapshot => _snapshot;
  CalloutSpeechService get speechService => _speechService;
  CalloutScheduler get scheduler => _scheduler;
  NavigationFusionService? get fusionService => _fusionService;
  TripRepository get tripRepository => _tripRepository;

  List<RoutePoint> get activeRoutePoints => _activeRoutePoints;
  List<PaceNote> get activeNotes => _activeNotes;
  List<RoadWarning> get visibleRoadWarnings => _visibleRoadWarnings;
  List<SpeedLimitSegment> get visibleSpeedLimitSegments =>
      _visibleSpeedLimitSegments;
  bool get isRerouting => _isRerouting;

  // Stream for when rerouting completes, so the map UI can redraw the line
  final _reroutedController = StreamController<List<RoutePoint>>.broadcast();
  Stream<List<RoutePoint>> get onRerouted => _reroutedController.stream;

  // Internal trace state
  DateTime? _sessionStartedAt;
  DateTime? _lastPointAt;
  double? _lastLat;
  double? _lastLon;
  bool _flushingTrip = false;
  bool _flushingAttempt = false;

  final List<TripRecordingPoint> _pendingTripPoints = [];
  final List<TripRecordingPoint> _pendingAttemptPoints = [];

  // Attempt-specific fields
  DateTime? _attemptStartedAt;
  DateTime? _lastAttemptPointAt;
  double? _lastAttemptLat;
  double? _lastAttemptLon;
  double _attemptDistanceMeters = 0.0;
  bool _attemptCleanEligible = true;

  // Rerouting timing
  DateTime? _lastOnRouteTime;
  bool _isRerouting = false;

  // Active config values
  List<RoutePoint> _activeRoutePoints = [];
  List<PaceNote> _activeNotes = [];
  List<RoadWarning> _visibleRoadWarnings = [];
  List<SpeedLimitSegment> _visibleSpeedLimitSegments = [];

  Future<void> startSession(DrivingSessionConfig config) async {
    if (_snapshot.state != DrivingSessionState.idle) {
      await cancelSession();
    }

    _snapshot = _snapshot.copyWith(
      state: DrivingSessionState.preparing,
      config: config,
    );
    notifyListeners();

    // Check location permission
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _snapshot = _snapshot.copyWith(
        state: DrivingSessionState.error,
        errorMessage: 'Location services are disabled.',
      );
      notifyListeners();
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _snapshot = _snapshot.copyWith(
        state: DrivingSessionState.error,
        errorMessage: 'Location permission is required to drive.',
      );
      notifyListeners();
      return;
    }

    _activeRoutePoints = List<RoutePoint>.from(config.routePoints);
    _activeNotes = config.pacenotes
        .map((n) => n.copyWith(spoken: false))
        .toList();
    _visibleRoadWarnings = filterRoadWarnings(config.roadWarnings, _settings);
    _visibleSpeedLimitSegments = _settings.showSpeedLimits
        ? config.speedLimitSegments
        : const [];

    _scheduler.reset();
    _scheduler.loadRouteData(
      notes: _activeNotes,
      warnings: _visibleRoadWarnings,
      speedLimits: _visibleSpeedLimitSegments,
    );

    _fusionService = NavigationFusionService(
      routePoints: _activeRoutePoints,
      settings: _settings,
    );
    _fusionService!.addListener(_onFusionUpdate);

    final now = DateTime.now();
    _sessionStartedAt = now;
    _lastPointAt = null;
    _lastLat = null;
    _lastLon = null;

    String? tripId;
    bool recording = config.recordTrip;

    if (recording) {
      tripId = 'trip-${now.microsecondsSinceEpoch}';
      await _tripRepository.startTrip(
        id: tripId,
        startedAt: now,
        name:
            'Trip ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      );
    }

    _snapshot = DrivingSessionSnapshot(
      state: DrivingSessionState.active,
      config: config,
      startedAt: now,
      elapsed: Duration.zero,
      distanceMeters: 0.0,
      recording: recording,
      tripId: tripId,
      attemptRecordingState: config.attemptMode
          ? AttemptRecordingState.waitingToStart
          : AttemptRecordingState.idle,
      progressPercentage: 0.0,
      remainingDistanceMeters: _activeRoutePoints.isNotEmpty
          ? _activeRoutePoints.last.distanceFromStart
          : 0.0,
      remainingDurationSeconds: 0.0,
      etaString: '--:--',
    );

    _fusionService!.start();
    notifyListeners();
  }

  void pauseSession() {
    if (_snapshot.state != DrivingSessionState.active) return;
    _snapshot = _snapshot.copyWith(state: DrivingSessionState.paused);

    if (_snapshot.recording && _snapshot.tripId != null) {
      _tripRepository.pauseTrip(_snapshot.tripId!);
    }
    notifyListeners();
  }

  void resumeSession() {
    if (_snapshot.state != DrivingSessionState.paused) return;
    _snapshot = _snapshot.copyWith(state: DrivingSessionState.active);

    if (_snapshot.recording && _snapshot.tripId != null) {
      _tripRepository.resumeTrip(_snapshot.tripId!);
    }
    notifyListeners();
  }

  void resetCallouts() {
    _scheduler.reset();
    _scheduler.loadRouteData(
      notes: _activeNotes,
      warnings: _visibleRoadWarnings,
      speedLimits: _visibleSpeedLimitSegments,
    );
    notifyListeners();
  }

  Future<void> toggleRecording(bool enabled) async {
    if (_snapshot.state != DrivingSessionState.active &&
        _snapshot.state != DrivingSessionState.paused) {
      return;
    }
    if (_snapshot.recording == enabled) return;

    final now = DateTime.now();
    String? tripId = _snapshot.tripId;

    if (enabled) {
      // Start recording mid-drive
      tripId = 'trip-${now.microsecondsSinceEpoch}';
      await _tripRepository.startTrip(
        id: tripId,
        startedAt: now,
        name:
            'Trip ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      );
      _lastLat = _fusionService?.currentState?.rawLat;
      _lastLon = _fusionService?.currentState?.rawLon;
    } else {
      // Stop/finish recording mid-drive
      if (tripId != null) {
        await _flushTripPoints();
        await _tripRepository.finishTrip(
          tripId: tripId,
          endedAt: now,
          distanceMeters: _snapshot.distanceMeters,
          cleanEligible: true,
        );
      }
      tripId = null;
    }

    _snapshot = _snapshot.copyWith(
      recording: enabled,
      tripId: tripId,
      clearTripId: !enabled,
    );
    notifyListeners();
  }

  Future<String?> finishSession() async {
    final state = _snapshot.state;
    if (state == DrivingSessionState.idle ||
        state == DrivingSessionState.finished) {
      return _snapshot.tripId;
    }

    _snapshot = _snapshot.copyWith(state: DrivingSessionState.finishing);
    notifyListeners();

    _fusionService?.removeListener(_onFusionUpdate);
    _fusionService?.stop();

    final now = DateTime.now();
    final tripId = _snapshot.tripId;

    if (_snapshot.recording && tripId != null) {
      await _flushTripPoints();
      await _tripRepository.finishTrip(
        tripId: tripId,
        endedAt: now,
        distanceMeters: _snapshot.distanceMeters,
        cleanEligible: true,
      );
    }

    if (_snapshot.config?.attemptMode == true &&
        _snapshot.attemptRecordingState == AttemptRecordingState.recording) {
      await _finishAttempt();
    }

    _snapshot = _snapshot.copyWith(state: DrivingSessionState.finished);
    notifyListeners();

    return tripId;
  }

  Future<void> cancelSession() async {
    _fusionService?.removeListener(_onFusionUpdate);
    _fusionService?.stop();

    final tripId = _snapshot.tripId;
    if (tripId != null) {
      await _tripRepository.deleteTrip(tripId);
    }

    if (_snapshot.config?.attemptMode == true && _snapshot.attemptId != null) {
      await _attemptRepository.deleteAttempt(_snapshot.attemptId!);
    }

    _pendingTripPoints.clear();
    _pendingAttemptPoints.clear();

    _snapshot = const DrivingSessionSnapshot(
      state: DrivingSessionState.idle,
      startedAt: null,
      elapsed: Duration.zero,
      distanceMeters: 0.0,
      recording: false,
      attemptRecordingState: AttemptRecordingState.idle,
      progressPercentage: 0.0,
      remainingDistanceMeters: 0.0,
      remainingDurationSeconds: 0.0,
      etaString: '--:--',
    );
    notifyListeners();
  }

  // Abort attempt specifically without cancelling trip/navigation
  Future<void> abortAttempt() async {
    if (_snapshot.attemptRecordingState == AttemptRecordingState.recording ||
        _snapshot.attemptRecordingState ==
            AttemptRecordingState.waitingToStart) {
      final attemptId = _snapshot.attemptId;
      if (attemptId != null) {
        await _attemptRepository.deleteAttempt(attemptId);
      }
      _snapshot = _snapshot.copyWith(
        attemptRecordingState: AttemptRecordingState.aborted,
        attemptId: null,
      );
      _pendingAttemptPoints.clear();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _fusionService?.removeListener(_onFusionUpdate);
    _fusionService?.stop();
    _reroutedController.close();
    super.dispose();
  }

  void _onFusionUpdate() {
    final state = _fusionService?.currentState;
    final config = _snapshot.config;
    if (state == null || config == null) return;

    final now = DateTime.now();

    // 1. Accumulate distance for trip/drive
    var distance = _snapshot.distanceMeters;
    if (_lastLat != null && _lastLon != null) {
      final delta = haversineDistanceMeters(
        _lastLat!,
        _lastLon!,
        state.rawLat,
        state.rawLon,
      );
      if (delta.isFinite && delta < 120.0) {
        distance += delta;
      }
    }
    _lastLat = state.rawLat;
    _lastLon = state.rawLon;

    // 2. Trip points appending
    if (_snapshot.recording && _snapshot.tripId != null) {
      if (_lastPointAt == null ||
          now.difference(_lastPointAt!).inMilliseconds >= 700) {
        _lastPointAt = now;
        final speedLimit = _getCurrentSpeedLimit(distance);
        final speedKmh = state.rawSpeedMps * 3.6;
        final speedCompliant = speedLimit == null || speedKmh <= speedLimit + 8;

        _pendingTripPoints.add(
          TripRecordingPoint(
            recordedAt: state.timestamp,
            lat: state.rawLat,
            lon: state.rawLon,
            accuracyMeters: state.gpsAccuracyMeters,
            speedMps: state.rawSpeedMps,
            headingDegrees: state.headingDegrees,
            distanceFromStart: distance,
            speedLimitKmh: speedLimit,
            speedCompliant: speedCompliant,
          ),
        );

        if (_pendingTripPoints.length >= 5) {
          _flushTripPoints();
        }
      }
    }

    // 3. Attempt state checking & execution
    double distanceToStart = double.infinity;
    double distanceToFinish = double.infinity;

    if (config.attemptMode && config.routePoints.isNotEmpty) {
      final startPoint = config.routePoints.first;
      final finishPoint = config.routePoints.last;

      distanceToStart = haversineDistanceMeters(
        state.rawLat,
        state.rawLon,
        startPoint.lat,
        startPoint.lon,
      );
      distanceToFinish = haversineDistanceMeters(
        state.rawLat,
        state.rawLon,
        finishPoint.lat,
        finishPoint.lon,
      );

      if (_snapshot.attemptRecordingState ==
              AttemptRecordingState.waitingToStart &&
          distanceToStart <= 35.0) {
        _startAttempt(state);
      } else if (_snapshot.attemptRecordingState ==
          AttemptRecordingState.recording) {
        _updateAttemptRecording(state, now);
      }
    }

    // 4. Update Speech & Pacenotes Scheduler
    final distanceAlong = _fusionService?.distanceAlongRoute ?? 0.0;
    _scheduler.update(distanceAlong, state.displaySpeedMps);

    // 5. Autodetect off-route and trigger rerouting
    final distanceFromRoute = _fusionService?.distanceFromRoute ?? 0.0;
    final offRoute = distanceFromRoute > 60.0 && _activeRoutePoints.isNotEmpty;

    if (offRoute) {
      if (_lastOnRouteTime == null) {
        _lastOnRouteTime = now;
      } else if (now.difference(_lastOnRouteTime!).inSeconds >= 5 &&
          !_isRerouting) {
        _recalculateRoute(state);
      }
    } else {
      _lastOnRouteTime = null;
    }

    // 6. Update DriveState elements
    final nextNote = _nextNote(distanceAlong);
    final nextWarning = _nextRoadWarning(distanceAlong);
    final currentLimit = _currentSpeedLimitSegment(distanceAlong);

    final distanceToNote = nextNote == null
        ? null
        : math.max(0.0, nextNote.distanceFromStart - distanceAlong);
    final distanceToWarning = nextWarning == null
        ? null
        : math.max(0.0, nextWarning.distanceFromStart - distanceAlong);

    // Compute remaining items
    final remainingDistanceMeters = _activeRoutePoints.isNotEmpty
        ? math.max(
            0.0,
            _activeRoutePoints.last.distanceFromStart - distanceAlong,
          )
        : 0.0;

    double remainingDurationSeconds = 0.0;
    double prevDist = distanceAlong;
    final matchedIdx = _fusionService?.lastMatchedIndex ?? 0;
    for (var i = matchedIdx + 1; i < _activeRoutePoints.length; i++) {
      final p = _activeRoutePoints[i];
      final segmentLength = p.distanceFromStart - prevDist;
      if (segmentLength <= 0) continue;
      final limitSegment = _visibleSpeedLimitSegments.firstWhere(
        (s) =>
            p.distanceFromStart >= s.startDistance &&
            p.distanceFromStart <= s.endDistance,
        orElse: () => const SpeedLimitSegment(
          id: 'default',
          startDistance: 0.0,
          endDistance: 0.0,
          rawMaxspeed: '60',
          parsedKmh: 60,
        ),
      );
      final speedLimitMps = (limitSegment.parsedKmh ?? 60) / 3.6;
      remainingDurationSeconds += segmentLength / speedLimitMps;
      prevDist = p.distanceFromStart;
    }

    final etaTime = now.add(
      Duration(seconds: remainingDurationSeconds.round()),
    );
    final etaString =
        "${etaTime.hour.toString().padLeft(2, '0')}:${etaTime.minute.toString().padLeft(2, '0')}";

    final totalDistance = _activeRoutePoints.isNotEmpty
        ? _activeRoutePoints.last.distanceFromStart
        : 1.0;
    final progressPercentage = (distanceAlong / totalDistance).clamp(0.0, 1.0);

    // Determine speed limit value
    int? speedLimitKmh;
    if (currentLimit != null) {
      speedLimitKmh = currentLimit.parsedKmh;
    } else {
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
    }

    _snapshot = _snapshot.copyWith(
      elapsed: _sessionStartedAt != null
          ? now.difference(_sessionStartedAt!)
          : Duration.zero,
      distanceMeters: distance,
      speedMps: state.rawSpeedMps,
      headingDegrees: state.headingDegrees,
      gpsAccuracyMeters: state.gpsAccuracyMeters,
      distanceToStart: distanceToStart,
      distanceToFinish: distanceToFinish,
      nextNote: nextNote,
      distanceToNote: distanceToNote,
      nextWarning: nextWarning,
      distanceToWarning: distanceToWarning,
      currentLimit: currentLimit,
      offRoute: offRoute,
      gpsWeak: state.gpsAccuracyMeters > 20.0,
      progressPercentage: progressPercentage,
      remainingDistanceMeters: remainingDistanceMeters,
      remainingDurationSeconds: remainingDurationSeconds,
      etaString: etaString,
      speedLimitKmh: speedLimitKmh,
    );

    notifyListeners();
  }

  // Helper selectors
  int? _getCurrentSpeedLimit(double distance) {
    if (_activeRoutePoints.isEmpty) {
      final speedKmh = (_fusionService?.currentState?.rawSpeedMps ?? 0) * 3.6;
      if (speedKmh > 100) return 110;
      if (speedKmh > 80) return 90;
      if (speedKmh > 50) return 70;
      return 50;
    }
    final currentLimit = _currentSpeedLimitSegment(distance);
    return currentLimit?.parsedKmh;
  }

  PaceNote? _nextNote(double distance) {
    if (_activeNotes.isEmpty) return null;
    for (final note in _activeNotes) {
      if (note.distanceFromStart >= distance &&
          !_scheduler.spokenIds.contains(note.id) &&
          !_scheduler.expiredIds.contains(note.id)) {
        return note;
      }
    }
    return null;
  }

  RoadWarning? _nextRoadWarning(double distance) {
    if (_visibleRoadWarnings.isEmpty) return null;
    for (final warning in _visibleRoadWarnings) {
      if (warning.distanceFromStart >= distance &&
          !_scheduler.spokenIds.contains(warning.id) &&
          !_scheduler.expiredIds.contains(warning.id)) {
        return warning;
      }
    }
    return null;
  }

  SpeedLimitSegment? _currentSpeedLimitSegment(double distance) {
    if (_visibleSpeedLimitSegments.isEmpty) return null;
    for (final seg in _visibleSpeedLimitSegments) {
      if (distance >= seg.startDistance && distance <= seg.endDistance) {
        return seg;
      }
    }
    return null;
  }

  // Attempt logic
  Future<void> _startAttempt(FusedNavigationState state) async {
    final now = DateTime.now();
    final attemptId = 'attempt-${now.microsecondsSinceEpoch}';

    _attemptStartedAt = state.timestamp;
    _lastAttemptPointAt = state.timestamp;
    _lastAttemptLat = state.rawLat;
    _lastAttemptLon = state.rawLon;
    _attemptDistanceMeters = 0.0;
    _attemptCleanEligible = true;

    _snapshot = _snapshot.copyWith(
      attemptRecordingState: AttemptRecordingState.recording,
      attemptId: attemptId,
    );
    notifyListeners();

    try {
      await _attemptRepository.createAttempt(
        id: attemptId,
        segmentId: _snapshot.config!.segmentId!,
        startedAt: _attemptStartedAt!,
      );
    } catch (e) {
      _snapshot = _snapshot.copyWith(
        attemptRecordingState: AttemptRecordingState.aborted,
        errorMessage: 'Failed to start attempt: $e',
      );
      notifyListeners();
    }
  }

  void _updateAttemptRecording(FusedNavigationState state, DateTime now) {
    if (_lastAttemptPointAt != null &&
        state.timestamp.difference(_lastAttemptPointAt!).inMilliseconds < 700) {
      return;
    }

    if (_lastAttemptLat != null && _lastAttemptLon != null) {
      final delta = haversineDistanceMeters(
        _lastAttemptLat!,
        _lastAttemptLon!,
        state.rawLat,
        state.rawLon,
      );
      if (delta.isFinite && delta < 120.0) {
        _attemptDistanceMeters += delta;
      }
    }

    _lastAttemptLat = state.rawLat;
    _lastAttemptLon = state.rawLon;
    _lastAttemptPointAt = state.timestamp;

    if (state.gpsAccuracyMeters > 35.0) {
      _attemptCleanEligible = false;
    }

    final speedLimit = _getCurrentSpeedLimit(_attemptDistanceMeters);
    final speedKmh = state.rawSpeedMps * 3.6;
    final speedCompliant = speedLimit == null || speedKmh <= speedLimit + 8;

    _pendingAttemptPoints.add(
      TripRecordingPoint(
        recordedAt: state.timestamp,
        lat: state.rawLat,
        lon: state.rawLon,
        accuracyMeters: state.gpsAccuracyMeters,
        speedMps: state.rawSpeedMps,
        headingDegrees: state.headingDegrees,
        distanceFromStart: _attemptDistanceMeters,
        speedLimitKmh: speedLimit,
        speedCompliant: speedCompliant,
      ),
    );

    if (_pendingAttemptPoints.length >= 5) {
      _flushAttemptPoints();
    }

    // Check finish gate
    final elapsed = state.timestamp.difference(_attemptStartedAt!);
    if (_snapshot.distanceToFinish <= 35.0 && elapsed.inSeconds >= 2) {
      _finishAttempt();
    }
  }

  Future<void> _finishAttempt() async {
    final attemptId = _snapshot.attemptId;
    if (attemptId == null) return;

    _snapshot = _snapshot.copyWith(
      attemptRecordingState: AttemptRecordingState.finished,
    );
    notifyListeners();

    try {
      await _flushAttemptPoints();
      await _attemptRepository.finishAttempt(
        attemptId: attemptId,
        finishedAt: DateTime.now(),
        status: 'finished',
        officialEligible: _attemptCleanEligible,
      );
      await _validatorService.validateAndPersist(attemptId);
    } catch (e) {
      _snapshot = _snapshot.copyWith(
        errorMessage: 'Attempt validation failed: $e',
      );
      notifyListeners();
    }
  }

  // Flushing methods
  Future<void> _flushTripPoints() async {
    final tripId = _snapshot.tripId;
    if (tripId == null || _pendingTripPoints.isEmpty || _flushingTrip) return;
    _flushingTrip = true;
    final batch = List<TripRecordingPoint>.from(_pendingTripPoints);
    _pendingTripPoints.clear();
    try {
      await _tripRepository.appendTripPoints(tripId, batch);
      await _tripRepository.updateTripProgress(
        tripId: tripId,
        distanceMeters: _snapshot.distanceMeters,
        cleanEligible: true,
        status: _snapshot.state == DrivingSessionState.paused
            ? 'paused'
            : 'recording',
      );
    } finally {
      _flushingTrip = false;
      if (_pendingTripPoints.length >= 5) {
        _flushTripPoints();
      }
    }
  }

  Future<void> _flushAttemptPoints() async {
    final attemptId = _snapshot.attemptId;
    if (attemptId == null || _pendingAttemptPoints.isEmpty || _flushingAttempt)
      return;
    _flushingAttempt = true;
    final batch = List<TripRecordingPoint>.from(_pendingAttemptPoints);
    _pendingAttemptPoints.clear();
    try {
      await _attemptRepository.appendAttemptPoints(attemptId, batch);
    } finally {
      _flushingAttempt = false;
      if (_pendingAttemptPoints.length >= 5) {
        _flushAttemptPoints();
      }
    }
  }

  // Recalculate route
  Future<void> _recalculateRoute(FusedNavigationState state) async {
    if (_isRerouting) return;
    _isRerouting = true;

    final startPoint = RoutePoint(lat: state.rawLat, lon: state.rawLon);
    final destination = _activeRoutePoints.last;

    try {
      _speechService.speak('Off route. Recalculating route.', () {});

      final newPoints = await OrsService(
        settings: _settings,
      ).buildRoute([startPoint, destination]);
      if (newPoints.isEmpty) throw Exception('No points returned');

      final newPacenotes = PacenoteGenerator(
        settings: _settings,
      ).generate(newPoints);

      _activeRoutePoints = newPoints;
      _activeNotes = newPacenotes
          .map((n) => n.copyWith(spoken: false))
          .toList();
      _visibleRoadWarnings = [];
      _visibleSpeedLimitSegments = [];

      _fusionService?.updateRoutePoints(_activeRoutePoints);

      _scheduler.reset();
      _scheduler.loadRouteData(
        notes: _activeNotes,
        warnings: _visibleRoadWarnings,
        speedLimits: _visibleSpeedLimitSegments,
      );

      _reroutedController.add(_activeRoutePoints);
      _lastOnRouteTime = null;

      _enrichRecalculatedRoute(newPoints);
    } catch (e) {
      debugPrint('Rerouting failed: $e');
      _speechService.speak(
        'Recalculating route failed. Please check internet connection.',
        () {},
      );
    } finally {
      _isRerouting = false;
    }
  }

  Future<void> _enrichRecalculatedRoute(List<RoutePoint> newPoints) async {
    try {
      final enrichment = await OverpassService().enrichRoute(newPoints);
      _visibleRoadWarnings = filterRoadWarnings(
        enrichment.roadWarnings,
        _settings,
      );
      _visibleSpeedLimitSegments = _settings.showSpeedLimits
          ? enrichment.speedLimitSegments
          : const [];

      _scheduler.reset();
      _scheduler.loadRouteData(
        notes: _activeNotes,
        warnings: _visibleRoadWarnings,
        speedLimits: _visibleSpeedLimitSegments,
      );
    } catch (e) {
      debugPrint('Enrichment failed: $e');
    }
  }
}
