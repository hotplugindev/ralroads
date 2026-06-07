import 'route_point.dart';
import 'pace_note.dart';
import 'road_warning.dart';
import 'speed_limit_segment.dart';

enum RouteManeuverType {
  continueStraight,
  turnLeft,
  turnRight,
  slightLeft,
  slightRight,
  sharpLeft,
  sharpRight,
  keepLeft,
  keepRight,
  fork,
  merge,
  enterRoundabout,
  exitRoundabout,
  uTurn,
  arrive,
}

enum RouteChunkStatus { pending, processing, ready, partial, failed }

enum RoadSectorType {
  straight,
  leftCurve,
  rightCurve,
  hairpinLeft,
  hairpinRight,
  roundabout,
  junction,
  fork,
  merge,
  crest,
  dip,
  surfaceChange,
  hazard,
}

class ConnectedRoad {
  final String? osmWayId;
  final String? name;
  final String? ref;
  final double bearing;
  final bool isTraversed;
  final Map<String, dynamic> tags;

  ConnectedRoad({
    this.osmWayId,
    this.name,
    this.ref,
    required this.bearing,
    required this.isTraversed,
    required this.tags,
  });

  Map<String, dynamic> toJson() {
    return {
      'osmWayId': osmWayId,
      'name': name,
      'ref': ref,
      'bearing': bearing,
      'isTraversed': isTraversed,
      'tags': tags,
    };
  }

  factory ConnectedRoad.fromJson(Map<dynamic, dynamic> json) {
    return ConnectedRoad(
      osmWayId: json['osmWayId'] as String?,
      name: json['name'] as String?,
      ref: json['ref'] as String?,
      bearing: (json['bearing'] as num).toDouble(),
      isTraversed: json['isTraversed'] as bool? ?? false,
      tags: Map<String, dynamic>.from(json['tags'] as Map? ?? const {}),
    );
  }
}

class MatchedRouteEdge {
  final String id;
  final int index;
  final String? osmWayId;
  final String? roadName;
  final String? roadRef;
  final String? roadClass;
  final double startDistance;
  final double endDistance;
  final List<RoutePoint> geometry;
  final double forwardBearing;
  final int? speedLimitKmh;
  final String? rawSpeedLimit;
  final String? surface;
  final int? layer;
  final bool isBridge;
  final bool isTunnel;
  final bool isRoundabout;
  final bool isOneWay;
  final Map<String, dynamic> tags;

  MatchedRouteEdge({
    required this.id,
    required this.index,
    this.osmWayId,
    this.roadName,
    this.roadRef,
    this.roadClass,
    required this.startDistance,
    required this.endDistance,
    required this.geometry,
    required this.forwardBearing,
    this.speedLimitKmh,
    this.rawSpeedLimit,
    this.surface,
    this.layer,
    this.isBridge = false,
    this.isTunnel = false,
    this.isRoundabout = false,
    this.isOneWay = false,
    this.tags = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'index': index,
      'osmWayId': osmWayId,
      'roadName': roadName,
      'roadRef': roadRef,
      'roadClass': roadClass,
      'startDistance': startDistance,
      'endDistance': endDistance,
      'geometry': geometry.map((p) => p.toJson()).toList(),
      'forwardBearing': forwardBearing,
      'speedLimitKmh': speedLimitKmh,
      'rawSpeedLimit': rawSpeedLimit,
      'surface': surface,
      'layer': layer,
      'isBridge': isBridge,
      'isTunnel': isTunnel,
      'isRoundabout': isRoundabout,
      'isOneWay': isOneWay,
      'tags': tags,
    };
  }

  factory MatchedRouteEdge.fromJson(Map<dynamic, dynamic> json) {
    return MatchedRouteEdge(
      id: json['id'] as String,
      index: (json['index'] as num).toInt(),
      osmWayId: json['osmWayId'] as String?,
      roadName: json['roadName'] as String?,
      roadRef: json['roadRef'] as String?,
      roadClass: json['roadClass'] as String?,
      startDistance: (json['startDistance'] as num).toDouble(),
      endDistance: (json['endDistance'] as num).toDouble(),
      geometry: (json['geometry'] as List)
          .map((p) => RoutePoint.fromJson(p as Map))
          .toList(),
      forwardBearing: (json['forwardBearing'] as num).toDouble(),
      speedLimitKmh: json['speedLimitKmh'] != null
          ? (json['speedLimitKmh'] as num).toInt()
          : null,
      rawSpeedLimit: json['rawSpeedLimit'] as String?,
      surface: json['surface'] as String?,
      layer: json['layer'] != null ? (json['layer'] as num).toInt() : null,
      isBridge: json['isBridge'] as bool? ?? false,
      isTunnel: json['isTunnel'] as bool? ?? false,
      isRoundabout: json['isRoundabout'] as bool? ?? false,
      isOneWay: json['isOneWay'] as bool? ?? false,
      tags: Map<String, dynamic>.from(json['tags'] as Map? ?? const {}),
    );
  }
}

