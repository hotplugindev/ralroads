import 'dart:math' as math;

import '../models/matched_route.dart';
import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../utils/geo_math.dart';
import 'settings_service.dart';

typedef SemanticRouteSector = RoadSector;

enum SemanticClassification {
  straight,
  leftCurve,
  rightCurve,
  hairpinLeft,
  hairpinRight,
  junctionLeft,
  junctionRight,
  junctionStraight,
  forkLeft,
  forkRight,
  merge,
  roundabout,
  uTurn,
  unknownManeuver,
  genericManeuver,
}

class RoadContinuationAnalysis {
  const RoadContinuationAnalysis({
    required this.incomingEdgeIndex,
    required this.outgoingEdgeIndex,
    this.naturalContinuationEdgeIndex,
    required this.geometricScore,
    required this.nameScore,
    required this.refScore,
    required this.classScore,
    required this.topologyScore,
    required this.overallScore,
    required this.followsNaturalContinuation,
  });

  final int incomingEdgeIndex;
  final int outgoingEdgeIndex;
  final int? naturalContinuationEdgeIndex;
  final double geometricScore;
  final double nameScore;
  final double refScore;
  final double classScore;
  final double topologyScore;
  final double overallScore;
  final bool followsNaturalContinuation;

  Map<String, dynamic> toJson() {
    return {
      'incomingEdgeIndex': incomingEdgeIndex,
      'outgoingEdgeIndex': outgoingEdgeIndex,
      'naturalContinuationEdgeIndex': naturalContinuationEdgeIndex,
      'geometricScore': geometricScore,
      'nameScore': nameScore,
      'refScore': refScore,
      'classScore': classScore,
      'topologyScore': topologyScore,
      'overallScore': overallScore,
      'followsNaturalContinuation': followsNaturalContinuation,
    };
  }
}

class IntersectionTopology {
  const IntersectionTopology({
    required this.routeDistance,
    required this.incomingEdgeIndex,
    required this.outgoingEdgeIndex,
    required this.connectedRoads,
    this.naturalContinuationEdgeIndex,
    required this.followsNaturalContinuation,
    required this.routeTurnAngle,
    required this.isGradeSeparated,
    required this.confidence,
  });

  final double routeDistance;
  final int incomingEdgeIndex;
  final int outgoingEdgeIndex;
  final List<ConnectedRoad> connectedRoads;
  final int? naturalContinuationEdgeIndex;
  final bool followsNaturalContinuation;
  final double routeTurnAngle;
  final bool isGradeSeparated;
  final double confidence;

  Map<String, dynamic> toJson() {
    return {
      'routeDistance': routeDistance,
      'incomingEdgeIndex': incomingEdgeIndex,
      'outgoingEdgeIndex': outgoingEdgeIndex,
      'naturalContinuationEdgeIndex': naturalContinuationEdgeIndex,
      'followsNaturalContinuation': followsNaturalContinuation,
      'routeTurnAngle': routeTurnAngle,
      'isGradeSeparated': isGradeSeparated,
      'confidence': confidence,
      'sideRoadCount': connectedRoads.where((road) => !road.isTraversed).length,
    };
  }
}

class SemanticScorecard {
  const SemanticScorecard({
    this.ordinaryCurveScore = 0.0,
    this.hairpinScore = 0.0,
    this.junctionScore = 0.0,
    this.roundaboutScore = 0.0,
  });

  final double ordinaryCurveScore;
  final double hairpinScore;
  final double junctionScore;
  final double roundaboutScore;

  Map<String, dynamic> toJson() {
    return {
      'ordinaryCurveScore': ordinaryCurveScore,
      'hairpinScore': hairpinScore,
      'junctionScore': junctionScore,
      'roundaboutScore': roundaboutScore,
    };
  }
}

class RouteSemanticNode {
  const RouteSemanticNode({
    required this.id,
    required this.routeDistance,
    required this.startDistance,
    required this.endDistance,
    required this.classification,
    required this.confidence,
    required this.displayText,
    required this.speechText,
    this.severity,
    this.speedKmh,
    this.diagnostics = const {},
  });

  final String id;
  final double routeDistance;
  final double startDistance;
  final double endDistance;
  final SemanticClassification classification;
  final double confidence;
  final String displayText;
  final String speechText;
  final int? severity;
  final int? speedKmh;
  final Map<String, dynamic> diagnostics;
}

class RouteAnalysisConfig {
  const RouteAnalysisConfig({
    this.style = PacenoteStyle.balanced,
    this.roundaboutWindowMeters = 80.0,
    this.junctionWindowMeters = 35.0,
    this.minimumSpecificConfidence = 0.72,
  });

  final PacenoteStyle style;
  final double roundaboutWindowMeters;
  final double junctionWindowMeters;
  final double minimumSpecificConfidence;
}

class MatchedRoadFeature {
  const MatchedRoadFeature({
    required this.id,
    required this.type,
    required this.distanceFromStart,
    this.startDistance,
    this.endDistance,
    this.confidence = 1.0,
    this.tags = const {},
  });

  final String id;
  final String type;
  final double distanceFromStart;
  final double? startDistance;
  final double? endDistance;
  final double confidence;
  final Map<String, dynamic> tags;
}

class SemanticCandidate {
  const SemanticCandidate({
    required this.id,
    required this.classification,
    required this.distanceFromStart,
    required this.startDistance,
    required this.endDistance,
    required this.confidence,
    this.direction,
    this.sourceId,
    this.evidence = const [],
    this.contradictingEvidence = const [],
    this.matchedEdgeIndexes = const [],
    this.topologyContext = const {},
    this.geometryContext = const {},
    this.scores = const SemanticScorecard(),
  });

