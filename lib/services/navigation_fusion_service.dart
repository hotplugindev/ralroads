import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../models/route_point.dart';
import '../utils/geo_math.dart';
import 'settings_service.dart';
import 'gps_route_matcher.dart';

class FusedNavigationState {
  final double rawLat;
  final double rawLon;
  final double displayLat;
  final double displayLon;
  final double rawSpeedMps;
  final double displaySpeedMps;
  final double headingDegrees;
  final double headingAccuracy;
  final double gpsAccuracyMeters;
  final bool isMoving;
  final bool headingReliable;
  final DateTime timestamp;

  FusedNavigationState({
    required this.rawLat,
    required this.rawLon,
    required this.displayLat,
    required this.displayLon,
    required this.rawSpeedMps,
    required this.displaySpeedMps,
    required this.headingDegrees,
    required this.headingAccuracy,
    required this.gpsAccuracyMeters,
    required this.isMoving,
    required this.headingReliable,
    required this.timestamp,
  });

  FusedNavigationState copyWith({
    double? rawLat,
    double? rawLon,
    double? displayLat,
    double? displayLon,
    double? rawSpeedMps,
    double? displaySpeedMps,
    double? headingDegrees,
    double? headingAccuracy,
    double? gpsAccuracyMeters,
    bool? isMoving,
    bool? headingReliable,
    DateTime? timestamp,
  }) {
    return FusedNavigationState(
      rawLat: rawLat ?? this.rawLat,
      rawLon: rawLon ?? this.rawLon,
      displayLat: displayLat ?? this.displayLat,
      displayLon: displayLon ?? this.displayLon,
      rawSpeedMps: rawSpeedMps ?? this.rawSpeedMps,
      displaySpeedMps: displaySpeedMps ?? this.displaySpeedMps,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      headingAccuracy: headingAccuracy ?? this.headingAccuracy,
      gpsAccuracyMeters: gpsAccuracyMeters ?? this.gpsAccuracyMeters,
      isMoving: isMoving ?? this.isMoving,
      headingReliable: headingReliable ?? this.headingReliable,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class NavigationFusionService extends ChangeNotifier {
  final List<RoutePoint> routePoints;
  final SettingsService settings;
  final GpsRouteMatcher matcher = GpsRouteMatcher();

  StreamSubscription<Position>? _gpsSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;

  FusedNavigationState? _currentState;
  FusedNavigationState? get currentState => _currentState;

  int _lastMatchedIndex = 0;
  int get lastMatchedIndex => _lastMatchedIndex;

  double _distanceAlongRoute = 0;
  double get distanceAlongRoute => _distanceAlongRoute;

  double _distanceFromRoute = 0;
  double get distanceFromRoute => _distanceFromRoute;

  // Fusion state variables
  double _fusedHeading = 0.0;
  DateTime? _lastGyroTime;

  // Accelerometer orientation state
  double _accelX = 0.0;
  double _accelY = 9.8;
  double _accelZ = 0.0;

  // Interpolation / Display state
  Timer? _tickerTimer;
  Position? _prevPosition;
  Position? _nextPosition;
  DateTime? _lastGpsTime;
  double _expectedIntervalMs = 500.0;

  bool _isMocked = false;

  NavigationFusionService({
    required this.routePoints,
    required this.settings,
  });

  void start() {
    _isMocked = false;
    _startSensors();
  }

  void stop() {
    _gpsSubscription?.cancel();
    _gyroSubscription?.cancel();
    _accelSubscription?.cancel();
    _compassSubscription?.cancel();
    _tickerTimer?.cancel();
    _gpsSubscription = null;
    _gyroSubscription = null;
    _accelSubscription = null;
    _compassSubscription = null;
    _tickerTimer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  void _startSensors() {
    // geolocator stream
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      intervalDuration: const Duration(milliseconds: 500),
    );

    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _handleGpsUpdate,
      onError: (e) => debugPrint('Geolocator stream error: $e'),
    );

    if (settings.sensorAssistedHeading) {
      try {
        _gyroSubscription = gyroscopeEvents.listen(
          _handleGyroUpdate,
          onError: (e) => debugPrint('Gyroscope error: $e'),
        );
      } catch (e) {
        debugPrint('Gyroscope init failed: $e');
      }

      try {
        _accelSubscription = accelerometerEvents.listen(
          _handleAccelUpdate,
          onError: (e) => debugPrint('Accelerometer error: $e'),
        );
      } catch (e) {
        debugPrint('Accelerometer init failed: $e');
      }

      try {
        _compassSubscription = FlutterCompass.events?.listen(
          _handleCompassUpdate,
          onError: (e) => debugPrint('Compass error: $e'),
        );
      } catch (e) {
        debugPrint('Compass init failed: $e');
      }
    }

    // Start 60fps display ticker timer
    _tickerTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (timer) => _onTick(),
    );
  }

  void updateMockPosition(Position position) {
    _isMocked = true;
    _handleGpsUpdate(position);
  }

  void _handleGpsUpdate(Position position) {
    if (position.accuracy > 35.0) {
      debugPrint('Skipping inaccurate GPS point: ${position.accuracy}m');
      return;
    }

    final now = DateTime.now();
    if (_lastGpsTime != null) {
      final elapsed = now.difference(_lastGpsTime!).inMilliseconds;
      if (elapsed < 0) {
        debugPrint('Skipping out-of-order GPS point');
        return;
      }
      if (elapsed > 100 && elapsed < 2000) {
        _expectedIntervalMs = _expectedIntervalMs * 0.7 + elapsed * 0.3;
      }
    }
    _lastGpsTime = now;

    if (_prevPosition != null) {
      final dist = haversineDistanceMeters(
        _prevPosition!.latitude,
        _prevPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (dist > 150.0 && position.speed < 1.0) {
        debugPrint('Skipping extreme GPS jump: ${dist}m');
        return;
      }
    }

    _prevPosition = _nextPosition ?? position;
    _nextPosition = position;

    final match = matcher.match(
      lat: position.latitude,
      lon: position.longitude,
      routePoints: routePoints,
      lastMatchedIndex: _lastMatchedIndex,
    );
    _lastMatchedIndex = match.nearestIndex;
    _distanceAlongRoute = match.distanceAlongRoute;
    _distanceFromRoute = match.distanceFromRoute;

    final gpsSpeed = position.speed;
    final hasGpsHeading = position.heading.isFinite && (position.heading > 0.001 || position.heading < -0.001 || position.heading != 0.0);

    if (!_isMocked && settings.sensorAssistedHeading) {
      if (gpsSpeed >= 4.5 && hasGpsHeading) {
        final routeBearing = routePoints[_lastMatchedIndex].heading;
        final gpsHeading = position.heading;

        final bearingDiff = normalizeAngleDeltaDegrees(gpsHeading, routeBearing).abs();
        if (bearingDiff < 90.0) {
          final diff = normalizeAngleDeltaDegrees(_fusedHeading, gpsHeading);
          _fusedHeading = (_fusedHeading + diff * 0.6) % 360;
        } else {
          final diff = normalizeAngleDeltaDegrees(_fusedHeading, gpsHeading);
          _fusedHeading = (_fusedHeading + diff * 0.3) % 360;
        }
      }
    } else {
      if (gpsSpeed > 1.0 && hasGpsHeading) {
        _fusedHeading = position.heading;
      } else {
        if (routePoints.isNotEmpty) {
          _fusedHeading = routePoints[_lastMatchedIndex].heading;
        }
      }
    }

    if (_currentState == null) {
      _currentState = FusedNavigationState(
        rawLat: position.latitude,
        rawLon: position.longitude,
        displayLat: position.latitude,
        displayLon: position.longitude,
        rawSpeedMps: gpsSpeed,
        displaySpeedMps: gpsSpeed,
        headingDegrees: _fusedHeading,
        headingAccuracy: 0.0,
        gpsAccuracyMeters: position.accuracy,
        isMoving: gpsSpeed > 1.0,
        headingReliable: true,
        timestamp: now,
      );
      notifyListeners();
    }
  }

  void _handleGyroUpdate(GyroscopeEvent event) {
    if (_isMocked || !settings.sensorAssistedHeading) return;

    final now = DateTime.now();
    if (_lastGyroTime == null) {
      _lastGyroTime = now;
      return;
    }

    final dt = now.difference(_lastGyroTime!).inMilliseconds / 1000.0;
    _lastGyroTime = now;

    if (dt <= 0.0 || dt > 0.5) return;

    final speed = _currentState?.rawSpeedMps ?? 0.0;
    if (speed < 0.5) {
      return;
    }

    final yawRateDeg = event.z * (180.0 / math.pi);
    final headingChange = -yawRateDeg * dt;

    _fusedHeading = (_fusedHeading + headingChange) % 360;
  }

  void _handleAccelUpdate(AccelerometerEvent event) {
    if (_isMocked || !settings.sensorAssistedHeading) return;

    const alpha = 0.1;
    _accelX = alpha * event.x + (1.0 - alpha) * _accelX;
    _accelY = alpha * event.y + (1.0 - alpha) * _accelY;
    _accelZ = alpha * event.z + (1.0 - alpha) * _accelZ;
  }

  void _handleCompassUpdate(CompassEvent event) {
    if (_isMocked || !settings.sensorAssistedHeading) return;

    final rawHeading = event.heading;
    if (rawHeading == null) return;

    double offset = 0.0;
    if (_accelY.abs() > _accelX.abs()) {
      if (_accelY < -5.0) {
        offset = 180.0;
      }
    } else {
      if (_accelX > 5.0) {
        offset = 90.0;
      } else if (_accelX < -5.0) {
        offset = -90.0;
      }
    }

    final correctedCompass = (rawHeading + offset) % 360;

    final speed = _currentState?.rawSpeedMps ?? 0.0;
    if (speed < 4.5) {
      final diff = normalizeAngleDeltaDegrees(_fusedHeading, correctedCompass);
      final blendWeight = speed < 1.0 ? 0.05 : 0.1;
      _fusedHeading = (_fusedHeading + diff * blendWeight) % 360;
    }
  }

  void _onTick() {
    if (_prevPosition == null || _nextPosition == null || _currentState == null) return;

    final now = DateTime.now();
    if (_lastGpsTime == null) return;

    final elapsedMs = now.difference(_lastGpsTime!).inMilliseconds.toDouble();

    double t = 1.0;
    if (settings.smoothMarkerMovement) {
      t = (elapsedMs / _expectedIntervalMs).clamp(0.0, 1.2);
    }

    final prevLat = _prevPosition!.latitude;
    final prevLon = _prevPosition!.longitude;
    final nextLat = _nextPosition!.latitude;
    final nextLon = _nextPosition!.longitude;

    final displayLat = prevLat + (nextLat - prevLat) * t;
    final displayLon = prevLon + (nextLon - prevLon) * t;

    final prevSpeed = _prevPosition!.speed;
    final nextSpeed = _nextPosition!.speed;
    final displaySpeed = prevSpeed + (nextSpeed - prevSpeed) * t;

    final gpsAccuracy = _nextPosition!.accuracy;
    final isMoving = displaySpeed > 0.8;

    _currentState = FusedNavigationState(
      rawLat: nextLat,
      rawLon: nextLon,
      displayLat: displayLat,
      displayLon: displayLon,
      rawSpeedMps: nextSpeed,
      displaySpeedMps: displaySpeed,
      headingDegrees: _fusedHeading,
      headingAccuracy: 0.0,
      gpsAccuracyMeters: gpsAccuracy,
      isMoving: isMoving,
      headingReliable: true,
      timestamp: now,
    );

    notifyListeners();
  }
}
