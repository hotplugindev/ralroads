import 'dart:async';
import 'dart:math' as math;
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
import '../services/navigation_fusion_service.dart';
import '../services/callout_speech_service.dart';
import '../services/callout_scheduler.dart';
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
    super.key,
  });

  final List<RoutePoint> routePoints;
  final List<PaceNote> pacenotes;
  final List<RoadWarning> roadWarnings;
  final List<SpeedLimitSegment> speedLimitSegments;
  final SettingsService settings;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> with WidgetsBindingObserver {
  final _matcher = GpsRouteMatcher();
  late final CalloutSpeechService _speechService;
  late final CalloutScheduler _scheduler;
  late final NavigationFusionService _fusionService;
  bool _showDebugOverlay = false;
  late List<PaceNote> _notes;
  late final List<RoadWarning> _visibleRoadWarnings;
  late final List<SpeedLimitSegment> _visibleSpeedLimitSegments;
  maplibre.MapLibreMapController? _controller;
  maplibre.Line? _baseRouteLine;
  final List<maplibre.Line> _dangerLines = [];
  final List<maplibre.Circle> _noteMarkers = [];
  final List<maplibre.Symbol> _noteLabels = [];
  final List<maplibre.Circle> _warningMarkers = [];
  final List<maplibre.Symbol> _warningLabels = [];
  maplibre.Circle? _currentOuterCircle;
  maplibre.Circle? _currentInnerCircle;
  bool _driverLayerAdded = false;
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

  String? _lastLoadedStyle;
  bool _carImageLoaded = false;
  bool _mapStyleReady = false;
  double _lastGoodHeading = 0;
  double? _lastVisualLat;
  double? _lastVisualLon;
  bool _gpsWeak = false;
  final Set<String> _spokenWarningIds = {};
  double _rawSpeedMps = 0;
  double _gpsAccuracy = 0;
  double _gpsHeading = 0;
  DateTime? _lastCameraUpdateTime;
  bool _cameraUpdateInFlight = false;

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
      final note = _notes[i];
      if (!_scheduler.spokenIds.contains(note.id) && !_scheduler.expiredIds.contains(note.id)) {
        return note;
      }
    }
    return null;
  }

  RoadWarning? get _nextRoadWarning {
    final idx = _findNextWarningIndex(_distanceAlongRoute);
    if (idx == -1) return null;
    for (var i = idx; i < _visibleRoadWarnings.length; i++) {
      final warning = _visibleRoadWarnings[i];
      if (!_scheduler.spokenIds.contains(warning.id) && !_scheduler.expiredIds.contains(warning.id)) {
        return warning;
      }
    }
    return null;
  }

  SpeedLimitSegment? get _currentSpeedLimit {
    final idx = _findCurrentSpeedLimitIndex(_distanceAlongRoute);
    if (idx == -1) return null;
    final seg = _visibleSpeedLimitSegments[idx];
    if (_distanceAlongRoute >= seg.startDistance &&
        _distanceAlongRoute <= seg.endDistance) {
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

    WidgetsBinding.instance.addObserver(this);
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock enable failed: $e');
    }
    _notes = widget.pacenotes
        .map((note) => note.copyWith(spoken: false))
        .toList();
    _visibleRoadWarnings = filterRoadWarnings(
      widget.roadWarnings,
      widget.settings,
    );
    _visibleSpeedLimitSegments = widget.settings.showSpeedLimits
        ? widget.speedLimitSegments
        : const [];

    _speechService = CalloutSpeechService();
    _speechService.init().then((_) {
      _speechService.setEnabled(_voiceEnabledNotifier.value);
    });

    _scheduler = CalloutScheduler(
      speechService: _speechService,
      settings: widget.settings,
    );
    _scheduler.loadRouteData(
      notes: _notes,
      warnings: _visibleRoadWarnings,
    );

    _fusionService = NavigationFusionService(
      routePoints: widget.routePoints,
      settings: widget.settings,
    );
    _fusionService.addListener(_onFusionUpdate);

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
    _fusionService.removeListener(_onFusionUpdate);
    _fusionService.stop();
    _speechService.stop();
    _scheduler.reset();
    _driveStateNotifier.dispose();
    _followLocationNotifier.dispose();
    _voiceEnabledNotifier.dispose();
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
              attributionButtonPosition:
                  maplibre.AttributionButtonPosition.bottomRight,
              attributionButtonMargins: const math.Point(-1000, -1000),
              myLocationEnabled: false,
              onMapCreated: (controller) {
                _controller = controller;
              },
              onStyleLoadedCallback: _drawStaticMapLayers,
            ),
          ),
          if (_showDebugOverlay)
            Positioned(
              top: 140,
              left: 12,
              child: SafeArea(
                child: Container(
                  width: 260,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withAlpha(235),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TELEMETRY & SCHEDULER',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _showDebugOverlay = false),
                            child: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      _buildDebugOverlayRow('Fused Speed', '${(_speedMps * 3.6).toStringAsFixed(1)} km/h'),
                      _buildDebugOverlayRow('Fused Heading', '${_gpsHeading.toStringAsFixed(1)}°'),
                      _buildDebugOverlayRow('GPS Accuracy', '${_gpsAccuracy.toStringAsFixed(1)} m'),
                      _buildDebugOverlayRow('Match Index', '$_lastMatchedIndex/${widget.routePoints.length}'),
                      _buildDebugOverlayRow('Queue Size', '${_scheduler.queue.length}'),
                      _buildDebugOverlayRow('Spoken Notes', '${_scheduler.spokenIds.length}'),
                      _buildDebugOverlayRow('Expired Notes', '${_scheduler.expiredIds.length}'),
                      if (_scheduler.queue.isNotEmpty) ...[
                        const Divider(height: 12),
                        Text(
                          'Next Up:',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _scheduler.queue.first.text,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
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
                    heroTag: 'drive-style',
                    tooltip: _labelForStyle(widget.settings.pacenoteStyle),
                    icon: _iconForStyle(widget.settings.pacenoteStyle),
                    active: widget.settings.pacenoteStyle != PacenoteStyle.balanced,
                    onPressed: _cyclePacenoteStyle,
                  ),
                  const SizedBox(height: 10),
                  _DriveRoundButton(
                    heroTag: 'drive-reset',
                    tooltip: 'Reset callouts',
                    icon: Icons.restart_alt,
                    active: false,
                    onPressed: _resetNotes,
                  ),
                  const SizedBox(height: 10),
                  _DriveRoundButton(
                    heroTag: 'drive-debug',
                    tooltip: 'Toggle debug overlay',
                    icon: Icons.bug_report_outlined,
                    active: _showDebugOverlay,
                    onPressed: () {
                      setState(() {
                        _showDebugOverlay = !_showDebugOverlay;
                      });
                    },
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
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withAlpha(238),
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
                          if (state.nextWarning != null &&
                              state.distanceToWarning != null) ...[
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

    _fusionService.start();
  }

  void _onFusionUpdate() {
    final state = _fusionService.currentState;
    if (state == null) return;

    _lastPosition = Position(
      latitude: state.rawLat,
      longitude: state.rawLon,
      timestamp: state.timestamp,
      accuracy: state.gpsAccuracyMeters,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: state.headingDegrees,
      headingAccuracy: state.headingAccuracy,
      speed: state.rawSpeedMps,
      speedAccuracy: 0.0,
      floor: null,
    );

    _lastMatchedIndex = _fusionService.lastMatchedIndex;
    _distanceAlongRoute = _fusionService.distanceAlongRoute;
    _distanceFromRoute = _fusionService.distanceFromRoute;
    _speedMps = state.displaySpeedMps;
    _rawSpeedMps = state.rawSpeedMps;
    _gpsAccuracy = state.gpsAccuracyMeters;
    _gpsHeading = state.headingDegrees;
    _gpsWeak = state.gpsAccuracyMeters > 20.0;

    if (_mapStyleReady) {
      _updateCurrentLocationMarker(state);

      if (_followLocationNotifier.value) {
        _followPosition(state.displayLat, state.displayLon, state.headingDegrees);
      }
    }

    _scheduler.update(_distanceAlongRoute, _speedMps);

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

  void _resetNotes() {
    _scheduler.reset();
    _scheduler.loadRouteData(
      notes: _notes,
      warnings: _visibleRoadWarnings,
    );
    _lastMatchedIndex = 0;

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
    _speechService.setEnabled(_voiceEnabledNotifier.value);
  }

  void _cyclePacenoteStyle() async {
    final current = widget.settings.pacenoteStyle;
    final next = switch (current) {
      PacenoteStyle.calm => PacenoteStyle.balanced,
      PacenoteStyle.balanced => PacenoteStyle.rally,
      PacenoteStyle.rally => PacenoteStyle.calm,
    };
    await widget.settings.setPacenoteStyle(next);
    _resetNotes();
    if (mounted) {
      setState(() {});
    }
    _speechService.speak('Co driver mode set to ${next.name}', () {});
  }

  IconData _iconForStyle(PacenoteStyle style) {
    return switch (style) {
      PacenoteStyle.calm => Icons.spa,
      PacenoteStyle.balanced => Icons.balance,
      PacenoteStyle.rally => Icons.bolt,
    };
  }

  String _labelForStyle(PacenoteStyle style) {
    return switch (style) {
      PacenoteStyle.calm => 'Calm Mode',
      PacenoteStyle.balanced => 'Balanced Mode',
      PacenoteStyle.rally => 'Rally Mode',
    };
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
    _mapStyleReady = false;
    _driverLayerAdded = false;
    final currentStyle = getMapStyle(context, widget.settings);
    _lastLoadedStyle = currentStyle;

    _currentInnerCircle = null;
    _currentOuterCircle = null;
    _carImageLoaded = false;

    try {
      final controller = _controller;
      if (controller != null) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        final bytes = await generateChevronImageBytes(primaryColor);
        try {
          await controller.addImage('car_chevron', bytes);
        } catch (e) {
          debugPrint('Error adding car_chevron image: $e');
        }
        if (mounted) {
          setState(() {
            _carImageLoaded = true;
          });
        }

        // Create a dedicated GeoJSON source and symbol layer for the driver
        // marker. This bypasses the SymbolManager entirely, setting
        // iconAllowOverlap at the LAYER level where MapLibre reads it.
        try {
          await controller.addGeoJsonSource('driver-source', {
            'type': 'FeatureCollection',
            'features': [],
          });
          await controller.addSymbolLayer(
            'driver-source',
            'driver-layer',
            maplibre.SymbolLayerProperties(
              iconAllowOverlap: true,
              iconIgnorePlacement: true,
              iconImage: [maplibre.Expressions.get, 'iconImage'],
              iconSize: [maplibre.Expressions.get, 'iconSize'],
              iconRotate: [maplibre.Expressions.get, 'iconRotate'],
            ),
            enableInteraction: false,
          );
          _driverLayerAdded = true;
          debugPrint('Driver layer created successfully');
        } catch (e) {
          debugPrint('Error creating driver layer: $e');
        }
      }

      await _drawNavigationRoute();
      _mapStyleReady = true;

      final state = _fusionService.currentState;
      if (state != null) {
        await _updateCurrentLocationMarker(state);
      } else if (widget.routePoints.isNotEmpty) {
        final first = widget.routePoints.first;
        final mockState = FusedNavigationState(
          rawLat: first.lat,
          rawLon: first.lon,
          displayLat: first.lat,
          displayLon: first.lon,
          rawSpeedMps: 0.0,
          displaySpeedMps: 0.0,
          headingDegrees: first.heading,
          headingAccuracy: 0.0,
          gpsAccuracyMeters: 3.0,
          isMoving: false,
          headingReliable: true,
          timestamp: DateTime.now(),
        );
        await _updateCurrentLocationMarker(mockState);
      }
    } catch (error, stack) {
      debugPrint('Error in _drawStaticMapLayers: $error\n$stack');
      if (!mounted) {
        return;
      }
      setState(() {
        _permissionMessage = 'Map route drawing failed: $error';
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

  Future<void> _updateCurrentLocationMarker(
    FusedNavigationState state,
  ) async {
    final controller = _controller;
    if (controller == null || !_mapStyleReady || !_driverLayerAdded) {
      return;
    }

    if (!_carImageLoaded) {
      try {
        final primaryColor = Theme.of(context).colorScheme.primary;
        final bytes = await generateChevronImageBytes(primaryColor);
        await controller.addImage('car_chevron', bytes);
        _carImageLoaded = true;
      } catch (e) {
        debugPrint('Error adding car_chevron in updateCurrentLocationMarker: $e');
        _carImageLoaded = true;
      }
    }

    // Update the dedicated GeoJSON source with the driver's current position.
    // The symbol layer reads iconImage/iconSize/iconRotate from feature properties.
    try {
      await controller.setGeoJsonSource('driver-source', {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'id': 'driver',
            'geometry': {
              'type': 'Point',
              'coordinates': [state.displayLon, state.displayLat],
            },
            'properties': {
              'iconImage': 'car_chevron',
              'iconSize': 1.0,
              'iconRotate': state.headingDegrees,
            },
          }
        ],
      });
    } catch (e) {
      debugPrint('Error updating driver location source: $e');
    }
  }

  Future<void> _followPosition(
    double lat,
    double lon,
    double heading, {
    bool force = false,
  }) async {
    final controller = _controller;
    if (controller == null || !_mapStyleReady) {
      return;
    }
    if (!force && _cameraUpdateInFlight) {
      return;
    }

    final now = DateTime.now();
    final lastUpdate = _lastCameraUpdateTime;
    if (!force &&
        lastUpdate != null &&
        now.difference(lastUpdate) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastCameraUpdateTime = now;

    final double targetBearing = widget.settings.mapHeadingUp
        ? heading
        : 0.0;
    final double targetTilt = widget.settings.mapHeadingUp ? 40.0 : 0.0;

    final speedKmh = _speedMps * 3.6;
    double targetZoom = 17.2;
    if (speedKmh > 25.0) {
      final fraction = ((speedKmh - 25.0) / 75.0).clamp(0.0, 1.0);
      targetZoom = 17.2 - fraction * 2.7;
    }

    _cameraUpdateInFlight = true;
    try {
      await controller.animateCamera(
        maplibre.CameraUpdate.newCameraPosition(
          maplibre.CameraPosition(
            target: maplibre.LatLng(lat, lon),
            zoom: targetZoom,
            bearing: targetBearing,
            tilt: targetTilt,
          ),
        ),
        duration: const Duration(milliseconds: 100),
      );
    } finally {
      _cameraUpdateInFlight = false;
    }
  }

  Future<Uint8List> generateChevronImageBytes(Color primaryColor) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, 64, 64));

    // 1. Draw background circle in primary color
    final bgPaint = ui.Paint()
      ..color = primaryColor
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(const ui.Offset(32, 32), 18, bgPaint);

    // 2. Draw white border
    final borderPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..strokeWidth = 3.0
      ..style = ui.PaintingStyle.stroke;
    canvas.drawCircle(const ui.Offset(32, 32), 18, borderPaint);

    // 3. Draw white chevron pointing UP
    final chevronPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill;
    final chevronPath = ui.Path()
      ..moveTo(32, 21)
      ..lineTo(41, 38)
      ..lineTo(32, 33)
      ..lineTo(23, 38)
      ..close();
    canvas.drawPath(chevronPath, chevronPaint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(64, 64);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _toggleFollowMode() {
    if (_followLocationNotifier.value) {
      _followLocationNotifier.value = false;
      return;
    }

    _followLocationNotifier.value = true;

    final state = _fusionService.currentState;
    if (state != null) {
      _followPosition(state.displayLat, state.displayLon, state.headingDegrees, force: true);
    } else {
      _fitNavigationCameraToRoute();
    }
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
            child: ListView(
              shrinkWrap: true,
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
                _buildDebugRow(
                  'GPS Accuracy',
                  '${_gpsAccuracy.toStringAsFixed(1)} m',
                ),
                _buildDebugRow(
                  'GPS Raw Speed',
                  '${rawSpeedKmh.toStringAsFixed(1)} km/h',
                ),
                _buildDebugRow(
                  'Smoothed Speed',
                  '${speedKmh.toStringAsFixed(1)} km/h',
                ),
                _buildDebugRow(
                  'Fused Heading',
                  '${_gpsHeading.toStringAsFixed(1)}°',
                ),
                _buildDebugRow(
                  'Matched Index',
                  '$_lastMatchedIndex / ${widget.routePoints.length}',
                ),
                _buildDebugRow(
                  'Distance Along Route',
                  '${(_distanceAlongRoute / 1000).toStringAsFixed(3)} km',
                ),
                _buildDebugRow(
                  'Off-Route Distance',
                  '${_distanceFromRoute.toStringAsFixed(1)} m',
                ),
                _buildDebugRow(
                  'Priority Queue Length',
                  '${_scheduler.queue.length}',
                ),
                _buildDebugRow(
                  'Spoken Note IDs Count',
                  '${_scheduler.spokenIds.length}',
                ),
                _buildDebugRow(
                  'Expired Note IDs Count',
                  '${_scheduler.expiredIds.length}',
                ),
                if (_scheduler.queue.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Queue Elements:',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ..._scheduler.queue.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '- [Priority ${item.priority}] ${item.text} (Dist: ${(item.routeDistance - _distanceAlongRoute).toStringAsFixed(1)}m)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      )),
                ],
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
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugOverlayRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
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
                    color: isOverSpeed
                        ? Colors.red.shade700
                        : colorScheme.onSurface,
                    height: 1.0,
                  ),
                ),
                Text(
                  'km/h',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isOverSpeed
                        ? Colors.red.shade700
                        : colorScheme.onSurfaceVariant,
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
                    ),
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
          : colorScheme.onSurface.withValues(alpha: 0.55),
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
      PaceNoteType.hairpinLeft ||
      PaceNoteType.hairpinRight ||
      PaceNoteType.hairpin => Icons.warning_amber_rounded,
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
            int.parse(
                  colorForRoadWarning(warning.type).substring(1),
                  radix: 16,
                ) +
                0xFF000000,
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
