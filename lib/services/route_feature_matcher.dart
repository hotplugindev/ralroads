import 'dart:math' as math;
import '../models/route_point.dart';
import '../models/matched_route.dart';
import '../utils/geo_math.dart';

class RouteFeatureMatch {
  final int nearestEdgeIndex;
  final double distanceFromRouteMeters;
  final double distanceFromStart;
  final double bearingDifferenceDegrees;
  final double overlapMeters;
  final double connectivityScore;
  final double directionScore;
  final double layerScore;
  final double confidence;
  final bool belongsToRoute;
  final String rejectionReason;

  RouteFeatureMatch({
    required this.nearestEdgeIndex,
    required this.distanceFromRouteMeters,
    required this.distanceFromStart,
    required this.bearingDifferenceDegrees,
    required this.overlapMeters,
    required this.connectivityScore,
    required this.directionScore,
    required this.layerScore,
    required this.confidence,
    required this.belongsToRoute,
    this.rejectionReason = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'nearestEdgeIndex': nearestEdgeIndex,
      'distanceFromRouteMeters': distanceFromRouteMeters,
      'distanceFromStart': distanceFromStart,
      'bearingDifferenceDegrees': bearingDifferenceDegrees,
      'overlapMeters': overlapMeters,
      'connectivityScore': connectivityScore,
      'directionScore': directionScore,
      'layerScore': layerScore,
      'confidence': confidence,
      'belongsToRoute': belongsToRoute,
      'rejectionReason': rejectionReason,
    };
  }
}

class ProjectionResult {
  final double perpendicularDistanceMeters;
  final double distanceFromStart;
  final int segmentStartIndex;
  final double fraction;
  final double lat;
  final double lon;

  ProjectionResult({
    required this.perpendicularDistanceMeters,
    required this.distanceFromStart,
    required this.segmentStartIndex,
    required this.fraction,
    required this.lat,
    required this.lon,
  });
}

class RouteFeatureMatcher {
  ProjectionResult projectPoint(
    double lat,
    double lon,
    List<RoutePoint> geometry,
  ) {
    if (geometry.isEmpty) {
      return ProjectionResult(
        perpendicularDistanceMeters: double.infinity,
        distanceFromStart: 0,
        segmentStartIndex: 0,
        fraction: 0,
        lat: 0,
        lon: 0,
      );
    }
    if (geometry.length == 1) {
      final d = haversineDistanceMeters(
        lat,
        lon,
        geometry.first.lat,
        geometry.first.lon,
      );
      return ProjectionResult(
        perpendicularDistanceMeters: d,
        distanceFromStart: geometry.first.distanceFromStart,
        segmentStartIndex: 0,
        fraction: 0,
        lat: geometry.first.lat,
        lon: geometry.first.lon,
      );
    }

    ProjectionResult? bestResult;

    for (var i = 0; i < geometry.length - 1; i++) {
      final p1 = geometry[i];
      final p2 = geometry[i + 1];

      final latAvgRad = degreesToRadians((p1.lat + p2.lat + lat) / 3.0);
      final cosLat = math.cos(latAvgRad);

      final px = lon * cosLat;
      final py = lat;
      final ax = p1.lon * cosLat;
      final ay = p1.lat;
      final bx = p2.lon * cosLat;
      final by = p2.lat;

      final dx = bx - ax;
      final dy = by - ay;
      final l2 = dx * dx + dy * dy;
      double t = 0.0;
      if (l2 > 0) {
        t = ((px - ax) * dx + (py - ay) * dy) / l2;
        t = t.clamp(0.0, 1.0);
      }

      final projLon = p1.lon + t * (p2.lon - p1.lon);
      final projLat = p1.lat + t * (p2.lat - p1.lat);
      final perp = haversineDistanceMeters(lat, lon, projLat, projLon);

      final distFromStart =
          p1.distanceFromStart +
          t * (p2.distanceFromStart - p1.distanceFromStart);

      if (bestResult == null || perp < bestResult.perpendicularDistanceMeters) {
        bestResult = ProjectionResult(
          perpendicularDistanceMeters: perp,
          distanceFromStart: distFromStart,
          segmentStartIndex: i,
          fraction: t,
          lat: projLat,
          lon: projLon,
        );
      }
    }

    return bestResult!;
  }

