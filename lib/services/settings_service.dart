import 'package:hive_flutter/hive_flutter.dart';

import 'local_hive.dart';

class SettingsService {
  static const _boxName = 'settings';
  static const _orsApiKeyKey = 'ors_api_key';
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
}
