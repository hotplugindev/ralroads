import 'dart:math' as math;
import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../utils/geo_math.dart';
import 'settings_service.dart';

class PacenoteGenerator {
  PacenoteGenerator({SettingsService? settings}) : _settings = settings;

  final SettingsService? _settings;

  PacenoteStyle get _style => _settings?.pacenoteStyle ?? PacenoteStyle.balanced;
  List<RoutePoint> densifyRoutePoints(List<RoutePoint> points, {double targetSpacingM = 5.0}) {
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
          
          double? elev;
          if (p1.elevation != null && p2.elevation != null) {
            elev = p1.elevation! + (p2.elevation! - p1.elevation!) * fraction;
          }
          
          densified.add(RoutePoint(lat: lat, lon: lon, elevation: elev));
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
      rawPoints.first.copyWith(distanceFromStart: 0, heading: 0, elevation: rawPoints.first.elevation),
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
        current.copyWith(
          distanceFromStart: distance,
          heading: heading,
          elevation: current.elevation,
        ),
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
      final distDiff = points[afterIdx].distanceFromStart - points[beforeIdx].distanceFromStart;
      
      double r = 9999.0;
      if (distDiff > 0) {
        final thetaRad = (delta.abs() * math.pi) / 180.0;
        r = thetaRad > 0.0001 ? distDiff / thetaRad : 9999.0;
      }

      final curveRadiusThreshold = switch (_style) {
        PacenoteStyle.calm => 140.0,
        PacenoteStyle.balanced => 180.0,
        PacenoteStyle.rally => 220.0,
      };

      if (r < curveRadiusThreshold) {
        pointTypes.add(delta < 0 ? 'L' : 'R');
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
        if (seg.length >= 100.0) {
          final roundedDist = (seg.length / 50.0).round() * 50;
          final distToShow = roundedDist < 100 ? (seg.length / 10.0).round() * 10 : roundedDist;
          notes.add(PaceNote(
            id: 'note-straight-$noteCount-${seg.startDistance.round()}',
            distanceFromStart: seg.startDistance,
            startDistance: seg.startDistance,
            endDistance: seg.endDistance,
            direction: 'straight',
            severity: 0,
            type: PaceNoteType.straight,
            text: 'straight $distToShow',
            distanceMeters: distToShow,
          ));
          noteCount++;
        }
      } else {
        final direction = seg.type == 'L' ? 'left' : 'right';
        final radiusInfo = _calculateRadiusInfo(points, seg.startIndex, seg.endIndex);
        final totalHeadingChange = _calculateTotalHeadingChange(points, seg.startIndex, seg.endIndex);

        int severity = 6;
        final r = radiusInfo.minRadius;
        bool isHairpin = false;

        final h1 = _style == PacenoteStyle.calm ? 18.0 : (_style == PacenoteStyle.rally ? 26.0 : 22.0);
        final h2 = _style == PacenoteStyle.calm ? 32.0 : (_style == PacenoteStyle.rally ? 44.0 : 38.0);
        final h3 = _style == PacenoteStyle.calm ? 48.0 : (_style == PacenoteStyle.rally ? 66.0 : 58.0);
        final h4 = _style == PacenoteStyle.calm ? 70.0 : (_style == PacenoteStyle.rally ? 95.0 : 85.0);
        final h5 = _style == PacenoteStyle.calm ? 100.0 : (_style == PacenoteStyle.rally ? 140.0 : 125.0);

        if (r < 24.0 && totalHeadingChange.abs() >= 65.0) {
          isHairpin = true;
          severity = 1;
        } else if (r < 30.0 && totalHeadingChange.abs() >= 85.0) {
          isHairpin = true;
          severity = 1;
        } else if (r < h1) {
          severity = 1;
        } else if (r < h2) {
          severity = 2;
        } else if (r < h3) {
          severity = 3;
        } else if (r < h4) {
          severity = 4;
        } else if (r < h5) {
          severity = 5;
        } else {
          severity = 6;
        }

        if (_style == PacenoteStyle.calm && severity >= 5) {
          continue;
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

        final isShort = seg.length < 35.0;
        final isLong = seg.length > 100.0;

        int baseSpeed = 90;
        switch (severity) {
          case 1: baseSpeed = 25; break;
          case 2: baseSpeed = 35; break;
          case 3: baseSpeed = 45; break;
          case 4: baseSpeed = 60; break;
          case 5: baseSpeed = 75; break;
          case 6: baseSpeed = 90; break;
        }

        int recommendedSpeed = baseSpeed;
        if (baseSpeed <= 45) {
          recommendedSpeed = baseSpeed - 5;
        } else {
          recommendedSpeed = baseSpeed - 10;
        }

        final noteType = isHairpin
            ? (direction == 'left' ? PaceNoteType.hairpinLeft : PaceNoteType.hairpinRight)
            : (direction == 'left' ? PaceNoteType.left : PaceNoteType.right);

        notes.add(PaceNote(
          id: 'note-curve-$noteCount-${seg.startDistance.round()}',
          distanceFromStart: seg.startDistance,
          startDistance: seg.startDistance,
          endDistance: seg.endDistance,
          direction: direction,
          severity: severity,
          type: noteType,
          tightens: tightens,
          opens: opens,
          text: '',
          recommendedSpeedKmh: recommendedSpeed,
          isShort: isShort,
          isLong: isLong,
        ));
        noteCount++;
      }
    }

    final linkedNotes = <PaceNote>[];
    for (var i = 0; i < notes.length; i++) {
      var note = notes[i];
      if (i < notes.length - 1) {
        final next = notes[i + 1];
        final gap = next.distanceFromStart - note.distanceFromStart;
        
        final canLinkSelf = note.type == PaceNoteType.left ||
                            note.type == PaceNoteType.right ||
                            note.type == PaceNoteType.hairpinLeft ||
                            note.type == PaceNoteType.hairpinRight ||
                            note.type == PaceNoteType.keepLeft ||
                            note.type == PaceNoteType.keepRight ||
                            note.type == PaceNoteType.straight;
        
        final canLinkNext = next.type == PaceNoteType.left ||
                            next.type == PaceNoteType.right ||
                            next.type == PaceNoteType.hairpinLeft ||
                            next.type == PaceNoteType.hairpinRight ||
                            next.type == PaceNoteType.keepLeft ||
                            next.type == PaceNoteType.keepRight;
                            
        if (gap <= 85.0 && canLinkSelf && canLinkNext) {
          note = note.copyWith(intoNoteId: next.id);
        }
      }
      linkedNotes.add(note);
    }

    return linkedNotes;
  }

