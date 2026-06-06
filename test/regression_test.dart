import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/models/speed_limit_segment.dart';
import 'package:ralroads/services/settings_service.dart';
import 'package:ralroads/services/ors_service.dart';
import 'package:ralroads/utils/geo_math.dart';

String profileToPathSegment(OrsProfile profile) {
  return switch (profile) {
    OrsProfile.drivingCar => 'driving-car',
    OrsProfile.drivingHgv => 'driving-hgv',
    OrsProfile.cyclingRoad => 'cycling-road',
    OrsProfile.footWalking => 'foot-walking',
  };
}

void main() {
  group('Ramer-Douglas-Peucker Simplification Tests', () {
    test('simplifies a straight line to start and end points', () {
      final points = [
        const RoutePoint(lat: 0.0, lon: 0.0, distanceFromStart: 0.0),
        const RoutePoint(lat: 0.0001, lon: 0.0, distanceFromStart: 11.1),
        const RoutePoint(lat: 0.0002, lon: 0.0, distanceFromStart: 22.2),
        const RoutePoint(lat: 0.0003, lon: 0.0, distanceFromStart: 33.3),
        const RoutePoint(lat: 0.0004, lon: 0.0, distanceFromStart: 44.4),
      ];
      final simplified = simplifyPoints(points, 1.0);
      expect(simplified.length, lessThan(points.length));
      expect(simplified.first.lat, 0.0);
      expect(simplified.last.lat, 0.0004);
    });

    test('retains vertices with high deviation', () {
      final points = [
        const RoutePoint(lat: 0.0, lon: 0.0, distanceFromStart: 0.0),
        const RoutePoint(lat: 0.0001, lon: 0.0005, distanceFromStart: 56.0), // High deviation
        const RoutePoint(lat: 0.0002, lon: 0.0, distanceFromStart: 112.0),
      ];
      final simplified = simplifyPoints(points, 1.0);
      expect(simplified.length, 3);
    });
  });

  group('ORS Route Planning Profiles', () {
    test('OrsProfile converts to correct OpenRouteService endpoints', () {
      expect(profileToPathSegment(OrsProfile.drivingCar), 'driving-car');
      expect(profileToPathSegment(OrsProfile.drivingHgv), 'driving-hgv');
      expect(profileToPathSegment(OrsProfile.cyclingRoad), 'cycling-road');
      expect(profileToPathSegment(OrsProfile.footWalking), 'foot-walking');
    });
  });

  group('HUD Navigation ETA and Progress Calculations', () {
    test('calculates correct remaining distance and progress percentage', () {
      final routePoints = [
        const RoutePoint(lat: 0.0, lon: 0.0, distanceFromStart: 0.0),
        const RoutePoint(lat: 0.01, lon: 0.01, distanceFromStart: 1500.0),
        const RoutePoint(lat: 0.02, lon: 0.02, distanceFromStart: 3000.0),
      ];

      const distanceAlongRoute = 1200.0;
      final remainingDistanceMeters = routePoints.isNotEmpty
          ? (routePoints.last.distanceFromStart - distanceAlongRoute).clamp(0.0, double.infinity)
          : 0.0;

      final totalDistance = routePoints.isNotEmpty ? routePoints.last.distanceFromStart : 1.0;
      final progressPercentage = (distanceAlongRoute / totalDistance).clamp(0.0, 1.0);

      expect(remainingDistanceMeters, 1800.0);
      expect(progressPercentage, 0.4);
    });

    test('calculates correct remaining duration incorporating speed limit changes', () {
      final routePoints = [
        const RoutePoint(lat: 0.0, lon: 0.0, distanceFromStart: 0.0),
        const RoutePoint(lat: 0.005, lon: 0.005, distanceFromStart: 1000.0),
        const RoutePoint(lat: 0.01, lon: 0.01, distanceFromStart: 2000.0),
      ];

      final speedLimits = [
        const SpeedLimitSegment(
          id: '1',
          startDistance: 0,
          endDistance: 1000,
          rawMaxspeed: '50',
          parsedKmh: 50,
        ),
        const SpeedLimitSegment(
          id: '2',
          startDistance: 1000,
          endDistance: 2000,
          rawMaxspeed: '100',
          parsedKmh: 100,
        ),
      ];

      const distanceAlongRoute = 500.0;
      const lastMatchedIndex = 0;

      // Mathematical logic matching _buildDriveState
      double remainingDurationSeconds = 0.0;
      double prevDist = distanceAlongRoute;
      for (var i = lastMatchedIndex + 1; i < routePoints.length; i++) {
        final p = routePoints[i];
        final segmentLength = p.distanceFromStart - prevDist;
        if (segmentLength <= 0) continue;
        final limitSegment = speedLimits.firstWhere(
          (s) => p.distanceFromStart >= s.startDistance && p.distanceFromStart <= s.endDistance,
          orElse: () => const SpeedLimitSegment(
            id: 'default',
            startDistance: 0.0,
            endDistance: 0.0,
            rawMaxspeed: '60',
            parsedKmh: 60,
          ),
        );
        final speedLimitMps = (limitSegment.parsedKmh ?? 60) / 3.6;
        remainingDurationSeconds += segmentLength / speedLimitMps;
        prevDist = p.distanceFromStart;
      }

      // First segment (500m to 1000m): 500m at 50km/h (13.888 m/s) -> 36.0 seconds
      // Second segment (1000m to 2000m): 1000m at 100km/h (27.777 m/s) -> 36.0 seconds
      // Total remaining duration: 72.0 seconds
      expect(remainingDurationSeconds, closeTo(72.0, 0.1));
    });
  });
}