  final String id;
  final SemanticClassification classification;
  final double distanceFromStart;
  final double startDistance;
  final double endDistance;
  final double confidence;
  final String? direction;
  final String? sourceId;
  final List<String> evidence;
  final List<String> contradictingEvidence;
  final List<int> matchedEdgeIndexes;
  final Map<String, dynamic> topologyContext;
  final Map<String, dynamic> geometryContext;
  final SemanticScorecard scores;

  bool overlaps(double start, double end) {
    return startDistance <= end && endDistance >= start;
  }
}

class RejectedClassification {
  const RejectedClassification({
    required this.id,
    required this.classification,
    required this.distanceFromStart,
    required this.reason,
    required this.confidence,
  });

  final String id;
  final SemanticClassification classification;
  final double distanceFromStart;
  final String reason;
  final double confidence;
}

class RouteAnalysisDiagnostics {
  const RouteAnalysisDiagnostics({
    required this.inputNotes,
    required this.inputWarnings,
    required this.acceptedCandidates,
    required this.rejectedCandidates,
    required this.insertedNotes,
    required this.convertedNotes,
    required this.downgradedHairpins,
  });

  final int inputNotes;
  final int inputWarnings;
  final int acceptedCandidates;
  final int rejectedCandidates;
  final int insertedNotes;
  final int convertedNotes;
  final int downgradedHairpins;
}

class RouteSemanticAnalysis {
  const RouteSemanticAnalysis({
    required this.sectors,
    required this.nodes,
    required this.pacenotes,
    required this.rejectedCandidates,
    required this.diagnostics,
  });

  final List<SemanticRouteSector> sectors;
  final List<RouteSemanticNode> nodes;
  final List<PaceNote> pacenotes;
  final List<RejectedClassification> rejectedCandidates;
  final RouteAnalysisDiagnostics diagnostics;
}

class RouteSemanticEngine {
  const RouteSemanticEngine();

  Future<RouteSemanticAnalysis> analyze({
    required MatchedRoute route,
    required List<RoutePoint> normalizedGeometry,
    required List<RouteManeuver> maneuvers,
    required List<RouteIntersection> intersections,
    required List<MatchedRoadFeature> roadFeatures,
    required RouteAnalysisConfig config,
  }) async {
    final warnings = roadFeatures
        .map(
          (feature) => RoadWarning(
            id: feature.id,
            type: feature.type == 'roundabout'
                ? RoadWarningType.roundabout
                : RoadWarningType.speedBump,
            lat: 0,
            lon: 0,
            distanceFromStart: feature.distanceFromStart,
            text: feature.type,
            tags: {
              ...feature.tags,
              'semantic_confidence': feature.confidence,
              if (feature.startDistance != null)
                'route_membership_start': feature.startDistance,
              if (feature.endDistance != null)
                'route_membership_end': feature.endDistance,
            },
          ),
        )
        .toList();

    return analyzePacenotes(
      notes: const [],
      routePoints: normalizedGeometry,
      warnings: warnings,
      speedLimits: const [],
      route: route,
      maneuvers: maneuvers,
      intersections: intersections,
      config: config,
    );
  }

