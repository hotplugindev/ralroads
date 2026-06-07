import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../controllers/driving_session_controller.dart';
import 'trip_summary_screen.dart';
import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
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
  final double remainingDistanceMeters;
  final double remainingDurationSeconds;
  final String etaString;
  final double progressPercentage;

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
    this.remainingDistanceMeters = 0.0,
    this.remainingDurationSeconds = 0.0,
    this.etaString = '--:--',
    this.progressPercentage = 0.0,
  });
}

class DriveScreen extends StatefulWidget {
  const DriveScreen({
    required this.routePoints,
    required this.pacenotes,
    required this.roadWarnings,
    required this.speedLimitSegments,
    required this.settings,
    required this.drivingSession,
    super.key,
  });

  final List<RoutePoint> routePoints;
  final List<PaceNote> pacenotes;
  final List<RoadWarning> roadWarnings;
  final List<SpeedLimitSegment> speedLimitSegments;
  final SettingsService settings;
  final DrivingSessionController drivingSession;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> with WidgetsBindingObserver {
  static const double driverIconHeadingOffsetDegrees = 0.0;
  late final CalloutSpeechService _speechService;
  late final CalloutScheduler _scheduler;
  StreamSubscription<List<RoutePoint>>? _reroutedSubscription;
  bool _showDebugOverlay = false;

  List<RoutePoint> get _activeRoutePoints => widget.drivingSession.activeRoutePoints;
  List<PaceNote> get _notes => widget.drivingSession.activeNotes;
  List<RoadWarning> get _visibleRoadWarnings => widget.drivingSession.visibleRoadWarnings;

  NavigationFusionService? get _fusionService => widget.drivingSession.fusionService;

  bool _isRerouting = false;
  maplibre.MapLibreMapController? _controller;
  maplibre.Line? _baseRouteLine;
  final List<maplibre.Line> _dangerLines = [];
  final List<maplibre.Circle> _noteMarkers = [];
  final List<maplibre.Symbol> _noteLabels = [];
  final List<maplibre.Circle> _warningMarkers = [];
  final List<maplibre.Symbol> _warningLabels = [];
  bool _driverLayerAdded = false;
  int _lastMatchedIndex = 0;
  double _distanceAlongRoute = 0;
  double _distanceFromRoute = 0;
  double _speedMps = 0;

  // ValueNotifiers for performance-optimized UI updates
  late final ValueNotifier<DriveState> _driveStateNotifier;
  late final ValueNotifier<bool> _followLocationNotifier;
  late final ValueNotifier<bool> _voiceEnabledNotifier;

  bool _carImageLoaded = false;
  bool _mapStyleReady = false;
  double _rawSpeedMps = 0;
  double _gpsAccuracy = 0;
  double _gpsHeading = 0;
  DateTime? _lastCameraUpdateTime;
  bool _cameraUpdateInFlight = false;

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

    _speechService = widget.drivingSession.speechService;
    _scheduler = widget.drivingSession.scheduler;
    _speechService.setEnabled(_voiceEnabledNotifier.value);

    widget.drivingSession.addListener(_onSessionUpdate);
    _reroutedSubscription = widget.drivingSession.onRerouted.listen((_) {
      if (mounted) {
        _drawNavigationRoute();
      }
    });

    final snap = widget.drivingSession.snapshot;
    if (snap.state == DrivingSessionState.idle) {
      final config = DrivingSessionConfig(
        routePoints: widget.routePoints,
        pacenotes: widget.pacenotes,
        roadWarnings: widget.roadWarnings,
        speedLimitSegments: widget.speedLimitSegments,
        recordTrip: widget.settings.autoRecordNavigation,
      );
      widget.drivingSession.startSession(config);
    }

    _onSessionUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock disable failed: $e');
    }
    widget.drivingSession.removeListener(_onSessionUpdate);
    _reroutedSubscription?.cancel();
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