  RouteFeatureMatch matchPointFeature({
    required double lat,
    required double lon,
    required Map<String, dynamic> tags,
    required MatchedRoute route,
  }) {
    if (route.edges.isEmpty) {
      return RouteFeatureMatch(
        nearestEdgeIndex: -1,
        distanceFromRouteMeters: double.infinity,
        distanceFromStart: 0,
        bearingDifferenceDegrees: 0,
        overlapMeters: 0,
        connectivityScore: 0,
        directionScore: 1.0,
        layerScore: 1.0,
        confidence: 0.0,
        belongsToRoute: false,
        rejectionReason: 'Route has no edges',
      );
    }

    int bestEdgeIdx = -1;
    ProjectionResult? bestProj;

    for (var i = 0; i < route.edges.length; i++) {
      final edge = route.edges[i];
      final proj = projectPoint(lat, lon, edge.geometry);
      if (bestProj == null ||
          proj.perpendicularDistanceMeters <
              bestProj.perpendicularDistanceMeters) {
        bestProj = proj;
        bestEdgeIdx = i;
      }
    }

    if (bestEdgeIdx == -1 || bestProj == null) {
      return RouteFeatureMatch(
        nearestEdgeIndex: -1,
        distanceFromRouteMeters: double.infinity,
        distanceFromStart: 0,
        bearingDifferenceDegrees: 0,
        overlapMeters: 0,
        connectivityScore: 0,
        directionScore: 1.0,
        layerScore: 1.0,
        confidence: 0.0,
        belongsToRoute: false,
        rejectionReason: 'Projection failed',
      );
    }

    final edge = route.edges[bestEdgeIdx];
    final distM = bestProj.perpendicularDistanceMeters;

    if (distM > 25.0) {
      return RouteFeatureMatch(
        nearestEdgeIndex: bestEdgeIdx,
        distanceFromRouteMeters: distM,
        distanceFromStart: bestProj.distanceFromStart,
        bearingDifferenceDegrees: 0,
        overlapMeters: 0,
        connectivityScore: 0.0,
        directionScore: 1.0,
        layerScore: 1.0,
        confidence: 0.0,
        belongsToRoute: false,
        rejectionReason:
            'Distance to route is ${distM.toStringAsFixed(1)} meters (limit 25m)',
      );
    }

    double layerScore = 1.0;
    String rejectionReason = '';
    int edgeLayer = edge.layer ?? 0;
    int featureLayer = 0;
    if (tags['layer'] != null) {
      featureLayer = int.tryParse(tags['layer'].toString()) ?? 0;
    }
    if (edgeLayer != featureLayer) {
      layerScore = 0.0;
      rejectionReason =
          'Layer mismatch: edge=$edgeLayer, feature=$featureLayer';
    }

    bool featureIsBridge = tags['bridge'] == 'yes';
    bool featureIsTunnel = tags['tunnel'] == 'yes';
    if (featureIsBridge && !edge.isBridge) {
      layerScore = 0.0;
      rejectionReason = 'Bridge mismatch: feature is bridge, edge is not';
    }
    if (featureIsTunnel && !edge.isTunnel) {
      layerScore = 0.0;
      rejectionReason = 'Tunnel mismatch: feature is tunnel, edge is not';
    }

    double directionScore = 1.0;
    double bearingDiff = 0.0;
    final dirValue =
        tags['direction'] ??
        tags['camera:direction'] ??
        tags['camera:bearing'] ??
        tags['bearing'] ??
        tags['traffic_signals:direction'];
    if (dirValue != null) {
      double? featureBearing = double.tryParse(dirValue.toString());
      if (featureBearing == null) {
        final str = dirValue.toString().toLowerCase();
        if (str == 'n') {
          featureBearing = 0;
        } else if (str == 'ne') {
          featureBearing = 45;
        } else if (str == 'e') {
          featureBearing = 90;
        } else if (str == 'se') {
          featureBearing = 135;
        } else if (str == 's') {
          featureBearing = 180;
        } else if (str == 'sw') {
          featureBearing = 225;
        } else if (str == 'w') {
          featureBearing = 270;
        } else if (str == 'nw') {
          featureBearing = 315;
        }
      }
      if (featureBearing != null) {
        bearingDiff = normalizeAngleDeltaDegrees(
          edge.forwardBearing,
          featureBearing,
        ).abs();
        if (bearingDiff > 45.0) {
          directionScore = 0.0;
          rejectionReason =
              'Bearing difference is ${bearingDiff.toStringAsFixed(1)} degrees (limit 45)';
        }
      }
    }

    double connectivityScore = 1.0;
    if (tags['ways'] != null) {
      final waysList = tags['ways'] as List<dynamic>?;
      if (waysList != null && waysList.isNotEmpty) {
        final traversedWayIds = route.edges.map((e) => e.osmWayId).toSet();
        final sharesWay = waysList.any(
          (w) => traversedWayIds.contains(w.toString()),
        );
        if (!sharesWay) {
          connectivityScore = 0.0;
          rejectionReason = 'Feature belongs only to side ways: $waysList';
        }
      }
    } else if (tags['way_id'] != null) {
      final wayId = tags['way_id'].toString();
      final traversedWayIds = route.edges.map((e) => e.osmWayId).toSet();
      if (!traversedWayIds.contains(wayId)) {
        connectivityScore = 0.0;
        rejectionReason = 'Feature belongs to side way: $wayId';
      }
    }

    final confidence = layerScore * directionScore * connectivityScore;
    final belongs = confidence > 0.5;

    return RouteFeatureMatch(
      nearestEdgeIndex: bestEdgeIdx,
      distanceFromRouteMeters: distM,
      distanceFromStart: bestProj.distanceFromStart,
      bearingDifferenceDegrees: bearingDiff,
      overlapMeters: 0,
      connectivityScore: connectivityScore,
      directionScore: directionScore,
      layerScore: layerScore,
      confidence: confidence,
      belongsToRoute: belongs,
      rejectionReason: belongs ? '' : rejectionReason,
    );
  }

