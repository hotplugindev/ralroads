import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../models/matched_route.dart';
import '../models/route_point.dart';
import '../utils/geo_math.dart';
import 'pacenote_generator.dart';
import 'settings_service.dart';

class OrsService {
  OrsService({required SettingsService settings, Dio? dio})
    : _settings = settings,
      _dio = dio ?? Dio();

  String get _endpoint {
    final profile = _settings.orsProfile;
    final pathSegment = switch (profile) {
      OrsProfile.drivingCar => 'driving-car',
      OrsProfile.drivingHgv => 'driving-hgv',
      OrsProfile.cyclingRoad => 'cycling-road',
      OrsProfile.footWalking => 'foot-walking',
    };
    return 'https://api.openrouteservice.org/v2/directions/$pathSegment/geojson';
  }

  final SettingsService _settings;
  final Dio _dio;
  late final PacenoteGenerator _pacenoteGenerator = PacenoteGenerator(
    settings: _settings,
  );
  List<RouteManeuver> _lastRouteManeuvers = const [];
  List<RouteManeuver> get lastRouteManeuvers => _lastRouteManeuvers;

  bool get hasApiKey => _settings.hasEffectiveOrsApiKey();

  Future<Map<String, dynamic>> buildRouteGeoJson(
    List<RoutePoint> points,
  ) async {
    if (points.length < 2) {
      throw const OrsRequestException('Add at least a start and destination.');
    }

    final apiKey = _settings.getEffectiveOrsApiKey();
    if (apiKey == null) {
      throw const MissingOrsApiKeyException();
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        data: {
          'coordinates': points.map((point) => [point.lon, point.lat]).toList(),
          'instructions': true,
          'geometry': true,
          'elevation': true,
          'extra_info': ['surface', 'waytype', 'steepness', 'suitability'],
          'radiuses': List.filled(points.length, -1),
        },
        options: Options(
          headers: {
            'Authorization': apiKey,
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data;
      if (data == null) {
        throw const OrsRequestException('OpenRouteService returned no data.');
      }
      return data;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<List<RoutePoint>> buildRoute(List<RoutePoint> points) async {
    final geoJson = await buildRouteGeoJson(points);
    final features = geoJson['features'] as List<dynamic>?;
    if (features == null || features.isEmpty) {
      throw const OrsRequestException('OpenRouteService returned no route.');
    }

    final geometry =
        (features.first as Map<String, dynamic>)['geometry']
            as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List<dynamic>?;
    if (coordinates == null || coordinates.isEmpty) {
      throw const OrsRequestException(
        'OpenRouteService returned an empty route geometry.',
      );
    }

    var routePoints = coordinates.map((coordinate) {
      final pair = coordinate as List<dynamic>;
      return RoutePoint(
        lon: (pair[0] as num).toDouble(),
        lat: (pair[1] as num).toDouble(),
        elevation: pair.length >= 3 ? (pair[2] as num).toDouble() : null,
      );
    }).toList();

    if (routePoints.length > 2000) {
      routePoints = simplifyPoints(routePoints, 1.5);
    }

    final enriched = _pacenoteGenerator.enrichRoutePoints(routePoints);
    _lastRouteManeuvers = _parseManeuversFromGeoJson(geoJson, enriched);
    return enriched;
  }

  List<RouteManeuver> _parseManeuversFromGeoJson(
    Map<String, dynamic> geoJson,
    List<RoutePoint> routePoints,
  ) {
    final features = geoJson['features'] as List<dynamic>?;
    if (features == null || features.isEmpty || routePoints.isEmpty) {
      return const [];
    }
    final feature = features.first as Map<String, dynamic>;
    final properties =
        feature['properties'] as Map<String, dynamic>? ?? const {};
    final segments = properties['segments'] as List<dynamic>? ?? const [];
    final maneuvers = <RouteManeuver>[];
    var cumulativeDistance = 0.0;

    for (final segment in segments.whereType<Map<String, dynamic>>()) {
      final steps = segment['steps'] as List<dynamic>? ?? const [];
      for (final step in steps.whereType<Map<String, dynamic>>()) {
        final type = (step['type'] as num?)?.toInt() ?? 14;
        final distance = (step['distance'] as num?)?.toDouble() ?? 0.0;
        final routeDistance = cumulativeDistance;
        cumulativeDistance += distance;

        final maneuverType = _mapOrsStepType(type);
        if (maneuverType == null) {
          continue;
        }
        final waypoint = step['way_points'] as List<dynamic>? ?? const [];
        final fromIndex = waypoint.isNotEmpty
            ? _edgeIndexNearWaypoint(waypoint.first, routePoints)
            : _indexNearDistance(routePoints, routeDistance);
        final toIndex = waypoint.length > 1
            ? _edgeIndexNearWaypoint(waypoint[1], routePoints)
            : _indexNearDistance(routePoints, routeDistance + distance);
        maneuvers.add(
          RouteManeuver(
            id: 'ors-step-${maneuvers.length}-$type-${routeDistance.round()}',
            type: maneuverType,
            distanceFromStart: routeDistance,
            fromEdgeIndex: fromIndex,
            toEdgeIndex: toIndex,
            instruction: step['instruction'] as String?,
            roundaboutExit: _parseRoundaboutExit(
              step['instruction'] as String?,
            ),
            confidence: _confidenceForOrsStep(type),
          ),
        );
      }
    }
    return maneuvers;
  }

  RouteManeuverType? _mapOrsStepType(int type) {
    return switch (type) {
      0 => RouteManeuverType.turnLeft,
      1 => RouteManeuverType.turnRight,
      2 => RouteManeuverType.sharpLeft,
      3 => RouteManeuverType.sharpRight,
      4 => RouteManeuverType.slightLeft,
      5 => RouteManeuverType.slightRight,
      7 => RouteManeuverType.enterRoundabout,
      8 => RouteManeuverType.exitRoundabout,
      9 => RouteManeuverType.uTurn,
      12 => RouteManeuverType.keepLeft,
      13 => RouteManeuverType.keepRight,
      _ => null,
    };
  }

  double _confidenceForOrsStep(int type) {
    if (type == 7 || type == 8) return 0.98;
    if (type == 0 || type == 1 || type == 2 || type == 3 || type == 9) {
      return 0.92;
    }
    return 0.82;
  }

  int? _parseRoundaboutExit(String? instruction) {
    if (instruction == null) return null;
    final numeric = RegExp(
      r'(\d+)(st|nd|rd|th)? exit',
      caseSensitive: false,
    ).firstMatch(instruction);
    if (numeric != null) {
      return int.tryParse(numeric.group(1)!);
    }
    final lower = instruction.toLowerCase();
    const words = {
      'first': 1,
      'second': 2,
      'third': 3,
      'fourth': 4,
      'fifth': 5,
      'sixth': 6,
    };
    for (final entry in words.entries) {
      if (lower.contains('${entry.key} exit')) {
        return entry.value;
      }
    }
    return null;
  }

  int _edgeIndexNearWaypoint(dynamic waypoint, List<RoutePoint> routePoints) {
    if (waypoint is num) {
      return waypoint.toInt().clamp(0, math.max(0, routePoints.length - 2));
    }
    return 0;
  }

  int _indexNearDistance(List<RoutePoint> points, double distance) {
    if (points.isEmpty) return 0;
    var best = 0;
    var bestDelta = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final delta = (points[i].distanceFromStart - distance).abs();
      if (delta < bestDelta) {
        best = i;
        bestDelta = delta;
      }
    }
    return best.clamp(0, math.max(0, points.length - 2));
  }

  Future<bool> validateApiKey(String key) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        _endpoint,
        data: const {
          'coordinates': [
            [11.6572, 46.7150],
            [11.6600, 46.7160],
          ],
          'instructions': false,
          'geometry': true,
          'elevation': false,
        },
        options: Options(
          headers: {
            'Authorization': key.trim(),
            'Content-Type': 'application/json',
          },
        ),
      );
      return true;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        return false;
      }
      if (error.response == null) {
        throw const OrsNetworkException('Network error while testing key.');
      }
      throw _mapDioException(error);
    }
  }

  OrsException _mapDioException(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return const InvalidOrsApiKeyException();
    }
    if (status == 429) {
      return const OrsRateLimitException();
    }
    if (error.response == null) {
      return const OrsNetworkException('Network error while building route.');
    }

    final details = error.response?.data?.toString() ?? error.message;
    return OrsRequestException(
      'Route request failed${status == null ? '' : ' ($status)'}: $details',
    );
  }
}

class OrsException implements Exception {
  const OrsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MissingOrsApiKeyException extends OrsException {
  const MissingOrsApiKeyException()
    : super('Online route planning requires an OpenRouteService API key.');
}

class InvalidOrsApiKeyException extends OrsException {
  const InvalidOrsApiKeyException()
    : super(
        'OpenRouteService rejected your API key. Please check it in Settings.',
      );
}

class OrsRateLimitException extends OrsException {
  const OrsRateLimitException()
    : super(
        'OpenRouteService rate limit reached. Try again later or use another key.',
      );
}

class OrsNetworkException extends OrsException {
  const OrsNetworkException(super.message);
}

class OrsRequestException extends OrsException {
  const OrsRequestException(super.message);
}
