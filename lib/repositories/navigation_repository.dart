import '../database/app_database.dart';
import '../models/saved_route.dart';
import '../services/route_storage_service.dart';
import '../services/saved_route_migration_service.dart';

class NavigationRepository {
  NavigationRepository({
    required RouteStorageService routeStorage,
    required AppDatabase database,
  }) : _routeStorage = routeStorage,
       _migration = SavedRouteMigrationService(database);

  final RouteStorageService _routeStorage;
  final SavedRouteMigrationService _migration;

  List<SavedRoute> getSavedRoutes() => _routeStorage.getRoutes();

  SavedRoute? getSavedRoute(String id) => _routeStorage.getRoute(id);

  Future<void> saveRoute(SavedRoute route) async {
    await _routeStorage.saveRoute(route);
    await _migration.migrateSavedRoutes([route]);
  }

  Future<void> renameRoute(String id, String newName) async {
    await _routeStorage.renameRoute(id, newName);
    final renamed = _routeStorage.getRoute(id);
    if (renamed != null) {
      await _migration.migrateSavedRoutes([renamed]);
    }
  }

  Future<void> deleteRoute(String id) async {
    await _routeStorage.deleteRoute(id);
  }

  Future<int> migrateLegacySavedRoutes() {
    return _migration.migrateSavedRoutes(_routeStorage.getRoutes());
  }

  Stream<List<SavedRoute>> watchSavedRoutes() => _routeStorage.watchRoutes();
}
