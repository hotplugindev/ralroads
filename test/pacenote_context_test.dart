import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/main.dart';
import 'package:ralroads/models/pace_note.dart';
import 'package:ralroads/models/road_warning.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/services/pacenote_generator.dart';

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
}
