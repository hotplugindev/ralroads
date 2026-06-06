import 'dart:math' as math;
import 'dart:developer' as developer;
import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../models/matched_route.dart';
import '../utils/geo_math.dart';
import 'settings_service.dart';
import 'route_semantic_engine.dart';

class PacenoteBackgroundParams {
  final List<RoutePoint> points;
  final PacenoteStyle style;
  final List<RouteManeuver> maneuvers;
  const PacenoteBackgroundParams(
    this.points,
    this.style, {
    this.maneuvers = const [],
  });
}

List<PaceNote> generatePacenotesBackground(PacenoteBackgroundParams params) {
  final generator = PacenoteGenerator(styleOverride: params.style);
  return generator.generate(params.points, maneuvers: params.maneuvers);
}

class PacenoteGenerator {
  PacenoteGenerator({SettingsService? settings, PacenoteStyle? styleOverride})
    : _settings = settings,
      _styleOverride = styleOverride;

  final SettingsService? _settings;
  final PacenoteStyle? _styleOverride;

  PacenoteStyle get _style =>
      _styleOverride ?? _settings?.pacenoteStyle ?? PacenoteStyle.balanced;
  List<RoutePoint> densifyRoutePoints(
    List<RoutePoint> points, {
    double targetSpacingM = 5.0,
  }) {
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
      rawPoints.first.copyWith(
        distanceFromStart: 0,
        heading: 0,
        elevation: rawPoints.first.elevation,
      ),
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

  List<PaceNote> generate(
    List<RoutePoint> inputPoints, {
    List<RouteManeuver> maneuvers = const [],
  }) {
    final densified = densifyRoutePoints(inputPoints);
    final points = enrichRoutePoints(densified);
    if (points.length < 4) {
      return const [];
    }

    final smoothedHeadings = <double>[];
    for (var i = 0; i < points.length; i++) {
      var sumSin = 0.0;
      var sumCos = 0.0;
      const window = 2;
      for (var j = i - window; j <= i + window; j++) {
        if (j >= 0 && j < points.length) {
          final headingRad = points[j].heading * math.pi / 180.0;
          sumSin += math.sin(headingRad);
          sumCos += math.cos(headingRad);
        }
      }
      final avgRad = math.atan2(sumSin, sumCos);
      smoothedHeadings.add((avgRad * 180.0 / math.pi + 360.0) % 360.0);
    }

    final curvatureSamples = _buildMultiScaleCurvatureSamples(
      points,
      smoothedHeadings,
    );
    var rawSegments = _buildRawSegmentsFromCurvature(points, curvatureSamples);

    var refinedSegments = _refineSegments(rawSegments, points);

    final sectors = <RoadSector>[];
    for (final seg in refinedSegments) {
      final isStraight = seg.type == 'S';
      final radiusInfo = _calculateRadiusInfo(
        points,
        seg.startIndex,
        seg.endIndex,
      );
      final totalHeadingChange = _calculateTotalHeadingChange(
        points,
        seg.startIndex,
        seg.endIndex,
      );

      final type = isStraight
          ? RoadSectorType.straight
          : (seg.type == 'L'
                ? RoadSectorType.leftCurve
                : RoadSectorType.rightCurve);

      sectors.add(
        RoadSector(
          id: 'sector_${type.name}_${seg.startDistance.round()}',
          type: type,
          startDistance: seg.startDistance,
          endDistance: seg.endDistance,
          lengthMeters: seg.length,
          totalHeadingChange: totalHeadingChange,
          averageCurvature:
              totalHeadingChange.abs() / math.max(1.0, seg.length),
          peakCurvature: radiusInfo.minRadius < 9999.0
              ? 1.0 / radiusInfo.minRadius
              : 0.0,
          approximateRadiusMeters: radiusInfo.minRadius,
          confidence: 1.0,
          modifiers: const [],
          matchedEdgeIndexes: const [],
          context: const {},
        ),
      );
    }

    final notes = <PaceNote>[];
    var noteCount = 0;

    for (final sector in sectors) {
      if (sector.type == RoadSectorType.straight) {
        if (sector.length >= 100.0) {
          final roundedDist = (sector.length / 50.0).round() * 50;
          final distToShow = roundedDist < 100
              ? (sector.length / 10.0).round() * 10
              : roundedDist;
          notes.add(
            PaceNote(
              id: 'note-straight-$noteCount-${sector.startDistance.round()}',
              distanceFromStart: sector.startDistance,
              startDistance: sector.startDistance,
              endDistance: sector.endDistance,
              direction: 'straight',
              severity: 0,
              type: PaceNoteType.straight,
              text: 'straight $distToShow',
              distanceMeters: distToShow,
            ),
          );
          noteCount++;
        }
      } else {
        final direction = sector.type == RoadSectorType.leftCurve
            ? 'left'
            : 'right';
        final radius = sector.approximateRadiusMeters ?? 9999.0;
        final totalHeadingChange = sector.averageCurvature * sector.length;

        int severity = 6;
        bool isHairpin = false;

        final h1 = _style == PacenoteStyle.calm
            ? 18.0
            : (_style == PacenoteStyle.rally ? 26.0 : 22.0);
        final h2 = _style == PacenoteStyle.calm
            ? 32.0
            : (_style == PacenoteStyle.rally ? 44.0 : 38.0);
        final h3 = _style == PacenoteStyle.calm
            ? 48.0
            : (_style == PacenoteStyle.rally ? 66.0 : 58.0);
        final h4 = _style == PacenoteStyle.calm
            ? 70.0
            : (_style == PacenoteStyle.rally ? 95.0 : 85.0);
        final h5 = _style == PacenoteStyle.calm
            ? 100.0
            : (_style == PacenoteStyle.rally ? 140.0 : 125.0);

        if (_hasConservativeHairpinEvidence(
          points,
          sector.startDistance,
          sector.endDistance,
          direction,
          radius,
          totalHeadingChange,
        )) {
          isHairpin = true;
          severity = 1;
        } else if (radius < h1) {
          severity = 1;
        } else if (radius < h2) {
          severity = 2;
        } else if (radius < h3) {
          severity = 3;
        } else if (radius < h4) {
          severity = 4;
        } else if (radius < h5) {
          severity = 5;
        } else {
          severity = 6;
        }

        if (_style == PacenoteStyle.calm && severity >= 5) {
          continue;
        }

        final midIdx = _indexNearDistance(
          points,
          sector.startDistance + sector.length / 2.0,
        );
        final firstHalfRadius = _calculateRadiusInfo(
          points,
          _indexNearDistance(points, sector.startDistance),
          midIdx,
        ).avgRadius;
        final secondHalfRadius = _calculateRadiusInfo(
          points,
          midIdx,
          _indexNearDistance(points, sector.endDistance),
        ).avgRadius;

        bool tightens = false;
        bool opens = false;
        if (secondHalfRadius < firstHalfRadius * 0.75) {
          tightens = true;
        } else if (firstHalfRadius < secondHalfRadius * 0.75) {
          opens = true;
        }

        final isShort = sector.length < 35.0;
        final isLong = sector.length > 100.0;

        int baseSpeed = 90;
        switch (severity) {
          case 1:
            baseSpeed = 25;
            break;
          case 2:
            baseSpeed = 35;
            break;
          case 3:
            baseSpeed = 45;
            break;
          case 4:
            baseSpeed = 60;
            break;
          case 5:
            baseSpeed = 75;
            break;
          case 6:
            baseSpeed = 90;
            break;
        }

        int recommendedSpeed = baseSpeed;
        if (baseSpeed <= 45) {
          recommendedSpeed = baseSpeed - 5;
        } else {
          recommendedSpeed = baseSpeed - 10;
        }

        final noteType = isHairpin
            ? (direction == 'left'
                  ? PaceNoteType.hairpinLeft
                  : PaceNoteType.hairpinRight)
            : (direction == 'left' ? PaceNoteType.left : PaceNoteType.right);

        notes.add(
          PaceNote(
            id: 'note-curve-$noteCount-${sector.startDistance.round()}',
            distanceFromStart: sector.startDistance,
            startDistance: sector.startDistance,
            endDistance: sector.endDistance,
            direction: direction,
            severity: severity,
            type: noteType,
            tightens: tightens,
            opens: opens,
            text: '',
            recommendedSpeedKmh: recommendedSpeed,
            isShort: isShort,
            isLong: isLong,
          ),
        );
        noteCount++;
      }
    }

    final sequenceNotes = _splitLongCurveNotesWithValleys(notes, points);
    final linkedNotes = <PaceNote>[];
    for (var i = 0; i < sequenceNotes.length; i++) {
      var note = sequenceNotes[i];
      if (i < sequenceNotes.length - 1) {
        final next = sequenceNotes[i + 1];
        final gap = next.distanceFromStart - note.distanceFromStart;

        final canLinkSelf =
            note.type == PaceNoteType.left ||
            note.type == PaceNoteType.right ||
            note.type == PaceNoteType.hairpinLeft ||
            note.type == PaceNoteType.hairpinRight ||
            note.type == PaceNoteType.keepLeft ||
            note.type == PaceNoteType.keepRight ||
            note.type == PaceNoteType.straight;

        final canLinkNext =
            next.type == PaceNoteType.left ||
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

    if (maneuvers.isEmpty) {
      return linkedNotes;
    }

    return const RouteSemanticEngine()
        .analyzePacenotes(
          notes: linkedNotes,
          routePoints: points,
          warnings: const [],
          speedLimits: const [],
          maneuvers: maneuvers,
          config: RouteAnalysisConfig(style: _style),
        )
        .pacenotes;
  }

  List<PaceNote> _splitLongCurveNotesWithValleys(
    List<PaceNote> notes,
    List<RoutePoint> points,
  ) {
    final result = <PaceNote>[];
    for (final note in notes) {
      if ((note.type != PaceNoteType.left && note.type != PaceNoteType.right) ||
          (note.endDistance ?? note.distanceFromStart) -
                  (note.startDistance ?? note.distanceFromStart) <
              85.0) {
        result.add(note);
        continue;
      }
      final split = _findStableHeadingValley(
        points,
        note.startDistance ?? note.distanceFromStart,
        note.endDistance ?? note.distanceFromStart,
      );
      if (split == null) {
        result.add(note);
        continue;
      }
      final (gapStart, gapEnd) = split;
      final firstLength =
          points[gapStart].distanceFromStart -
          (note.startDistance ?? note.distanceFromStart);
      final secondLength =
          (note.endDistance ?? note.distanceFromStart) -
          points[gapEnd].distanceFromStart;
      if (firstLength < 15.0 || secondLength < 15.0) {
        result.add(note);
        continue;
      }
      result
        ..add(
          note.copyWith(
            id: '${note.id}-a',
            endDistance: points[gapStart].distanceFromStart,
            tightens: false,
            opens: false,
            isLong: firstLength > 100.0,
            isShort: firstLength < 35.0,
          ),
        )
        ..add(
          note.copyWith(
            id: '${note.id}-b',
            distanceFromStart: points[gapEnd].distanceFromStart,
            startDistance: points[gapEnd].distanceFromStart,
            tightens: false,
            opens: false,
            isLong: secondLength > 100.0,
            isShort: secondLength < 35.0,
          ),
        );
    }
    return result;
  }

  (int, int)? _findStableHeadingValley(
    List<RoutePoint> points,
    double startDistance,
    double endDistance,
  ) {
    final start = _indexNearDistance(points, startDistance);
    final end = _indexNearDistance(points, endDistance);
    int? bestStart;
    int? bestEnd;
    var bestLength = 0.0;
    int? runStart;
    for (var i = start + 2; i <= end - 2; i++) {
      if (_stepHeadingDeltaAbs(points, i) <= 0.9) {
        runStart ??= i;
      } else if (runStart != null) {
        final runEnd = i - 1;
        final length =
            points[runEnd].distanceFromStart -
            points[runStart].distanceFromStart;
        if (length > bestLength) {
          bestLength = length;
          bestStart = runStart;
          bestEnd = runEnd;
        }
        runStart = null;
      }
    }
    if (runStart != null) {
      final runEnd = end - 2;
      final length =
          points[runEnd].distanceFromStart - points[runStart].distanceFromStart;
      if (length > bestLength) {
        bestLength = length;
        bestStart = runStart;
        bestEnd = runEnd;
      }
    }
    if (bestStart == null || bestEnd == null || bestLength < 8.0) {
      return null;
    }
    final beforeHeading = _calculateTotalHeadingChange(
      points,
      start,
      bestStart,
    ).abs();
    final afterHeading = _calculateTotalHeadingChange(
      points,
      bestEnd,
      end,
    ).abs();
    if (beforeHeading < 8.0 || afterHeading < 8.0) {
      return null;
    }
    return (bestStart, bestEnd);
  }

  List<PaceNote> refinePacenotesWithRoadContext({
    required List<PaceNote> notes,
    required List<RoutePoint> routePoints,
    required List<RoadWarning> warnings,
    required List<SpeedLimitSegment> speedLimits,
  }) {
    final analysis = const RouteSemanticEngine().analyzePacenotes(
      notes: notes,
      routePoints: routePoints,
      warnings: warnings,
      speedLimits: speedLimits,
      config: RouteAnalysisConfig(style: _style),
    );
    assert(() {
      developer.log(
        'Pacenotes refined by semantic engine: raw=${notes.length}, accepted=${analysis.diagnostics.acceptedCandidates}, rejected=${analysis.diagnostics.rejectedCandidates}, inserted=${analysis.diagnostics.insertedNotes}, converted=${analysis.diagnostics.convertedNotes}, downgradedHairpins=${analysis.diagnostics.downgradedHairpins}, final=${analysis.pacenotes.length}, warnings=${warnings.length}',
      );
      return true;
    }());

    return analysis.pacenotes;
  }

  List<RoadWarning> detectElevationFeatures(List<RoutePoint> points) {
    final warnings = <RoadWarning>[];
    if (points.length < 20) return warnings;

    // Dual-pass Gaussian-weighted smoothing to clean up raw ORS elevation profiles
    final smoothed = <double>[];
    const sigma = 5.0;
    const window = 12; // ~120m search window
    for (var i = 0; i < points.length; i++) {
      if (points[i].elevation == null) {
        smoothed.add(0.0);
        continue;
      }
      var weightedSum = 0.0;
      var weightSum = 0.0;
      for (var j = i - window; j <= i + window; j++) {
        if (j >= 0 && j < points.length && points[j].elevation != null) {
          final dist = (j - i).abs();
          final w = math.exp(-(dist * dist) / (2 * sigma * sigma));
          weightedSum += points[j].elevation! * w;
          weightSum += w;
        }
      }
      smoothed.add(
        weightSum > 0 ? weightedSum / weightSum : points[i].elevation!,
      );
    }

    // Peak and valley detection using local search window
    const lookahead = 12; // Search +/- 60m to confirm crest/dip
    for (var i = lookahead; i < points.length - lookahead; i++) {
      final currentElev = smoothed[i];
      if (points[i].elevation == null) continue;

      // 1. Check Peak (Crest)
      bool isPeak = true;
      for (var j = i - lookahead; j <= i + lookahead; j++) {
        if (smoothed[j] > currentElev + 0.0001) {
          isPeak = false;
          break;
        }
      }
      if (isPeak) {
        final diffBefore = currentElev - smoothed[i - lookahead];
        final diffAfter = currentElev - smoothed[i + lookahead];

        // Compute slope gradient
        final distBefore =
            points[i].distanceFromStart -
            points[i - lookahead].distanceFromStart;
        final distAfter =
            points[i + lookahead].distanceFromStart -
            points[i].distanceFromStart;

        final slopeBefore = distBefore > 0 ? diffBefore / distBefore : 0.0;
        final slopeAfter = distAfter > 0 ? diffAfter / distAfter : 0.0;
        final slopeChange =
            (slopeBefore + slopeAfter) * 100.0; // total percentage change

        // Required threshold: elevation rise/fall of >= 1.2m and slope change >= 3.0%
        if (diffBefore >= 1.2 && diffAfter >= 1.2 && slopeChange >= 3.0) {
          final pt = points[i];
          final isSevere =
              slopeChange >= 7.0 || (diffBefore >= 2.5 && diffAfter >= 2.5);

          warnings.add(
            RoadWarning(
              id: 'crest-${pt.distanceFromStart.round()}',
              type: RoadWarningType.crest,
              lat: pt.lat,
              lon: pt.lon,
              distanceFromStart: pt.distanceFromStart,
              text: isSevere ? 'Blind Crest' : 'Crest',
            ),
          );
          i += lookahead; // Skip to avoid duplicate detections
          continue;
        }
      }

      // 2. Check Valley (Dip)
      bool isValley = true;
      for (var j = i - lookahead; j <= i + lookahead; j++) {
        if (smoothed[j] < currentElev - 0.0001) {
          isValley = false;
          break;
        }
      }
      if (isValley) {
        final diffBefore = smoothed[i - lookahead] - currentElev;
        final diffAfter = smoothed[i + lookahead] - currentElev;

        // Compute slope gradient
        final distBefore =
            points[i].distanceFromStart -
            points[i - lookahead].distanceFromStart;
        final distAfter =
            points[i + lookahead].distanceFromStart -
            points[i].distanceFromStart;

        final slopeBefore = distBefore > 0 ? diffBefore / distBefore : 0.0;
        final slopeAfter = distAfter > 0 ? diffAfter / distAfter : 0.0;
        final slopeChange =
            (slopeBefore + slopeAfter) * 100.0; // total percentage change

        // Required threshold: elevation fall/rise of >= 1.2m and slope change >= 3.0%
        if (diffBefore >= 1.2 && diffAfter >= 1.2 && slopeChange >= 3.0) {
          final pt = points[i];
          final isSevere =
              slopeChange >= 7.0 || (diffBefore >= 2.5 && diffAfter >= 2.5);

          warnings.add(
            RoadWarning(
              id: 'dip-${pt.distanceFromStart.round()}',
              type: RoadWarningType.dip,
              lat: pt.lat,
              lon: pt.lon,
              distanceFromStart: pt.distanceFromStart,
              text: isSevere ? 'Severe Dip' : 'Dip',
            ),
          );
          i += lookahead;
          continue;
        }
      }
    }
    return warnings;
  }

  int _indexNearDistance(List<RoutePoint> points, double targetDistance) {
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

  List<MultiScaleCurvatureSample> _buildMultiScaleCurvatureSamples(
    List<RoutePoint> points,
    List<double> smoothedHeadings,
  ) {
    return [
      for (var i = 0; i < points.length; i++)
        _curvatureSampleAt(points, smoothedHeadings, i),
    ];
  }

  MultiScaleCurvatureSample _curvatureSampleAt(
    List<RoutePoint> points,
    List<double> smoothedHeadings,
    int index,
  ) {
    final local = _headingDeltaAndSpan(points, smoothedHeadings, index, 12.0);
    final medium = _headingDeltaAndSpan(points, smoothedHeadings, index, 35.0);
    final broad = _headingDeltaAndSpan(points, smoothedHeadings, index, 85.0);
    return MultiScaleCurvatureSample(
      distanceFromStart: points[index].distanceFromStart,
      localCurvature: _signedCurvature(local.deltaDegrees, local.spanMeters),
      mediumCurvature: _signedCurvature(medium.deltaDegrees, medium.spanMeters),
      broadCurvature: _signedCurvature(broad.deltaDegrees, broad.spanMeters),
      localHeadingDelta: local.deltaDegrees,
      mediumHeadingDelta: medium.deltaDegrees,
      broadHeadingDelta: broad.deltaDegrees,
    );
  }

  _HeadingWindow _headingDeltaAndSpan(
    List<RoutePoint> points,
    List<double> headings,
    int index,
    double halfWindowMeters,
  ) {
    final before = _indexNearDistance(
      points,
      points[index].distanceFromStart - halfWindowMeters,
    );
    final after = _indexNearDistance(
      points,
      points[index].distanceFromStart + halfWindowMeters,
    );
    final span =
        points[after].distanceFromStart - points[before].distanceFromStart;
    return _HeadingWindow(
      deltaDegrees: normalizeAngleDeltaDegrees(
        headings[before],
        headings[after],
      ),
      spanMeters: math.max(1.0, span),
    );
  }

  double _signedCurvature(double deltaDegrees, double spanMeters) {
    return (deltaDegrees * math.pi / 180.0) / math.max(1.0, spanMeters);
  }

  List<_RouteSegment> _buildRawSegmentsFromCurvature(
    List<RoutePoint> points,
    List<MultiScaleCurvatureSample> samples,
  ) {
    if (points.isEmpty || samples.isEmpty) {
      return const [];
    }

    final directions = samples.map(_directionForSample).toList();
    final segments = <_RouteSegment>[];
    var currentType = directions.first;
    var startIdx = 0;
    for (var i = 1; i < directions.length; i++) {
      if (directions[i] != currentType) {
        segments.add(
          _RouteSegment(
            type: currentType,
            startIndex: startIdx,
            endIndex: i - 1,
            startDistance: points[startIdx].distanceFromStart,
            endDistance: points[i - 1].distanceFromStart,
          ),
        );
        currentType = directions[i];
        startIdx = i;
      }
    }
    segments.add(
      _RouteSegment(
        type: currentType,
        startIndex: startIdx,
        endIndex: points.length - 1,
        startDistance: points[startIdx].distanceFromStart,
        endDistance: points.last.distanceFromStart,
      ),
    );
    return segments;
  }

  String _directionForSample(MultiScaleCurvatureSample sample) {
    final curveRadiusThreshold = switch (_style) {
      PacenoteStyle.calm => 140.0,
      PacenoteStyle.balanced => 180.0,
      PacenoteStyle.rally => 220.0,
    };
    final minCurvature = 1.0 / curveRadiusThreshold;
    final localSignal = sample.localCurvature.abs();
    final dominant =
        localSignal >= minCurvature * 0.72 &&
            sample.localHeadingDelta.abs() >= 3.5
        ? sample.localCurvature
        : sample.mediumCurvature;

    if (dominant.abs() < minCurvature ||
        (sample.localHeadingDelta.abs() < 3.0 &&
            sample.mediumHeadingDelta.abs() < 7.0)) {
      return 'S';
    }
    return dominant < 0 ? 'L' : 'R';
  }

  List<_RouteSegment> _refineSegments(
    List<_RouteSegment> input,
    List<RoutePoint> points,
  ) {
    var list = List<_RouteSegment>.from(input);

    list = _mergeConsecutiveSameType(list);
    list = _splitSegmentsAtInternalValleys(list, points);

    for (var i = 0; i < list.length; i++) {
      if ((list[i].type == 'L' || list[i].type == 'R') &&
          list[i].length < 15.0) {
        list[i].type = 'S';
      }
    }
    list = _mergeConsecutiveSameType(list);
    list = _splitSegmentsAtInternalValleys(list, points);

    bool changed = true;
    while (changed) {
      changed = false;
      final merged = <_RouteSegment>[];
      for (var i = 0; i < list.length; i++) {
        if (i < list.length - 2 &&
            list[i].type != 'S' &&
            list[i + 1].type == 'S' &&
            !list[i + 1].preserveBoundary &&
            list[i + 1].length < 35.0 &&
            list[i + 2].type == list[i].type &&
            _shouldMergeSameDirectionAcrossGap(
              points,
              list[i],
              list[i + 1],
              list[i + 2],
            )) {
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
        final totalHeadingChange = _calculateTotalHeadingChange(
          points,
          seg.startIndex,
          seg.endIndex,
        );
        if (totalHeadingChange.abs() < 12.0) {
          seg.type = 'S';
        }
      }
    }
    list = _mergeConsecutiveSameType(list);

    for (var i = 0; i < list.length; i++) {
      final seg = list[i];
      if (seg.type == 'L' || seg.type == 'R') {
        final radiusInfo = _calculateRadiusInfo(
          points,
          seg.startIndex,
          seg.endIndex,
        );
        final totalHeadingChange = _calculateTotalHeadingChange(
          points,
          seg.startIndex,
          seg.endIndex,
        );

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
          final isRealCurve =
              seg.length >= 20.0 && totalHeadingChange.abs() >= 10.0;
          if (!isRealCurve) {
            seg.type = 'S';
          }
        }
      }
    }
    list = _mergeConsecutiveSameType(list);

    return list;
  }

  List<_RouteSegment> _splitSegmentsAtInternalValleys(
    List<_RouteSegment> input,
    List<RoutePoint> points,
  ) {
    final output = <_RouteSegment>[];
    for (final segment in input) {
      if (segment.type == 'S' || segment.length < 65.0) {
        output.add(segment);
        continue;
      }
      final split = _findInternalValleySplit(segment, points);
      if (split == null) {
        output.add(segment);
        continue;
      }
      final (gapStart, gapEnd) = split;
      output
        ..add(
          _RouteSegment(
            type: segment.type,
            startIndex: segment.startIndex,
            endIndex: gapStart,
            startDistance: segment.startDistance,
            endDistance: points[gapStart].distanceFromStart,
          ),
        )
        ..add(
          _RouteSegment(
            type: 'S',
            startIndex: gapStart,
            endIndex: gapEnd,
            startDistance: points[gapStart].distanceFromStart,
            endDistance: points[gapEnd].distanceFromStart,
            preserveBoundary: true,
          ),
        )
        ..add(
          _RouteSegment(
            type: segment.type,
            startIndex: gapEnd,
            endIndex: segment.endIndex,
            startDistance: points[gapEnd].distanceFromStart,
            endDistance: segment.endDistance,
          ),
        );
    }
    return output;
  }

  (int, int)? _findInternalValleySplit(
    _RouteSegment segment,
    List<RoutePoint> points,
  ) {
    final peak = _segmentPeakCurvature(points, segment);
    if (peak <= 0.0001) {
      return null;
    }
    final valleyLimit = math.max(peak * 0.28, 1.0 / 520.0);
    int? bestStart;
    int? bestEnd;
    var bestLength = 0.0;
    int? runStart;

    for (var i = segment.startIndex + 2; i <= segment.endIndex - 2; i++) {
      final local = _localAbsCurvature(points, i, 5.0);
      final stabilizedHeading = _stepHeadingDeltaAbs(points, i) <= 0.9;
      if (local <= valleyLimit || stabilizedHeading) {
        runStart ??= i;
      } else if (runStart != null) {
        final runEnd = i - 1;
        final length =
            points[runEnd].distanceFromStart -
            points[runStart].distanceFromStart;
        if (length > bestLength) {
          bestLength = length;
          bestStart = runStart;
          bestEnd = runEnd;
        }
        runStart = null;
      }
    }
    if (runStart != null) {
      final runEnd = segment.endIndex - 2;
      final length =
          points[runEnd].distanceFromStart - points[runStart].distanceFromStart;
      if (length > bestLength) {
        bestLength = length;
        bestStart = runStart;
        bestEnd = runEnd;
      }
    }
    if (bestStart == null || bestEnd == null || bestLength < 8.0) {
      return null;
    }

    final beforeHeading = _calculateTotalHeadingChange(
      points,
      segment.startIndex,
      bestStart,
    ).abs();
    final afterHeading = _calculateTotalHeadingChange(
      points,
      bestEnd,
      segment.endIndex,
    ).abs();
    if (beforeHeading < 8.0 || afterHeading < 8.0) {
      return null;
    }
    return (bestStart, bestEnd);
  }

  bool _shouldMergeSameDirectionAcrossGap(
    List<RoutePoint> points,
    _RouteSegment first,
    _RouteSegment gap,
    _RouteSegment second,
  ) {
    if (gap.length < 8.0) {
      return true;
    }
    final firstPeak = _segmentPeakCurvature(points, first);
    final secondPeak = _segmentPeakCurvature(points, second);
    final gapPeak = _segmentPeakCurvature(points, gap);
    final neighbourPeak = math.min(firstPeak, secondPeak);
    if (neighbourPeak <= 0.0001) {
      return true;
    }
    final valleyRatio = gapPeak / neighbourPeak;
    final severityDelta =
        (_severityForRadius(
                  _calculateRadiusInfo(
                    points,
                    first.startIndex,
                    first.endIndex,
                  ).minRadius,
                ) -
                _severityForRadius(
                  _calculateRadiusInfo(
                    points,
                    second.startIndex,
                    second.endIndex,
                  ).minRadius,
                ))
            .abs();
    final decision = CurveSplitDecision(
      shouldSplit:
          gap.length >= 8.0 && valleyRatio <= 0.28 || severityDelta >= 2,
      confidence: (1.0 - valleyRatio).clamp(0.0, 1.0),
      reason:
          'valleyRatio=${valleyRatio.toStringAsFixed(2)}, gap=${gap.length.toStringAsFixed(1)}m',
    );
    return !decision.shouldSplit;
  }

  double _segmentPeakCurvature(List<RoutePoint> points, _RouteSegment segment) {
    if (segment.endIndex <= segment.startIndex) {
      return 0.0;
    }
    var peak = 0.0;
    for (var i = segment.startIndex; i <= segment.endIndex; i++) {
      final before = _indexNearDistance(
        points,
        points[i].distanceFromStart - 10.0,
      );
      final after = _indexNearDistance(
        points,
        points[i].distanceFromStart + 10.0,
      );
      final span =
          points[after].distanceFromStart - points[before].distanceFromStart;
      if (span <= 0) {
        continue;
      }
      final delta = normalizeAngleDeltaDegrees(
        points[before].heading,
        points[after].heading,
      );
      peak = math.max(peak, (delta * math.pi / 180.0 / span).abs());
    }
    return peak;
  }

  double _localAbsCurvature(
    List<RoutePoint> points,
    int index,
    double halfWindowMeters,
  ) {
    final before = _indexNearDistance(
      points,
      points[index].distanceFromStart - halfWindowMeters,
    );
    final after = _indexNearDistance(
      points,
      points[index].distanceFromStart + halfWindowMeters,
    );
    final span =
        points[after].distanceFromStart - points[before].distanceFromStart;
    if (span <= 0) {
      return 0.0;
    }
    final delta = normalizeAngleDeltaDegrees(
      points[before].heading,
      points[after].heading,
    );
    return (delta * math.pi / 180.0 / span).abs();
  }

  double _stepHeadingDeltaAbs(List<RoutePoint> points, int index) {
    if (index <= 0 || index >= points.length - 1) {
      return double.infinity;
    }
    final before = normalizeAngleDeltaDegrees(
      points[index - 1].heading,
      points[index].heading,
    ).abs();
    final after = normalizeAngleDeltaDegrees(
      points[index].heading,
      points[index + 1].heading,
    ).abs();
    return math.max(before, after);
  }

  int _severityForRadius(double radius) {
    if (radius < 22.0) return 1;
    if (radius < 38.0) return 2;
    if (radius < 58.0) return 3;
    if (radius < 85.0) return 4;
    if (radius < 125.0) return 5;
    return 6;
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
        current.preserveBoundary =
            current.preserveBoundary || next.preserveBoundary;
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
    return merged;
  }

  double _calculateTotalHeadingChange(
    List<RoutePoint> points,
    int start,
    int end,
  ) {
    double sum = 0.0;
    for (var i = start; i < end; i++) {
      sum += normalizeAngleDeltaDegrees(
        points[i].heading,
        points[i + 1].heading,
      );
    }
    return sum;
  }

  _RadiusInfo _calculateRadiusInfo(
    List<RoutePoint> points,
    int start,
    int end,
  ) {
    double minRadius = double.infinity;
    double sumRadius = 0.0;
    int count = 0;

    final segLength =
        points[end].distanceFromStart - points[start].distanceFromStart;
    final halfWindow = math.min(10.0, segLength / 2.0);

    for (var i = start; i <= end; i++) {
      final before = _indexNearDistance(
        points,
        points[i].distanceFromStart - halfWindow,
      );
      final after = _indexNearDistance(
        points,
        points[i].distanceFromStart + halfWindow,
      );
      final distDiff =
          points[after].distanceFromStart - points[before].distanceFromStart;
      if (distDiff > 0) {
        final delta = normalizeAngleDeltaDegrees(
          points[before].heading,
          points[after].heading,
        );
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

  bool _hasConservativeHairpinEvidence(
    List<RoutePoint> points,
    double startDistance,
    double endDistance,
    String direction,
    double radius,
    double totalHeadingChange,
  ) {
    if (points.length < 5 ||
        radius > 18.0 ||
        totalHeadingChange.abs() < 145.0) {
      return false;
    }

    final start = _indexNearDistance(points, startDistance);
    final end = _indexNearDistance(points, endDistance);
    if (end <= start + 2) {
      return false;
    }

    final length =
        points[end].distanceFromStart - points[start].distanceFromStart;
    if (length < 25.0 || length > 110.0) {
      return false;
    }

    final expectedSign = direction == 'left' ? -1 : 1;
    var sameSign = 0;
    var nonZero = 0;
    for (var i = start; i < end; i++) {
      final delta = normalizeAngleDeltaDegrees(
        points[i].heading,
        points[i + 1].heading,
      );
      if (delta.abs() < 1.0) {
        continue;
      }
      nonZero++;
      if (delta.sign.toInt() == expectedSign) {
        sameSign++;
      }
    }
    final coherence = nonZero == 0 ? 0.0 : sameSign / nonZero;
    if (coherence < 0.72) {
      return false;
    }

    final entryExitDelta = normalizeAngleDeltaDegrees(
      points[start].heading,
      points[end].heading,
    ).abs();
    if (entryExitDelta < 125.0) {
      return false;
    }

    final chord = haversineDistanceMeters(
      points[start].lat,
      points[start].lon,
      points[end].lat,
      points[end].lon,
    );
    return chord / length <= 0.72;
  }
}

class _RouteSegment {
  String type;
  int startIndex;
  int endIndex;
  double startDistance;
  double endDistance;
  bool preserveBoundary;

  _RouteSegment({
    required this.type,
    required this.startIndex,
    required this.endIndex,
    required this.startDistance,
    required this.endDistance,
    this.preserveBoundary = false,
  });

  double get length => endDistance - startDistance;
}

class _RadiusInfo {
  final double minRadius;
  final double avgRadius;
  const _RadiusInfo({required this.minRadius, required this.avgRadius});
}

class MultiScaleCurvatureSample {
  const MultiScaleCurvatureSample({
    required this.distanceFromStart,
    required this.localCurvature,
    required this.mediumCurvature,
    required this.broadCurvature,
    required this.localHeadingDelta,
    required this.mediumHeadingDelta,
    required this.broadHeadingDelta,
  });

  final double distanceFromStart;
  final double localCurvature;
  final double mediumCurvature;
  final double broadCurvature;
  final double localHeadingDelta;
  final double mediumHeadingDelta;
  final double broadHeadingDelta;
}

class CurveApex {
  const CurveApex({
    required this.distanceFromStart,
    required this.signedCurvature,
    required this.prominence,
    required this.widthMeters,
    required this.direction,
  });

  final double distanceFromStart;
  final double signedCurvature;
  final double prominence;
  final double widthMeters;
  final int direction;
}

class CurveSplitDecision {
  const CurveSplitDecision({
    required this.shouldSplit,
    required this.confidence,
    required this.reason,
  });

  final bool shouldSplit;
  final double confidence;
  final String reason;
}

class CurveSequence {
  const CurveSequence({
    required this.sectors,
    required this.startDistance,
    required this.endDistance,
    required this.isLinked,
    required this.confidence,
  });

  final List<RoadSector> sectors;
  final double startDistance;
  final double endDistance;
  final bool isLinked;
  final double confidence;
}

class _HeadingWindow {
  const _HeadingWindow({required this.deltaDegrees, required this.spanMeters});

  final double deltaDegrees;
  final double spanMeters;
}

// RoadSector and RoadSectorType are now imported from matched_route.dart
