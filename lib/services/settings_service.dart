import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/road_warning.dart';
import 'local_hive.dart';
import 'secure_credential_service.dart';

enum PacenoteStyle { calm, balanced, rally }

enum OrsProfile { drivingCar, drivingHgv, cyclingRoad, footWalking }

class SettingsService extends ChangeNotifier {
  SettingsService({SecureCredentialService? secureCredentials})
    : _secureCredentials = secureCredentials ?? SecureCredentialService();

  static const _boxName = 'settings';
  static const _orsApiKeyKey = 'ors_api_key';
  static const _orsProfileKey = 'ors_profile';
  static const _showSpeedLimitsKey = 'show_speed_limits';
  static const _showTrafficLightsKey = 'show_traffic_lights';
  static const _showStopGiveWayKey = 'show_stop_give_way';
  static const _showSpeedBumpsKey = 'show_speed_bumps';
  static const _showRoadFeaturesKey = 'show_road_features';
  static const _showSpeedCamerasKey = 'show_speed_cameras';
  static const _pacenoteStyleKey = 'pacenote_style';
  static const _onboardingCompleteKey = 'onboarding_complete';
  static const developmentOrsApiKey = String.fromEnvironment('ORS_API_KEY');

  final SecureCredentialService _secureCredentials;
  String? _cachedOrsApiKey;

  PacenoteStyle get pacenoteStyle {
    final value = _box?.get(_pacenoteStyleKey);
    if (value is String) {
      return PacenoteStyle.values.firstWhere(
        (e) => e.name == value,
        orElse: () => PacenoteStyle.balanced,
      );
    }
    return PacenoteStyle.balanced;
  }

  Future<void> setPacenoteStyle(PacenoteStyle style) async {
    await _box?.put(_pacenoteStyleKey, style.name);
    notifyListeners();
  }

  Box<dynamic>? _box;

  Future<void> init() async {
    await LocalHive.ensureInitialized();
    _box = await Hive.openBox<dynamic>(_boxName);
    await _loadAndMigrateSecureCredentials();
  }

  String? getOrsApiKey() {
    return _cachedOrsApiKey;
  }

  String? getEffectiveOrsApiKey() {
    return getOrsApiKey() ??
        (developmentOrsApiKey.isEmpty ? null : developmentOrsApiKey);
  }