  RouteSemanticAnalysis analyzePacenotes({
    required List<PaceNote> notes,
    required List<RoutePoint> routePoints,
    required List<RoadWarning> warnings,
    required List<SpeedLimitSegment> speedLimits,
    MatchedRoute? route,
    List<RouteManeuver> maneuvers = const [],
    List<RouteIntersection> intersections = const [],
    RouteAnalysisConfig config = const RouteAnalysisConfig(),
  }) {
    final rejected = <RejectedClassification>[];
    final accepted = <SemanticCandidate>[];

    for (final warning in warnings) {
      if (warning.type == RoadWarningType.roundabout) {
        final candidate = _roundaboutCandidate(warning, route, config);
        if (candidate.confidence >= config.minimumSpecificConfidence) {
          accepted.add(candidate);
        } else {
          rejected.add(
            RejectedClassification(
              id: 'reject-${warning.id}',
              classification: SemanticClassification.roundabout,
              distanceFromStart: warning.distanceFromStart,
              reason: 'Roundabout warning lacks traversed-route evidence',
              confidence: candidate.confidence,
            ),
          );
        }
      } else if (_isJunctionWarning(warning.type)) {
        rejected.add(
          RejectedClassification(
            id: 'reject-${warning.id}',
            classification: SemanticClassification.genericManeuver,
            distanceFromStart: warning.distanceFromStart,
            reason: 'Warning-only junction evidence is kept as a road warning',
            confidence: 0.25,
          ),
        );
      }
    }

    accepted.addAll(_maneuverCandidates(maneuvers, intersections, config));
    accepted.sort((a, b) {
      final priority = _priority(
        b.classification,
      ).compareTo(_priority(a.classification));
      if (priority != 0) return priority;
      return b.confidence.compareTo(a.confidence);
    });

    final suppressedNoteIds = <String>{};
    final replacements = <String, PaceNote>{};
    final inserted = <PaceNote>[];
    var convertedNotes = 0;

    for (final candidate in accepted) {
      if (candidate.classification == SemanticClassification.roundabout) {
        final note = _nearestConvertibleNote(
          notes,
          candidate.distanceFromStart,
          config.roundaboutWindowMeters,
          suppressedNoteIds,
        );
        final roundaboutNote = _roundaboutNote(
          candidate,
          routePoints,
          fallback: note,
        );
        if (note == null) {
          inserted.add(roundaboutNote);
        } else {
          replacements[note.id] = roundaboutNote.copyWith(
            id: '${note.id}-roundabout',
          );
          suppressedNoteIds.add(note.id);
          convertedNotes++;
        }

        for (final other in notes) {
          if (note != null && other.id == note.id) {
            continue;
          }
          final start = other.startDistance ?? other.distanceFromStart;
          final end = other.endDistance ?? other.distanceFromStart;
          if (candidate.overlaps(start, end) ||
              (other.distanceFromStart - candidate.distanceFromStart).abs() <=
                  config.roundaboutWindowMeters * 0.65) {
            suppressedNoteIds.add(other.id);
          }
        }
      } else if (_isJunctionClassification(candidate.classification)) {
        final note = _nearestConvertibleNote(
          notes,
          candidate.distanceFromStart,
          config.junctionWindowMeters,
          suppressedNoteIds,
        );
        if (note != null) {
          replacements[note.id] = _junctionNote(candidate, note);
          suppressedNoteIds.add(note.id);
          convertedNotes++;
        } else if (candidate.confidence >= config.minimumSpecificConfidence) {
          inserted.add(_insertedManeuverNote(candidate, routePoints));
        }
      }
    }

    final refined = <PaceNote>[];
    var downgradedHairpins = 0;

    for (final note in notes) {
      if (replacements.containsKey(note.id)) {
        refined.add(_capSpeed(replacements[note.id]!, speedLimits));
        continue;
      }
      if (suppressedNoteIds.contains(note.id)) {
        continue;
      }

      var next = note;
      final scores = _scoreForNote(note, routePoints, accepted);
      if (_isHairpin(note) &&
          (!_hasHairpinEvidence(note, routePoints) ||
              scores.hairpinScore < scores.ordinaryCurveScore + 0.06 ||
              scores.hairpinScore < scores.junctionScore + 0.18 ||
              scores.hairpinScore < scores.roundaboutScore + 0.18)) {
        next = _downgradeHairpin(note);
        downgradedHairpins++;
        rejected.add(
          RejectedClassification(
            id: 'reject-${note.id}-hairpin',
            classification: note.direction.toLowerCase().startsWith('l')
                ? SemanticClassification.hairpinLeft
                : SemanticClassification.hairpinRight,
            distanceFromStart: note.distanceFromStart,
            reason:
                'Hairpin rejected: compact reversal evidence did not beat competing scores ${scores.toJson()}',
            confidence: scores.hairpinScore,
          ),
        );
      }

      final junction = _bestJunctionCandidateForNote(accepted, next, config);
      if (junction != null) {
        next = _junctionNote(junction, next);
      }

      refined.add(_capSpeed(next, speedLimits));
    }

    refined.addAll(inserted.map((note) => _capSpeed(note, speedLimits)));
    refined.sort((a, b) => a.distanceFromStart.compareTo(b.distanceFromStart));

    final deduped = _dedupeSemanticNotes(refined);
    final sectors = sectorsFromPacenotes(deduped, routePoints);
    final nodes = nodesFromPacenotes(deduped, routePoints);

    return RouteSemanticAnalysis(
      sectors: sectors,
      nodes: nodes,
      pacenotes: deduped,
      rejectedCandidates: rejected,
      diagnostics: RouteAnalysisDiagnostics(
        inputNotes: notes.length,
        inputWarnings: warnings.length,
        acceptedCandidates: accepted.length,
        rejectedCandidates: rejected.length,
        insertedNotes: inserted.length,
        convertedNotes: convertedNotes,
        downgradedHairpins: downgradedHairpins,
      ),
    );
  }

  static List<RouteSemanticNode> nodesFromPacenotes(
    List<PaceNote> notes,
    List<RoutePoint> routePoints,
  ) {
    return notes.map((note) {
      final start = note.startDistance ?? note.distanceFromStart;
      final end = note.endDistance ?? _defaultEndFor(note, routePoints);
      final classification = switch (note.type) {
        PaceNoteType.roundabout => SemanticClassification.roundabout,
        PaceNoteType.junction =>
          note.direction.toLowerCase().startsWith('l')
              ? SemanticClassification.junctionLeft
              : SemanticClassification.junctionRight,
        PaceNoteType.keepLeft => SemanticClassification.forkLeft,
        PaceNoteType.keepRight => SemanticClassification.forkRight,
        PaceNoteType.hairpinLeft => SemanticClassification.hairpinLeft,
        PaceNoteType.hairpinRight => SemanticClassification.hairpinRight,
        PaceNoteType.hairpin =>
          note.direction.toLowerCase().startsWith('l')
              ? SemanticClassification.hairpinLeft
              : SemanticClassification.hairpinRight,
        PaceNoteType.left => SemanticClassification.leftCurve,
        PaceNoteType.right => SemanticClassification.rightCurve,
        PaceNoteType.straight => SemanticClassification.straight,
        _ => SemanticClassification.unknownManeuver,
      };
      return RouteSemanticNode(
        id: 'semantic-node-${note.id}',
        routeDistance: note.distanceFromStart,
        startDistance: start,
        endDistance: end,
        classification: classification,
        confidence: classification == SemanticClassification.straight
            ? 0.65
            : 0.8,
        displayText: note.text.isNotEmpty ? note.text : note.rallyText,
        speechText: note.text.isNotEmpty ? note.text : note.rallyText,
        severity: note.severity,
        speedKmh: note.recommendedSpeedKmh,
        diagnostics: {
          'paceNoteId': note.id,
          'headingChange': _headingChangeBetween(routePoints, start, end),
        },
      );
    }).toList();
  }

