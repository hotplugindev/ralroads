import 'dart:math' as math;
import '../models/matched_route.dart';
import '../models/pace_note.dart';
import '../models/road_warning.dart';

class RouteEventScorer {
  static RouteEventScore scorePaceNote(
    PaceNote note,
    double speedLimitKmh,
    double precedingStraightDistanceMeters,
    String driveMode,
    {double routeMembership = 1.0, double classificationConfidence = 0.85}
  ) {
    double drivingRelevance = 0.8;
    double severityVal = 0.1;

    switch (note.type) {
      case PaceNoteType.hairpinLeft:
      case PaceNoteType.hairpinRight:
      case PaceNoteType.hairpin:
        drivingRelevance = 1.0;
        severityVal = 1.0;
        break;
      case PaceNoteType.left:
      case PaceNoteType.right:
      case PaceNoteType.corner:
        final sev = note.severity;
        if (sev <= 1) {
          severityVal = 0.95;
        } else if (sev == 2) {
          severityVal = 0.85;
        } else if (sev == 3) {
          severityVal = 0.7;
        } else if (sev == 4) {
          severityVal = 0.5;
        } else if (sev == 5) {
          severityVal = 0.3;
          drivingRelevance = 0.7;
        } else {
          severityVal = 0.15;
          drivingRelevance = 0.6;
        }
        break;
      case PaceNoteType.roundabout:
        drivingRelevance = 0.9;
        severityVal = 0.7;
        break;
      case PaceNoteType.junction:
        drivingRelevance = 0.95;
        severityVal = 0.75;
        break;
      case PaceNoteType.keepLeft:
      case PaceNoteType.keepRight:
        drivingRelevance = 0.8;
        severityVal = 0.5;
        break;
      case PaceNoteType.straight:
        drivingRelevance = 0.4;
        severityVal = 0.1;
        break;
      case PaceNoteType.warning:
        drivingRelevance = 0.95;
        severityVal = 0.85;
        break;
    }

    final urgency = (speedLimitKmh / 100.0).clamp(0.4, 1.0);
    final novelty = (precedingStraightDistanceMeters / 400.0).clamp(0.2, 1.0);

    // Compute finalScore based on weights
    double membershipWeight = 0.2;
    double confidenceWeight = 0.15;
    double relevanceWeight = 0.2;
    double severityWeight = 0.2;
    double urgencyWeight = 0.15;
    double noveltyWeight = 0.1;

    final finalScore = (routeMembership * membershipWeight) +
                       (classificationConfidence * confidenceWeight) +
                       (drivingRelevance * relevanceWeight) +
                       (severityVal * severityWeight) +
                       (urgency * urgencyWeight) +
                       (novelty * noveltyWeight);

    // Calculate speechValue depending on the driver style/mode
    double speechValue = finalScore;
    final mode = driveMode.toLowerCase();
    if (mode == 'calm') {
      if (note.type == PaceNoteType.straight || severityVal < 0.7) {
        speechValue = finalScore * 0.3;
      } else {
        speechValue = finalScore * 0.9;
      }
    } else if (mode == 'rally') {
      if (note.type != PaceNoteType.straight) {
        speechValue = finalScore * 1.2;
      }
    }

    return RouteEventScore(
      routeMembership: routeMembership,
      classificationConfidence: classificationConfidence,
      drivingRelevance: drivingRelevance,
      severity: severityVal,
      urgency: urgency,
      novelty: novelty,
      speechValue: speechValue.clamp(0.0, 1.0),
      finalScore: finalScore.clamp(0.0, 1.0),
    );
  }

  static RouteEventScore scoreRoadWarning(
    RoadWarning warning,
    double speedLimitKmh,
    double precedingStraightDistanceMeters,
    String driveMode,
    {double routeMembership = 1.0, double classificationConfidence = 1.0}
  ) {
    double drivingRelevance = 0.9;
    double severityVal = 0.6;

    switch (warning.type) {
      case RoadWarningType.stopSign:
        drivingRelevance = 1.0;
        severityVal = 0.95;
        break;
      case RoadWarningType.trafficLight:
        drivingRelevance = 0.9;
        severityVal = 0.75;
        break;
      case RoadWarningType.giveWay:
        drivingRelevance = 0.95;
        severityVal = 0.85;
        break;
      case RoadWarningType.speedCamera:
        drivingRelevance = 0.85;
        severityVal = 0.8;
        break;
      case RoadWarningType.roundabout:
        drivingRelevance = 0.95;
        severityVal = 0.7;
        break;
      case RoadWarningType.crest:
        final text = warning.text.toLowerCase();
        drivingRelevance = 0.9;
        severityVal = text.contains('blind') ? 0.9 : 0.6;
        break;
      case RoadWarningType.dip:
        final text = warning.text.toLowerCase();
        drivingRelevance = 0.9;
        severityVal = text.contains('severe') ? 0.85 : 0.55;
        break;
      case RoadWarningType.speedBump:
        drivingRelevance = 0.8;
        severityVal = 0.5;
        break;
      case RoadWarningType.speedLimitChange:
        drivingRelevance = 0.85;
        severityVal = 0.6;
        break;
      case RoadWarningType.tunnel:
        drivingRelevance = 0.7;
        severityVal = 0.4;
        break;
      case RoadWarningType.bridge:
        drivingRelevance = 0.7;
        severityVal = 0.4;
        break;
      case RoadWarningType.surfaceChange:
        drivingRelevance = 0.75;
        severityVal = 0.5;
        break;
    }

    final urgency = (speedLimitKmh / 100.0).clamp(0.4, 1.0);
    final novelty = (precedingStraightDistanceMeters / 400.0).clamp(0.2, 1.0);

    double membershipWeight = 0.2;
    double confidenceWeight = 0.15;
    double relevanceWeight = 0.2;
    double severityWeight = 0.2;
    double urgencyWeight = 0.15;
    double noveltyWeight = 0.1;

    final finalScore = (routeMembership * membershipWeight) +
                       (classificationConfidence * confidenceWeight) +
                       (drivingRelevance * relevanceWeight) +
                       (severityVal * severityWeight) +
                       (urgency * urgencyWeight) +
                       (novelty * noveltyWeight);

    double speechValue = finalScore;
    final mode = driveMode.toLowerCase();
    if (mode == 'calm') {
      speechValue = finalScore * 1.1;
    } else if (mode == 'rally') {
      speechValue = finalScore * 0.75;
    }

    return RouteEventScore(
      routeMembership: routeMembership,
      classificationConfidence: classificationConfidence,
      drivingRelevance: drivingRelevance,
      severity: severityVal,
      urgency: urgency,
      novelty: novelty,
      speechValue: speechValue.clamp(0.0, 1.0),
      finalScore: finalScore.clamp(0.0, 1.0),
    );
  }
}