  RouteFeatureMatch matchLineFeature({
    required List<RoutePoint> wayGeometry,
    required Map<String, dynamic> tags,
    required MatchedRoute route,
  }) {
    if (route.edges.isEmpty || wayGeometry.isEmpty) {
      return RouteFeatureMatch(
        nearestEdgeIndex: -1,
        distanceFromRouteMeters: double.infinity,
        distanceFromStart: 0,
        bearingDifferenceDegrees: 0,
        overlapMeters: 0,
        connectivityScore: 0,
        directionScore: 1.0,
        layerScore: 1.0,
        confidence: 0.0,
        belongsToRoute: false,
        rejectionReason: 'Route or feature geometry is empty',
      );
    }

    final wayId = tags['way_id'] ?? tags['id'];
    if (wayId != null) {
      final matchingEdges = route.edges
          .where((e) => e.osmWayId == wayId.toString())
          .toList();
      if (matchingEdges.isNotEmpty) {
        double totalLen = 0.0;
        for (final edge in matchingEdges) {
          totalLen += edge.endDistance - edge.startDistance;
        }
        return RouteFeatureMatch(
          nearestEdgeIndex: matchingEdges.first.index,
          distanceFromRouteMeters: 0.0,
          distanceFromStart: matchingEdges.first.startDistance,
          bearingDifferenceDegrees: 0.0,
          overlapMeters: totalLen,
          connectivityScore: 1.0,
          directionScore: 1.0,
          layerScore: 1.0,
          confidence: 1.0,
          belongsToRoute: true,
        );
      }
    }

    double overlapLen = 0.0;
    double minPerp = double.infinity;
    double bestStartDist = 0.0;
    int bestEdgeIdx = -1;

    for (final p in wayGeometry) {
      int edgeIdx = -1;
      ProjectionResult? bestProj;
      for (var i = 0; i < route.edges.length; i++) {
        final edge = route.edges[i];
        final proj = projectPoint(p.lat, p.lon, edge.geometry);
        if (bestProj == null ||
            proj.perpendicularDistanceMeters <
                bestProj.perpendicularDistanceMeters) {
          bestProj = proj;
          edgeIdx = i;
        }
      }

      if (bestProj != null && bestProj.perpendicularDistanceMeters <= 15.0) {
        if (bestProj.perpendicularDistanceMeters < minPerp) {
          minPerp = bestProj.perpendicularDistanceMeters;
          bestStartDist = bestProj.distanceFromStart;
          bestEdgeIdx = edgeIdx;
        }
        overlapLen += 10.0;
      }
    }

    if (bestEdgeIdx == -1 || overlapLen < 15.0) {
      return RouteFeatureMatch(
        nearestEdgeIndex: bestEdgeIdx,
        distanceFromRouteMeters: minPerp,
        distanceFromStart: bestStartDist,
        bearingDifferenceDegrees: 0.0,
        overlapMeters: overlapLen,
        connectivityScore: 0.0,
        directionScore: 1.0,
        layerScore: 1.0,
        confidence: 0.0,
        belongsToRoute: false,
        rejectionReason:
            'Geometry overlap too small (${overlapLen.toStringAsFixed(1)} meters, limit 15m)',
      );
    }

    return RouteFeatureMatch(
      nearestEdgeIndex: bestEdgeIdx,
      distanceFromRouteMeters: minPerp,
      distanceFromStart: bestStartDist,
      bearingDifferenceDegrees: 0.0,
      overlapMeters: overlapLen,
      connectivityScore: 0.8,
      directionScore: 1.0,
      layerScore: 1.0,
      confidence: 0.8,
      belongsToRoute: true,
    );
  }
}