  static List<RoadSector> sectorsFromPacenotes(
    List<PaceNote> notes,
    List<RoutePoint> routePoints,
  ) {
    return notes.map((note) {
      final type = switch (note.type) {
        PaceNoteType.roundabout => RoadSectorType.roundabout,
        PaceNoteType.junction => RoadSectorType.junction,
        PaceNoteType.hairpinLeft => RoadSectorType.hairpinLeft,
        PaceNoteType.hairpinRight => RoadSectorType.hairpinRight,
        PaceNoteType.hairpin =>
          note.direction.toLowerCase().startsWith('l')
              ? RoadSectorType.hairpinLeft
              : RoadSectorType.hairpinRight,
        PaceNoteType.left => RoadSectorType.leftCurve,
        PaceNoteType.right => RoadSectorType.rightCurve,
        PaceNoteType.keepLeft || PaceNoteType.keepRight => RoadSectorType.fork,
        _ => RoadSectorType.straight,
      };
      final start = note.startDistance ?? note.distanceFromStart;
      final end = note.endDistance ?? _defaultEndFor(note, routePoints);
      final length = math.max(0.0, end - start);
      return RoadSector(
        id: 'semantic-${note.id}',
        type: type,
        startDistance: start,
        endDistance: end,
        lengthMeters: length,
        totalHeadingChange: _headingChangeBetween(routePoints, start, end),
        averageCurvature: length > 0
            ? _headingChangeBetween(routePoints, start, end).abs() / length
            : 0.0,
        peakCurvature: 0.0,
        severity: note.severity,
        gripSpeedKmh: note.recommendedSpeedKmh,
        confidence: type == RoadSectorType.straight ? 0.65 : 0.8,
        modifiers: [
          if (note.tightens) 'tightens',
          if (note.opens) 'opens',
          if (note.isShort) 'short',
          if (note.isLong) 'long',
        ],
        context: {'paceNoteId': note.id, 'canonical': true},
      );
    }).toList();
  }

  SemanticCandidate _roundaboutCandidate(
    RoadWarning warning,
    MatchedRoute? route,
    RouteAnalysisConfig config,
  ) {
    final tags = warning.tags;
    final explicitConfidence =
        _tagDouble(tags, 'route_membership_confidence') ??
        _tagDouble(tags, 'semantic_confidence');
    final overlap =
        _tagDouble(tags, 'route_membership_overlap') ??
        _tagDouble(tags, 'overlapMeters');
    final headingChange = _tagDouble(tags, 'route_membership_heading_change');
    final closePointCount = _tagInt(tags, 'route_membership_close_points');
    final start =
        _tagDouble(tags, 'route_membership_start') ??
        warning.distanceFromStart - 25.0;
    final end =
        _tagDouble(tags, 'route_membership_end') ??
        warning.distanceFromStart + 25.0;

    final hasRouteEdge =
        route?.edges.any((edge) {
          return edge.isRoundabout &&
              edge.startDistance <= end + config.roundaboutWindowMeters &&
              edge.endDistance >= start - config.roundaboutWindowMeters;
        }) ??
        false;
    final matchedEdgeIndexes = <int>[
      if (route != null)
        for (final edge in route.edges)
          if (edge.isRoundabout &&
              edge.startDistance <= end + config.roundaboutWindowMeters &&
              edge.endDistance >= start - config.roundaboutWindowMeters)
            edge.index,
    ];
    final hasManeuver =
        route?.maneuvers.any((maneuver) {
          return (maneuver.type == RouteManeuverType.enterRoundabout ||
                  maneuver.type == RouteManeuverType.exitRoundabout) &&
              (maneuver.distanceFromStart - warning.distanceFromStart).abs() <=
                  config.roundaboutWindowMeters;
        }) ??
        false;

    var confidence = explicitConfidence ?? 0.58;
    final evidence = <String>[];
    final contradictions = <String>[];
    if (explicitConfidence != null) {
      evidence.add(
        'Overpass route-membership confidence ${explicitConfidence.toStringAsFixed(2)}',
      );
    } else {
      contradictions.add('No explicit route-membership evidence on warning');
    }
    if (overlap != null) {
      confidence = math.min(1.0, confidence + (overlap >= 12.0 ? 0.12 : -0.35));
      evidence.add('Roundabout overlap ${overlap.toStringAsFixed(1)} m');
      if (overlap < 12.0) {
        contradictions.add('Roundabout overlap below traversed threshold');
      }
    } else {
      contradictions.add('No roundabout overlap interval');
    }
    if (hasRouteEdge) {
      confidence = math.max(confidence, 0.95);
      evidence.add('Matched route edge is tagged roundabout');
    }
    if (hasManeuver) {
      confidence = math.max(confidence, 0.95);
      evidence.add('Route maneuver enters/exits roundabout');
    }
    if (!hasRouteEdge && !hasManeuver && explicitConfidence == null) {
      confidence = math.min(confidence, 0.58);
    }
    if (!hasRouteEdge && !hasManeuver) {
      if (headingChange != null) {
        evidence.add(
          'Route heading changes ${headingChange.toStringAsFixed(1)} deg through warning',
        );
        if (headingChange < 30.0) {
          confidence = math.min(confidence, 0.42);
          contradictions.add(
            'Roundabout route interval has too little internal heading change',
          );
        }
      }
      if (closePointCount != null && closePointCount < 3) {
        confidence = math.min(confidence, 0.42);
        contradictions.add('Too few close route points on tagged roundabout');
      }
    }

    final geometryContext = <String, dynamic>{};
    if (overlap != null) {
      geometryContext['overlapMeters'] = overlap;
    }
    if (headingChange != null) {
      geometryContext['headingChangeDegrees'] = headingChange;
    }
    if (closePointCount != null) {
      geometryContext['closePointCount'] = closePointCount;
    }

    return SemanticCandidate(
      id: 'candidate-roundabout-${warning.id}',
      classification: SemanticClassification.roundabout,
      distanceFromStart: warning.distanceFromStart,
      startDistance: math.min(start, end),
      endDistance: math.max(start, end),
      confidence: confidence.clamp(0.0, 1.0),
      sourceId: warning.id,
      evidence: evidence,
      contradictingEvidence: contradictions,
      matchedEdgeIndexes: matchedEdgeIndexes,
      topologyContext: {
        'hasRouteEdge': hasRouteEdge,
        'hasManeuver': hasManeuver,
        'startDistance': start,
        'endDistance': end,
      },
      geometryContext: geometryContext,
      scores: SemanticScorecard(roundaboutScore: confidence.clamp(0.0, 1.0)),
    );
  }