class RouteManeuver {
  final String id;
  final RouteManeuverType type;
  final double distanceFromStart;
  final int fromEdgeIndex;
  final int toEdgeIndex;
  final String? instruction;
  final int? roundaboutExit;
  final double confidence;

  RouteManeuver({
    required this.id,
    required this.type,
    required this.distanceFromStart,
    required this.fromEdgeIndex,
    required this.toEdgeIndex,
    this.instruction,
    this.roundaboutExit,
    this.confidence = 1.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'distanceFromStart': distanceFromStart,
      'fromEdgeIndex': fromEdgeIndex,
      'toEdgeIndex': toEdgeIndex,
      'instruction': instruction,
      'roundaboutExit': roundaboutExit,
      'confidence': confidence,
    };
  }

  factory RouteManeuver.fromJson(Map<dynamic, dynamic> json) {
    final typeName =
        json['type'] as String? ?? RouteManeuverType.continueStraight.name;
    return RouteManeuver(
      id: json['id'] as String,
      type: RouteManeuverType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => RouteManeuverType.continueStraight,
      ),
      distanceFromStart: (json['distanceFromStart'] as num).toDouble(),
      fromEdgeIndex: (json['fromEdgeIndex'] as num).toInt(),
      toEdgeIndex: (json['toEdgeIndex'] as num).toInt(),
      instruction: json['instruction'] as String?,
      roundaboutExit: json['roundaboutExit'] != null
          ? (json['roundaboutExit'] as num).toInt()
          : null,
      confidence: (json['confidence'] as num? ?? 1.0).toDouble(),
    );
  }
}

class RouteIntersection {
  final String id;
  final double distanceFromStart;
  final double lat;
  final double lon;
  final List<ConnectedRoad> connectedRoads;
  final int traversedIncomingEdgeIndex;
  final int traversedOutgoingEdgeIndex;

  RouteIntersection({
    required this.id,
    required this.distanceFromStart,
    required this.lat,
    required this.lon,
    required this.connectedRoads,
    required this.traversedIncomingEdgeIndex,
    required this.traversedOutgoingEdgeIndex,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'distanceFromStart': distanceFromStart,
      'lat': lat,
      'lon': lon,
      'connectedRoads': connectedRoads.map((c) => c.toJson()).toList(),
      'traversedIncomingEdgeIndex': traversedIncomingEdgeIndex,
      'traversedOutgoingEdgeIndex': traversedOutgoingEdgeIndex,
    };
  }

  factory RouteIntersection.fromJson(Map<dynamic, dynamic> json) {
    return RouteIntersection(
      id: json['id'] as String,
      distanceFromStart: (json['distanceFromStart'] as num).toDouble(),
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      connectedRoads: (json['connectedRoads'] as List)
          .map((c) => ConnectedRoad.fromJson(c as Map))
          .toList(),
      traversedIncomingEdgeIndex: (json['traversedIncomingEdgeIndex'] as num)
          .toInt(),
      traversedOutgoingEdgeIndex: (json['traversedOutgoingEdgeIndex'] as num)
          .toInt(),
    );
  }
}

class RoadSector {
  final String id;
  final RoadSectorType type;
  final double startDistance;
  final double endDistance;
  final double lengthMeters;
  final double totalHeadingChange;
  final double averageCurvature;
  final double peakCurvature;
  final double? approximateRadiusMeters;
  final int? severity;
  final int? gripSpeedKmh;
  final double confidence;
  final List<String> modifiers;
  final List<int> matchedEdgeIndexes;
  final Map<String, dynamic> context;

  RoadSector({
    required this.id,
    required this.type,
    required this.startDistance,
    required this.endDistance,
    required this.lengthMeters,
    required this.totalHeadingChange,
    required this.averageCurvature,
    required this.peakCurvature,
    this.approximateRadiusMeters,
    this.severity,
    this.gripSpeedKmh,
    required this.confidence,
    this.modifiers = const [],
    this.matchedEdgeIndexes = const [],
    this.context = const {},
  });