  List<PaceNote> refinePacenotesWithRoadContext({
    required List<PaceNote> notes,
    required List<RoutePoint> routePoints,
    required List<RoadWarning> warnings,
    required List<SpeedLimitSegment> speedLimits,
  }) {
    var roundaboutConversions = 0;
    var junctionConversions = 0;

    final List<double> roundaboutPositions = [];

    // 1. Add OSM roundabout warning positions (deduplicated within 75m)
    for (final w in warnings) {
      if (w.type == RoadWarningType.roundabout) {
        bool isDuplicate = false;
        for (final pos in roundaboutPositions) {
          if ((w.distanceFromStart - pos).abs() <= 75.0) {
            isDuplicate = true;
            break;
          }
        }
        if (!isDuplicate) {
          roundaboutPositions.add(w.distanceFromStart);
        }
      }
    }

    // 2. Add geometry-detected roundabout positions if not close to already added positions
    for (final note in notes) {
      if (note.direction != 'straight') {
        final confidence = _calculateRoundaboutGeometryConfidence(note, routePoints);
        if (confidence >= 0.8) {
          bool alreadyCovered = false;
          for (final pos in roundaboutPositions) {
            if ((note.distanceFromStart - pos).abs() <= 75.0) {
              alreadyCovered = true;
              break;
            }
          }
          if (!alreadyCovered) {
            roundaboutPositions.add(note.distanceFromStart);
          }
        }
      }
    }

    // Identify which note is the closest to each roundabout center and should be converted,
    // and which other notes are within 60 meters and should be skipped.
    final notesToSkip = <String>{};
    final convertedNotes = <String, PaceNote>{};

    for (final rPos in roundaboutPositions) {
      PaceNote? closestNote;
      double minDiff = double.infinity;
      
      for (final note in notes) {
        if (notesToSkip.contains(note.id) || convertedNotes.containsKey(note.id)) {
          continue;
        }
        final diff = (note.distanceFromStart - rPos).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestNote = note;
        }
      }

      if (closestNote != null && minDiff <= 65.0) {
        convertedNotes[closestNote.id] = closestNote.copyWith(
          id: '${closestNote.id}-roundabout',
          type: PaceNoteType.roundabout,
          severity: 4,
          direction: 'roundabout',
          text: 'Roundabout ahead',
          tightens: false,
          opens: false,
          recommendedSpeedKmh: 30,
        );

        for (final note in notes) {
          if (note.id != closestNote.id) {
            final diff = (note.distanceFromStart - rPos).abs();
            if (diff <= 60.0) {
              notesToSkip.add(note.id);
            }
          }
        }
      }
    }