  List<SemanticCandidate> _maneuverCandidates(
    List<RouteManeuver> maneuvers,
    List<RouteIntersection> intersections,
    RouteAnalysisConfig config,
  ) {
    final candidates = <SemanticCandidate>[];
    for (final maneuver in maneuvers) {
      final classification = switch (maneuver.type) {
        RouteManeuverType.turnLeft ||
        RouteManeuverType.sharpLeft ||
        RouteManeuverType.slightLeft => SemanticClassification.junctionLeft,
        RouteManeuverType.turnRight ||
        RouteManeuverType.sharpRight ||
        RouteManeuverType.slightRight => SemanticClassification.junctionRight,
        RouteManeuverType.keepLeft => SemanticClassification.forkLeft,
        RouteManeuverType.keepRight => SemanticClassification.forkRight,
        RouteManeuverType.fork => SemanticClassification.genericManeuver,
        RouteManeuverType.merge => SemanticClassification.merge,
        RouteManeuverType.uTurn => SemanticClassification.uTurn,
        RouteManeuverType.enterRoundabout ||
        RouteManeuverType.exitRoundabout => SemanticClassification.roundabout,
        _ => null,
      };
      if (classification == null) continue;
      candidates.add(
        SemanticCandidate(
          id: 'candidate-maneuver-${maneuver.id}',
          classification: classification,
          distanceFromStart: maneuver.distanceFromStart,
          startDistance:
              maneuver.distanceFromStart - config.junctionWindowMeters,
          endDistance: maneuver.distanceFromStart + config.junctionWindowMeters,
          confidence: math.max(0.0, math.min(1.0, maneuver.confidence)),
          direction: _directionForClassification(classification),
          sourceId: maneuver.id,
          evidence: const ['Route maneuver evidence'],
          matchedEdgeIndexes: [maneuver.fromEdgeIndex, maneuver.toEdgeIndex],
          topologyContext: {
            'fromEdgeIndex': maneuver.fromEdgeIndex,
            'toEdgeIndex': maneuver.toEdgeIndex,
            'routeManeuverType': maneuver.type.name,
            if (maneuver.roundaboutExit != null)
              'roundaboutExit': maneuver.roundaboutExit,
          },
          scores: SemanticScorecard(
            junctionScore: _isJunctionClassification(classification)
                ? maneuver.confidence
                : 0.0,
            roundaboutScore: classification == SemanticClassification.roundabout
                ? maneuver.confidence
                : 0.0,
          ),
        ),
      );
    }

    for (final intersection in intersections) {
      final topology = _topologyForIntersection(intersection);
      if (topology.isGradeSeparated || topology.followsNaturalContinuation) {
        continue;
      }
      final sideRoads = intersection.connectedRoads
          .where((road) => !road.isTraversed)
          .length;
      if (sideRoads == 0) continue;
      final classification = topology.routeTurnAngle.abs() < 20.0
          ? SemanticClassification.junctionStraight
          : (topology.routeTurnAngle < 0
                ? SemanticClassification.junctionLeft
                : SemanticClassification.junctionRight);
      final confidence = math.min(
        0.92,
        math.max(0.0, topology.confidence - (sideRoads == 1 ? 0.08 : 0.0)),
      );
      candidates.add(
        SemanticCandidate(
          id: 'candidate-intersection-${intersection.id}',
          classification: classification,
          distanceFromStart: intersection.distanceFromStart,
          startDistance:
              intersection.distanceFromStart - config.junctionWindowMeters,
          endDistance:
              intersection.distanceFromStart + config.junctionWindowMeters,
          confidence: confidence,
          direction: _directionForClassification(classification),
          sourceId: intersection.id,
          evidence: [
            'Route leaves natural continuation at intersection',
            'Intersection topology with $sideRoads side road(s)',
          ],
          contradictingEvidence: [
            if (confidence < config.minimumSpecificConfidence)
              'Intersection evidence below specific threshold',
          ],
          matchedEdgeIndexes: [
            intersection.traversedIncomingEdgeIndex,
            intersection.traversedOutgoingEdgeIndex,
          ],
          topologyContext: topology.toJson(),
          scores: SemanticScorecard(junctionScore: confidence),
        ),
      );
    }
    return candidates;
  }

