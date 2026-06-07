import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/main.dart';
import 'package:ralroads/models/matched_route.dart';
import 'package:ralroads/models/pace_note.dart';
import 'package:ralroads/models/road_warning.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/models/speed_limit_segment.dart';
import 'package:ralroads/services/pacenote_generator.dart';
import 'package:ralroads/services/route_semantic_engine.dart';
import 'package:ralroads/services/settings_service.dart';
import 'package:ralroads/services/route_event_scorer.dart';
import 'package:ralroads/services/callout_scheduler.dart';
import 'package:ralroads/services/callout_speech_service.dart';
import 'package:ralroads/utils/ui_helpers.dart';
import 'package:flutter/foundation.dart';

void main() {
  test('smoothHeading handles wraparound', () {
    expect(smoothHeading(359, 1, 0.5), closeTo(0, 0.001));
  });

  test('roundabout warning converts severe note away from hairpin', () {
    final generator = PacenoteGenerator();
    final notes = [
      const PaceNote(
        id: 'n1',
        distanceFromStart: 100,
        direction: 'right',
        severity: 1,
        type: PaceNoteType.hairpin,
        text: 'Hairpin right',
      ),
    ];

    final refined = generator.refinePacenotesWithRoadContext(
      notes: notes,
      routePoints: const [
        RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
        RoutePoint(
          lat: 45.001,
          lon: 7.001,
          distanceFromStart: 120,
          heading: 90,
        ),
      ],
      warnings: const [
        RoadWarning(
          id: 'r1',
          type: RoadWarningType.roundabout,
          lat: 45.001,
          lon: 7.001,
          distanceFromStart: 105,
          text: 'Roundabout',
          tags: {
            'route_membership_confidence': 0.96,
            'route_membership_start': 90.0,
            'route_membership_end': 125.0,
            'route_membership_overlap': 35.0,
            'route_membership_heading_change': 90.0,
            'route_membership_close_points': 4,
          },
        ),
      ],
      speedLimits: const [],
    );

    expect(refined.single.type, PaceNoteType.roundabout);
    expect(refined.single.text, 'Roundabout ahead');
  });

  test('true hairpin stays hairpin without road context', () {
    final generator = PacenoteGenerator();
    final notes = [
      const PaceNote(
        id: 'n1',
        distanceFromStart: 40,
        startDistance: 0,
        endDistance: 80,
        direction: 'left',
        severity: 1,
        type: PaceNoteType.hairpin,
        text: 'Hairpin left',
      ),
    ];

    final refined = generator.refinePacenotesWithRoadContext(
      notes: notes,
      routePoints: const [
        RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
        RoutePoint(
          lat: 45.0001,
          lon: 7.0001,
          distanceFromStart: 20,
          heading: 315,
        ),
        RoutePoint(
          lat: 45.0002,
          lon: 7.0001,
          distanceFromStart: 40,
          heading: 270,
        ),
        RoutePoint(lat: 45.0001, lon: 7, distanceFromStart: 60, heading: 225),
        RoutePoint(lat: 45, lon: 7, distanceFromStart: 80, heading: 180),
      ],
      warnings: const [],
      speedLimits: const [],
    );

    expect(refined.single.type, PaceNoteType.hairpin);
    expect(refined.single.text, 'Hairpin left');
  });

  test(
    'broad 180 degree sweep is downgraded from hairpin to ordinary curve',
    () {
      final generator = PacenoteGenerator();
      final notes = [
        const PaceNote(
          id: 'n1',
          distanceFromStart: 180,
          startDistance: 0,
          endDistance: 360,
          direction: 'left',
          severity: 1,
          type: PaceNoteType.hairpin,
          text: 'Hairpin left',
        ),
      ];

      final refined = generator.refinePacenotesWithRoadContext(
        notes: notes,
        routePoints: const [
          RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
          RoutePoint(
            lat: 45.001,
            lon: 7.001,
            distanceFromStart: 120,
            heading: 320,
          ),
          RoutePoint(
            lat: 45.002,
            lon: 7.001,
            distanceFromStart: 240,
            heading: 260,
          ),
          RoutePoint(lat: 45.003, lon: 7, distanceFromStart: 360, heading: 180),
        ],
        warnings: const [],
        speedLimits: const [],
      );

      expect(refined.single.type, PaceNoteType.left);
    },
  );

  test('warning-only stop sign does not convert curve to junction turn', () {
    final generator = PacenoteGenerator();
    final notes = [
      const PaceNote(
        id: 'n1',
        distanceFromStart: 50,
        direction: 'left',
        severity: 3,
        type: PaceNoteType.corner,
        text: 'left 3',
      ),
    ];

    final refined = generator.refinePacenotesWithRoadContext(
      notes: notes,
      routePoints: const [
        RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
        RoutePoint(
          lat: 45.0005,
          lon: 7.0005,
          distanceFromStart: 60,
          heading: 45,
        ),
      ],
      warnings: const [
        RoadWarning(
          id: 'w1',
          type: RoadWarningType.stopSign,
          lat: 45.00045,
          lon: 7.00045,
          distanceFromStart: 52,
          text: 'Stop Sign',
        ),
      ],
      speedLimits: const [],
    );

    expect(refined.single.type, PaceNoteType.corner);
    expect(refined.single.text, 'left 3');
  });

  test(
    'traversed roundabout warning inserts note when no curve note exists',
    () {
      final generator = PacenoteGenerator();

      final refined = generator.refinePacenotesWithRoadContext(
        notes: const [],
        routePoints: const [
          RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
          RoutePoint(
            lat: 45.0005,
            lon: 7.0005,
            distanceFromStart: 100,
            heading: 90,
          ),
          RoutePoint(
            lat: 45.001,
            lon: 7.001,
            distanceFromStart: 200,
            heading: 180,
          ),
        ],
        warnings: const [
          RoadWarning(
            id: 'r2',
            type: RoadWarningType.roundabout,
            lat: 45.0005,
            lon: 7.0005,
            distanceFromStart: 100,
            text: 'Roundabout',
            tags: {
              'route_membership_confidence': 0.96,
              'route_membership_start': 90.0,
              'route_membership_end': 130.0,
              'route_membership_overlap': 40.0,
              'route_membership_heading_change': 110.0,
              'route_membership_close_points': 5,
            },
          ),
        ],
        speedLimits: const [],
      );

      expect(refined.single.type, PaceNoteType.roundabout);
      expect(refined.single.distanceFromStart, 100);
    },
  );

  test('low-membership roundabout warning is rejected', () {
    final generator = PacenoteGenerator();
    final notes = [
      const PaceNote(
        id: 'n1',
        distanceFromStart: 100,
        direction: 'right',
        severity: 2,
        type: PaceNoteType.right,
        text: 'right 2',
      ),
    ];

    final refined = generator.refinePacenotesWithRoadContext(
      notes: notes,
      routePoints: const [
        RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
        RoutePoint(
          lat: 45.0005,
          lon: 7.0005,
          distanceFromStart: 100,
          heading: 45,
        ),
      ],
      warnings: const [
        RoadWarning(
          id: 'r3',
          type: RoadWarningType.roundabout,
          lat: 45.0005,
          lon: 7.0005,
          distanceFromStart: 100,
          text: 'Roundabout',
          tags: {
            'route_membership_confidence': 0.2,
            'route_membership_start': 98.0,
            'route_membership_end': 100.0,
            'route_membership_overlap': 2.0,
          },
        ),
      ],
      speedLimits: const [],
    );

    expect(refined.single.type, PaceNoteType.right);
  });

  test('low-curvature roundabout warning is rejected as side-road anomaly', () {
    final generator = PacenoteGenerator();
    final notes = [
      const PaceNote(
        id: 'n1',
        distanceFromStart: 100,
        direction: 'straight',
        severity: 0,
        type: PaceNoteType.straight,
        text: 'straight 100',
      ),
    ];

    final refined = generator.refinePacenotesWithRoadContext(
      notes: notes,
      routePoints: const [
        RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
        RoutePoint(lat: 45.0005, lon: 7, distanceFromStart: 100, heading: 8),
        RoutePoint(
          lat: 45.001,
          lon: 7.0001,
          distanceFromStart: 200,
          heading: 12,
        ),
      ],
      warnings: const [
        RoadWarning(
          id: 'r4',
          type: RoadWarningType.roundabout,
          lat: 45.0005,
          lon: 7,
          distanceFromStart: 100,
          text: 'Roundabout',
          tags: {
            'route_membership_confidence': 0.95,
            'route_membership_start': 80.0,
            'route_membership_end': 125.0,
            'route_membership_overlap': 45.0,
            'route_membership_heading_change': 12.0,
            'route_membership_close_points': 4,
          },
        ),
      ],
      speedLimits: const [],
    );

    expect(refined.single.type, PaceNoteType.straight);
    expect(refined.single.text, 'straight 100');
  });

  test(
    'matched intersection following natural continuation remains a curve',
    () {
      const note = PaceNote(
        id: 'n1',
        distanceFromStart: 100,
        direction: 'right',
        severity: 3,
        type: PaceNoteType.right,
        text: '',
      );
      final intersection = RouteIntersection(
        id: 'i1',
        distanceFromStart: 100,
        lat: 45,
        lon: 7,
        traversedIncomingEdgeIndex: 1,
        traversedOutgoingEdgeIndex: 2,
        connectedRoads: [
          ConnectedRoad(
            osmWayId: '10',
            name: 'Main Road',
            bearing: 0,
            isTraversed: true,
            tags: {'highway': 'secondary'},
          ),
          ConnectedRoad(
            osmWayId: '10',
            name: 'Main Road',
            bearing: 12,
            isTraversed: true,
            tags: {'highway': 'secondary'},
          ),
          ConnectedRoad(
            osmWayId: '99',
            name: 'Side Road',
            bearing: 90,
            isTraversed: false,
            tags: {'highway': 'residential'},
          ),
        ],
      );

      final analysis = const RouteSemanticEngine().analyzePacenotes(
        notes: const [note],
        routePoints: const [
          RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
          RoutePoint(
            lat: 45.001,
            lon: 7.001,
            distanceFromStart: 150,
            heading: 12,
          ),
        ],
        warnings: const [],
        speedLimits: const [],
        intersections: [intersection],
      );

      expect(analysis.pacenotes.single.type, PaceNoteType.right);
    },
  );

  test('matched turn maneuver converts nearby curve to junction', () {
    const note = PaceNote(
      id: 'n1',
      distanceFromStart: 100,
      direction: 'left',
      severity: 3,
      type: PaceNoteType.left,
      text: '',
    );
    final maneuver = RouteManeuver(
      id: 'm1',
      type: RouteManeuverType.turnLeft,
      distanceFromStart: 102,
      fromEdgeIndex: 1,
      toEdgeIndex: 2,
      confidence: 0.95,
    );

    final analysis = const RouteSemanticEngine().analyzePacenotes(
      notes: const [note],
      routePoints: const [
        RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
        RoutePoint(
          lat: 45.001,
          lon: 7.001,
          distanceFromStart: 150,
          heading: 270,
        ),
      ],
      warnings: const [],
      speedLimits: const [],
      maneuvers: [maneuver],
    );

    expect(analysis.pacenotes.single.type, PaceNoteType.junction);
    expect(
      displayTextForPaceNote(analysis.pacenotes.single),
      'At junction, left',
    );
  });

  test('matched roundabout maneuver inserts roundabout note', () {
    final maneuver = RouteManeuver(
      id: 'm-rab',
      type: RouteManeuverType.enterRoundabout,
      distanceFromStart: 100,
      fromEdgeIndex: 1,
      toEdgeIndex: 2,
      roundaboutExit: 2,
      confidence: 0.98,
    );

    final analysis = const RouteSemanticEngine().analyzePacenotes(
      notes: const [],
      routePoints: const [
        RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
        RoutePoint(
          lat: 45.0005,
          lon: 7.0005,
          distanceFromStart: 100,
          heading: 90,
        ),
        RoutePoint(
          lat: 45.001,
          lon: 7.001,
          distanceFromStart: 200,
          heading: 180,
        ),
      ],
      warnings: const [],
      speedLimits: const [],
      maneuvers: [maneuver],
    );

    expect(analysis.pacenotes.single.type, PaceNoteType.roundabout);
    expect(
      displayTextForPaceNote(analysis.pacenotes.single),
      contains('2nd exit'),
    );
  });

  test('top HUD display helper falls back to canonical rally text', () {
    const note = PaceNote(
      id: 'n1',
      distanceFromStart: 100,
      direction: 'right',
      severity: 3,
      type: PaceNoteType.right,
      text: '',
      tightens: true,
      recommendedSpeedKmh: 45,
    );

    expect(displayTextForPaceNote(note), 'right 3 tightens');
    expect(secondaryTextForPaceNote(note, 120), contains('In 120 m'));
    expect(secondaryTextForPaceNote(note, 120), contains('45 km/h'));
  });

  test('right left right winding section creates three curve notes', () {
    final generator = PacenoteGenerator();
    final points = _PathBuilder()
        .arc(0, 52, 45)
        .arc(52, -28, 45)
        .arc(-28, 36, 45)
        .build();

    final notes = generator
        .generate(points)
        .where(
          (note) =>
              note.type == PaceNoteType.left || note.type == PaceNoteType.right,
        )
        .toList();

    expect(notes.length, greaterThanOrEqualTo(3));
    expect(notes[0].type, PaceNoteType.right);
    expect(notes[1].type, PaceNoteType.left);
    expect(notes[2].type, PaceNoteType.right);
  });

  test('two same-direction corners separated by easing stay separate', () {
    final generator = PacenoteGenerator();
    final points = _PathBuilder()
        .arc(0, 45, 45)
        .straight(45, 22)
        .arc(45, 82, 45)
        .build();

    final rightNotes = generator
        .generate(points)
        .where((note) => note.type == PaceNoteType.right)
        .toList();

    expect(rightNotes.length, greaterThanOrEqualTo(2));
  });

  test('one continuous right curve remains one curve note', () {
    final generator = PacenoteGenerator();
    final points = _PathBuilder().arc(0, 85, 120).build();

    final rightNotes = generator
        .generate(points)
        .where((note) => note.type == PaceNoteType.right)
        .toList();

    expect(rightNotes.length, 1);
  });

  test('tiny noisy sign flips do not create fake s curve', () {
    final generator = PacenoteGenerator();
    final points = _PathBuilder()
        .arc(0, 3, 20)
        .arc(3, -2, 20)
        .arc(-2, 4, 20)
        .straight(4, 80)
        .build();

    final curveNotes = generator
        .generate(points)
        .where(
          (note) =>
              note.type == PaceNoteType.left || note.type == PaceNoteType.right,
        )
        .toList();

    expect(curveNotes, isEmpty);
  });

  test('straight pacenote is generated for long segments', () {
    final generator = PacenoteGenerator();
    // Create points representing a straight line of ~150 meters
    final points = <RoutePoint>[];
    for (var i = 0; i < 20; i++) {
      points.add(RoutePoint(lat: 45.0 + i * 0.0001, lon: 7.0));
    }

    final notes = generator.generate(points);
    final straightNotes = notes
        .where((n) => n.direction == 'straight')
        .toList();
    expect(straightNotes.isNotEmpty, isTrue);
    expect(straightNotes.first.text, contains('straight'));
  });

  test('advisory speed is capped by speed limit', () {
    final generator = PacenoteGenerator();
    final notes = [
      const PaceNote(
        id: 'n1',
        distanceFromStart: 50,
        direction: 'right',
        severity: 5, // typically 75 km/h
        type: PaceNoteType.corner,
        text: 'right 5',
        recommendedSpeedKmh: 75,
      ),
    ];

    // Cap with speed limit segment of 50 km/h
    final refined = generator.refinePacenotesWithRoadContext(
      notes: notes,
      routePoints: const [
        RoutePoint(lat: 45, lon: 7, distanceFromStart: 0, heading: 0),
        RoutePoint(
          lat: 45.0005,
          lon: 7.0005,
          distanceFromStart: 60,
          heading: 45,
        ),
      ],
      warnings: const [],
      speedLimits: const [
        SpeedLimitSegment(
          id: 's1',
          startDistance: 0,
          endDistance: 100,
          rawMaxspeed: '50',
          parsedKmh: 50,
        ),
      ],
    );

    expect(refined.single.recommendedSpeedKmh, equals(50));
  });

  test('severity 6 wiggles are filtered out and merged into straights', () {
    final generator = PacenoteGenerator();

    // We create a route with a mild bend (severity 6 radius ~150m) of short length (~30m)
    // and no sharp corner nearby.
    final points = <RoutePoint>[];
    for (var i = 0; i < 30; i++) {
      final dist = i * 7.0;
      final double latOffset = i < 10 ? 0.0 : (i - 10) * 0.00002;
      points.add(
        RoutePoint(
          lat: 45.0 + i * 0.00006 + latOffset,
          lon: 7.0,
          distanceFromStart: dist,
        ),
      );
    }

    final notes = generator.generate(points);
    // Since severity 6 note is filtered, the entire segment should just merge into straights
    // or not produce any severity 6 corner note.
    final corners = notes
        .where(
          (n) =>
              n.type == PaceNoteType.corner ||
              n.type == PaceNoteType.left ||
              n.type == PaceNoteType.right,
        )
        .toList();
    for (final corner in corners) {
      expect(corner.severity, isNot(6));
    }
  });

  test('PacenoteGenerator handles Calm, Balanced, and Rally styles', () {
    final points = <RoutePoint>[];
    for (var i = 0; i < 30; i++) {
      points.add(
        RoutePoint(
          lat: 45.0 + math.sin(i * 0.08) * 0.0003,
          lon: 7.0 + i * 0.0001,
        ),
      );
    }

    final calmGenerator = PacenoteGenerator(
      settings: FakeSettingsService(PacenoteStyle.calm),
    );
    final balancedGenerator = PacenoteGenerator(
      settings: FakeSettingsService(PacenoteStyle.balanced),
    );
    final rallyGenerator = PacenoteGenerator(
      settings: FakeSettingsService(PacenoteStyle.rally),
    );

    final calmNotes = calmGenerator.generate(points);
    final balancedNotes = balancedGenerator.generate(points);
    final rallyNotes = rallyGenerator.generate(points);

    expect(rallyNotes.length, greaterThanOrEqualTo(balancedNotes.length));
    expect(balancedNotes.length, greaterThanOrEqualTo(calmNotes.length));
  });

  test('RouteEventScorer scores curves and warnings properly by mode', () {
    const sharpCurve = PaceNote(
      id: 'c1',
      distanceFromStart: 100,
      direction: 'left',
      severity: 1,
      type: PaceNoteType.corner,
      text: 'left 1',
    );
    const mildCurve = PaceNote(
      id: 'c2',
      distanceFromStart: 200,
      direction: 'right',
      severity: 5,
      type: PaceNoteType.corner,
      text: 'right 5',
    );

    // Calm mode
    final sharpCalm = RouteEventScorer.scorePaceNote(
      sharpCurve,
      80.0,
      50.0,
      'calm',
    );
    final mildCalm = RouteEventScorer.scorePaceNote(
      mildCurve,
      80.0,
      50.0,
      'calm',
    );
    expect(sharpCalm.finalScore, greaterThan(mildCalm.finalScore));
    expect(mildCalm.speechValue, lessThan(0.3));

    // Rally mode
    final mildRally = RouteEventScorer.scorePaceNote(
      mildCurve,
      80.0,
      50.0,
      'rally',
    );
    expect(mildRally.speechValue, greaterThan(mildCalm.speechValue));
  });

  test(
    'CalloutScheduler merges PaceNote and RoadWarning with over template',
    () {
      final speechService = FakeCalloutSpeechService();
      final scheduler = CalloutScheduler(
        speechService: speechService,
        settings: FakeSettingsService(PacenoteStyle.rally),
      );

      final notes = [
        const PaceNote(
          id: 'n1',
          distanceFromStart: 50,
          direction: 'left',
          severity: 3,
          type: PaceNoteType.corner,
          text: 'left 3',
        ),
      ];
      final warnings = [
        const RoadWarning(
          id: 'w1',
          type: RoadWarningType.crest,
          lat: 45.0,
          lon: 7.0,
          distanceFromStart: 70,
          text: 'Crest',
        ),
      ];

      speechService.speak('busy', () {});
      scheduler.loadRouteData(notes: notes, warnings: warnings);
      scheduler.update(40.0, 20.0);

      expect(scheduler.queue.length, equals(1));
      expect(scheduler.queue.first.text, contains('crest into left 3'));
    },
  );

  test('CalloutScheduler prunes queue when density exceeds 90%', () {
    final speechService = FakeCalloutSpeechService();
    final scheduler = CalloutScheduler(
      speechService: speechService,
      settings: FakeSettingsService(PacenoteStyle.rally),
    );

    final notes = [
      const PaceNote(
        id: 'n1',
        distanceFromStart: 50,
        direction: 'left',
        severity: 1,
        type: PaceNoteType.corner,
        text: 'left 1',
      ),
      const PaceNote(
        id: 'n2',
        distanceFromStart: 55,
        direction: 'right',
        severity: 5,
        type: PaceNoteType.corner,
        text: 'right 5',
      ),
      const PaceNote(
        id: 'n3',
        distanceFromStart: 60,
        direction: 'left',
        severity: 6,
        type: PaceNoteType.corner,
        text: 'left 6',
      ),
      const PaceNote(
        id: 'n4',
        distanceFromStart: 65,
        direction: 'right',
        severity: 5,
        type: PaceNoteType.corner,
        text: 'right 5',
      ),
    ];

    speechService.speak('busy', () {});
    scheduler.loadRouteData(notes: notes, warnings: const []);
    scheduler.update(35.0, 5.0);

    expect(scheduler.queue.length, lessThan(4));
  });

  test('CalloutScheduler scales lead distance with speed', () {
    final speechService = FakeCalloutSpeechService();
    final scheduler = CalloutScheduler(
      speechService: speechService,
      settings: FakeSettingsService(PacenoteStyle.rally),
    );

    const nearNote = PaceNote(
      id: 'n-near',
      distanceFromStart: 40,
      direction: 'right',
      severity: 1,
      type: PaceNoteType.right,
      text: '',
    );
    const farNote = PaceNote(
      id: 'n-far',
      distanceFromStart: 55,
      direction: 'left',
      severity: 1,
      type: PaceNoteType.left,
      text: '',
    );

    scheduler.loadRouteData(
      notes: const [nearNote, farNote],
      warnings: const [],
    );
    scheduler.update(0, 5);

    expect(scheduler.spokenIds, contains('n-near'));
    expect(scheduler.spokenIds, isNot(contains('n-far')));

    final fastScheduler = CalloutScheduler(
      speechService: FakeCalloutSpeechService(),
      settings: FakeSettingsService(PacenoteStyle.rally),
    );
    fastScheduler.loadRouteData(notes: const [farNote], warnings: const []);
    fastScheduler.update(0, 25);

    expect(fastScheduler.spokenIds, contains('n-far'));
  });
}

