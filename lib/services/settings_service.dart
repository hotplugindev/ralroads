import 'package:hive_flutter/hive_flutter.dart';

import '../models/road_warning.dart';
import 'local_hive.dart';

class SettingsService {
  static const _boxName = 'settings';
  static const _orsApiKeyKey = 'ors_api_key';
  static const _showSpeedLimitsKey = 'show_speed_limits';
  static const _showTrafficLightsKey = 'show_traffic_lights';
  static const _showStopGiveWayKey = 'show_stop_give_way';
  static const _showSpeedBumpsKey = 'show_speed_bumps';
  static const _showRoadFeaturesKey = 'show_road_features';
  static const _showSpeedCamerasKey = 'show_speed_cameras';
  static const developmentOrsApiKey = String.fromEnvironment('ORS_API_KEY');

  Box<dynamic>? _box;

  Future<void> init() async {
    await LocalHive.ensureInitialized();
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  String? getOrsApiKey() {
    final value = _box?.get(_orsApiKeyKey);
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
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

    // For production, move this to flutter_secure_storage or platform keystore.
    await _box?.put(_orsApiKeyKey, trimmed);
  }

  Future<void> deleteOrsApiKey() async {
    await _box?.delete(_orsApiKeyKey);
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

  Future<void> setMapHeadingUp(bool value) =>
      _setBool('map_heading_up', value);

  bool get useCleanMap => _getBool('use_clean_map', true);

  Future<void> setUseCleanMap(bool value) =>
      _setBool('use_clean_map', value);

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
      RoadWarningType.roundabout => showRoadFeatures,
      RoadWarningType.speedLimitChange => showSpeedLimits,
    };
  }

  bool _getBool(String key, bool defaultValue) {
    final value = _box?.get(key);
    return value is bool ? value : defaultValue;
  }

  Future<void> _setBool(String key, bool value) async {
    await _box?.put(key, value);
  }
}