  IntersectionTopology _topologyForIntersection(
    RouteIntersection intersection,
  ) {
    final traversed = intersection.connectedRoads
        .where((road) => road.isTraversed)
        .toList();
    final sideRoadCount = intersection.connectedRoads.length - traversed.length;
    if (traversed.length < 2) {
      return IntersectionTopology(
        routeDistance: intersection.distanceFromStart,
        incomingEdgeIndex: intersection.traversedIncomingEdgeIndex,
        outgoingEdgeIndex: intersection.traversedOutgoingEdgeIndex,
        connectedRoads: intersection.connectedRoads,
        naturalContinuationEdgeIndex: intersection.traversedOutgoingEdgeIndex,
        followsNaturalContinuation: true,
        routeTurnAngle: 0.0,
        isGradeSeparated: false,
        confidence: 0.35,
      );
    }

    final incoming = traversed.first;
    final outgoing = traversed[1];
    final routeTurnAngle = normalizeAngleDeltaDegrees(
      incoming.bearing,
      outgoing.bearing,
    );
    final geometricScore = (1.0 - (routeTurnAngle.abs() / 90.0)).clamp(
      0.0,
      1.0,
    );
    final nameScore = _sameNullableText(incoming.name, outgoing.name)
        ? 1.0
        : 0.0;
    final refScore = _sameNullableText(incoming.ref, outgoing.ref) ? 1.0 : 0.0;
    final incomingClass = incoming.tags['highway']?.toString();
    final outgoingClass = outgoing.tags['highway']?.toString();
    final classScore = _sameNullableText(incomingClass, outgoingClass)
        ? 1.0
        : 0.0;
    final sameWay =
        incoming.osmWayId != null && incoming.osmWayId == outgoing.osmWayId;
    final topologyScore = sideRoadCount <= 0 ? 1.0 : 0.65;
    final overall =
        (geometricScore * 0.52) +
        (nameScore * 0.16) +
        (refScore * 0.12) +
        (classScore * 0.10) +
        (topologyScore * 0.10) +
        (sameWay ? 0.10 : 0.0);
    final followsNatural =
        overall >= 0.72 || (sameWay && routeTurnAngle.abs() <= 55.0);
    final incomingLayer = _tagInt(incoming.tags, 'layer') ?? 0;
    final outgoingLayer = _tagInt(outgoing.tags, 'layer') ?? 0;
    final gradeSeparated =
        incomingLayer != outgoingLayer ||
        incoming.tags['bridge'] == 'yes' ||
        outgoing.tags['bridge'] == 'yes' ||
        incoming.tags['tunnel'] == 'yes' ||
        outgoing.tags['tunnel'] == 'yes';

    final continuity = RoadContinuationAnalysis(
      incomingEdgeIndex: intersection.traversedIncomingEdgeIndex,
      outgoingEdgeIndex: intersection.traversedOutgoingEdgeIndex,
      naturalContinuationEdgeIndex: followsNatural
          ? intersection.traversedOutgoingEdgeIndex
          : null,
      geometricScore: geometricScore,
      nameScore: nameScore,
      refScore: refScore,
      classScore: classScore,
      topologyScore: topologyScore,
      overallScore: overall.clamp(0.0, 1.0),
      followsNaturalContinuation: followsNatural,
    );

    return IntersectionTopology(
      routeDistance: intersection.distanceFromStart,
      incomingEdgeIndex: intersection.traversedIncomingEdgeIndex,
      outgoingEdgeIndex: intersection.traversedOutgoingEdgeIndex,
      connectedRoads: intersection.connectedRoads,
      naturalContinuationEdgeIndex: continuity.naturalContinuationEdgeIndex,
      followsNaturalContinuation: followsNatural,
      routeTurnAngle: routeTurnAngle,
      isGradeSeparated: gradeSeparated,
      confidence: followsNatural
          ? 0.45
          : math.min(
              0.94,
              0.55 + routeTurnAngle.abs() / 140.0 + sideRoadCount * 0.04,
            ),
    );
  }

  PaceNote? _nearestConvertibleNote(
    List<PaceNote> notes,
    double distance,
    double threshold,
    Set<String> suppressed,
  ) {
    PaceNote? best;
    var bestDelta = double.infinity;
    for (final note in notes) {
      if (suppressed.contains(note.id) || note.type == PaceNoteType.straight) {
        continue;
      }
      final delta = (note.distanceFromStart - distance).abs();
      if (delta <= threshold && delta < bestDelta) {
        best = note;
        bestDelta = delta;
      }
    }
    return best;
  }

  PaceNote _roundaboutNote(
    SemanticCandidate candidate,
    List<RoutePoint> routePoints, {
    PaceNote? fallback,
  }) {
    final point = _pointNearDistance(routePoints, candidate.distanceFromStart);
    final exitNumber = candidate.topologyContext['roundaboutExit'];
    final text = exitNumber is int
        ? 'Roundabout ahead, take ${_ordinal(exitNumber)} exit'
        : 'Roundabout ahead';
    return PaceNote(
      id:
          fallback?.id ??
          'note-roundabout-${candidate.distanceFromStart.round()}',
      distanceFromStart: candidate.distanceFromStart,
      startDistance: candidate.startDistance,
      endDistance: candidate.endDistance,
      direction: 'roundabout',
      severity: 4,
      type: PaceNoteType.roundabout,
      text: text,
      recommendedSpeedKmh: fallback?.recommendedSpeedKmh ?? 30,
      isShort: false,
      isLong: false,
      tightens: false,
      opens: false,
      distanceMeters: fallback?.distanceMeters,
      intoNoteId: fallback?.intoNoteId,
    ).copyWith(
      distanceFromStart:
          point?.distanceFromStart ?? candidate.distanceFromStart,
    );
  }

  PaceNote _insertedManeuverNote(
    SemanticCandidate candidate,
    List<RoutePoint> routePoints,
  ) {
    final point = _pointNearDistance(routePoints, candidate.distanceFromStart);
    final direction = candidate.direction ?? 'straight';
    final isFork =
        candidate.classification == SemanticClassification.forkLeft ||
        candidate.classification == SemanticClassification.forkRight;
    final isKeepLeft =
        candidate.classification == SemanticClassification.forkLeft;
    final isKeepRight =
        candidate.classification == SemanticClassification.forkRight;
    final type = isKeepLeft
        ? PaceNoteType.keepLeft
        : isKeepRight
        ? PaceNoteType.keepRight
        : PaceNoteType.junction;
    final text = isFork
        ? (direction == 'left' ? 'Keep left' : 'Keep right')
        : candidate.classification == SemanticClassification.uTurn
        ? 'U-turn'
        : direction == 'straight'
        ? 'Continue through junction'
        : 'At junction, $direction';
    return PaceNote(
      id: 'note-maneuver-${candidate.distanceFromStart.round()}',
      distanceFromStart:
          point?.distanceFromStart ?? candidate.distanceFromStart,
      startDistance: candidate.startDistance,
      endDistance: candidate.endDistance,
      direction: direction,
      severity: 3,
      type: type,
      text: text,
      recommendedSpeedKmh: isFork ? 40 : 30,
    );
  }