  Future<void> saveOrsApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await deleteOrsApiKey();
      return;
    }

    await _secureCredentials.writeString(
      SecureCredentialKey.orsApiKey,
      trimmed,
    );
    _cachedOrsApiKey = trimmed;
    await _box?.delete(_orsApiKeyKey);
    notifyListeners();
  }

  Future<void> deleteOrsApiKey() async {
    await _secureCredentials.delete(SecureCredentialKey.orsApiKey);
    _cachedOrsApiKey = null;
    await _box?.delete(_orsApiKeyKey);
    notifyListeners();
  }

  bool hasOrsApiKey() => getOrsApiKey() != null;

  bool hasEffectiveOrsApiKey() => getEffectiveOrsApiKey() != null;

  bool get isUsingDevelopmentKey {
    return !hasOrsApiKey() && developmentOrsApiKey.isNotEmpty;
  }

  bool get showSpeedLimits => _getBool(_showSpeedLimitsKey, true);

  bool get showTrafficLights => _getBool(_showTrafficLightsKey, true);

  bool get showStopGiveWay => _getBool(_showStopGiveWayKey, true);

  bool get showSpeedBumps => _getBool(_showSpeedBumpsKey, true);

  bool get showRoadFeatures => _getBool(_showRoadFeaturesKey, true);

  bool get showSpeedCameras => _getBool(_showSpeedCamerasKey, false);

  bool get mapHeadingUp => _getBool('map_heading_up', true);

  Future<void> setMapHeadingUp(bool value) => _setBool('map_heading_up', value);

  bool get useCleanMap => _getBool('use_clean_map', true);

  Future<void> setUseCleanMap(bool value) => _setBool('use_clean_map', value);

  bool get sensorAssistedHeading => _getBool('sensor_assisted_heading', true);

  Future<void> setSensorAssistedHeading(bool value) =>
      _setBool('sensor_assisted_heading', value);

  bool get smoothMarkerMovement => _getBool('smooth_marker_movement', true);

  Future<void> setSmoothMarkerMovement(bool value) =>
      _setBool('smooth_marker_movement', value);

  bool get onboardingComplete => _getBool(_onboardingCompleteKey, false);

  Future<void> setOnboardingComplete(bool value) =>
      _setBool(_onboardingCompleteKey, value);

  Future<void> setShowSpeedLimits(bool value) =>
      _setBool(_showSpeedLimitsKey, value);

  Future<void> setShowTrafficLights(bool value) =>
      _setBool(_showTrafficLightsKey, value);

  Future<void> setShowStopGiveWay(bool value) =>
      _setBool(_showStopGiveWayKey, value);

  Future<void> setShowSpeedBumps(bool value) =>
      _setBool(_showSpeedBumpsKey, value);

  Future<void> setShowRoadFeatures(bool value) =>
      _setBool(_showRoadFeaturesKey, value);

  Future<void> setShowSpeedCameras(bool value) =>
      _setBool(_showSpeedCamerasKey, value);

  bool isWarningTypeEnabled(RoadWarningType type) {
    return switch (type) {
      RoadWarningType.speedCamera => showSpeedCameras,
      RoadWarningType.speedBump => showSpeedBumps,
      RoadWarningType.trafficLight => showTrafficLights,
      RoadWarningType.stopSign || RoadWarningType.giveWay => showStopGiveWay,
      RoadWarningType.surfaceChange ||
      RoadWarningType.tunnel ||
      RoadWarningType.bridge ||
      RoadWarningType.roundabout ||
      RoadWarningType.crest ||
      RoadWarningType.dip => showRoadFeatures,
      RoadWarningType.speedLimitChange => showSpeedLimits,
    };
  }

  OrsProfile get orsProfile {
    final value = _box?.get(_orsProfileKey);
    if (value is String) {
      return OrsProfile.values.firstWhere(
        (e) => e.name == value,
        orElse: () => OrsProfile.drivingCar,
      );
    }
    return OrsProfile.drivingCar;
  }

  Future<void> setOrsProfile(OrsProfile profile) async {
    await _box?.put(_orsProfileKey, profile.name);
    notifyListeners();
  }

  bool _getBool(String key, bool defaultValue) {
    final value = _box?.get(key);
    return value is bool ? value : defaultValue;
  }

  Future<void> _setBool(String key, bool value) async {
    await _box?.put(key, value);
    notifyListeners();
  }

  bool get autoRecordNavigation => _getBool('auto_record_navigation', true);
  Future<void> setAutoRecordNavigation(bool value) => _setBool('auto_record_navigation', value);

  String get defaultTripPrivacy => _box?.get('default_trip_privacy') as String? ?? 'private';
  Future<void> setDefaultTripPrivacy(String value) async {
    await _box?.put('default_trip_privacy', value);
    notifyListeners();
  }

  bool get wakeLockEnabled => _getBool('wake_lock_enabled', true);
  Future<void> setWakeLockEnabled(bool value) => _setBool('wake_lock_enabled', value);

  Future<void> _loadAndMigrateSecureCredentials() async {
    final secureOrsKey = await _secureCredentials.readString(
      SecureCredentialKey.orsApiKey,
    );
    if (secureOrsKey != null) {
      _cachedOrsApiKey = secureOrsKey;
      await _box?.delete(_orsApiKeyKey);
      return;
    }

    final legacyValue = _box?.get(_orsApiKeyKey);
    if (legacyValue is String && legacyValue.trim().isNotEmpty) {
      final migratedKey = legacyValue.trim();
      await _secureCredentials.writeString(
        SecureCredentialKey.orsApiKey,
        migratedKey,
      );
      _cachedOrsApiKey = migratedKey;
      await _box?.delete(_orsApiKeyKey);
    }
  }
}