  double get length => endDistance - startDistance;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'startDistance': startDistance,
      'endDistance': endDistance,
      'lengthMeters': lengthMeters,
      'totalHeadingChange': totalHeadingChange,
      'averageCurvature': averageCurvature,
      'peakCurvature': peakCurvature,
      'approximateRadiusMeters': approximateRadiusMeters,
      'severity': severity,
      'gripSpeedKmh': gripSpeedKmh,
      'confidence': confidence,
      'modifiers': modifiers,
      'matchedEdgeIndexes': matchedEdgeIndexes,
      'context': context,
    };
  }

  factory RoadSector.fromJson(Map<dynamic, dynamic> json) {
    final typeName = json['type'] as String? ?? RoadSectorType.straight.name;
    return RoadSector(
      id: json['id'] as String? ?? '',
      type: RoadSectorType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => RoadSectorType.straight,
      ),
      startDistance: (json['startDistance'] as num).toDouble(),
      endDistance: (json['endDistance'] as num).toDouble(),
      lengthMeters: (json['lengthMeters'] as num).toDouble(),
      totalHeadingChange: (json['totalHeadingChange'] as num? ?? 0.0)
          .toDouble(),
      averageCurvature: (json['averageCurvature'] as num).toDouble(),
      peakCurvature: (json['peakCurvature'] as num).toDouble(),
      approximateRadiusMeters: json['approximateRadiusMeters'] != null
          ? (json['approximateRadiusMeters'] as num).toDouble()
          : null,
      severity: json['severity'] != null
          ? (json['severity'] as num).toInt()
          : null,
      gripSpeedKmh: json['gripSpeedKmh'] != null
          ? (json['gripSpeedKmh'] as num).toInt()
          : null,
      confidence: (json['confidence'] as num).toDouble(),
      modifiers: List<String>.from(json['modifiers'] as List? ?? const []),
      matchedEdgeIndexes: List<int>.from(
        json['matchedEdgeIndexes'] as List? ?? const [],
      ),
      context: Map<String, dynamic>.from(json['context'] as Map? ?? const {}),
    );
  }
}

class RouteChunk {
  final String id;
  final int index;
  final double startDistance;
  final double endDistance;
  final List<RoutePoint> rawGeometry;
  final List<RoutePoint> displayGeometry;
  final RouteChunkStatus status;
  final List<RoadSector> sectors;
  final List<RoadWarning> warnings;
  final List<PaceNote> notes;
  final List<SpeedLimitSegment> speedLimits;
  final String? error;

  RouteChunk({
    required this.id,
    required this.index,
    required this.startDistance,
    required this.endDistance,
    required this.rawGeometry,
    required this.displayGeometry,
    required this.status,
    this.sectors = const [],
    this.warnings = const [],
    this.notes = const [],
    this.speedLimits = const [],
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'index': index,
      'startDistance': startDistance,
      'endDistance': endDistance,
      'rawGeometry': rawGeometry.map((p) => p.toJson()).toList(),
      'displayGeometry': displayGeometry.map((p) => p.toJson()).toList(),
      'status': status.name,
      'sectors': sectors.map((s) => s.toJson()).toList(),
      'warnings': warnings.map((w) => w.toJson()).toList(),
      'notes': notes.map((n) => n.toJson()).toList(),
      'speedLimits': speedLimits.map((s) => s.toJson()).toList(),
      'error': error,
    };
  }

  factory RouteChunk.fromJson(Map<dynamic, dynamic> json) {
    final statusName =
        json['status'] as String? ?? RouteChunkStatus.pending.name;
    return RouteChunk(
      id: json['id'] as String,
      index: (json['index'] as num).toInt(),
      startDistance: (json['startDistance'] as num).toDouble(),
      endDistance: (json['endDistance'] as num).toDouble(),
      rawGeometry: (json['rawGeometry'] as List)
          .map((p) => RoutePoint.fromJson(p as Map))
          .toList(),
      displayGeometry: (json['displayGeometry'] as List)
          .map((p) => RoutePoint.fromJson(p as Map))
          .toList(),
      status: RouteChunkStatus.values.firstWhere(
        (e) => e.name == statusName,
        orElse: () => RouteChunkStatus.pending,
      ),
      sectors: (json['sectors'] as List? ?? const [])
          .map((s) => RoadSector.fromJson(s as Map))
          .toList(),
      warnings: (json['warnings'] as List? ?? const [])
          .map((w) => RoadWarning.fromJson(w as Map))
          .toList(),
      notes: (json['notes'] as List? ?? const [])
          .map((n) => PaceNote.fromJson(n as Map))
          .toList(),
      speedLimits: (json['speedLimits'] as List? ?? const [])
          .map((s) => SpeedLimitSegment.fromJson(s as Map))
          .toList(),
      error: json['error'] as String?,
    );
  }
}