    final refined = <PaceNote>[];
    for (final note in notes) {
      if (notesToSkip.contains(note.id)) {
        continue;
      }
      
      if (convertedNotes.containsKey(note.id)) {
        refined.add(convertedNotes[note.id]!);
        roundaboutConversions++;
        continue;
      }

      final nearbyJunction = _nearestWarningOfTypes(note, warnings, const {
        RoadWarningType.trafficLight,
        RoadWarningType.stopSign,
        RoadWarningType.giveWay,
      }, 45);
      if (nearbyJunction != null && note.severity <= 4 && note.direction != 'straight') {
        junctionConversions++;
        final direction = note.direction.toLowerCase().startsWith('l')
            ? 'left'
            : 'right';
            
        if (note.severity >= 5) {
          final isLeft = direction == 'left';
          refined.add(
            note.copyWith(
              id: '${note.id}-keep',
              type: isLeft ? PaceNoteType.keepLeft : PaceNoteType.keepRight,
              direction: direction,
              text: isLeft ? 'keep left' : 'keep right',
              tightens: false,
              opens: false,
              recommendedSpeedKmh: 40,
            ),
          );
        } else {
          refined.add(
            note.copyWith(
              id: '${note.id}-junction',
              type: PaceNoteType.junction,
              direction: direction,
              text: 'At junction, $direction',
              tightens: false,
              opens: false,
              recommendedSpeedKmh: 30,
            ),
          );
        }
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

  List<RoadWarning> detectElevationFeatures(List<RoutePoint> points) {
    final warnings = <RoadWarning>[];
    if (points.length < 20) return warnings;

    // Smooth elevations using a moving average window of 11 points (approx 55m at 5m spacing)
    final smoothed = <double>[];
    for (var i = 0; i < points.length; i++) {
      var sum = 0.0;
      var count = 0;
      const half = 5;
      for (var j = i - half; j <= i + half; j++) {
        if (j >= 0 && j < points.length && points[j].elevation != null) {
          sum += points[j].elevation!;
          count++;
        }
      }
      smoothed.add(count > 0 ? sum / count : (points[i].elevation ?? 0.0));
    }

    // Scan for peaks (crests) and valleys (dips)
    // Look ahead of 10 points (50m) to confirm peak/valley
    const lookahead = 10;
    for (var i = lookahead; i < points.length - lookahead; i++) {
      final currentElev = smoothed[i];
      if (points[i].elevation == null) continue;

      // Check peak (crest)
      bool isPeak = true;
      for (var j = i - lookahead; j <= i + lookahead; j++) {
        if (smoothed[j] > currentElev) {
          isPeak = false;
          break;
        }
      }
      if (isPeak) {
        final diffBefore = currentElev - smoothed[i - lookahead];
        final diffAfter = currentElev - smoothed[i + lookahead];
        // Elevation must rise by at least 1.0 meters and fall by at least 1.0 meters
        if (diffBefore >= 1.0 && diffAfter >= 1.0) {
          final pt = points[i];
          warnings.add(RoadWarning(
            id: 'crest-${pt.distanceFromStart.round()}',
            type: RoadWarningType.crest,
            lat: pt.lat,
            lon: pt.lon,
            distanceFromStart: pt.distanceFromStart,
            text: 'Crest',
          ));
          i += lookahead; // Skip to avoid duplicate detections
          continue;
        }
      }

      // Check valley (dip)
      bool isValley = true;
      for (var j = i - lookahead; j <= i + lookahead; j++) {
        if (smoothed[j] < currentElev) {
          isValley = false;
          break;
        }
      }
      if (isValley) {
        final diffBefore = smoothed[i - lookahead] - currentElev;
        final diffAfter = smoothed[i + lookahead] - currentElev;
        if (diffBefore >= 1.0 && diffAfter >= 1.0) {
          final pt = points[i];
          warnings.add(RoadWarning(
            id: 'dip-${pt.distanceFromStart.round()}',
            type: RoadWarningType.dip,
            lat: pt.lat,
            lon: pt.lon,
            distanceFromStart: pt.distanceFromStart,
            text: 'Dip',
          ));
          i += lookahead;
        }
      }
    }
    return warnings;
  }

  int _indexNearDistance(List<RoutePoint> points, double targetDistance) {
    if (points.isEmpty) return 0;
    if (targetDistance <= points.first.distanceFromStart) return 0;
    if (targetDistance >= points.last.distanceFromStart) return points.length - 1;

    var low = 0;
    var high = points.length - 1;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final midDist = points[mid].distanceFromStart;

      if (midDist == targetDistance) {
        return mid;
      } else if (midDist < targetDistance) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (low >= points.length) return high;
    if (high < 0) return low;

    final diff1 = (points[low].distanceFromStart - targetDistance).abs();
    final diff2 = (points[high].distanceFromStart - targetDistance).abs();
    return diff1 < diff2 ? low : high;
  }

  List<_RouteSegment> refineSegments(List<_RouteSegment> input, List<RoutePoint> points) {
    var list = List<_RouteSegment>.from(input);
    
    list = _mergeConsecutiveSameType(list);

    for (var i = 0; i < list.length; i++) {
      if ((list[i].type == 'L' || list[i].type == 'R') && list[i].length < 15.0) {
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
            list[i + 1].length < 35.0 &&
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
        if (totalHeadingChange.abs() < 12.0) {
          seg.type = 'S';
        }
      }
    }
    list = _mergeConsecutiveSameType(list);

    for (var i = 0; i < list.length; i++) {
      final seg = list[i];
      if (seg.type == 'L' || seg.type == 'R') {
        final radiusInfo = _calculateRadiusInfo(points, seg.startIndex, seg.endIndex);
        final totalHeadingChange = _calculateTotalHeadingChange(points, seg.startIndex, seg.endIndex);

        int severity = 6;
        final r = radiusInfo.minRadius;
        bool isHairpin = false;

        if (r < 24.0 && totalHeadingChange.abs() >= 65.0) {
          isHairpin = true;
          severity = 1;
        } else if (r < 30.0 && totalHeadingChange.abs() >= 85.0) {
          isHairpin = true;
          severity = 1;
        } else if (r < 22.0) {
          severity = 1;
        } else if (r < 38.0) {
          severity = 2;
        } else if (r < 58.0) {
          severity = 3;
        } else if (r < 85.0) {
          severity = 4;
        } else if (r < 125.0) {
          severity = 5;
        } else {
          severity = 6;
        }

        if (severity == 6 && !isHairpin) {
          final isRealCurve = seg.length >= 20.0 && totalHeadingChange.abs() >= 10.0;
          if (!isRealCurve) {
            seg.type = 'S';
          }
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
    
    final segLength = points[end].distanceFromStart - points[start].distanceFromStart;
    final halfWindow = math.min(10.0, segLength / 2.0);

    for (var i = start; i <= end; i++) {
      final before = _indexNearDistance(points, points[i].distanceFromStart - halfWindow);
      final after = _indexNearDistance(points, points[i].distanceFromStart + halfWindow);
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
    return 0.0;
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
