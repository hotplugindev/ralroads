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

class RouteChunk {
  final int startIndex;
  final int endIndex;
  final double centerLat;
  final double centerLon;
  final double radiusMeters;

  const RouteChunk({
    required this.startIndex,
    required this.endIndex,
    required this.centerLat,
    required this.centerLon,
    required this.radiusMeters,
  });
}

class GpsRouteMatcher {
  List<RoutePoint>? _lastRoutePoints;
  List<RouteChunk> _chunks = const [];

  void _ensureIndex(List<RoutePoint> routePoints) {
    if (identical(_lastRoutePoints, routePoints)) return;
    _lastRoutePoints = routePoints;
    _chunks = _buildChunks(routePoints);
  }

  List<RouteChunk> _buildChunks(List<RoutePoint> routePoints) {
    if (routePoints.isEmpty) return const [];
    final chunks = <RouteChunk>[];
    const chunkSize = 200;

    for (var i = 0; i < routePoints.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, routePoints.length - 1);
      final count = end - i + 1;

      var sumLat = 0.0;
      var sumLon = 0.0;
      for (var j = i; j <= end; j++) {
        sumLat += routePoints[j].lat;
        sumLon += routePoints[j].lon;
      }
      final centerLat = sumLat / count;
      final centerLon = sumLon / count;

      var maxDist = 0.0;
      for (var j = i; j <= end; j++) {
        final dist = haversineDistanceMeters(
          centerLat,
          centerLon,
          routePoints[j].lat,
          routePoints[j].lon,
        );
        if (dist > maxDist) maxDist = dist;
      }

      chunks.add(
        RouteChunk(
          startIndex: i,
          endIndex: end,
          centerLat: centerLat,
          centerLon: centerLon,
          radiusMeters: maxDist,
        ),
      );
    }
    return chunks;
  }

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

    _ensureIndex(routePoints);

    final localStart = clampInt(
      lastMatchedIndex - 10,
      0,
      routePoints.length - 1,
    );
    final localEnd = clampInt(lastMatchedIndex + 50, 0, routePoints.length - 1);

    var nearestIndex = localStart;
    var nearestDistance = double.infinity;

    for (var i = localStart; i <= localEnd; i++) {
      final point = routePoints[i];
      final distance = haversineDistanceMeters(lat, lon, point.lat, point.lon);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    if (nearestDistance > 60.0) {
      var globalNearestIndex = nearestIndex;
      var globalNearestDistance = nearestDistance;

      // Find the closest chunks by center distance
      final chunkDistances = <(RouteChunk, double)>[];
      for (final chunk in _chunks) {
        final distToCenter = haversineDistanceMeters(
          lat,
          lon,
          chunk.centerLat,
          chunk.centerLon,
        );
        chunkDistances.add((chunk, distToCenter));
      }

      // Sort by center distance
      chunkDistances.sort((a, b) => a.$2.compareTo(b.$2));

      // Scan the top 3 closest chunks (covers about 600 route points max)
      final candidateChunks = chunkDistances.take(3);
      for (final candidate in candidateChunks) {
        final chunk = candidate.$1;
        for (var i = chunk.startIndex; i <= chunk.endIndex; i++) {
          final point = routePoints[i];
          final distance = haversineDistanceMeters(
            lat,
            lon,
            point.lat,
            point.lon,
          );
          if (distance < globalNearestDistance) {
            globalNearestDistance = distance;
            globalNearestIndex = i;
          }
        }
      }

      nearestIndex = globalNearestIndex;
      nearestDistance = globalNearestDistance;
    }

    return RouteMatch(
      nearestIndex: nearestIndex,
      distanceFromRoute: nearestDistance,
      distanceAlongRoute: routePoints[nearestIndex].distanceFromStart,
    );
  }
}
