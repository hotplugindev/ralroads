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
import '../services/attempt_validator_service.dart';
import '../services/navigation_fusion_service.dart';
import '../services/callout_speech_service.dart';
import '../services/callout_scheduler.dart';
import '../utils/geo_math.dart';

import 'callout_runtime_controller.dart';
import 'trip_capture_controller.dart';
import 'attempt_runtime_controller.dart';
import 'navigation_runtime_controller.dart';

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
      attemptRecordingState: attemptRecordingState ?? this.attemptRecordingState,
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
      remainingDistanceMeters: remainingDistanceMeters ?? this.remainingDistanceMeters,
      remainingDurationSeconds: remainingDurationSeconds ?? this.remainingDurationSeconds,
      etaString: etaString ?? this.etaString,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class DrivingSessionCoordinator extends ChangeNotifier {
  DrivingSessionCoordinator({
    required TripRepository tripRepository,
    required AttemptRepository attemptRepository,
    required AttemptValidatorService validatorService,
    required SettingsService settings,
  }) : _tripRepository = tripRepository,
       _attemptRepository = attemptRepository,
       _validatorService = validatorService,
       _settings = settings {
    _calloutController = CalloutRuntimeController(settings: _settings);
    _tripCapture = TripCaptureController(tripRepository: _tripRepository);
    _attemptRuntime = AttemptRuntimeController(
      attemptRepository: _attemptRepository,
      validatorService: _validatorService,
    );
    _navigationRuntime = NavigationRuntimeController(settings: _settings);
  }

  final TripRepository _tripRepository;
  final AttemptRepository _attemptRepository;
  final AttemptValidatorService _validatorService;
  final SettingsService _settings;

  late final CalloutRuntimeController _calloutController;
  late final TripCaptureController _tripCapture;
  late final AttemptRuntimeController _attemptRuntime;
  late final NavigationRuntimeController _navigationRuntime;

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

  CalloutSpeechService get speechService => _calloutController.speechService;
  CalloutScheduler get scheduler => _calloutController.scheduler;
  NavigationFusionService? get fusionService => _navigationRuntime.fusionService;
  TripRepository get tripRepository => _tripRepository;

  List<RoutePoint> get activeRoutePoints => _navigationRuntime.activeRoutePoints;
  List<PaceNote> get activeNotes => _navigationRuntime.activeNotes;
  List<RoadWarning> get visibleRoadWarnings => _navigationRuntime.visibleRoadWarnings;
  List<SpeedLimitSegment> get visibleSpeedLimitSegments => _navigationRuntime.visibleSpeedLimitSegments;
  bool get isRerouting => _navigationRuntime.isRerouting;
  Stream<List<RoutePoint>> get onRerouted => _navigationRuntime.onRerouted;

  DateTime? _sessionStartedAt;

  Future<void> startSession(DrivingSessionConfig config) async {
    if (_snapshot.state != DrivingSessionState.idle) {
      await cancelSession();
    }

    _snapshot = _snapshot.copyWith(
      state: DrivingSessionState.preparing,
      config: config,
    );
    notifyListeners();

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

    _navigationRuntime.initializeRoute(
      routePoints: config.routePoints,
      pacenotes: config.pacenotes,
      roadWarnings: config.roadWarnings,
      speedLimitSegments: config.speedLimitSegments,
    );

    _calloutController.reset();
    _calloutController.loadRouteData(
      notes: _navigationRuntime.activeNotes,
      warnings: _navigationRuntime.visibleRoadWarnings,
      speedLimits: _navigationRuntime.visibleSpeedLimitSegments,
    );

    final now = DateTime.now();
    _sessionStartedAt = now;

    _tripCapture.reset(
      _navigationRuntime.currentState?.rawLat,
      _navigationRuntime.currentState?.rawLon,
    );
    _attemptRuntime.reset();

    String? tripId;
    bool recording = config.recordTrip;

    if (recording) {
      tripId = 'trip-${now.microsecondsSinceEpoch}';
      await _tripCapture.startTrip(
        tripId: tripId,
        startedAt: now,
        name: 'Trip ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
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
      remainingDistanceMeters: activeRoutePoints.isNotEmpty
          ? activeRoutePoints.last.distanceFromStart
          : 0.0,
      remainingDurationSeconds: 0.0,
      etaString: '--:--',
    );

    _navigationRuntime.startFusion(_onFusionUpdate);
    notifyListeners();
  }

  void pauseSession() {
    if (_snapshot.state != DrivingSessionState.active) return;
    _snapshot = _snapshot.copyWith(state: DrivingSessionState.paused);

    if (_snapshot.recording && _snapshot.tripId != null) {
      _tripCapture.pauseTrip(_snapshot.tripId!);
    }
    notifyListeners();
  }

  void resumeSession() {
    if (_snapshot.state != DrivingSessionState.paused) return;
    _snapshot = _snapshot.copyWith(state: DrivingSessionState.active);

    if (_snapshot.recording && _snapshot.tripId != null) {
      _tripCapture.resumeTrip(_snapshot.tripId!);
    }
    notifyListeners();
  }

  void resetCallouts() {
    _calloutController.reset();
    _calloutController.loadRouteData(
      notes: _navigationRuntime.activeNotes,
      warnings: _navigationRuntime.visibleRoadWarnings,
      speedLimits: _navigationRuntime.visibleSpeedLimitSegments,
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
      tripId = 'trip-${now.microsecondsSinceEpoch}';
      await _tripCapture.startTrip(
        tripId: tripId,
        startedAt: now,
        name: 'Trip ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      );
      _tripCapture.reset(
        _navigationRuntime.currentState?.rawLat,
        _navigationRuntime.currentState?.rawLon,
      );
    } else {
      if (tripId != null) {
        await _tripCapture.flushAndFinish(
          tripId: tripId,
          endedAt: now,
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

    _navigationRuntime.stopFusion(_onFusionUpdate);

    final now = DateTime.now();
    final tripId = _snapshot.tripId;

    if (_snapshot.recording && tripId != null) {
      await _tripCapture.flushAndFinish(
        tripId: tripId,
        endedAt: now,
        cleanEligible: true,
      );
    }

    if (_snapshot.config?.attemptMode == true &&
        _snapshot.attemptRecordingState == AttemptRecordingState.recording) {
      await _attemptRuntime.finishAttempt();
    }

    _snapshot = _snapshot.copyWith(
      state: DrivingSessionState.finished,
      attemptRecordingState: _snapshot.config?.attemptMode == true
          ? _attemptRuntime.recordingState
          : _snapshot.attemptRecordingState,
    );
    notifyListeners();

    return tripId;
  }

  Future<void> cancelSession() async {
    _navigationRuntime.stopFusion(_onFusionUpdate);

    final tripId = _snapshot.tripId;
    if (tripId != null) {
      await _tripCapture.deleteTrip(tripId);
    }

    if (_snapshot.config?.attemptMode == true && _snapshot.attemptId != null) {
      await _attemptRuntime.deleteAttempt();
    }

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

  Future<void> abortAttempt() async {
    if (_snapshot.attemptRecordingState == AttemptRecordingState.recording ||
        _snapshot.attemptRecordingState == AttemptRecordingState.waitingToStart) {
      await _attemptRuntime.deleteAttempt();
      _snapshot = _snapshot.copyWith(
        attemptRecordingState: AttemptRecordingState.aborted,
        attemptId: null,
        clearAttemptId: true,
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _navigationRuntime.stopFusion(_onFusionUpdate);
    _navigationRuntime.dispose();
    _calloutController.dispose();
    super.dispose();
  }

  void _onFusionUpdate() {
    final state = _navigationRuntime.currentState;
    final config = _snapshot.config;
    if (state == null || config == null) return;

    final now = DateTime.now();

    final speedLimit = _getCurrentSpeedLimit(_tripCapture.distanceMeters);

    // 1. Accumulate and record trip location
    if (_snapshot.recording && _snapshot.tripId != null) {
      _tripCapture.trackLocation(
        tripId: _snapshot.tripId!,
        timestamp: state.timestamp,
        lat: state.rawLat,
        lon: state.rawLon,
        gpsAccuracyMeters: state.gpsAccuracyMeters,
        rawSpeedMps: state.rawSpeedMps,
        headingDegrees: state.headingDegrees,
        speedLimitKmh: speedLimit,
        isPaused: _snapshot.state == DrivingSessionState.paused,
      );
    }

    // 2. Attempt checks
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

      if (_snapshot.attemptRecordingState == AttemptRecordingState.waitingToStart &&
          distanceToStart <= 35.0) {
        final attId = 'attempt-${now.microsecondsSinceEpoch}';
        _attemptRuntime.startAttempt(
          attemptId: attId,
          segmentId: config.segmentId!,
          lat: state.rawLat,
          lon: state.rawLon,
          timestamp: state.timestamp,
        ).then((_) {
          _snapshot = _snapshot.copyWith(
            attemptRecordingState: _attemptRuntime.recordingState,
            attemptId: _attemptRuntime.attemptId,
          );
          notifyListeners();
        });
      } else if (_snapshot.attemptRecordingState == AttemptRecordingState.recording) {
        _attemptRuntime.updateAttemptRecording(
          lat: state.rawLat,
          lon: state.rawLon,
          gpsAccuracyMeters: state.gpsAccuracyMeters,
          rawSpeedMps: state.rawSpeedMps,
          headingDegrees: state.headingDegrees,
          speedLimitKmh: speedLimit,
          timestamp: state.timestamp,
        );

        final elapsed = state.timestamp.difference(_attemptRuntime.attemptStartedAt ?? now);
        if (distanceToFinish <= 35.0 && elapsed.inSeconds >= 2) {
          _attemptRuntime.finishAttempt().then((_) {
            _snapshot = _snapshot.copyWith(
              attemptRecordingState: _attemptRuntime.recordingState,
            );
            notifyListeners();
          });
        }
      }
    }

    // 3. Speech & Pacenotes updates
    final distanceAlong = _navigationRuntime.distanceAlongRoute;
    _calloutController.update(distanceAlong, state.displaySpeedMps);

    // 4. Off route checks
    _navigationRuntime.checkOffRoute(
      state,
      now,
      (msg) async => _calloutController.speechService.speak(msg, () {}),
      () {
        _snapshot = _snapshot.copyWith(offRoute: true);
        notifyListeners();
      },
      (newNotes, newWarnings, newLimits) {
        _calloutController.reset();
        _calloutController.loadRouteData(
          notes: newNotes,
          warnings: newWarnings,
          speedLimits: newLimits,
        );
        notifyListeners();
      },
    );

    // 5. Build snapshot properties
    final nextNote = _nextNote(distanceAlong);
    final nextWarning = _nextRoadWarning(distanceAlong);
    final currentLimit = _currentSpeedLimitSegment(distanceAlong);

    final distanceToNote = nextNote == null
        ? null
        : math.max(0.0, nextNote.distanceFromStart - distanceAlong);
    final distanceToWarning = nextWarning == null
        ? null
        : math.max(0.0, nextWarning.distanceFromStart - distanceAlong);

    final remainingDistanceMeters = activeRoutePoints.isNotEmpty
        ? math.max(0.0, activeRoutePoints.last.distanceFromStart - distanceAlong)
        : 0.0;

    double remainingDurationSeconds = 0.0;
    double prevDist = distanceAlong;
    final matchedIdx = _navigationRuntime.lastMatchedIndex;
    for (var i = matchedIdx + 1; i < activeRoutePoints.length; i++) {
      final p = activeRoutePoints[i];
      final segmentLength = p.distanceFromStart - prevDist;
      if (segmentLength <= 0) continue;
      final limitSegment = visibleSpeedLimitSegments.firstWhere(
        (s) => p.distanceFromStart >= s.startDistance && p.distanceFromStart <= s.endDistance,
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

    final etaTime = now.add(Duration(seconds: remainingDurationSeconds.round()));
    final etaString = "${etaTime.hour.toString().padLeft(2, '0')}:${etaTime.minute.toString().padLeft(2, '0')}";

    final totalDistance = activeRoutePoints.isNotEmpty
        ? activeRoutePoints.last.distanceFromStart
        : 1.0;
    final progressPercentage = (distanceAlong / totalDistance).clamp(0.0, 1.0);

    // Speed limit value
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
      elapsed: _sessionStartedAt != null ? now.difference(_sessionStartedAt!) : Duration.zero,
      distanceMeters: _tripCapture.distanceMeters,
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
      offRoute: _navigationRuntime.isRerouting || _navigationRuntime.distanceFromRoute > 60.0,
      gpsWeak: state.gpsAccuracyMeters > 20.0,
      progressPercentage: progressPercentage,
      remainingDistanceMeters: remainingDistanceMeters,
      remainingDurationSeconds: remainingDurationSeconds,
      etaString: etaString,
      speedLimitKmh: speedLimitKmh,
      attemptRecordingState: _attemptRuntime.recordingState,
      attemptId: _attemptRuntime.attemptId,
    );

    notifyListeners();
  }

  int? _getCurrentSpeedLimit(double distance) {
    if (activeRoutePoints.isEmpty) {
      final speedKmh = (_navigationRuntime.currentState?.rawSpeedMps ?? 0) * 3.6;
      if (speedKmh > 100) return 110;
      if (speedKmh > 80) return 90;
      if (speedKmh > 50) return 70;
      return 50;
    }
    final currentLimit = _currentSpeedLimitSegment(distance);
    return currentLimit?.parsedKmh;
  }

  PaceNote? _nextNote(double distance) {
    if (activeNotes.isEmpty) return null;
    for (final note in activeNotes) {
      if (note.distanceFromStart >= distance &&
          !scheduler.spokenIds.contains(note.id) &&
          !scheduler.expiredIds.contains(note.id)) {
        return note;
      }
    }
    return null;
  }

  RoadWarning? _nextRoadWarning(double distance) {
    if (visibleRoadWarnings.isEmpty) return null;
    for (final warning in visibleRoadWarnings) {
      if (warning.distanceFromStart >= distance &&
          !scheduler.spokenIds.contains(warning.id) &&
          !scheduler.expiredIds.contains(warning.id)) {
        return warning;
      }
    }
    return null;
  }

  SpeedLimitSegment? _currentSpeedLimitSegment(double distance) {
    if (visibleSpeedLimitSegments.isEmpty) return null;
    for (final seg in visibleSpeedLimitSegments) {
      if (distance >= seg.startDistance && distance <= seg.endDistance) {
        return seg;
      }
    }
    return null;
  }
}
