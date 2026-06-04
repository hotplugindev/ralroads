import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../services/gps_route_matcher.dart';
import '../services/settings_service.dart';
import '../services/voice_service.dart';
import '../utils/geo_math.dart';
import '../utils/format_helpers.dart';
import '../utils/ui_helpers.dart';

class DriveState {
  final PaceNote? nextNote;
  final double? distanceToNote;
  final RoadWarning? nextWarning;
  final double? distanceToWarning;
  final SpeedLimitSegment? currentLimit;
  final double speedMps;
  final bool offRoute;
  final bool gpsWeak;
  final String? permissionMessage;

  const DriveState({
    this.nextNote,
    this.distanceToNote,
    this.nextWarning,
    this.distanceToWarning,
    this.currentLimit,
    this.speedMps = 0.0,
    this.offRoute = false,
    this.gpsWeak = false,
    this.permissionMessage,
  });
}

class DriveScreen extends StatefulWidget {
  const DriveScreen({
    required this.routePoints,
    required this.pacenotes,
    required this.roadWarnings,
    required this.speedLimitSegments,
    required this.settings,
    this.isSimulation = false,
    super.key,
  });

  final List<RoutePoint> routePoints;
  final List<PaceNote> pacenotes;
  final List<RoadWarning> roadWarnings;
  final List<SpeedLimitSegment> speedLimitSegments;
  final SettingsService settings;
  final bool isSimulation;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> with WidgetsBindingObserver {
  final _matcher = GpsRouteMatcher();
  final _voice = VoiceService();
  late List<PaceNote> _notes;
  StreamSubscription<Position>? _positionSubscription;
  maplibre.MapLibreMapController? _controller;
  maplibre.Line? _baseRouteLine;
  final List<maplibre.Line> _dangerLines = [];
  final List<maplibre.Circle> _noteMarkers = [];
  final List<maplibre.Symbol> _noteLabels = [];
  final List<maplibre.Circle> _warningMarkers = [];
  final List<maplibre.Symbol> _warningLabels = [];
  maplibre.Circle? _currentOuterCircle;
  maplibre.Circle? _currentInnerCircle;
  maplibre.Symbol? _currentArrow;
  Position? _lastPosition;
  Position? _previousPosition;
  int _lastMatchedIndex = 0;
  double _distanceAlongRoute = 0;
  double _distanceFromRoute = 0;
  double _speedMps = 0;
  String? _permissionMessage;

  // ValueNotifiers for performance-optimized UI updates
  late final ValueNotifier<DriveState> _driveStateNotifier;
  late final ValueNotifier<bool> _followLocationNotifier;
  late final ValueNotifier<bool> _voiceEnabledNotifier;
  late final ValueNotifier<bool> _simulationPausedNotifier;
  late final ValueNotifier<double> _simulationSpeedKmhNotifier;

  String? _lastLoadedStyle;
  bool _carImageLoaded = false;
  double _lastGoodHeading = 0;
  double? _lastVisualLat;
  double? _lastVisualLon;
  bool _gpsWeak = false;
  final Set<String> _spokenWarningIds = {};
  double _rawSpeedMps = 0;
  double _gpsAccuracy = 0;
  double _gpsHeading = 0;
  Timer? _simulationTimer;
  double _simulatedDistance = 0.0;
  DateTime? _lastCameraUpdateTime;

  int _findNextNoteIndex(double distance) {
    if (_notes.isEmpty) return -1;
    var low = 0;
    var high = _notes.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_notes[mid].distanceFromStart >= distance) {
        result = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return result;
  }

  int _findNextWarningIndex(double distance) {
    final warnings = _visibleRoadWarnings;
    if (warnings.isEmpty) return -1;
    var low = 0;
    var high = warnings.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (warnings[mid].distanceFromStart >= distance) {
        result = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return result;
  }

  int _findCurrentSpeedLimitIndex(double distance) {
    final segments = _visibleSpeedLimitSegments;
    if (segments.isEmpty) return -1;
    var low = 0;
    var high = segments.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (segments[mid].startDistance <= distance) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }

  PaceNote? get _nextNote {
    final idx = _findNextNoteIndex(_distanceAlongRoute);
    if (idx == -1) return null;
    for (var i = idx; i < _notes.length; i++) {
      if (!_notes[i].spoken) {
        return _notes[i];
      }
    }
    return null;
  }

  List<RoadWarning> get _visibleRoadWarnings =>
      filterRoadWarnings(widget.roadWarnings, widget.settings);

  List<SpeedLimitSegment> get _visibleSpeedLimitSegments =>
      widget.settings.showSpeedLimits ? widget.speedLimitSegments : const [];

  RoadWarning? get _nextRoadWarning {
    final idx = _findNextWarningIndex(_distanceAlongRoute);
    if (idx == -1) return null;
    return _visibleRoadWarnings[idx];
  }

  SpeedLimitSegment? get _currentSpeedLimit {
    final idx = _findCurrentSpeedLimitIndex(_distanceAlongRoute);
    if (idx == -1) return null;
    final seg = _visibleSpeedLimitSegments[idx];
    if (_distanceAlongRoute >= seg.startDistance && _distanceAlongRoute <= seg.endDistance) {
      return seg;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _driveStateNotifier = ValueNotifier<DriveState>(const DriveState());
    _followLocationNotifier = ValueNotifier<bool>(true);
    _voiceEnabledNotifier = ValueNotifier<bool>(true);
    _simulationPausedNotifier = ValueNotifier<bool>(false);
    _simulationSpeedKmhNotifier = ValueNotifier<double>(50.0);

    WidgetsBinding.instance.addObserver(this);
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock enable failed: $e');
    }
    _notes = widget.pacenotes
        .map((note) => note.copyWith(spoken: false))
        .toList();
    _voice.init();
    _startLocationTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock disable failed: $e');
    }
    _positionSubscription?.cancel();
    _simulationTimer?.cancel();
    _voice.stop();
    _driveStateNotifier.dispose();
    _followLocationNotifier.dispose();
    _voiceEnabledNotifier.dispose();
    _simulationPausedNotifier.dispose();
    _simulationSpeedKmhNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      if (state == AppLifecycleState.resumed) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('Wakelock toggle on lifecycle failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) {
              if (_followLocationNotifier.value) {
                _followLocationNotifier.value = false;
              }
            },
            child: maplibre.MapLibreMap(
              styleString: getMapStyle(context, widget.settings),
              initialCameraPosition: _initialDriveCameraPosition(),
              attributionButtonPosition: maplibre.AttributionButtonPosition.bottomRight,
              attributionButtonMargins: const math.Point(-1000, -1000),
              myLocationEnabled: false,
              onMapCreated: (controller) {
                _controller = controller;
              },
              onStyleLoadedCallback: _drawStaticMapLayers,
            ),
          ),
          if (widget.routePoints.isEmpty)
            Positioned(
              top: 96,
              left: 16,
              right: 16,
              child: SafeArea(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No route geometry available.'),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: FloatingActionButton.small(
                heroTag: 'drive-back',
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                child: const Icon(Icons.arrow_back),
              ),
            ),
          ),
          if (widget.isSimulation)
            Positioned(
              top: 72,
              left: 12,
              right: 12,
              child: SafeArea(
                child: Card(
                  color: Theme.of(context).colorScheme.surface.withAlpha(230),
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: _simulationPausedNotifier,
                          builder: (context, paused, _) {
                            return IconButton(
                              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                              tooltip: paused ? 'Play' : 'Pause',
                              onPressed: () {
                                _simulationPausedNotifier.value = !paused;
                              },
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.replay),
                          tooltip: 'Restart',
                          onPressed: () {
                            _simulatedDistance = 0.0;
                            _lastMatchedIndex = 0;
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: ValueListenableBuilder<double>(
                              valueListenable: _simulationSpeedKmhNotifier,
                              builder: (context, speedKmh, _) {
                                return DropdownButton<double>(
                                  value: speedKmh,
                                  isExpanded: true,
                                  items: [30.0, 50.0, 70.0, 90.0, 120.0].map((speed) {
                                    return DropdownMenuItem<double>(
                                      value: speed,
                                      child: Text('${speed.round()} km/h'),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      _simulationSpeedKmhNotifier.value = val;
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          tooltip: 'Exit Simulation',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 72,
            child: SafeArea(
              child: GestureDetector(
                onLongPress: _showDebugBottomSheet,
                child: ValueListenableBuilder<DriveState>(
                  valueListenable: _driveStateNotifier,
                  builder: (context, state, _) {
                    return _SpeedCard(
                      speedMps: state.speedMps,
                      speedLimit: state.currentLimit,
                      gpsWeak: state.gpsWeak,
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _followLocationNotifier,
                    builder: (context, follow, _) {
                      return _DriveRoundButton(
                        heroTag: 'drive-follow',
                        tooltip: follow ? 'Disable follow' : 'Recenter',
                        icon: follow ? Icons.gps_fixed : Icons.my_location,
                        active: follow,
                        onPressed: _toggleFollowMode,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<bool>(
                    valueListenable: _voiceEnabledNotifier,
                    builder: (context, voice, _) {
                      return _DriveRoundButton(
                        heroTag: 'drive-voice',
                        tooltip: voice ? 'Pause voice' : 'Resume voice',
                        icon: voice ? Icons.volume_up : Icons.volume_off,
                        active: voice,
                        onPressed: _toggleVoice,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _DriveRoundButton(
                    heroTag: 'drive-reset',
                    tooltip: 'Reset callouts',
                    icon: Icons.restart_alt,
                    active: false,
                    onPressed: _resetNotes,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: ValueListenableBuilder<DriveState>(
                valueListenable: _driveStateNotifier,
                builder: (context, state, _) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withAlpha(238),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 14,
                          color: Colors.black38,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (state.permissionMessage != null) ...[
                            Text(
                              state.permissionMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (state.offRoute) ...[
                            Text(
                              'Off route',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          _CalloutRow(
                            note: state.nextNote,
                            distanceMeters: state.distanceToNote,
                          ),
                          if (state.nextWarning != null && state.distanceToWarning != null) ...[
                            const SizedBox(height: 10),
                            _WarningRow(
                              warning: state.nextWarning!,
                              distanceMeters: state.distanceToWarning!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  maplibre.CameraPosition _initialDriveCameraPosition() {
    if (widget.routePoints.isEmpty) {
      return const maplibre.CameraPosition(
        target: maplibre.LatLng(43.8, 11.2),
        zoom: 5,
      );
    }

    final first = widget.routePoints.first;
    return maplibre.CameraPosition(
      target: maplibre.LatLng(first.lat, first.lon),
      zoom: 12,
    );
  }

  Future<void> _startLocationTracking() async {
    if (widget.isSimulation) {
      _startSimulation();
      return;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _permissionMessage = 'Location services are disabled.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _permissionMessage = 'Location permission is required for drive mode.';
      });
      return;
    }

    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        intervalDuration: const Duration(milliseconds: 500),
        forceLocationManager: false,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      );
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_handlePosition);
  }

  void _handlePosition(Position position) {
    final match = _matcher.match(
      lat: position.latitude,
      lon: position.longitude,
      routePoints: widget.routePoints,
      lastMatchedIndex: _lastMatchedIndex,
    );

    double calculatedSpeed = position.speed;
    final prevPos = _lastPosition;
    if (calculatedSpeed < 0 || calculatedSpeed.isNaN || !calculatedSpeed.isFinite) {
      if (prevPos != null) {
        final timeDiffSec = position.timestamp.difference(prevPos.timestamp).inMilliseconds / 1000.0;
        if (timeDiffSec > 0.05) {
          final dist = haversineDistanceMeters(
            prevPos.latitude,
            prevPos.longitude,
            position.latitude,
            position.longitude,
          );
          calculatedSpeed = dist / timeDiffSec;
        } else {
          calculatedSpeed = _speedMps;
        }
      } else {
        calculatedSpeed = 0.0;
      }
    }

    if (prevPos != null) {
      final timeDiffSec = position.timestamp.difference(prevPos.timestamp).inMilliseconds / 1000.0;
      if (timeDiffSec > 0.05) {
        final acceleration = (calculatedSpeed - _speedMps).abs() / timeDiffSec;
        if (acceleration > 15.0) {
          calculatedSpeed = _speedMps + (calculatedSpeed > _speedMps ? 15.0 : -15.0) * timeDiffSec;
          if (calculatedSpeed < 0) calculatedSpeed = 0;
        }
      }
    }

    final newSpeed = _speedMps * 0.65 + calculatedSpeed * 0.35;

    double visualLat = position.latitude;
    double visualLon = position.longitude;
    if (_lastVisualLat != null && _lastVisualLon != null) {
      final dist = haversineDistanceMeters(
        _lastVisualLat!,
        _lastVisualLon!,
        position.latitude,
        position.longitude,
      );
      if (dist > 150.0) {
        final fraction = 150.0 / dist;
        visualLat = _lastVisualLat! + (position.latitude - _lastVisualLat!) * fraction;
        visualLon = _lastVisualLon! + (position.longitude - _lastVisualLon!) * fraction;
      }
      visualLat = _lastVisualLat! * 0.25 + visualLat * 0.75;
      visualLon = _lastVisualLon! * 0.25 + visualLon * 0.75;
    }
    _lastVisualLat = visualLat;
    _lastVisualLon = visualLon;

    _previousPosition = _lastPosition;
    _lastPosition = position;
    _lastMatchedIndex = match.nearestIndex;
    _distanceAlongRoute = match.distanceAlongRoute;
    _distanceFromRoute = match.distanceFromRoute;
    _speedMps = newSpeed;
    _rawSpeedMps = calculatedSpeed;
    _gpsAccuracy = position.accuracy;
    _gpsHeading = position.heading.isFinite ? position.heading : 0.0;
    _gpsWeak = position.accuracy > 20.0;

    _updateCurrentLocationMarker(position, visualLat, visualLon);
    if (_followLocationNotifier.value) {
      _followPosition(visualLat, visualLon);
    }
    _maybeSpeakNextNote();
    _maybeSpeakNextWarning();

    final nextNote = _nextNote;
    final nextWarning = _nextRoadWarning;
    final currentLimit = _currentSpeedLimit;
    final distanceToNote = nextNote == null
        ? null
        : math.max(0.0, nextNote.distanceFromStart - _distanceAlongRoute);
    final distanceToWarning = nextWarning == null
        ? null
        : math.max(0.0, nextWarning.distanceFromStart - _distanceAlongRoute);
    final offRoute = _distanceFromRoute > 60 && _lastPosition != null;

    _driveStateNotifier.value = DriveState(
      nextNote: nextNote,
      distanceToNote: distanceToNote,
      nextWarning: nextWarning,
      distanceToWarning: distanceToWarning,
      currentLimit: currentLimit,
      speedMps: _speedMps,
      offRoute: offRoute,
      gpsWeak: _gpsWeak,
      permissionMessage: _permissionMessage,
    );
  }

  void _maybeSpeakNextNote() {
    final note = _nextNote;
    if (note == null) {
      return;
    }

    final distanceToNote = note.distanceFromStart - _distanceAlongRoute;
    final triggerDistance = _speedMps > 1
        ? math.max(50.0, _speedMps * 4.5)
        : 50.0;

    if (distanceToNote > triggerDistance) {
      return;
    }

    final noteIndex = _notes.indexWhere((candidate) => candidate.id == note.id);
    if (noteIndex == -1) {
      return;
    }

    String speakText = note.rallyText;

    final List<int> spokenIndices = [noteIndex];
    var currentIdx = noteIndex;
    var linkCount = 0;

    while (linkCount < 2) {
      final currentNote = _notes[currentIdx];
      if (currentNote.intoNoteId == null) {
        break;
      }
      
      final nextIdx = _notes.indexWhere((n) => n.id == currentNote.intoNoteId);
      if (nextIdx == -1 || nextIdx <= currentIdx || _notes[nextIdx].spoken) {
        break;
      }
      
      final nextNote = _notes[nextIdx];
      speakText = '$speakText into ${nextNote.rallyText}';
      currentIdx = nextIdx;
      spokenIndices.add(nextIdx);
      linkCount++;
    }

    _voice.speak(speakText);

    for (final idx in spokenIndices) {
      _notes[idx] = _notes[idx].copyWith(spoken: true);
    }
  }

  void _maybeSpeakNextWarning() {
    if (!_voiceEnabledNotifier.value) {
      return;
    }
    final warning = _nextRoadWarning;
    if (warning == null || _spokenWarningIds.contains(warning.id)) {
      return;
    }

    final distanceToWarning = warning.distanceFromStart - _distanceAlongRoute;
    
    double triggerDistance = 70.0;
    if (warning.type == RoadWarningType.speedCamera) {
      triggerDistance = 180.0;
    } else if (warning.type == RoadWarningType.stopSign || warning.type == RoadWarningType.speedBump) {
      triggerDistance = 80.0;
    } else if (warning.type == RoadWarningType.surfaceChange) {
      triggerDistance = 60.0;
    } else if (warning.type == RoadWarningType.crest || warning.type == RoadWarningType.dip) {
      triggerDistance = 60.0;
    }

    final dynamicTrigger = _speedMps > 1
        ? math.max(triggerDistance, _speedMps * 5.0)
        : triggerDistance;

    if (distanceToWarning > dynamicTrigger) {
      return;
    }

    String speakText = warning.text;
    if (warning.type == RoadWarningType.stopSign) {
      speakText = 'Stop sign ahead';
    } else if (warning.type == RoadWarningType.speedBump) {
      speakText = 'Speed bump ahead';
    } else if (warning.type == RoadWarningType.giveWay) {
      speakText = 'Yield ahead';
    } else if (warning.type == RoadWarningType.trafficLight) {
      speakText = 'Traffic light ahead';
    } else if (warning.type == RoadWarningType.crest) {
      speakText = 'Crest';
    } else if (warning.type == RoadWarningType.dip) {
      speakText = 'Dip';
    }

    _voice.speak(speakText);
    _spokenWarningIds.add(warning.id);
  }

  void _resetNotes() {
    _notes = _notes.map((note) => note.copyWith(spoken: false)).toList();
    _spokenWarningIds.clear();
    _lastMatchedIndex = 0;
    if (widget.isSimulation) {
      _simulatedDistance = 0.0;
    }

    final nextNote = _nextNote;
    final nextWarning = _nextRoadWarning;
    final currentLimit = _currentSpeedLimit;
    final distanceToNote = nextNote == null
        ? null
        : math.max(0.0, nextNote.distanceFromStart - _distanceAlongRoute);
    final distanceToWarning = nextWarning == null
        ? null
        : math.max(0.0, nextWarning.distanceFromStart - _distanceAlongRoute);
    final offRoute = _distanceFromRoute > 60 && _lastPosition != null;

    _driveStateNotifier.value = DriveState(
      nextNote: nextNote,
      distanceToNote: distanceToNote,
      nextWarning: nextWarning,
      distanceToWarning: distanceToWarning,
      currentLimit: currentLimit,
      speedMps: _speedMps,
      offRoute: offRoute,
      gpsWeak: _gpsWeak,
      permissionMessage: _permissionMessage,
    );
  }

  void _toggleVoice() {
    _voiceEnabledNotifier.value = !_voiceEnabledNotifier.value;
    _voice.setEnabled(_voiceEnabledNotifier.value);
  }

  Future<void> _drawNavigationRoute() async {
    final controller = _controller;
    if (controller == null || widget.routePoints.length < 2) {
      return;
    }

    final oldBaseLine = _baseRouteLine;
    if (oldBaseLine != null) {
      await controller.removeLine(oldBaseLine);
    }
    if (_dangerLines.isNotEmpty) {
      await controller.removeLines(_dangerLines);
      _dangerLines.clear();
    }
    if (_noteLabels.isNotEmpty) {
      await controller.removeSymbols(_noteLabels);
      _noteLabels.clear();
    }
    if (_noteMarkers.isNotEmpty) {
      await controller.removeCircles(_noteMarkers);
      _noteMarkers.clear();
    }
    if (_warningLabels.isNotEmpty) {
      await controller.removeSymbols(_warningLabels);
      _warningLabels.clear();
    }
    if (_warningMarkers.isNotEmpty) {
      await controller.removeCircles(_warningMarkers);
      _warningMarkers.clear();
    }

    _baseRouteLine = await controller.addLine(
      maplibre.LineOptions(
        geometry: widget.routePoints
            .map((point) => maplibre.LatLng(point.lat, point.lon))
            .toList(),
        lineColor: '#607D8B',
        lineWidth: 6,
        lineOpacity: 0.85,
      ),
    );

    for (final note in widget.pacenotes) {
      if (note.type == PaceNoteType.straight) {
        continue;
      }
      final start = note.startDistance ?? (note.distanceFromStart - 25);
      final end = note.endDistance ?? (note.distanceFromStart + 45);
      final segment = routeSegmentBetweenDistances(
        widget.routePoints,
        start,
        end,
      );
      if (segment.length >= 2) {
        final line = await controller.addLine(
          maplibre.LineOptions(
            geometry: segment
                .map((point) => maplibre.LatLng(point.lat, point.lon))
                .toList(),
            lineColor: colorForPaceNote(note),
            lineWidth: 8,
            lineOpacity: 0.95,
          ),
        );
        _dangerLines.add(line);
      }

      final markerPoint = nearestRoutePointAtDistance(
        widget.routePoints,
        note.startDistance ?? note.distanceFromStart,
      );
      if (markerPoint != null) {
        final coordinates = maplibre.LatLng(markerPoint.lat, markerPoint.lon);
        final circle = await controller.addCircle(
          maplibre.CircleOptions(
            geometry: coordinates,
            circleRadius: 8,
            circleColor: colorForPaceNote(note),
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2,
          ),
        );
        final label = await controller.addSymbol(
          maplibre.SymbolOptions(
            geometry: coordinates,
            textField: shortCalloutLabel(note),
            textSize: 11,
            textColor: '#FFFFFF',
            textHaloColor: '#263238',
            textHaloWidth: 2,
            textAnchor: 'top',
            textOffset: const Offset(0, 1.2),
            zIndex: 20,
          ),
        );
        _noteMarkers.add(circle);
        _noteLabels.add(label);
      }
    }

    for (final warning in _visibleRoadWarnings) {
      final coordinates = maplibre.LatLng(warning.lat, warning.lon);
      final circle = await controller.addCircle(
        maplibre.CircleOptions(
          geometry: coordinates,
          circleRadius: 7,
          circleColor: colorForRoadWarning(warning.type),
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      );
      final label = await controller.addSymbol(
        maplibre.SymbolOptions(
          geometry: coordinates,
          textField: shortRoadWarningLabel(warning.type),
          textSize: 11,
          textColor: '#FFFFFF',
          textHaloColor: '#263238',
          textHaloWidth: 2,
          textAnchor: 'top',
          textOffset: const Offset(0, 1.1),
          zIndex: 30,
        ),
      );
      _warningMarkers.add(circle);
      _warningLabels.add(label);
    }

    await _fitNavigationCameraToRoute();
  }

  Future<void> _drawStaticMapLayers() async {
    final currentStyle = getMapStyle(context, widget.settings);
    if (_lastLoadedStyle == currentStyle) {
      return;
    }
    _lastLoadedStyle = currentStyle;

    _currentArrow = null;
    _currentInnerCircle = null;
    _currentOuterCircle = null;
    _carImageLoaded = false;

    try {
      final bytes = await generateChevronImageBytes();
      await _controller?.addImage('car_chevron', bytes);
      if (mounted) {
        setState(() {
          _carImageLoaded = true;
        });
      }

      await _drawNavigationRoute();
      final position = _lastPosition;
      if (position != null) {
        final lat = _lastVisualLat ?? position.latitude;
        final lon = _lastVisualLon ?? position.longitude;
        await _updateCurrentLocationMarker(position, lat, lon);
      } else if (widget.routePoints.isNotEmpty) {
        final first = widget.routePoints.first;
        final mockPosition = Position(
          latitude: first.lat,
          longitude: first.lon,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: first.heading,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
        await _updateCurrentLocationMarker(mockPosition, first.lat, first.lon);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _permissionMessage = 'Map route drawing failed.';
      });
    }
  }

  Future<void> _fitNavigationCameraToRoute() async {
    final controller = _controller;
    if (controller == null || widget.routePoints.isEmpty) {
      return;
    }

    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngBounds(
        routeBoundsFromPoints(widget.routePoints),
        left: 48,
        top: 80,
        right: 48,
        bottom: 260,
      ),
    );
  }

  Future<void> _updateCurrentLocationMarker(Position position, double visualLat, double visualLon) async {
    final controller = _controller;
    if (!_carImageLoaded || controller == null) {
      return;
    }

    final coordinates = maplibre.LatLng(visualLat, visualLon);
    final heading = _headingForPosition(position);

    final existingArrow = _currentArrow;
    final existingCircle = _currentInnerCircle;
    if (existingArrow != null && existingCircle != null) {
      await controller.updateCircle(
        existingCircle,
        maplibre.CircleOptions(
          geometry: coordinates,
        ),
      );
      await controller.updateSymbol(
        existingArrow,
        OverlapSymbolOptions(
          geometry: coordinates,
          iconRotate: heading,
        ),
      );
      
      final existingOuter = _currentOuterCircle;
      if (existingOuter != null) {
        try { await controller.removeCircle(existingOuter); } catch (_) {}
        _currentOuterCircle = null;
      }
      return;
    }

    if (existingCircle != null) {
      try { await controller.removeCircle(existingCircle); } catch (_) {}
    }
    if (existingArrow != null) {
      try { await controller.removeSymbol(existingArrow); } catch (_) {}
    }

    final circle = await controller.addCircle(
      maplibre.CircleOptions(
        geometry: coordinates,
        circleRadius: 10,
        circleColor: '#1E88E5',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
        circleOpacity: 0.9,
      ),
    );

    final arrow = await controller.addSymbol(
      OverlapSymbolOptions(
        geometry: coordinates,
        iconImage: 'car_chevron',
        iconSize: 0.8,
        iconRotate: heading,
        zIndex: 100,
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _currentArrow = arrow;
      _currentInnerCircle = circle;
      _currentOuterCircle = null;
    });
  }

  Future<void> _followPosition(double lat, double lon) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    final double targetBearing = widget.settings.mapHeadingUp ? _lastGoodHeading : 0.0;
    final double targetTilt = widget.settings.mapHeadingUp ? 30.0 : 0.0;

    await controller.animateCamera(
      maplibre.CameraUpdate.newCameraPosition(
        maplibre.CameraPosition(
          target: maplibre.LatLng(lat, lon),
          zoom: 16.5,
          bearing: targetBearing,
          tilt: targetTilt,
        ),
      ),
      duration: const Duration(milliseconds: 90),
    );
  }

  Future<Uint8List> generateChevronImageBytes() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, 64, 64));
    
    // White chevron arrow pointing UP
    final chevronPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill;
    final chevronPath = ui.Path()
      ..moveTo(32, 16)
      ..lineTo(44, 40)
      ..lineTo(32, 33)
      ..lineTo(20, 40)
      ..close();
    canvas.drawPath(chevronPath, chevronPaint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(64, 64);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _toggleFollowMode() {
    if (_followLocation) {
      setState(() {
        _followLocation = false;
      });
      return;
    }

    setState(() {
      _followLocation = true;
    });

    if (_lastVisualLat != null && _lastVisualLon != null) {
      _followPosition(_lastVisualLat!, _lastVisualLon!);
    } else {
      _fitNavigationCameraToRoute();
    }
  }

  double _headingForPosition(Position position) {
    double? candidate;
    // 1. GPS heading if available and valid
    if (_speedMps > 0.8 && position.heading.isFinite && position.heading >= 0 && position.heading <= 360) {
      candidate = position.heading;
    }

    // 2. Movement bearing between previous and current if distance > 3m
    final previous = _previousPosition;
    if (candidate == null && previous != null) {
      final movementMeters = haversineDistanceMeters(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
      if (movementMeters >= 3.0) {
        candidate = bearingDegrees(
          previous.latitude,
          previous.longitude,
          position.latitude,
          position.longitude,
        );
      }
    }

    // 3. Nearest route segment bearing
    if (candidate == null &&
        _lastMatchedIndex >= 0 &&
        _lastMatchedIndex < widget.routePoints.length) {
      final routeHeading = widget.routePoints[_lastMatchedIndex].heading;
      if (routeHeading.isFinite) {
        candidate = routeHeading;
      }
    }

    // 4. Last good heading is candidate ?? _lastGoodHeading
    if (candidate != null) {
      // if stopped/very slow, keep last good heading
      if (_speedMps > 0.3) {
        _lastGoodHeading = smoothHeading(_lastGoodHeading, candidate, 0.4);
      }
    }
    return _lastGoodHeading;
  }

  void _startSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_simulationPausedNotifier.value || !mounted) return;

      final double speedMps = _simulationSpeedKmhNotifier.value / 3.6;
      _simulatedDistance += speedMps * 0.05; // 0.05 seconds

      if (widget.routePoints.isEmpty) return;

      if (_simulatedDistance >= widget.routePoints.last.distanceFromStart) {
        _simulatedDistance = 0.0;
        _lastMatchedIndex = 0;
      }

      final interpolated = interpolateRoutePositionAtDistance(widget.routePoints, _simulatedDistance);

      final mockPosition = Position(
        latitude: interpolated.lat,
        longitude: interpolated.lon,
        timestamp: DateTime.now(),
        accuracy: 3.0,
        altitude: interpolated.elevation,
        altitudeAccuracy: 0.0,
        heading: interpolated.heading,
        headingAccuracy: 0.0,
        speed: speedMps,
        speedAccuracy: 0.0,
        floor: null,
        isMocked: true,
      );

      _handlePosition(mockPosition);
    });
  }

  void _showDebugBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final speedKmh = _speedMps * 3.6;
        final rawSpeedKmh = _rawSpeedMps * 3.6;
        
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'GPS Telemetry & Matcher Status',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                _buildDebugRow('GPS Accuracy', '${_gpsAccuracy.toStringAsFixed(1)} m'),
                _buildDebugRow('GPS Raw Speed', '${rawSpeedKmh.toStringAsFixed(1)} km/h'),
                _buildDebugRow('Smoothed Speed', '${speedKmh.toStringAsFixed(1)} km/h'),
                _buildDebugRow('Smoothed Heading', '${_lastGoodHeading.toStringAsFixed(1)}°'),
                _buildDebugRow('GPS Heading (Course)', '${_gpsHeading.toStringAsFixed(1)}°'),
                _buildDebugRow('Matched Index', '$_lastMatchedIndex / ${widget.routePoints.length}'),
                _buildDebugRow('Distance Along Route', '${(_distanceAlongRoute / 1000).toStringAsFixed(3)} km'),
                _buildDebugRow('Off-Route Distance', '${_distanceFromRoute.toStringAsFixed(1)} m'),
                _buildDebugRow('Route Points Count', '${widget.routePoints.length}'),
                _buildDebugRow('Pacenotes Count', '${widget.pacenotes.length}'),
                _buildDebugRow('Warnings Count', '${widget.roadWarnings.length}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({
    required this.speedMps,
    required this.speedLimit,
    required this.gpsWeak,
  });

  final double speedMps;
  final SpeedLimitSegment? speedLimit;
  final bool gpsWeak;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final speedKmh = (speedMps * 3.6).round();
    final limit = speedLimit?.parsedKmh;
    final isOverSpeed = limit != null && speedKmh > limit;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withAlpha(238),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black26,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$speedKmh',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isOverSpeed ? Colors.red.shade700 : colorScheme.onSurface,
                    height: 1.0,
                  ),
                ),
                Text(
                  'km/h',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isOverSpeed ? Colors.red.shade700 : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (limit != null) ...[
              const SizedBox(width: 14),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.shade700, width: 4.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    )
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '$limit',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    height: 1.0,
                  ),
                ),
              ),
            ],
            if (gpsWeak) ...[
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gps_off, size: 16, color: Colors.orange),
                  const SizedBox(height: 2),
                  Text(
                    'GPS WEAK',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[800],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriveRoundButton extends StatelessWidget {
  const _DriveRoundButton({
    required this.heroTag,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String heroTag;
  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      heroTag: heroTag,
      tooltip: tooltip,
      backgroundColor: active
          ? colorScheme.primary
          : colorScheme.surface.withAlpha(220),
      foregroundColor: active
          ? colorScheme.onPrimary
          : colorScheme.onSurface.withOpacity(0.55),
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}

class _CalloutRow extends StatelessWidget {
  const _CalloutRow({required this.note, required this.distanceMeters});

  final PaceNote? note;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (note != null) _CalloutBadge(note: note),
        if (note != null) const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                note?.rallyText ?? 'No more callouts',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                distanceMeters == null
                    ? 'Route complete'
                    : '${formatDistance(distanceMeters!)} to callout',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalloutBadge extends StatelessWidget {
  const _CalloutBadge({required this.note});

  final PaceNote note;

  @override
  Widget build(BuildContext context) {
    final color = Color(
      int.parse(colorForPaceNote(note).substring(1), radix: 16) + 0xFF000000,
    );
    final icon = switch (note.type) {
      PaceNoteType.roundabout => Icons.roundabout_right,
      PaceNoteType.junction => Icons.turn_right,
      PaceNoteType.hairpinLeft || PaceNoteType.hairpinRight || PaceNoteType.hairpin => Icons.warning_amber_rounded,
      PaceNoteType.warning => Icons.warning_rounded,
      PaceNoteType.straight => Icons.straight,
      PaceNoteType.keepLeft => Icons.turn_left,
      PaceNoteType.keepRight => Icons.turn_right,
      _ => null,
    };

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: icon == null
          ? Text(
              '${note.severity}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            )
          : Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.warning, required this.distanceMeters});

  final RoadWarning warning;
  final double distanceMeters;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          iconForRoadWarning(warning.type),
          color: Color(
            int.parse(colorForRoadWarning(warning.type).substring(1), radix: 16) + 0xFF000000,
          ),
          size: 22,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${warning.text} in ${formatDistance(distanceMeters)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

maplibre.LatLngBounds routeBoundsFromPoints(List<RoutePoint> points) {
  var minLat = points.first.lat;
  var maxLat = points.first.lat;
  var minLon = points.first.lon;
  var maxLon = points.first.lon;

  for (final point in points) {
    minLat = math.min(minLat, point.lat);
    maxLat = math.max(maxLat, point.lat);
    minLon = math.min(minLon, point.lon);
    maxLon = math.max(maxLon, point.lon);
  }

  return maplibre.LatLngBounds(
    southwest: maplibre.LatLng(minLat, minLon),
    northeast: maplibre.LatLng(maxLat, maxLon),
  );
}

List<RoutePoint> routeSegmentBetweenDistances(
  List<RoutePoint> points,
  double startMeters,
  double endMeters,
) {
  if (points.isEmpty) {
    return const [];
  }

  final start = math.min(startMeters, endMeters);
  final end = math.max(startMeters, endMeters);
  final segment = points
      .where(
        (point) =>
            point.distanceFromStart >= start && point.distanceFromStart <= end,
      )
      .toList();

  if (segment.length >= 2) {
    return segment;
  }

  RoutePoint? before;
  RoutePoint? after;
  for (final point in points) {
    if (point.distanceFromStart <= start) {
      before = point;
    }
    if (point.distanceFromStart >= end) {
      after = point;
      break;
    }
  }

  final fallback = <RoutePoint>[];
  if (before != null) {
    fallback.add(before);
  }
  fallback.addAll(segment);
  if (after != null && after != before) {
    fallback.add(after);
  }

  if (fallback.length >= 2) {
    return fallback;
  }

  final nearest = nearestRoutePointAtDistance(points, (start + end) / 2);
  final nearestIndex = nearest == null ? -1 : points.indexOf(nearest);
  if (nearestIndex <= 0 && points.length >= 2) {
    return points.take(2).toList();
  }
  if (nearestIndex >= points.length - 1 && points.length >= 2) {
    return points.skip(points.length - 2).toList();
  }
  if (nearestIndex > 0) {
    return points.sublist(nearestIndex - 1, nearestIndex + 1);
  }
  return fallback;
}

RoutePoint? nearestRoutePointAtDistance(
  List<RoutePoint> points,
  double distanceMeters,
) {
  if (points.isEmpty) {
    return null;
  }

  var nearest = points.first;
  var nearestDelta = (nearest.distanceFromStart - distanceMeters).abs();
  for (final point in points.skip(1)) {
    final delta = (point.distanceFromStart - distanceMeters).abs();
    if (delta < nearestDelta) {
      nearest = point;
      nearestDelta = delta;
    }
  }
  return nearest;
}
