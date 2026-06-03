import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../utils/geo_math.dart';

const double cornerWindowMeters = 30;
const double cornerCandidateThresholdDegrees = 18;
const double cornerGroupingMeters = 45;
const double intoDistanceMeters = 90;

class PacenoteGenerator {
  List<RoutePoint> enrichRoutePoints(List<RoutePoint> rawPoints) {
    if (rawPoints.isEmpty) {
      return const [];
    }

    final enriched = <RoutePoint>[
      rawPoints.first.copyWith(distanceFromStart: 0, heading: 0),
    ];

    var distance = 0.0;
    for (var i = 1; i < rawPoints.length; i++) {
      final previous = rawPoints[i - 1];
      final current = rawPoints[i];
      distance += haversineDistanceMeters(
        previous.lat,
        previous.lon,
        current.lat,
        current.lon,
      );
      final heading = bearingDegrees(
        previous.lat,
        previous.lon,
        current.lat,
        current.lon,
      );
      enriched.add(
        current.copyWith(distanceFromStart: distance, heading: heading),
      );
    }

    if (enriched.length > 1) {
      enriched[0] = enriched[0].copyWith(heading: enriched[1].heading);
    }

    return enriched;
  }

  List<PaceNote> generate(List<RoutePoint> inputPoints) {
    final points = enrichRoutePoints(inputPoints);
    if (points.length < 4) {
      return const [];
    }

    final candidates = <_CornerCandidate>[];
    for (var i = 1; i < points.length - 1; i++) {
      final before = _indexNearDistance(
        points,
        points[i].distanceFromStart - cornerWindowMeters,
      );
      final after = _indexNearDistance(
        points,
        points[i].distanceFromStart + cornerWindowMeters,
      );

      if (before == after) {
        continue;
      }

      final delta = normalizeAngleDeltaDegrees(
        points[before].heading,
        points[after].heading,
      );
      if (delta.abs() >= cornerCandidateThresholdDegrees) {
        candidates.add(_CornerCandidate(index: i, delta: delta));
      }
    }

    if (candidates.isEmpty) {
      return const [];
    }

    final zones = _groupCandidates(points, candidates);
    final notes = <PaceNote>[];
    for (var zoneIndex = 0; zoneIndex < zones.length; zoneIndex++) {
      final zone = zones[zoneIndex];
      final note = _zoneToNote(points, zone, zoneIndex);
      if (note != null) {
        notes.add(note);
      }
    }

    return _linkCloseCorners(notes);
  }

  List<PaceNote> refinePacenotesWithRoadContext({
    required List<PaceNote> notes,
    required List<RoutePoint> routePoints,
    required List<RoadWarning> warnings,
    required List<SpeedLimitSegment> speedLimits,
  }) {
    var roundaboutConversions = 0;
    var junctionConversions = 0;

    final refined = <PaceNote>[];
    for (final note in notes) {
      final nearbyRoundabout = _nearestWarningOfTypes(note, warnings, const {
        RoadWarningType.roundabout,
      }, 55);
      if (nearbyRoundabout != null ||
          _isLikelyRoundaboutGeometry(note, routePoints)) {
        roundaboutConversions++;
        refined.add(
          note.copyWith(
            id: '${note.id}-roundabout',
            type: PaceNoteType.roundabout,
            severity: 4,
            direction: 'roundabout',
            text: 'Roundabout ahead',
            tightens: false,
            opens: false,
          ),
        );
        continue;
      }

      final nearbyJunction = _nearestWarningOfTypes(note, warnings, const {
        RoadWarningType.trafficLight,
        RoadWarningType.stopSign,
        RoadWarningType.giveWay,
      }, 28);
      if (nearbyJunction != null && note.severity <= 3) {
        junctionConversions++;
        final direction = note.direction.toLowerCase().startsWith('l')
            ? 'left'
            : 'right';
        refined.add(
          note.copyWith(
            id: '${note.id}-junction',
            type: PaceNoteType.junction,
            severity: 4,
            text: 'At junction, $direction',
            tightens: false,
            opens: false,
          ),
        );
        continue;
      }

      refined.add(
        note.copyWith(
          type: note.severity == 1 ? PaceNoteType.hairpin : note.type,
        ),
      );
    }

    final deduped = _dedupeRoadContextNotes(refined);
    assert(() {
      // Debug-only summary for tuning road-context refinement.
      // ignore: avoid_print
      print(
        'Pacenotes refined: raw=${notes.length}, roundabouts=$roundaboutConversions, junctions=$junctionConversions, final=${deduped.length}, warnings=${warnings.length}',
      );
      return true;
    }());
    return _linkCloseCorners(deduped);
  }