class FakeSettingsService extends SettingsService {
  FakeSettingsService(this._style);
  final PacenoteStyle _style;

  @override
  PacenoteStyle get pacenoteStyle => _style;
}

class _PathBuilder {
  static const double _metersPerDegree = 111139.0;

  double _lat = 45.0;
  double _lon = 7.0;
  final List<RoutePoint> _points = [const RoutePoint(lat: 45.0, lon: 7.0)];

  _PathBuilder straight(double headingDegrees, double lengthMeters) {
    return arc(headingDegrees, headingDegrees, lengthMeters);
  }

  _PathBuilder arc(
    double startHeadingDegrees,
    double endHeadingDegrees,
    double lengthMeters,
  ) {
    final steps = math.max(2, (lengthMeters / 5.0).ceil());
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final heading =
          startHeadingDegrees + (endHeadingDegrees - startHeadingDegrees) * t;
      _advance(heading, lengthMeters / steps);
    }
    return this;
  }

  List<RoutePoint> build() => List.unmodifiable(_points);

  void _advance(double headingDegrees, double meters) {
    final radians = headingDegrees * math.pi / 180.0;
    final dNorth = math.cos(radians) * meters;
    final dEast = math.sin(radians) * meters;
    _lat += dNorth / _metersPerDegree;
    _lon += dEast / (_metersPerDegree * math.cos(_lat * math.pi / 180.0));
    _points.add(RoutePoint(lat: _lat, lon: _lon));
  }
}

class FakeCalloutSpeechService implements CalloutSpeechService {
  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<void> init() async {}

  @override
  void setEnabled(bool enabled) {}

  @override
  Future<void> speak(String text, VoidCallback onComplete) async {
    _speaking = true;
    Future.microtask(() {
      if (_speaking) {
        _speaking = false;
        onComplete();
      }
    });
  }

  @override
  Future<void> stop() async {
    _speaking = false;
  }
}
