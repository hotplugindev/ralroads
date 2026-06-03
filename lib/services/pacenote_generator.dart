import 'dart:math' as math;
import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../utils/geo_math.dart';

class PacenoteGenerator {
  List<RoutePoint> densifyRoutePoints(List<RoutePoint> points, {double targetSpacingM = 7.0}) {
    if (points.length < 2) return points;
    final densified = <RoutePoint>[];
    
    for (var i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final dist = haversineDistanceMeters(p1.lat, p1.lon, p2.lat, p2.lon);
      
      densified.add(p1);
      
      if (dist > targetSpacingM) {
        final numSegments = (dist / targetSpacingM).ceil();
        for (var j = 1; j < numSegments; j++) {
          final fraction = j / numSegments;
          final lat = p1.lat + (p2.lat - p1.lat) * fraction;
          final lon = p1.lon + (p2.lon - p1.lon) * fraction;
          densified.add(RoutePoint(lat: lat, lon: lon));
        }
      }
    }
    densified.add(points.last);
    return densified;
  }

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
    final densified = densifyRoutePoints(inputPoints);
    final points = enrichRoutePoints(densified);
    if (points.length < 4) {
      return const [];
    }

    final pointTypes = <String>[];
    for (var i = 0; i < points.length; i++) {
      final beforeIdx = _indexNearDistance(points, points[i].distanceFromStart - 15.0);
      final afterIdx = _indexNearDistance(points, points[i].distanceFromStart + 15.0);
      final delta = normalizeAngleDeltaDegrees(points[beforeIdx].heading, points[afterIdx].heading);
      if (delta <= -8.0) {
        pointTypes.add('L');
      } else if (delta >= 8.0) {
        pointTypes.add('R');
      } else {
        pointTypes.add('S');
      }
    }

    final rawSegments = <_RouteSegment>[];
    if (points.isNotEmpty) {
      var currentType = pointTypes[0];
      var startIdx = 0;
      for (var i = 1; i < points.length; i++) {
        if (pointTypes[i] != currentType) {
          rawSegments.add(_RouteSegment(
            type: currentType,
            startIndex: startIdx,
            endIndex: i - 1,
            startDistance: points[startIdx].distanceFromStart,
            endDistance: points[i - 1].distanceFromStart,
          ));
          currentType = pointTypes[i];
          startIdx = i;
        }
      }
      rawSegments.add(_RouteSegment(
        type: currentType,
        startIndex: startIdx,
        endIndex: points.length - 1,
        startDistance: points[startIdx].distanceFromStart,
        endDistance: points.last.distanceFromStart,
      ));
    }

    final segments = refineSegments(rawSegments, points);
    final notes = <PaceNote>[];
    var noteCount = 0;

    for (final seg in segments) {
      if (seg.type == 'S') {
        if (seg.length >= 80.0) {
          final roundedDist = (seg.length / 50.0).round() * 50;
          final distToShow = roundedDist < 80 ? (seg.length / 10.0).round() * 10 : roundedDist;
          notes.add(PaceNote(
            id: 'note-straight-$noteCount-${seg.startDistance.round()}',
            distanceFromStart: seg.startDistance,
            direction: 'straight',
            severity: 0,
            type: PaceNoteType.corner,
            text: 'straight $distToShow',
          ));
          noteCount++;
        }
      } else {
        final direction = seg.type == 'L' ? 'left' : 'right';
        final radiusInfo = _calculateRadiusInfo(points, seg.startIndex, seg.endIndex);
        final totalHeadingChange = _calculateTotalHeadingChange(points, seg.startIndex, seg.endIndex);

        int severity = 6;
        final r = radiusInfo.minRadius;
        if (r < 18.0 && totalHeadingChange.abs() >= 75.0 && seg.length < 55.0) {
          severity = 1;
        } else if (r < 25.0) {
          severity = 2;
        } else if (r < 45.0) {
          severity = 3;
        } else if (r < 75.0) {
          severity = 4;
        } else if (r < 125.0) {
          severity = 5;
        } else {
          severity = 6;
        }

        final mid = seg.startIndex + (seg.endIndex - seg.startIndex) ~/ 2;
        final firstHalfRadius = _calculateRadiusInfo(points, seg.startIndex, mid).avgRadius;
        final secondHalfRadius = _calculateRadiusInfo(points, mid, seg.endIndex).avgRadius;
        bool tightens = false;
        bool opens = false;
        if (secondHalfRadius < firstHalfRadius * 0.75) {
          tightens = true;
        } else if (firstHalfRadius < secondHalfRadius * 0.75) {
          opens = true;
        }

        String mainText = '';
        if (severity == 1) {
          mainText = 'hairpin $direction';
        } else if (severity == 2) {
          mainText = '$direction 2';
        } else if (severity == 3) {
          mainText = '$direction 3';
        } else if (severity == 4) {
          mainText = 'medium $direction';
        } else if (severity == 5) {
          mainText = 'easy $direction';
        } else {
          mainText = 'very easy $direction';
        }

        if (seg.length > 180) {
          mainText = '$mainText very long';
        } else if (seg.length > 100) {
          mainText = '$mainText long';
        } else if (seg.length < 35) {
          mainText = '$mainText short';
        }

        if (tightens) {
          mainText = '$mainText tightens';
        } else if (opens) {
          mainText = '$mainText opens';
        }

        int baseSpeed = 90;
        switch (severity) {
          case 1: baseSpeed = 25; break;
          case 2: baseSpeed = 35; break;
          case 3: baseSpeed = 45; break;
          case 4: baseSpeed = 60; break;
          case 5: baseSpeed = 75; break;
          case 6: baseSpeed = 90; break;
        }

        notes.add(PaceNote(
          id: 'note-curve-$noteCount-${seg.startDistance.round()}',
          distanceFromStart: (seg.startDistance + seg.endDistance) / 2,
          direction: direction,
          severity: severity,
          type: severity == 1 ? PaceNoteType.hairpin : PaceNoteType.corner,
          tightens: tightens,
          opens: opens,
          text: mainText,
          recommendedSpeedKmh: baseSpeed,
        ));
        noteCount++;
      }
    }

