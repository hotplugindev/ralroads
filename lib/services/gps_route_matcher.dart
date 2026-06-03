import '../models/route_point.dart';
import '../utils/geo_math.dart';

class RouteMatch {
  const RouteMatch({
    required this.nearestIndex,
    required this.distanceFromRoute,
    required this.distanceAlongRoute,
  });

  final int nearestIndex;
  final double distanceFromRoute;
  final double distanceAlongRoute;
}

class GpsRouteMatcher {
  RouteMatch match({
    required double lat,
    required double lon,
    required List<RoutePoint> routePoints,
    int lastMatchedIndex = 0,
  }) {
    if (routePoints.isEmpty) {
      return const RouteMatch(
        nearestIndex: 0,
        distanceFromRoute: double.infinity,
        distanceAlongRoute: 0,
      );
    }

    final startIndex = clampInt(
      lastMatchedIndex - 8,
      0,
      routePoints.length - 1,
    );
    var nearestIndex = startIndex;
    var nearestDistance = double.infinity;

    for (var i = startIndex; i < routePoints.length; i++) {
      final point = routePoints[i];
      final distance = haversineDistanceMeters(lat, lon, point.lat, point.lon);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    return RouteMatch(
      nearestIndex: nearestIndex,
      distanceFromRoute: nearestDistance,
      distanceAlongRoute: routePoints[nearestIndex].distanceFromStart,
    );
  }
}
