import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/main.dart';
import 'package:ralroads/models/pace_note.dart';
import 'package:ralroads/models/road_warning.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/models/speed_limit_segment.dart';
import 'package:ralroads/services/pacenote_generator.dart';
import 'package:ralroads/services/settings_service.dart';

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
        distanceFromStart: 100,
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
          heading: 180,
        ),
      ],
      warnings: const [],
      speedLimits: const [],
    );

    expect(refined.single.type, PaceNoteType.hairpin);
    expect(refined.single.text, 'Hairpin left');
  });

  test('junction warning converts curve to junction turn', () {
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
        RoutePoint(lat: 45.0005, lon: 7.0005, distanceFromStart: 60, heading: 45),
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

    expect(refined.single.type, PaceNoteType.junction);
    expect(refined.single.text, 'At junction, left');
  });

  test('straight pacenote is generated for long segments', () {
    final generator = PacenoteGenerator();
    // Create points representing a straight line of ~150 meters
    final points = <RoutePoint>[];
    for (var i = 0; i < 20; i++) {
      points.add(RoutePoint(lat: 45.0 + i * 0.0001, lon: 7.0));
    }

    final notes = generator.generate(points);
    final straightNotes = notes.where((n) => n.direction == 'straight').toList();
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
        RoutePoint(lat: 45.0005, lon: 7.0005, distanceFromStart: 60, heading: 45),
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
      points.add(RoutePoint(
        lat: 45.0 + i * 0.00006 + latOffset,
        lon: 7.0,
        distanceFromStart: dist,
      ));
    }
    
    final notes = generator.generate(points);
    // Since severity 6 note is filtered, the entire segment should just merge into straights
    // or not produce any severity 6 corner note.
    final corners = notes.where((n) => n.type == PaceNoteType.corner || n.type == PaceNoteType.left || n.type == PaceNoteType.right).toList();
    for (final corner in corners) {
      expect(corner.severity, isNot(6));
    }
  });

  test('PacenoteGenerator handles Calm, Balanced, and Rally styles', () {
    final points = <RoutePoint>[];
    for (var i = 0; i < 30; i++) {
      points.add(RoutePoint(
        lat: 45.0 + math.sin(i * 0.08) * 0.0003,
        lon: 7.0 + i * 0.0001,
      ));
    }

    final calmGenerator = PacenoteGenerator(settings: FakeSettingsService(PacenoteStyle.calm));
    final balancedGenerator = PacenoteGenerator(settings: FakeSettingsService(PacenoteStyle.balanced));
    final rallyGenerator = PacenoteGenerator(settings: FakeSettingsService(PacenoteStyle.rally));

    final calmNotes = calmGenerator.generate(points);
    final balancedNotes = balancedGenerator.generate(points);
    final rallyNotes = rallyGenerator.generate(points);

    expect(rallyNotes.length, greaterThanOrEqualTo(balancedNotes.length));
    expect(balancedNotes.length, greaterThanOrEqualTo(calmNotes.length));
  });
}

class FakeSettingsService extends SettingsService {
  FakeSettingsService(this._style);
  final PacenoteStyle _style;

  @override
  PacenoteStyle get pacenoteStyle => _style;
}