  IconData _iconForPaceNote(PaceNote note) {
    if (note.type == PaceNoteType.left) {
      return Icons.turn_left;
    } else if (note.type == PaceNoteType.right) {
      return Icons.turn_right;
    }
    return switch (note.type) {
      PaceNoteType.roundabout => Icons.rotate_left,
      PaceNoteType.junction => Icons.turn_right,
      PaceNoteType.hairpinLeft => Icons.u_turn_left,
      PaceNoteType.hairpinRight => Icons.u_turn_right,
      PaceNoteType.hairpin => Icons.u_turn_left,
      PaceNoteType.warning => Icons.warning_rounded,
      PaceNoteType.straight => Icons.straight,
      PaceNoteType.keepLeft => Icons.turn_slight_left,
      PaceNoteType.keepRight => Icons.turn_slight_right,
      _ => Icons.navigation,
    };
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
                            onTap: () =>
                                setState(() => _showDebugOverlay = false),
                            child: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      _buildDebugOverlayRow(
                        'Fused Speed',
                        '${(_speedMps * 3.6).toStringAsFixed(1)} km/h',
                      ),
                      _buildDebugOverlayRow(
                        'GPS Heading',
                        '${_gpsHeading.toStringAsFixed(1)}°',
                      ),
                      _buildDebugOverlayRow(
                        'GPS Accuracy',
                        '${_gpsAccuracy.toStringAsFixed(1)} m',
                      ),
                      _buildDebugOverlayRow(
                        'Match Index',
                        '$_lastMatchedIndex/${_activeRoutePoints.length}',
                      ),
                      _buildDebugOverlayRow(
                        'Distance Along',
                        '${_distanceAlongRoute.toStringAsFixed(1)} m',
                      ),
                      _buildDebugOverlayRow(
                        'Distance From',
                        '${_distanceFromRoute.toStringAsFixed(1)} m',
                      ),
                      _buildDebugOverlayRow(
                        'Queue Size',
                        '${_scheduler.queue.length}',
                      ),
                      _buildDebugOverlayRow(
                        'Spoken Notes',
                        '${_scheduler.spokenIds.length}',
                      ),
                      _buildDebugOverlayRow(
                        'Expired Notes',
                        '${_scheduler.expiredIds.length}',
                      ),
                      if (_scheduler.queue.isNotEmpty) ...[
                        const Divider(height: 12),
                        Text(
                          'Next Up:',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
          if (_activeRoutePoints.isEmpty)
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
                    active:
                        widget.settings.pacenoteStyle != PacenoteStyle.balanced,
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
          // Maneuver / Off-route HUD (Phase 14 & 16)
          ValueListenableBuilder<DriveState>(
            valueListenable: _driveStateNotifier,
            builder: (context, state, _) {
              if (state.offRoute) {
                return Positioned(
                  top: 80,
                  left: 16,
                  right: 80,
                  child: SafeArea(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer.withAlpha(38),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 30,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isRerouting
                                      ? 'Recalculating Route...'
                                      : 'Off Route',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isRerouting
                                      ? 'Fetching new coordinates from OpenRouteService'
                                      : 'Rerouting automatically in a few seconds',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer
                                        .withAlpha(204),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              if (state.nextNote != null &&
                  state.distanceToNote != null &&
                  state.distanceToNote! < 300) {
                final note = state.nextNote!;
                return Positioned(
                  top: 80,
                  left: 16,
                  right: 80,
                  child: SafeArea(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer.withAlpha(38),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _iconForPaceNote(note),
                              size: 30,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayTextForPaceNote(note),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  secondaryTextForPaceNote(
                                    note,
                                    state.distanceToNote,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer
                                        .withAlpha(204),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return const SizedBox.shrink();
            },
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
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Remaining',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withAlpha(153),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${(state.remainingDistanceMeters / 1000.0).toStringAsFixed(1)} km',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Time Left',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withAlpha(153),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${(state.remainingDurationSeconds / 60.0).toStringAsFixed(0)} min',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'ETA',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withAlpha(153),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    state.etaString,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: state.progressPercentage,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              color: Theme.of(context).colorScheme.primary,
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ListenableBuilder(
                                  listenable: widget.drivingSession,
                                  builder: (context, _) {
                                    final recording = widget.drivingSession.snapshot.recording;
                                    return OutlinedButton.icon(
                                      onPressed: () {
                                        widget.drivingSession.toggleRecording(!recording);
                                      },
                                      icon: Icon(
                                        recording
                                            ? Icons.stop_circle
                                            : Icons.fiber_manual_record,
                                        color: recording ? Colors.red : null,
                                      ),
                                      label: Text(
                                        recording ? 'Stop Rec' : 'Record',
                                        style: TextStyle(
                                          color: recording ? Colors.red : null,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        side: BorderSide(
                                          color: recording
                                              ? Colors.red
                                              : Theme.of(context).colorScheme.outline,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ListenableBuilder(
                                  listenable: widget.drivingSession,
                                  builder: (context, _) {
                                    final stateVal = widget.drivingSession.snapshot.state;
                                    final isPaused = stateVal == DrivingSessionState.paused;
                                    return ElevatedButton.icon(
                                      onPressed: () {
                                        if (isPaused) {
                                          widget.drivingSession.resumeSession();
                                        } else {
                                          widget.drivingSession.pauseSession();
                                        }
                                      },
                                      icon: Icon(
                                        isPaused ? Icons.play_arrow : Icons.pause,
                                      ),
                                      label: Text(isPaused ? 'Resume' : 'Pause'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: _finishSession,
                                icon: const Icon(Icons.check),
                                tooltip: 'Finish Session',
                                style: IconButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                onPressed: _cancelSession,
                                icon: const Icon(Icons.close),
                                tooltip: 'Discard Session',
                                style: IconButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                                  foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                            ],
                          ),
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
    if (_activeRoutePoints.isEmpty) {
      return const maplibre.CameraPosition(
        target: maplibre.LatLng(43.8, 11.2),
        zoom: 5,
      );
    }

    final first = _activeRoutePoints.first;
    return maplibre.CameraPosition(
      target: maplibre.LatLng(first.lat, first.lon),
      zoom: 12,
    );
  }

  void _onSessionUpdate() {
    if (!mounted) return;

    final snap = widget.drivingSession.snapshot;
    final state = widget.drivingSession.fusionService?.currentState;



    _lastMatchedIndex = widget.drivingSession.fusionService?.lastMatchedIndex ?? 0;
    _distanceAlongRoute = widget.drivingSession.fusionService?.distanceAlongRoute ?? 0.0;
    _distanceFromRoute = widget.drivingSession.fusionService?.distanceFromRoute ?? 0.0;
    _speedMps = snap.speedMps;
    if (state != null) {
      _rawSpeedMps = state.rawSpeedMps;
      _gpsAccuracy = state.gpsAccuracyMeters;
      _gpsHeading = state.headingDegrees;
    }
    _isRerouting = widget.drivingSession.isRerouting;

    if (_mapStyleReady && state != null) {
      _updateCurrentLocationMarker(state);

      if (_followLocationNotifier.value) {
        _followPosition(
          state.displayLat,
          state.displayLon,
          state.headingDegrees,
        );
      }
    }

    _driveStateNotifier.value = DriveState(
      nextNote: snap.nextNote,
      distanceToNote: snap.distanceToNote,
      nextWarning: snap.nextWarning,
      distanceToWarning: snap.distanceToWarning,
      currentLimit: snap.currentLimit,
      speedMps: snap.speedMps,
      offRoute: snap.offRoute,
      gpsWeak: snap.gpsWeak,
      permissionMessage: snap.errorMessage,
      remainingDistanceMeters: snap.remainingDistanceMeters,
      remainingDurationSeconds: snap.remainingDurationSeconds,
      etaString: snap.etaString,
      progressPercentage: snap.progressPercentage,
    );
  }

  void _resetNotes() {
    widget.drivingSession.resetCallouts();
    _onSessionUpdate();
  }

  void _toggleVoice() {
    _voiceEnabledNotifier.value = !_voiceEnabledNotifier.value;
    _speechService.setEnabled(_voiceEnabledNotifier.value);
  }

  Future<void> _finishSession() async {
    final tripId = await widget.drivingSession.finishSession();
    if (!mounted) return;
    Navigator.of(context).pop();
    if (tripId != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TripSummaryScreen(
            repository: widget.drivingSession.tripRepository,
            tripId: tripId,
          ),
        ),
      );
    }
  }

  Future<void> _cancelSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Session?'),
        content: const Text('This will end the drive and discard the recorded trip data (if any).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.drivingSession.cancelSession();
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
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
    if (controller == null || _activeRoutePoints.length < 2) {
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
        geometry: _activeRoutePoints
            .map((point) => maplibre.LatLng(point.lat, point.lon))
            .toList(),
        lineColor: '#607D8B',
        lineWidth: 6,
        lineOpacity: 0.85,
      ),
    );

    for (final note in _notes) {
      if (note.type == PaceNoteType.straight) {
        continue;
      }
      final start = note.startDistance ?? (note.distanceFromStart - 25);
      final end = note.endDistance ?? (note.distanceFromStart + 45);
      final segment = routeSegmentBetweenDistances(
        _activeRoutePoints,
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
        _activeRoutePoints,
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
              iconRotationAlignment: 'map',
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

      final state = _fusionService?.currentState;
      if (state != null) {
        await _updateCurrentLocationMarker(state);
      } else if (_activeRoutePoints.isNotEmpty) {
        final first = _activeRoutePoints.first;
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
      _driveStateNotifier.value = DriveState(
        nextNote: _driveStateNotifier.value.nextNote,
        distanceToNote: _driveStateNotifier.value.distanceToNote,
        nextWarning: _driveStateNotifier.value.nextWarning,
        distanceToWarning: _driveStateNotifier.value.distanceToWarning,
        currentLimit: _driveStateNotifier.value.currentLimit,
        speedMps: _driveStateNotifier.value.speedMps,
        offRoute: _driveStateNotifier.value.offRoute,
        gpsWeak: _driveStateNotifier.value.gpsWeak,
        permissionMessage: 'Map route drawing failed: $error',
        remainingDistanceMeters: _driveStateNotifier.value.remainingDistanceMeters,
        remainingDurationSeconds: _driveStateNotifier.value.remainingDurationSeconds,
        etaString: _driveStateNotifier.value.etaString,
        progressPercentage: _driveStateNotifier.value.progressPercentage,
      );
    }
  }

  Future<void> _fitNavigationCameraToRoute() async {
    final controller = _controller;
    if (controller == null || _activeRoutePoints.isEmpty) {
      return;
    }

    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngBounds(
        routeBoundsFromPoints(_activeRoutePoints),
        left: 48,
        top: 80,
        right: 48,
        bottom: 260,
      ),
    );
  }

  Future<void> _updateCurrentLocationMarker(FusedNavigationState state) async {
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
        debugPrint(
          'Error adding car_chevron in updateCurrentLocationMarker: $e',
        );
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
              'iconRotate': normalizeHeading(
                state.headingDegrees + driverIconHeadingOffsetDegrees,
              ),
            },
          },
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

    final double targetBearing = widget.settings.mapHeadingUp ? heading : 0.0;
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

    final state = _fusionService?.currentState;
    if (state != null) {
      _followPosition(
        state.displayLat,
        state.displayLon,
        state.headingDegrees,
        force: true,
      );
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
                  '$_lastMatchedIndex / ${_activeRoutePoints.length}',
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ..._scheduler.queue.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '- [Priority ${item.priority}] ${item.text} (Dist: ${(item.routeDistance - _distanceAlongRoute).toStringAsFixed(1)}m)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
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
                note == null
                    ? 'No more callouts'
                    : displayTextForPaceNote(note),
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
