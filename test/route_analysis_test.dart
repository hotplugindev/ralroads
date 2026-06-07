import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/models/matched_route.dart';
import 'package:ralroads/models/pace_note.dart';
import 'package:ralroads/models/road_warning.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/models/speed_limit_segment.dart';
import 'package:ralroads/services/overpass_service.dart';
import 'package:ralroads/services/pacenote_generator.dart';
import 'package:ralroads/services/route_analysis_service.dart';

class FakeOverpassService extends OverpassService {
  FakeOverpassService() : super();

  @override
  Future<RoadEnrichment> enrichRoute(List<RoutePoint> routePoints) async {
    // Generate a warning and a speed limit inside the chunk's range if any points exist
    if (routePoints.isEmpty) {
      return const RoadEnrichment(roadWarnings: [], speedLimitSegments: []);
    }

    final midPt = routePoints[routePoints.length ~/ 2];
    final dist = midPt.distanceFromStart;

    return RoadEnrichment(
      roadWarnings: [
        RoadWarning(
          id: 'w_$dist',
          type: RoadWarningType.speedCamera,
          lat: midPt.lat,
          lon: midPt.lon,
          distanceFromStart: dist,
          text: 'Speed Camera',
        ),
      ],
      speedLimitSegments: [
        SpeedLimitSegment(
          id: 'limit_$dist',
          startDistance: dist,
          endDistance: dist + 100.0,
          rawMaxspeed: '50',
          parsedKmh: 50,
        ),
      ],
    );
  }
}

class FakePacenoteGenerator extends PacenoteGenerator {
  FakePacenoteGenerator() : super();

  @override
  List<RoadWarning> detectElevationFeatures(List<RoutePoint> points) {
    return const [];
  }

  @override
  List<PaceNote> refinePacenotesWithRoadContext({
    required List<PaceNote> notes,
    required List<RoutePoint> routePoints,
    required List<RoadWarning> warnings,
    required List<SpeedLimitSegment> speedLimits,
  }) {
    // Simply return the notes with added tags/context
    return notes.map((n) => n.copyWith(text: '${n.text} refined')).toList();
  }
}

void main() {
  group('RouteAnalysisService Partitioning & Slicing Tests', () {
    test('correctly partitions a 25km route into 3 chunks', () {
      final points = <RoutePoint>[];
      for (var i = 0; i <= 250; i++) {
        points.add(
          RoutePoint(
            lat: 45.0 + (i * 0.0001),
            lon: 7.0 + (i * 0.0001),
            distanceFromStart: i * 100.0, // 0 to 25,000 meters
          ),
        );
      }

      final service = RouteAnalysisService(
        routeId: 'test_route_1',
        routeName: 'Test Route 1',
        routePoints: points,
        initialPacenotes: const [],
        overpassService: FakeOverpassService(),
        pacenoteGenerator: FakePacenoteGenerator(),
        createdAt: DateTime.now(),
      );

      expect(service.chunks.length, 3);
      expect(service.chunks[0].startDistance, 0.0);
      expect(service.chunks[0].endDistance, 10000.0);
      expect(service.chunks[1].startDistance, 10000.0);
      expect(service.chunks[1].endDistance, 20000.0);
      expect(service.chunks[2].startDistance, 20000.0);
      expect(service.chunks[2].endDistance, 25000.0);
    });

    test('sequential runAnalysis updates state progressively', () async {
      final points = <RoutePoint>[];
      for (var i = 0; i <= 250; i++) {
        points.add(
          RoutePoint(
            lat: 45.0 + (i * 0.0001),
            lon: 7.0 + (i * 0.0001),
            distanceFromStart: i * 100.0,
          ),
        );
      }

      final initialNotes = [
        const PaceNote(
          id: 'note_1',
          distanceFromStart: 5000.0,
          direction: 'left',
          severity: 3,
          text: 'Left 3',
        ),
        const PaceNote(
          id: 'note_2',
          distanceFromStart: 15000.0,
          direction: 'right',
          severity: 2,
          text: 'Right 2',
        ),
      ];

      final service = RouteAnalysisService(
        routeId: 'test_route_2',
        routeName: 'Test Route 2',
        routePoints: points,
        initialPacenotes: initialNotes,
        overpassService: FakeOverpassService(),
        pacenoteGenerator: FakePacenoteGenerator(),
        createdAt: DateTime.now(),
      );

      var updateCount = 0;
      service.addListener(() {
        updateCount++;
      });

      expect(service.manifest.readyChunks, 0);
      expect(service.manifest.isComplete, false);

      await service.runAnalysis();

      expect(service.manifest.readyChunks, 3);
      expect(service.manifest.isComplete, true);
      expect(updateCount, greaterThan(0));

      // Check all warnings aggregated correctly
      expect(service.allWarnings.length, 3);
      // Check speed limit segments aggregated correctly
      expect(service.allSpeedLimits.length, 3);
      // Check pacenotes refined correctly
      expect(service.allPacenotes.length, 2);
      expect(service.allPacenotes[0].text, 'Left 3 refined');
      expect(service.allPacenotes[1].text, 'Right 2 refined');
    });

    test('can retry failed chunks individually', () async {
      final points = <RoutePoint>[
        const RoutePoint(lat: 45, lon: 7, distanceFromStart: 0),
        const RoutePoint(lat: 45.01, lon: 7.01, distanceFromStart: 5000),
      ];

      final service = RouteAnalysisService(
        routeId: 'test_route_3',
        routeName: 'Test Route 3',
        routePoints: points,
        initialPacenotes: const [],
        overpassService: FakeOverpassService(),
        pacenoteGenerator: FakePacenoteGenerator(),
        createdAt: DateTime.now(),
      );

      // Manually set chunk 0 to failed
      service.chunks[0] = RouteChunk(
        id: service.chunks[0].id,
        index: service.chunks[0].index,
        startDistance: service.chunks[0].startDistance,
        endDistance: service.chunks[0].endDistance,
        rawGeometry: service.chunks[0].rawGeometry,
        displayGeometry: service.chunks[0].displayGeometry,
        status: RouteChunkStatus.failed,
        error: 'Network Timeout',
      );

      expect(service.manifest.failedChunks, 1);
      expect(service.manifest.readyChunks, 0);

      await service.analyzeChunk(0);

      expect(service.manifest.failedChunks, 0);
      expect(service.manifest.readyChunks, 1);
      expect(service.chunks[0].status, RouteChunkStatus.ready);
    });
  });
}