    return notes;
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
      
      double roundaboutConfidence = 0.0;
      if (nearbyRoundabout != null) {
        roundaboutConfidence = 1.0;
      } else {
        roundaboutConfidence = _calculateRoundaboutGeometryConfidence(note, routePoints);
      }

      if (roundaboutConfidence >= 0.8) {
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
            recommendedSpeedKmh: 35,
          ),
        );
        continue;
      }

      final nearbyJunction = _nearestWarningOfTypes(note, warnings, const {
        RoadWarningType.trafficLight,
        RoadWarningType.stopSign,
        RoadWarningType.giveWay,
      }, 28);
      if (nearbyJunction != null && note.severity <= 4 && note.direction != 'straight') {
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
            recommendedSpeedKmh: 30,
          ),
        );
        continue;
      }

      int? speed = note.recommendedSpeedKmh;
      if (speed != null && speedLimits.isNotEmpty) {
        int? limitVal;
        for (final limit in speedLimits) {
          if (note.distanceFromStart >= limit.startDistance &&
              note.distanceFromStart <= limit.endDistance) {
            limitVal = limit.parsedKmh;
            break;
          }
        }
        if (limitVal != null) {
          speed = math.min(speed, limitVal);
        }
      }

      refined.add(
        note.copyWith(
          type: note.severity == 1 ? PaceNoteType.hairpin : note.type,
          recommendedSpeedKmh: speed,
        ),
      );
    }

    final deduped = _dedupeRoadContextNotes(refined);
    assert(() {
      print(
        'Pacenotes refined: raw=${notes.length}, roundabouts=$roundaboutConversions, junctions=$junctionConversions, final=${deduped.length}, warnings=${warnings.length}',
      );
      return true;
    }());
    
    return deduped;
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

  List<_RouteSegment> refineSegments(List<_RouteSegment> input, List<RoutePoint> points) {
    var list = List<_RouteSegment>.from(input);
    
    list = _mergeConsecutiveSameType(list);

    for (var i = 0; i < list.length; i++) {
      if ((list[i].type == 'L' || list[i].type == 'R') && list[i].length < 12.0) {
        list[i].type = 'S';
      }
    }
    list = _mergeConsecutiveSameType(list);

    bool changed = true;
    while (changed) {
      changed = false;
      final merged = <_RouteSegment>[];
      for (var i = 0; i < list.length; i++) {
        if (i < list.length - 2 &&
            list[i].type != 'S' &&
            list[i + 1].type == 'S' &&
            list[i + 1].length < 30.0 &&
            list[i + 2].type == list[i].type) {
          final newSeg = _RouteSegment(
            type: list[i].type,
            startIndex: list[i].startIndex,
            endIndex: list[i + 2].endIndex,
            startDistance: list[i].startDistance,
            endDistance: list[i + 2].endDistance,
          );
          merged.add(newSeg);
          i += 2;
          changed = true;
        } else {
          merged.add(list[i]);
        }
      }
      list = _mergeConsecutiveSameType(merged);
    }
    
    for (var i = 0; i < list.length; i++) {
      final seg = list[i];
      if (seg.type == 'L' || seg.type == 'R') {
        final totalHeadingChange = _calculateTotalHeadingChange(points, seg.startIndex, seg.endIndex);
        if (totalHeadingChange.abs() < 10.0) {
          seg.type = 'S';
        }
      }
    }
    list = _mergeConsecutiveSameType(list);
    
    return list;
  }

  List<_RouteSegment> _mergeConsecutiveSameType(List<_RouteSegment> input) {
    if (input.isEmpty) return const [];
    final merged = <_RouteSegment>[];
    var current = input.first;
    for (var i = 1; i < input.length; i++) {
      final next = input[i];
      if (next.type == current.type) {
        current.endIndex = next.endIndex;
        current.endDistance = next.endDistance;
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
    return merged;
  }

  double _calculateTotalHeadingChange(List<RoutePoint> points, int start, int end) {
    double sum = 0.0;
    for (var i = start; i < end; i++) {
      sum += normalizeAngleDeltaDegrees(points[i].heading, points[i + 1].heading);
    }
    return sum;
  }

  _RadiusInfo _calculateRadiusInfo(List<RoutePoint> points, int start, int end) {
    double minRadius = double.infinity;
    double sumRadius = 0.0;
    int count = 0;
    for (var i = start; i <= end; i++) {
      final before = _indexNearDistance(points, points[i].distanceFromStart - 15.0);
      final after = _indexNearDistance(points, points[i].distanceFromStart + 15.0);
      final distDiff = points[after].distanceFromStart - points[before].distanceFromStart;
      if (distDiff > 0) {
        final delta = normalizeAngleDeltaDegrees(points[before].heading, points[after].heading);
        final thetaRad = (delta.abs() * math.pi) / 180.0;
        final r = thetaRad > 0.0001 ? distDiff / thetaRad : 9999.0;
        if (r < minRadius) {
          minRadius = r;
        }
        sumRadius += r;
        count++;
      }
    }
    final avgRadius = count > 0 ? sumRadius / count : minRadius;
    return _RadiusInfo(minRadius: minRadius, avgRadius: avgRadius);
  }

  double _calculateRoundaboutGeometryConfidence(PaceNote note, List<RoutePoint> points) {
    final segment = points
        .where(
          (point) =>
              point.distanceFromStart >= note.distanceFromStart - 60 &&
              point.distanceFromStart <= note.distanceFromStart + 60,
        )
        .toList();
    if (segment.length < 8) {
      return 0.0;
    }

    final length = segment.last.distanceFromStart - segment.first.distanceFromStart;
    if (length < 20 || length > 120) {
      return 0.0;
    }

    var totalAbsDelta = 0.0;
    var maxDelta = 0.0;
    for (var i = 1; i < segment.length; i++) {
      final delta = normalizeAngleDeltaDegrees(
        segment[i - 1].heading,
        segment[i].heading,
      ).abs();
      totalAbsDelta += delta;
      if (delta > maxDelta) {
        maxDelta = delta;
      }
    }
    
    if (maxDelta > 20.0) {
      return 0.0;
    }

    if (totalAbsDelta < 100 || totalAbsDelta > 400) {
      return 0.0;
    }

    var minLat = segment.first.lat;
    var maxLat = segment.first.lat;
    var minLon = segment.first.lon;
    var maxLon = segment.first.lon;
    for (final point in segment) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLon = math.min(minLon, point.lon);
      maxLon = math.max(maxLon, point.lon);
    }
    final diagonal = haversineDistanceMeters(minLat, minLon, maxLat, maxLon);
    if (diagonal > 80) {
      return 0.0;
    }

    return 0.5;
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

class _RouteSegment {
  String type;
  int startIndex;
  int endIndex;
  double startDistance;
  double endDistance;

  _RouteSegment({
    required this.type,
    required this.startIndex,
    required this.endIndex,
    required this.startDistance,
    required this.endDistance,
  });

  double get length => endDistance - startDistance;
}

class _RadiusInfo {
  final double minRadius;
  final double avgRadius;
  const _RadiusInfo({required this.minRadius, required this.avgRadius});
}
