import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../utils/geo_math.dart';

class RoadEnrichment {
  const RoadEnrichment({
    required this.roadWarnings,
    required this.speedLimitSegments,
  });

  final List<RoadWarning> roadWarnings;
  final List<SpeedLimitSegment> speedLimitSegments;
}

class OverpassService {
  OverpassService({Dio? dio}) : _dio = dio ?? Dio();

  static const _endpoint = 'https://overpass-api.de/api/interpreter';
  static const _bboxPaddingDegrees = 0.005;
  static const _pointMatchThresholdMeters = 35.0;
  static const _wayMatchThresholdMeters = 50.0;

  final Dio _dio;

  Future<RoadEnrichment> enrichRoute(List<RoutePoint> routePoints) async {
    if (routePoints.length < 2) {
      return const RoadEnrichment(roadWarnings: [], speedLimitSegments: []);
    }

    try {
      final query = _buildQuery(routePoints);
      final response = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        data: {'data': query},
        options: Options(
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 28),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'RalRoads/0.1 contact: local-dev',
          },
        ),
      );

      final elements = response.data?['elements'] as List<dynamic>? ?? const [];
      final warnings = <RoadWarning>[];
      final speedLimits = <SpeedLimitSegment>[];

      for (final element in elements.whereType<Map<String, dynamic>>()) {
        final tags = Map<String, dynamic>.from(
          element['tags'] as Map<dynamic, dynamic>? ?? const {},
        );
        final type = element['type'] as String?;

        if (type == 'node') {
          final warning = _warningFromNode(element, tags, routePoints);
          if (warning != null) {
            warnings.add(warning);
          }
          continue;
        }

        if (type == 'way') {
          final geometry = _geometryFromWay(element);
          if (geometry.isEmpty) {
            continue;
          }

          if (tags['maxspeed'] != null) {
            final segment = _speedLimitFromWay(
              element,
              tags,
              geometry,
              routePoints,
            );
            if (segment != null) {
              speedLimits.add(segment);
            }
          }

          final warning = _warningFromWay(element, tags, geometry, routePoints);
          if (warning != null) {
            warnings.add(warning);
          }
        }
      }

      return RoadEnrichment(
        roadWarnings: _dedupeWarnings(warnings)
          ..sort((a, b) => a.distanceFromStart.compareTo(b.distanceFromStart)),
        speedLimitSegments: speedLimits
          ..sort((a, b) => a.startDistance.compareTo(b.startDistance)),
      );
    } on DioException catch (error) {
      throw OverpassException(error.message ?? 'Overpass request failed.');
    } catch (error) {
      throw OverpassException('Road warning parsing failed: $error');
    }
  }

  String _buildQuery(List<RoutePoint> points) {
    var south = points.first.lat;
    var north = points.first.lat;
    var west = points.first.lon;
    var east = points.first.lon;

    for (final point in points) {
      south = math.min(south, point.lat);
      north = math.max(north, point.lat);
      west = math.min(west, point.lon);
      east = math.max(east, point.lon);
    }

    south -= _bboxPaddingDegrees;
    north += _bboxPaddingDegrees;
    west -= _bboxPaddingDegrees;
    east += _bboxPaddingDegrees;

    final bbox = '$south,$west,$north,$east';
    return '''
[out:json][timeout:25];
(
  node["highway"="speed_camera"]($bbox);
  node["highway"="traffic_signals"]($bbox);
  node["highway"="stop"]($bbox);
  node["highway"="give_way"]($bbox);
  node["traffic_calming"]($bbox);
  way["highway"]["maxspeed"]($bbox);
  way["highway"]["surface"]($bbox);
  way["highway"]["tunnel"]($bbox);
  way["highway"]["bridge"]($bbox);
  way["junction"="roundabout"]($bbox);
  way["junction"="circular"]($bbox);
  relation["type"="enforcement"]["enforcement"="maxspeed"]($bbox);
);
out body geom;
''';
  }

  RoadWarning? _warningFromNode(
    Map<String, dynamic> element,
    Map<String, dynamic> tags,
    List<RoutePoint> routePoints,
  ) {
    final lat = (element['lat'] as num?)?.toDouble();
    final lon = (element['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      return null;
    }

    final match = nearestRouteMatchForLatLon(lat, lon, routePoints);
    if (match.distanceToRouteMeters > _pointMatchThresholdMeters) {
      return null;
    }

    final mapped = _nodeWarningText(tags);
    if (mapped == null) {
      return null;
    }

    return RoadWarning(
      id: 'osm-node-${element['id']}-${mapped.$1.name}',
      type: mapped.$1,
      lat: lat,
      lon: lon,
      distanceFromStart: match.distanceFromStart,
      text: mapped.$2,
      tags: tags,
    );
  }

  (RoadWarningType, String)? _nodeWarningText(Map<String, dynamic> tags) {
    if (tags['highway'] == 'speed_camera') {
      final maxspeed = tags['maxspeed']?.toString();
      return (
        RoadWarningType.speedCamera,
        maxspeed == null ? 'Speed camera' : 'Speed camera, $maxspeed',
      );
    }
    if (tags['highway'] == 'traffic_signals') {
      return (RoadWarningType.trafficLight, 'Traffic lights');
    }
    if (tags['highway'] == 'stop') {
      return (RoadWarningType.stopSign, 'Stop sign');
    }
    if (tags['highway'] == 'give_way') {
      return (RoadWarningType.giveWay, 'Give way');
    }
    if (tags['traffic_calming'] != null) {
      final value = tags['traffic_calming'].toString().replaceAll('_', ' ');
      return (
        RoadWarningType.speedBump,
        value.isEmpty ? 'Traffic calming' : 'Traffic calming: $value',
      );
    }
    return null;
  }

  RoadWarning? _warningFromWay(
    Map<String, dynamic> element,
    Map<String, dynamic> tags,
    List<_LatLon> geometry,
    List<RoutePoint> routePoints,
  ) {
    final mapped = _wayWarningText(tags);
    if (mapped == null) {
      return null;
    }

    final best = _bestGeometryMatch(geometry, routePoints);
    if (best == null ||
        best.match.distanceToRouteMeters > _wayMatchThresholdMeters) {
      return null;
    }

    return RoadWarning(
      id: 'osm-way-${element['id']}-${mapped.$1.name}',
      type: mapped.$1,
      lat: best.lat,
      lon: best.lon,
      distanceFromStart: best.match.distanceFromStart,
      text: mapped.$2,
      tags: tags,
    );
  }

  (RoadWarningType, String)? _wayWarningText(Map<String, dynamic> tags) {
    final surface = tags['surface']?.toString();
    if (surface != null && surface.isNotEmpty && surface != 'asphalt') {
      return (RoadWarningType.surfaceChange, 'Surface: $surface');
    }
    if (tags['tunnel'] == 'yes') {
      return (RoadWarningType.tunnel, 'Tunnel');
    }
    if (tags['bridge'] == 'yes') {
      return (RoadWarningType.bridge, 'Bridge');
    }
    if (tags['junction'] == 'roundabout' || tags['junction'] == 'circular') {
      return (RoadWarningType.roundabout, 'Roundabout');
    }
    return null;
  }

  SpeedLimitSegment? _speedLimitFromWay(
    Map<String, dynamic> element,
    Map<String, dynamic> tags,
    List<_LatLon> geometry,
    List<RoutePoint> routePoints,
  ) {
    if (geometry.length < 2) {
      return null;
    }

    final first = _bestGeometryMatch([geometry.first], routePoints);
    final last = _bestGeometryMatch([geometry.last], routePoints);
    if (first == null ||
        last == null ||
        first.match.distanceToRouteMeters > _wayMatchThresholdMeters ||
        last.match.distanceToRouteMeters > _wayMatchThresholdMeters) {
      return null;
    }

    final start = math.min(
      first.match.distanceFromStart,
      last.match.distanceFromStart,
    );
    final end = math.max(
      first.match.distanceFromStart,
      last.match.distanceFromStart,
    );
    if ((end - start).abs() < 15) {
      return null;
    }

    final rawMaxspeed = tags['maxspeed'].toString();
    return SpeedLimitSegment(
      id: 'osm-speed-${element['id']}',
      startDistance: start,
      endDistance: end,
      rawMaxspeed: rawMaxspeed,
      parsedKmh: parseMaxspeedKmh(rawMaxspeed),
      tags: tags,
    );
  }

  List<_LatLon> _geometryFromWay(Map<String, dynamic> element) {
    final geometry = element['geometry'] as List<dynamic>? ?? const [];
    return geometry
        .whereType<Map<String, dynamic>>()
        .map(
          (point) => _LatLon(
            lat: (point['lat'] as num).toDouble(),
            lon: (point['lon'] as num).toDouble(),
          ),
        )
        .toList();
  }

  _GeometryMatch? _bestGeometryMatch(
    List<_LatLon> geometry,
    List<RoutePoint> routePoints,
  ) {
    _GeometryMatch? best;
    for (final point in geometry) {
      final match = nearestRouteMatchForLatLon(
        point.lat,
        point.lon,
        routePoints,
      );
      if (best == null ||
          match.distanceToRouteMeters < best.match.distanceToRouteMeters) {
        best = _GeometryMatch(lat: point.lat, lon: point.lon, match: match);
      }
    }
    return best;
  }

  List<RoadWarning> _dedupeWarnings(List<RoadWarning> warnings) {
    final deduped = <RoadWarning>[];
    for (final warning in warnings) {
      final duplicate = deduped.any(
        (existing) =>
            existing.type == warning.type &&
            existing.text == warning.text &&
            (existing.distanceFromStart - warning.distanceFromStart).abs() < 20,
      );
      if (!duplicate) {
        deduped.add(warning);
      }
    }
    return deduped;
  }
}