  SemanticCandidate? _bestJunctionCandidateForNote(
    List<SemanticCandidate> candidates,
    PaceNote note,
    RouteAnalysisConfig config,
  ) {
    if (note.direction == 'straight') return null;
    SemanticCandidate? best;
    for (final candidate in candidates) {
      if (!_isJunctionClassification(candidate.classification)) continue;
      if (candidate.confidence < config.minimumSpecificConfidence) continue;
      final delta = (candidate.distanceFromStart - note.distanceFromStart)
          .abs();
      if (delta > config.junctionWindowMeters) continue;
      if (best == null || candidate.confidence > best.confidence) {
        best = candidate;
      }
    }
    return best;
  }

  PaceNote _junctionNote(SemanticCandidate candidate, PaceNote note) {
    final direction =
        candidate.direction ??
        (note.direction.toLowerCase().startsWith('l') ? 'left' : 'right');
    final isFork =
        candidate.classification == SemanticClassification.forkLeft ||
        candidate.classification == SemanticClassification.forkRight;
    if (isFork) {
      final isLeft = direction == 'left';
      return note.copyWith(
        id: '${note.id}-fork',
        type: isLeft ? PaceNoteType.keepLeft : PaceNoteType.keepRight,
        direction: direction,
        text: isLeft ? 'keep left' : 'keep right',
        tightens: false,
        opens: false,
        recommendedSpeedKmh: math.min(note.recommendedSpeedKmh ?? 40, 40),
      );
    }
    return note.copyWith(
      id: '${note.id}-junction',
      type: PaceNoteType.junction,
      direction: direction,
      text: 'At junction, $direction',
      tightens: false,
      opens: false,
      recommendedSpeedKmh: math.min(note.recommendedSpeedKmh ?? 30, 30),
    );
  }

  bool _hasHairpinEvidence(PaceNote note, List<RoutePoint> routePoints) {
    if (routePoints.length < 5) return false;
    final start = note.startDistance ?? note.distanceFromStart - 25.0;
    final end = note.endDistance ?? note.distanceFromStart + 25.0;
    final startIndex = _indexNearDistance(routePoints, start);
    final endIndex = _indexNearDistance(routePoints, end);
    if (endIndex <= startIndex + 2) return false;

    var headingChange = 0.0;
    var sameSign = 0;
    var nonZero = 0;
    final expectedSign = note.direction.toLowerCase().startsWith('l') ? -1 : 1;
    for (var i = startIndex; i < endIndex; i++) {
      final delta = normalizeAngleDeltaDegrees(
        routePoints[i].heading,
        routePoints[i + 1].heading,
      );
      if (delta.abs() < 1.0) continue;
      headingChange += delta;
      nonZero++;
      if (delta.sign.toInt() == expectedSign) {
        sameSign++;
      }
    }
    final coherence = nonZero == 0 ? 0.0 : sameSign / nonZero;
    final length =
        routePoints[endIndex].distanceFromStart -
        routePoints[startIndex].distanceFromStart;
    final chord = haversineDistanceMeters(
      routePoints[startIndex].lat,
      routePoints[startIndex].lon,
      routePoints[endIndex].lat,
      routePoints[endIndex].lon,
    );
    final chordRatio = length <= 0 ? 1.0 : chord / length;
    final entryExitDelta = normalizeAngleDeltaDegrees(
      routePoints[startIndex].heading,
      routePoints[endIndex].heading,
    ).abs();

    return headingChange.abs() >= 145.0 &&
        entryExitDelta >= 125.0 &&
        coherence >= 0.72 &&
        length >= 25.0 &&
        length <= 110.0 &&
        chordRatio <= 0.72;
  }

  PaceNote _downgradeHairpin(PaceNote note) {
    final isLeft = note.direction.toLowerCase().startsWith('l');
    return note.copyWith(
      type: isLeft ? PaceNoteType.left : PaceNoteType.right,
      direction: isLeft ? 'left' : 'right',
      text: '',
      severity: math.max(note.severity, 1),
    );
  }

  PaceNote _capSpeed(PaceNote note, List<SpeedLimitSegment> speedLimits) {
    if (note.recommendedSpeedKmh == null || speedLimits.isEmpty) {
      return note;
    }
    var speed = note.recommendedSpeedKmh!;
    for (final limit in speedLimits) {
      if (note.distanceFromStart >= limit.startDistance &&
          note.distanceFromStart <= limit.endDistance &&
          limit.parsedKmh != null) {
        speed = math.min(speed, limit.parsedKmh!).toInt();
        break;
      }
    }
    return note.copyWith(recommendedSpeedKmh: speed);
  }

  List<PaceNote> _dedupeSemanticNotes(List<PaceNote> notes) {
    final deduped = <PaceNote>[];
    for (final note in notes) {
      final duplicate = deduped.any((existing) {
        final close =
            (existing.distanceFromStart - note.distanceFromStart).abs() < 70;
        final sameSpecific =
            existing.type == note.type &&
            (note.type == PaceNoteType.roundabout ||
                note.type == PaceNoteType.junction);
        return close && sameSpecific;
      });
      if (!duplicate) {
        deduped.add(note);
      }
    }
    return deduped;
  }

  static double _defaultEndFor(PaceNote note, List<RoutePoint> routePoints) {
    if (note.type == PaceNoteType.straight && note.distanceMeters != null) {
      return note.distanceFromStart + note.distanceMeters!;
    }
    final routeEnd = routePoints.isEmpty
        ? note.distanceFromStart
        : routePoints.last.distanceFromStart;
    return math.min(routeEnd, note.distanceFromStart + 40.0);
  }

