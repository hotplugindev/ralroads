import 'dart:math' as math;

double degreesToRadians(double degrees) => degrees * math.pi / 180;

double radiansToDegrees(double radians) => radians * 180 / math.pi;

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
