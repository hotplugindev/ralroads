import 'dart:math' as math;
import 'package:drift/drift.dart';
import '../database/app_database.dart';

class PrivacyRepository {
  PrivacyRepository(this.database);

  final AppDatabase database;

  Future<void> createPrivateZone({
    required String id,
    required String name,
    required double lat,
    required double lon,
    required double radiusMeters,
  }) {
    final now = DateTime.now();
    return database.into(database.privateZones).insertOnConflictUpdate(
      PrivateZonesCompanion(
        id: Value(id),
        name: Value(name),
        lat: Value(lat),
        lon: Value(lon),
        radiusMeters: Value(radiusMeters),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<List<PrivateZone>> getPrivateZones() {
    return database.select(database.privateZones).get();
  }

  Future<void> deletePrivateZone(String id) {
    return (database.delete(database.privateZones)..where((row) => row.id.equals(id))).go();
  }

  /// Checks if a coordinate falls within any active privacy zone.
  Future<bool> isPointInPrivacyZone(double lat, double lon) async {
    final zones = await getPrivateZones();
    for (final zone in zones) {
      final distance = distanceMeters(lat, lon, zone.lat, zone.lon);
      if (distance <= zone.radiusMeters) {
        return true;
      }
    }
    return false;
  }

  /// Computes Haversine distance in meters.
  double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final rLat1 = lat1 * math.pi / 180.0;
    final rLat2 = lat2 * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) *
            math.cos(rLat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