class RouteAnalysisManifest {
  final int totalChunks;
  final int readyChunks;
  final int partialChunks;
  final int failedChunks;
  final DateTime lastUpdated;
  final bool isComplete;

  RouteAnalysisManifest({
    required this.totalChunks,
    required this.readyChunks,
    required this.partialChunks,
    required this.failedChunks,
    required this.lastUpdated,
    required this.isComplete,
  });

  Map<String, dynamic> toJson() {
    return {
      'totalChunks': totalChunks,
      'readyChunks': readyChunks,
      'partialChunks': partialChunks,
      'failedChunks': failedChunks,
      'lastUpdated': lastUpdated.toIso8601String(),
      'isComplete': isComplete,
    };
  }

  factory RouteAnalysisManifest.fromJson(Map<dynamic, dynamic> json) {
    return RouteAnalysisManifest(
      totalChunks: (json['totalChunks'] as num).toInt(),
      readyChunks: (json['readyChunks'] as num).toInt(),
      partialChunks: (json['partialChunks'] as num).toInt(),
      failedChunks: (json['failedChunks'] as num).toInt(),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      isComplete: json['isComplete'] as bool? ?? false,
    );
  }
}

class RouteEventScore {
  final double routeMembership;
  final double classificationConfidence;
  final double drivingRelevance;
  final double severity;
  final double urgency;
  final double novelty;
  final double speechValue;
  final double finalScore;

  RouteEventScore({
    required this.routeMembership,
    required this.classificationConfidence,
    required this.drivingRelevance,
    required this.severity,
    required this.urgency,
    required this.novelty,
    required this.speechValue,
    required this.finalScore,
  });

  Map<String, dynamic> toJson() {
    return {
      'routeMembership': routeMembership,
      'classificationConfidence': classificationConfidence,
      'drivingRelevance': drivingRelevance,
      'severity': severity,
      'urgency': urgency,
      'novelty': novelty,
      'speechValue': speechValue,
      'finalScore': finalScore,
    };
  }

  factory RouteEventScore.fromJson(Map<dynamic, dynamic> json) {
    return RouteEventScore(
      routeMembership: (json['routeMembership'] as num).toDouble(),
      classificationConfidence: (json['classificationConfidence'] as num)
          .toDouble(),
      drivingRelevance: (json['drivingRelevance'] as num).toDouble(),
      severity: (json['severity'] as num).toDouble(),
      urgency: (json['urgency'] as num).toDouble(),
      novelty: (json['novelty'] as num? ?? 0.0).toDouble(),
      speechValue: (json['speechValue'] as num).toDouble(),
      finalScore: (json['finalScore'] as num).toDouble(),
    );
  }
}

class MatchedRoute {
  final String id;
  final List<MatchedRouteEdge> edges;
  final List<RouteManeuver> maneuvers;
  final List<RouteIntersection> intersections;
  final List<RouteChunk> chunks;
  final double totalDistanceMeters;
  final RouteAnalysisManifest analysisManifest;

  MatchedRoute({
    required this.id,
    required this.edges,
    required this.maneuvers,
    required this.intersections,
    required this.chunks,
    required this.totalDistanceMeters,
    required this.analysisManifest,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'edges': edges.map((e) => e.toJson()).toList(),
      'maneuvers': maneuvers.map((m) => m.toJson()).toList(),
      'intersections': intersections.map((i) => i.toJson()).toList(),
      'chunks': chunks.map((c) => c.toJson()).toList(),
      'totalDistanceMeters': totalDistanceMeters,
      'analysisManifest': analysisManifest.toJson(),
    };
  }

  factory MatchedRoute.fromJson(Map<dynamic, dynamic> json) {
    return MatchedRoute(
      id: json['id'] as String,
      edges: (json['edges'] as List)
          .map((e) => MatchedRouteEdge.fromJson(e as Map))
          .toList(),
      maneuvers: (json['maneuvers'] as List)
          .map((m) => RouteManeuver.fromJson(m as Map))
          .toList(),
      intersections: (json['intersections'] as List)
          .map((i) => RouteIntersection.fromJson(i as Map))
          .toList(),
      chunks: (json['chunks'] as List)
          .map((c) => RouteChunk.fromJson(c as Map))
          .toList(),
      totalDistanceMeters: (json['totalDistanceMeters'] as num).toDouble(),
      analysisManifest: RouteAnalysisManifest.fromJson(
        json['analysisManifest'] as Map,
      ),
    );
  }
}