  int _indexNearDistance(List<RoutePoint> points, double targetDistance) {
    var bestIndex = 0;
    var bestDelta = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final delta = (points[i].distanceFromStart - targetDistance).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  List<_CornerZone> _groupCandidates(
    List<RoutePoint> points,
    List<_CornerCandidate> candidates,
  ) {
    final zones = <_CornerZone>[];
    var current = <_CornerCandidate>[candidates.first];

    for (var i = 1; i < candidates.length; i++) {
      final previous = current.last;
      final candidate = candidates[i];
      final gap =
          points[candidate.index].distanceFromStart -
          points[previous.index].distanceFromStart;
      if (gap <= cornerGroupingMeters) {
        current.add(candidate);
      } else {
        zones.add(_CornerZone(List<_CornerCandidate>.from(current)));
        current = <_CornerCandidate>[candidate];
      }
    }

    zones.add(_CornerZone(current));
    return zones;
  }

  PaceNote? _zoneToNote(
    List<RoutePoint> points,
    _CornerZone zone,
    int zoneIndex,
  ) {
    final startIndex = zone.candidates.first.index;
    final endIndex = zone.candidates.last.index;
    final startDistance = points[startIndex].distanceFromStart;
    final endDistance = points[endIndex].distanceFromStart;
    final totalDelta = zone.candidates.fold<double>(
      0,
      (sum, candidate) => sum + candidate.delta,
    );

    if (totalDelta.abs() < cornerCandidateThresholdDegrees) {
      return null;
    }

    final direction = totalDelta > 0 ? 'right' : 'left';
    final severity = _severityForDelta(totalDelta.abs());
    final modifiers = _cornerModifiers(zone);
    final baseText = severity == 1
        ? 'Hairpin $direction'
        : '${_capitalize(direction)} $severity';
    final text = '$baseText${modifiers.suffix}';

    return PaceNote(
      id: 'note-$zoneIndex-${startDistance.round()}',
      distanceFromStart: (startDistance + endDistance) / 2,
      direction: direction,
      severity: severity,
      type: severity == 1 ? PaceNoteType.hairpin : PaceNoteType.corner,
      tightens: modifiers.tightens,
      opens: modifiers.opens,
      text: text,
    );
  }

  int _severityForDelta(double delta) {
    if (delta >= 135) {
      return 1;
    }
    if (delta >= 100) {
      return 2;
    }
    if (delta >= 70) {
      return 3;
    }
    if (delta >= 45) {
      return 4;
    }
    if (delta >= 28) {
      return 5;
    }
    return 6;
  }

  _CornerModifiers _cornerModifiers(_CornerZone zone) {
    if (zone.candidates.length < 4) {
      return const _CornerModifiers();
    }

    final midpoint = zone.candidates.length ~/ 2;
    final firstHalf = zone.candidates
        .take(midpoint)
        .fold<double>(0, (sum, candidate) => sum + candidate.delta.abs());
    final secondHalf = zone.candidates
        .skip(midpoint)
        .fold<double>(0, (sum, candidate) => sum + candidate.delta.abs());

    if (secondHalf > firstHalf * 1.25) {
      return const _CornerModifiers(tightens: true);
    }
    if (firstHalf > secondHalf * 1.25) {
      return const _CornerModifiers(opens: true);
    }
    return const _CornerModifiers();
  }

  List<PaceNote> _linkCloseCorners(List<PaceNote> notes) {
    if (notes.length < 2) {
      return notes;
    }

    final linked = <PaceNote>[];
    for (var i = 0; i < notes.length; i++) {
      var note = notes[i];
      if (i < notes.length - 1) {
        final next = notes[i + 1];
        final gap = next.distanceFromStart - note.distanceFromStart;
        if (gap < intoDistanceMeters &&
            note.type != PaceNoteType.roundabout &&
            next.type != PaceNoteType.roundabout &&
            note.type != PaceNoteType.junction &&
            next.type != PaceNoteType.junction) {
          note = note.copyWith(text: '${note.text} into ${next.text}');
        }
      }
      linked.add(note);
    }
    return linked;
  }

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }

  RoadWarning? _nearestWarningOfTypes(
    PaceNote note,
    List<RoadWarning> warnings,
    Set<RoadWarningType> types,
    double thresholdMeters,
  ) {
    RoadWarning? nearest;
    var nearestDelta = double.infinity;
    for (final warning in warnings) {
      if (!types.contains(warning.type)) {
        continue;
      }
      final delta = (warning.distanceFromStart - note.distanceFromStart).abs();
      if (delta <= thresholdMeters && delta < nearestDelta) {
        nearest = warning;
        nearestDelta = delta;
      }
    }
    return nearest;
  }

  bool _isLikelyRoundaboutGeometry(PaceNote note, List<RoutePoint> points) {
    final segment = points
        .where(
          (point) =>
              point.distanceFromStart >= note.distanceFromStart - 70 &&
              point.distanceFromStart <= note.distanceFromStart + 70,
        )
        .toList();
    if (segment.length < 8) {
      return false;
    }

    final length =
        segment.last.distanceFromStart - segment.first.distanceFromStart;
    if (length < 25 || length > 170) {
      return false;
    }

    var totalAbsDelta = 0.0;
    var maxDelta = 0.0;
    for (var i = 1; i < segment.length; i++) {
      final delta = normalizeAngleDeltaDegrees(
        segment[i - 1].heading,
        segment[i].heading,
      ).abs();
      totalAbsDelta += delta;
      maxDelta = delta > maxDelta ? delta : maxDelta;
    }
    if (totalAbsDelta < 120 || maxDelta > totalAbsDelta * 0.55) {
      return false;
    }

    var minLat = segment.first.lat;
    var maxLat = segment.first.lat;
    var minLon = segment.first.lon;
    var maxLon = segment.first.lon;
    for (final point in segment) {
      minLat = point.lat < minLat ? point.lat : minLat;
      maxLat = point.lat > maxLat ? point.lat : maxLat;
      minLon = point.lon < minLon ? point.lon : minLon;
      maxLon = point.lon > maxLon ? point.lon : maxLon;
    }

    final diagonal = haversineDistanceMeters(minLat, minLon, maxLat, maxLon);
    return diagonal <= 130 && note.severity <= 3;
  }

  List<PaceNote> _dedupeRoadContextNotes(List<PaceNote> notes) {
    final deduped = <PaceNote>[];
    for (final note in notes) {
      final duplicate = deduped.any((existing) {
        final close =
            (existing.distanceFromStart - note.distanceFromStart).abs() < 80;
        final sameContext =
            existing.type == note.type &&
            (note.type == PaceNoteType.roundabout ||
                note.type == PaceNoteType.junction);
        return close && sameContext;
      });
      if (!duplicate) {
        deduped.add(note);
      }
    }
    return deduped;
  }
}

class _CornerCandidate {
  const _CornerCandidate({required this.index, required this.delta});

  final int index;
  final double delta;
}

class _CornerZone {
  const _CornerZone(this.candidates);

  final List<_CornerCandidate> candidates;
}

class _CornerModifiers {
  const _CornerModifiers({this.tightens = false, this.opens = false});

  final bool tightens;
  final bool opens;

  String get suffix {
    if (tightens) {
      return ' tightens';
    }
    if (opens) {
      return ' opens';
    }
    return '';
  }
}
