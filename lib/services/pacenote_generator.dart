import '../models/pace_note.dart';
import '../models/route_point.dart';
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
        if (gap < intoDistanceMeters) {
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