  static double _headingChangeBetween(
    List<RoutePoint> routePoints,
    double start,
    double end,
  ) {
    if (routePoints.length < 2) return 0.0;
    final startIndex = _staticIndexNearDistance(routePoints, start);
    final endIndex = _staticIndexNearDistance(routePoints, end);
    var sum = 0.0;
    for (var i = startIndex; i < endIndex; i++) {
      sum += normalizeAngleDeltaDegrees(
        routePoints[i].heading,
        routePoints[i + 1].heading,
      );
    }
    return sum;
  }

  RoutePoint? _pointNearDistance(
    List<RoutePoint> routePoints,
    double distance,
  ) {
    if (routePoints.isEmpty) return null;
    return routePoints[_indexNearDistance(routePoints, distance)];
  }

  int _indexNearDistance(List<RoutePoint> points, double targetDistance) {
    return _staticIndexNearDistance(points, targetDistance);
  }

  static int _staticIndexNearDistance(
    List<RoutePoint> points,
    double targetDistance,
  ) {
    if (points.isEmpty) return 0;
    if (targetDistance <= points.first.distanceFromStart) return 0;
    if (targetDistance >= points.last.distanceFromStart) {
      return points.length - 1;
    }
    var low = 0;
    var high = points.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final midDist = points[mid].distanceFromStart;
      if (midDist == targetDistance) {
        return mid;
      }
      if (midDist < targetDistance) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (low >= points.length) return high;
    if (high < 0) return low;
    final lowDelta = (points[low].distanceFromStart - targetDistance).abs();
    final highDelta = (points[high].distanceFromStart - targetDistance).abs();
    return lowDelta < highDelta ? low : high;
  }

  bool _isHairpin(PaceNote note) {
    return note.type == PaceNoteType.hairpin ||
        note.type == PaceNoteType.hairpinLeft ||
        note.type == PaceNoteType.hairpinRight;
  }

  bool _isJunctionWarning(RoadWarningType type) {
    return type == RoadWarningType.trafficLight ||
        type == RoadWarningType.stopSign ||
        type == RoadWarningType.giveWay;
  }

  bool _isJunctionClassification(SemanticClassification classification) {
    return classification == SemanticClassification.junctionLeft ||
        classification == SemanticClassification.junctionRight ||
        classification == SemanticClassification.junctionStraight ||
        classification == SemanticClassification.forkLeft ||
        classification == SemanticClassification.forkRight ||
        classification == SemanticClassification.merge ||
        classification == SemanticClassification.uTurn;
  }

  int _priority(SemanticClassification classification) {
    return switch (classification) {
      SemanticClassification.roundabout => 40,
      SemanticClassification.junctionLeft ||
      SemanticClassification.junctionRight ||
      SemanticClassification.junctionStraight ||
      SemanticClassification.forkLeft ||
      SemanticClassification.forkRight ||
      SemanticClassification.merge ||
      SemanticClassification.uTurn => 30,
      SemanticClassification.hairpinLeft ||
      SemanticClassification.hairpinRight => 20,
      _ => 10,
    };
  }

  String? _directionForClassification(SemanticClassification classification) {
    return switch (classification) {
      SemanticClassification.junctionLeft ||
      SemanticClassification.forkLeft ||
      SemanticClassification.hairpinLeft ||
      SemanticClassification.leftCurve => 'left',
      SemanticClassification.junctionRight ||
      SemanticClassification.forkRight ||
      SemanticClassification.hairpinRight ||
      SemanticClassification.rightCurve => 'right',
      _ => null,
    };
  }

  String _ordinal(int value) {
    final mod100 = value % 100;
    if (mod100 >= 11 && mod100 <= 13) {
      return '${value}th';
    }
    return switch (value % 10) {
      1 => '${value}st',
      2 => '${value}nd',
      3 => '${value}rd',
      _ => '${value}th',
    };
  }

  double? _tagDouble(Map<String, dynamic> tags, String key) {
    final value = tags[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _tagInt(Map<String, dynamic> tags, String key) {
    final value = tags[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _sameNullableText(String? a, String? b) {
    if (a == null || b == null) return false;
    final left = a.trim().toLowerCase();
    final right = b.trim().toLowerCase();
    return left.isNotEmpty && left == right;
  }

  SemanticScorecard _scoreForNote(
    PaceNote note,
    List<RoutePoint> routePoints,
    List<SemanticCandidate> accepted,
  ) {
    final start = note.startDistance ?? note.distanceFromStart - 25.0;
    final end = note.endDistance ?? note.distanceFromStart + 25.0;
    final headingChange = _headingChangeBetween(routePoints, start, end).abs();
    final isCurve =
        note.type == PaceNoteType.left ||
        note.type == PaceNoteType.right ||
        note.type == PaceNoteType.corner ||
        _isHairpin(note);
    final ordinaryCurveScore = isCurve
        ? (0.48 + math.min(0.34, headingChange / 240.0)).clamp(0.0, 0.86)
        : 0.0;
    final hairpinScore = _hasHairpinEvidence(note, routePoints)
        ? 0.94
        : (_isHairpin(note) ? 0.42 : 0.0);

    var junctionScore = 0.0;
    var roundaboutScore = 0.0;
    for (final candidate in accepted) {
      if (!candidate.overlaps(start, end) &&
          (candidate.distanceFromStart - note.distanceFromStart).abs() > 55.0) {
        continue;
      }
      if (_isJunctionClassification(candidate.classification)) {
        junctionScore = math.max(junctionScore, candidate.confidence);
      }
      if (candidate.classification == SemanticClassification.roundabout) {
        roundaboutScore = math.max(roundaboutScore, candidate.confidence);
      }
    }

    return SemanticScorecard(
      ordinaryCurveScore: ordinaryCurveScore.toDouble(),
      hairpinScore: hairpinScore.toDouble(),
      junctionScore: junctionScore,
      roundaboutScore: roundaboutScore,
    );
  }
}
