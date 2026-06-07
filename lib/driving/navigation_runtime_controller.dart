import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../services/navigation_fusion_service.dart';
import '../services/ors_service.dart';
import '../services/pacenote_generator.dart';
import '../services/overpass_service.dart';
import '../services/settings_service.dart';
import '../utils/ui_helpers.dart';

class NavigationRuntimeController {
  NavigationRuntimeController({
    required SettingsService settings,
  }) : _settings = settings;

  final SettingsService _settings;
  NavigationFusionService? _fusionService;

  List<RoutePoint> _activeRoutePoints = [];
  List<PaceNote> _activeNotes = [];
  List<RoadWarning> _visibleRoadWarnings = [];
  List<SpeedLimitSegment> _visibleSpeedLimitSegments = [];

  List<RoutePoint> get activeRoutePoints => _activeRoutePoints;
  List<PaceNote> get activeNotes => _activeNotes;
  List<RoadWarning> get visibleRoadWarnings => _visibleRoadWarnings;
  List<SpeedLimitSegment> get visibleSpeedLimitSegments => _visibleSpeedLimitSegments;

  NavigationFusionService? get fusionService => _fusionService;

  bool _isRerouting = false;
  bool get isRerouting => _isRerouting;

  DateTime? _lastOnRouteTime;

  final _reroutedController = StreamController<List<RoutePoint>>.broadcast();
  Stream<List<RoutePoint>> get onRerouted => _reroutedController.stream;

  void initializeRoute({
    required List<RoutePoint> routePoints,
    required List<PaceNote> pacenotes,
    required List<RoadWarning> roadWarnings,
    required List<SpeedLimitSegment> speedLimitSegments,
  }) {
    _activeRoutePoints = List<RoutePoint>.from(routePoints);
    _activeNotes = pacenotes.map((n) => n.copyWith(spoken: false)).toList();
    _visibleRoadWarnings = filterRoadWarnings(roadWarnings, _settings);
    _visibleSpeedLimitSegments = _settings.showSpeedLimits ? speedLimitSegments : const [];

    _fusionService = NavigationFusionService(
      routePoints: _activeRoutePoints,
      settings: _settings,
    );
  }

  void startFusion(VoidCallback onUpdate) {
    _fusionService?.addListener(onUpdate);
    _fusionService?.start();
    _lastOnRouteTime = null;
  }

  void stopFusion(VoidCallback onUpdate) {
    _fusionService?.removeListener(onUpdate);
    _fusionService?.stop();
    _fusionService = null;
  }

  void updateRoutePoints(List<RoutePoint> points) {
    _activeRoutePoints = points;
    _fusionService?.updateRoutePoints(points);
  }

  double get distanceAlongRoute => _fusionService?.distanceAlongRoute ?? 0.0;
  double get distanceFromRoute => _fusionService?.distanceFromRoute ?? 0.0;
  int get lastMatchedIndex => _fusionService?.lastMatchedIndex ?? 0;

  FusedNavigationState? get currentState => _fusionService?.currentState;

  // Checks off route and triggers rerouting if necessary
  Future<void> checkOffRoute(
    FusedNavigationState state,
    DateTime now,
    Future<void> Function(String message) speak,
    VoidCallback onRerouteStart,
    void Function(List<PaceNote> newNotes, List<RoadWarning> newWarnings, List<SpeedLimitSegment> newLimits) onRerouteComplete,
  ) async {
    final distFromRoute = distanceFromRoute;
    final offRoute = distFromRoute > 60.0 && _activeRoutePoints.isNotEmpty;

    if (offRoute) {
      if (_lastOnRouteTime == null) {
        _lastOnRouteTime = now;
      } else if (now.difference(_lastOnRouteTime!).inSeconds >= 5 && !_isRerouting) {
        onRerouteStart();
        await _recalculateRoute(state, speak, onRerouteComplete);
      }
    } else {
      _lastOnRouteTime = null;
    }
  }

  Future<void> _recalculateRoute(
    FusedNavigationState state,
    Future<void> Function(String message) speak,
    void Function(List<PaceNote> newNotes, List<RoadWarning> newWarnings, List<SpeedLimitSegment> newLimits) onRerouteComplete,
  ) async {
    if (_isRerouting) return;
    _isRerouting = true;

    final startPoint = RoutePoint(lat: state.rawLat, lon: state.rawLon);
    final destination = _activeRoutePoints.last;

    try {
      await speak('Off route. Recalculating route.');

      final newPoints = await OrsService(
        settings: _settings,
      ).buildRoute([startPoint, destination]);
      if (newPoints.isEmpty) throw Exception('No points returned');

      final newPacenotes = PacenoteGenerator(
        settings: _settings,
      ).generate(newPoints);

      _activeRoutePoints = newPoints;
      _activeNotes = newPacenotes.map((n) => n.copyWith(spoken: false)).toList();
      _visibleRoadWarnings = [];
      _visibleSpeedLimitSegments = [];

      _fusionService?.updateRoutePoints(_activeRoutePoints);

      onRerouteComplete(_activeNotes, _visibleRoadWarnings, _visibleSpeedLimitSegments);

      _reroutedController.add(_activeRoutePoints);
      _lastOnRouteTime = null;

      _enrichRecalculatedRoute(newPoints, onRerouteComplete);
    } catch (e) {
      debugPrint('Rerouting failed: $e');
      await speak('Recalculating route failed. Please check internet connection.');
    } finally {
      _isRerouting = false;
    }
  }

  Future<void> _enrichRecalculatedRoute(
    List<RoutePoint> newPoints,
    void Function(List<PaceNote> newNotes, List<RoadWarning> newWarnings, List<SpeedLimitSegment> newLimits) onRerouteComplete,
  ) async {
    try {
      final enrichment = await OverpassService().enrichRoute(newPoints);
      _visibleRoadWarnings = filterRoadWarnings(enrichment.roadWarnings, _settings);
      _visibleSpeedLimitSegments = _settings.showSpeedLimits ? enrichment.speedLimitSegments : const [];

      onRerouteComplete(_activeNotes, _visibleRoadWarnings, _visibleSpeedLimitSegments);
    } catch (e) {
      debugPrint('Enrichment failed: $e');
    }
  }

  void dispose() {
    _reroutedController.close();
  }
}
