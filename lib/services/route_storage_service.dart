import 'package:hive_flutter/hive_flutter.dart';

import '../models/saved_route.dart';
import 'local_hive.dart';

class RouteStorageService {
  static const _boxName = 'saved_routes';

  late final Box<dynamic> _box;

  Future<void> init() async {
    await LocalHive.ensureInitialized();
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Future<void> saveRoute(SavedRoute route) async {
    await _box.put(route.id, route.toJson());
  }

  Future<void> renameRoute(String id, String newName) async {
    final route = getRoute(id);
    if (route == null) {
      return;
    }
    await saveRoute(route.copyWith(name: newName));
  }

  List<SavedRoute> getRoutes() {
    return _box.values
        .whereType<Map<dynamic, dynamic>>()
        .map(SavedRoute.fromJson)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  SavedRoute? getRoute(String id) {
    final value = _box.get(id);
    if (value is Map<dynamic, dynamic>) {
      return SavedRoute.fromJson(value);
    }
    return null;
  }

  Future<void> deleteRoute(String id) => _box.delete(id);
}
