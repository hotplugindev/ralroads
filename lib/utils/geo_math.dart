import 'dart:math' as math;
import '../models/route_point.dart';


double degreesToRadians(double degrees) => degrees * math.pi / 180;

double radiansToDegrees(double radians) => radians * 180 / math.pi;

double normalizeHeading(double heading) {
  return (heading % 360 + 360) % 360;
}

double haversineDistanceMeters(

  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadiusMeters = 6371000.0;
  final phi1 = degreesToRadians(lat1);
  final phi2 = degreesToRadians(lat2);
  final deltaPhi = degreesToRadians(lat2 - lat1);
  final deltaLambda = degreesToRadians(lon2 - lon1);

  final a =
      math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
      math.cos(phi1) *
          math.cos(phi2) *
          math.sin(deltaLambda / 2) *
          math.sin(deltaLambda / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = degreesToRadians(lat1);
  final phi2 = degreesToRadians(lat2);
  final deltaLambda = degreesToRadians(lon2 - lon1);

  final y = math.sin(deltaLambda) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
  return (radiansToDegrees(math.atan2(y, x)) + 360) % 360;
}

double normalizeAngleDeltaDegrees(double a, double b) {
  var delta = (b - a + 540) % 360 - 180;
  if (delta == -180) {
    delta = 180;
  }
  return delta;
}

double clampDouble(double value, double min, double max) {
  return math.max(min, math.min(max, value));
}

int clampInt(int value, int min, int max) {
  return math.max(min, math.min(max, value));
}

double perpendicularDistance(RoutePoint p, RoutePoint start, RoutePoint end) {
  final lat = p.lat;
  final lon = p.lon;
  final startLat = start.lat;
  final startLon = start.lon;
  final endLat = end.lat;
  final endLon = end.lon;

  final dx = endLon - startLon;
  final dy = endLat - startLat;
  if (dx == 0 && dy == 0) {
    return haversineDistanceMeters(lat, lon, startLat, startLon);
  }

  final latAvgRad = degreesToRadians((startLat + endLat + lat) / 3.0);
  final cosLat = math.cos(latAvgRad);

  final px = lon * cosLat;
  final py = lat;
  final ax = startLon * cosLat;
  final ay = startLat;
  final bx = endLon * cosLat;
  final by = endLat;

  final l2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay);
  var t = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / l2;
  t = math.max(0.0, math.min(1.0, t));

  final projX = ax + t * (bx - ax);
  final projY = ay + t * (by - ay);

  final dLat = py - projY;
  final dLon = (px - projX) / (cosLat != 0 ? cosLat : 1.0);

  final distLatMeters = dLat * 111139.0;
  final distLonMeters = dLon * 111139.0 * cosLat;
  return math.sqrt(distLatMeters * distLatMeters + distLonMeters * distLonMeters);
}

List<RoutePoint> simplifyPoints(List<RoutePoint> points, double epsilonMeters) {
  if (points.length < 3) return points;

  var maxIndex = 0;
  var maxDist = 0.0;
  final end = points.length - 1;

  for (var i = 1; i < end; i++) {
    final dist = perpendicularDistance(points[i], points[0], points[end]);
    if (dist > maxDist) {
      maxDist = dist;
      maxIndex = i;
    }
  }

  if (maxDist > epsilonMeters) {
    final results1 = simplifyPoints(points.sublist(0, maxIndex + 1), epsilonMeters);
    final results2 = simplifyPoints(points.sublist(maxIndex), epsilonMeters);

    return [...results1.sublist(0, results1.length - 1), ...results2];
  } else {
    return [points.first, points.last];
  }
}