RouteWarningMatch nearestRouteMatchForLatLon(
  double lat,
  double lon,
  List<RoutePoint> routePoints,
) {
  var nearestIndex = 0;
  var nearestDistance = double.infinity;
  for (var i = 0; i < routePoints.length; i++) {
    final point = routePoints[i];
    final distance = haversineDistanceMeters(lat, lon, point.lat, point.lon);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestIndex = i;
    }
  }

  return RouteWarningMatch(
    routeIndex: nearestIndex,
    distanceFromStart: routePoints[nearestIndex].distanceFromStart,
    distanceToRouteMeters: nearestDistance,
  );
}

int? parseMaxspeedKmh(String rawMaxspeed) {
  final normalized = rawMaxspeed.trim().toLowerCase();
  final numeric = RegExp(r'(\d+)').firstMatch(normalized);
  if (numeric == null) {
    return null;
  }

  final value = int.tryParse(numeric.group(1)!);
  if (value == null) {
    return null;
  }
  if (normalized.contains('mph')) {
    return (value * 1.60934).round();
  }
  return value;
}

class RouteWarningMatch {
  const RouteWarningMatch({
    required this.routeIndex,
    required this.distanceFromStart,
    required this.distanceToRouteMeters,
  });

  final int routeIndex;
  final double distanceFromStart;
  final double distanceToRouteMeters;
}

class OverpassException implements Exception {
  const OverpassException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _LatLon {
  const _LatLon({required this.lat, required this.lon});

  final double lat;
  final double lon;
}

class _GeometryMatch {
  const _GeometryMatch({
    required this.lat,
    required this.lon,
    required this.match,
  });

  final double lat;
  final double lon;
  final RouteWarningMatch match;
}
