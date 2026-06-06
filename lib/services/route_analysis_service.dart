import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../models/matched_route.dart';
import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/speed_limit_segment.dart';
import '../models/route_point.dart';
import '../models/saved_route.dart';
import 'overpass_service.dart';
import 'pacenote_generator.dart';
import 'route_semantic_engine.dart';
import 'route_storage_service.dart';

class RouteAnalysisService extends ChangeNotifier {
  final String routeId;
  final String routeName;
  final List<RoutePoint> routePoints;
  final List<PaceNote> initialPacenotes;
  final OverpassService overpassService;
  final PacenoteGenerator pacenoteGenerator;
  RouteStorageService? _storageService;
  final DateTime createdAt;
  final String? startName;
  final String? destinationName;

  final List<RouteChunk> _chunks = [];
  List<RouteChunk> get chunks => _chunks;

  bool _isAnalyzing = false;
  bool get isAnalyzing => _isAnalyzing;

  RouteAnalysisService({
    required this.routeId,
    required this.routeName,
    required this.routePoints,
    required this.initialPacenotes,
    required this.overpassService,
    required this.pacenoteGenerator,
    RouteStorageService? storageService,
    required this.createdAt,
    this.startName,
    this.destinationName,
    List<RouteChunk>? initialChunks,
  }) : _storageService = storageService {
    if (initialChunks != null && initialChunks.isNotEmpty) {
      _chunks.addAll(initialChunks);
    } else {
      _partitionRoute();
    }
  }

  void enableProgressSaving(RouteStorageService storage) {
    _storageService = storage;
  }

  void _partitionRoute() {
    _chunks.clear();
    if (routePoints.isEmpty) return;

    // Chunk size: 10km (10000 meters)
    const chunkLengthM = 10000.0;
    final totalDist = routePoints.last.distanceFromStart;
    final chunkCount = (totalDist / chunkLengthM).ceil();

    for (var i = 0; i < chunkCount; i++) {
      final startDist = i * chunkLengthM;
      final endDist = math.min((i + 1) * chunkLengthM, totalDist);

      final chunkPoints = routePoints
          .where(
            (p) =>
                p.distanceFromStart >= startDist &&
                p.distanceFromStart <= endDist,
          )
          .toList();

      _chunks.add(
        RouteChunk(
          id: 'chunk_${routeId}_$i',
          index: i,
          startDistance: startDist,
          endDistance: endDist,
          rawGeometry: chunkPoints,
          displayGeometry: chunkPoints,
          status: RouteChunkStatus.pending,
          sectors: const [],
          warnings: const [],
          notes: const [],
          speedLimits: const [],
        ),
      );
    }
  }

  RouteAnalysisManifest get manifest {
    final total = _chunks.length;
    final ready = _chunks
        .where((c) => c.status == RouteChunkStatus.ready)
        .length;
    final partial = _chunks
        .where((c) => c.status == RouteChunkStatus.partial)
        .length;
    final failed = _chunks
        .where((c) => c.status == RouteChunkStatus.failed)
        .length;
    final isComplete = (ready + failed) == total && total > 0;

    return RouteAnalysisManifest(
      totalChunks: total,
      readyChunks: ready,
      partialChunks: partial,
      failedChunks: failed,
      lastUpdated: DateTime.now(),
      isComplete: isComplete,
    );
  }

  List<RoadWarning> get allWarnings {
    final list = <RoadWarning>[];
    for (final c in _chunks) {
      if (c.status == RouteChunkStatus.ready) {
        list.addAll(c.warnings);
      }
    }
    return list;
  }

  List<SpeedLimitSegment> get allSpeedLimits {
    final list = <SpeedLimitSegment>[];
    for (final c in _chunks) {
      if (c.status == RouteChunkStatus.ready) {
        list.addAll(c.speedLimits);
      }
    }
    // Deduplicate by ID
    final deduplicated = <String, SpeedLimitSegment>{};
    for (final segment in list) {
      deduplicated[segment.id] = segment;
    }
    return deduplicated.values.toList();
  }

  List<PaceNote> get allPacenotes {
    final list = <PaceNote>[];
    for (final c in _chunks) {
      if (c.status == RouteChunkStatus.ready) {
        list.addAll(c.notes);
      } else {
        // Fall back to initial notes in this chunk range
        list.addAll(
          initialPacenotes.where(
            (n) =>
                n.distanceFromStart >= c.startDistance &&
                n.distanceFromStart <= c.endDistance,
          ),
        );
      }
    }
    list.sort((a, b) => a.distanceFromStart.compareTo(b.distanceFromStart));
    return list;
  }

  MatchedRoute buildMatchedRoute() {
    return MatchedRoute(
      id: routeId,
      edges: const [],
      maneuvers: const [],
      intersections: const [],
      chunks: _chunks,
      totalDistanceMeters: routePoints.isEmpty
          ? 0.0
          : routePoints.last.distanceFromStart,
      analysisManifest: manifest,
    );
  }

  SavedRoute buildSavedRoute() {
    return SavedRoute(
      id: routeId,
      name: routeName,
      createdAt: createdAt,
      totalDistance: routePoints.isEmpty
          ? 0.0
          : routePoints.last.distanceFromStart,
      points: routePoints,
      pacenotes: allPacenotes,
      roadWarnings: allWarnings,
      speedLimitSegments: allSpeedLimits,
      matchedRoute: buildMatchedRoute(),
      startName: startName,
      destinationName: destinationName,
    );
  }

  Future<void> saveCurrentProgress() async {
    final storage = _storageService;
    if (storage != null) {
      final route = buildSavedRoute();
      await storage.saveRoute(route);
    }
  }

  Future<void> analyzeChunk(int i) async {
    if (i < 0 || i >= _chunks.length) return;
    final chunk = _chunks[i];

    _chunks[i] = RouteChunk(
      id: chunk.id,
      index: chunk.index,
      startDistance: chunk.startDistance,
      endDistance: chunk.endDistance,
      rawGeometry: chunk.rawGeometry,
      displayGeometry: chunk.displayGeometry,
      status: RouteChunkStatus.processing,
      sectors: chunk.sectors,
      warnings: chunk.warnings,
      notes: chunk.notes,
      speedLimits: chunk.speedLimits,
      error: null,
    );
    notifyListeners();

    try {
      // 1. Slice points with 500m overlap buffer for computation context
      const overlapM = 500.0;
      final compStart = math.max(0.0, chunk.startDistance - overlapM);
      final compEnd = math.min(
        routePoints.isEmpty ? 0.0 : routePoints.last.distanceFromStart,
        chunk.endDistance + overlapM,
      );

      final compPoints = routePoints
          .where(
            (p) =>
                p.distanceFromStart >= compStart &&
                p.distanceFromStart <= compEnd,
          )
          .toList();

      // 2. Query Overpass and detect elevation
      final enrichment = await overpassService.enrichRoute(compPoints);
      final elevationWarnings = pacenoteGenerator.detectElevationFeatures(
        compPoints,
      );
      final combinedWarnings = [
        ...enrichment.roadWarnings,
        ...elevationWarnings,
      ];

      // 3. Filter warnings back strictly to chunk boundaries
      final isLastChunk = i == _chunks.length - 1;
      final chunkWarnings = combinedWarnings
          .where(
            (w) =>
                w.distanceFromStart >= chunk.startDistance &&
                w.distanceFromStart <
                    (isLastChunk ? chunk.endDistance + 0.1 : chunk.endDistance),
          )
          .toList();

      // 4. Overlapping speed limits
      final chunkSpeedLimits = enrichment.speedLimitSegments
          .where(
            (s) =>
                s.startDistance < chunk.endDistance &&
                s.endDistance > chunk.startDistance,
          )
          .toList();

      // 5. Filter and refine pacenotes
      final chunkPacenotes = initialPacenotes
          .where(
            (n) =>
                n.distanceFromStart >= chunk.startDistance &&
                n.distanceFromStart <= chunk.endDistance,
          )
          .toList();

      final refinedPacenotes = pacenoteGenerator.refinePacenotesWithRoadContext(
        notes: chunkPacenotes,
        routePoints: chunk.rawGeometry,
        warnings: chunkWarnings,
        speedLimits: chunkSpeedLimits,
      );

      _chunks[i] = RouteChunk(
        id: chunk.id,
        index: chunk.index,
        startDistance: chunk.startDistance,
        endDistance: chunk.endDistance,
        rawGeometry: chunk.rawGeometry,
        displayGeometry: chunk.displayGeometry,
        status: RouteChunkStatus.ready,
        sectors: RouteSemanticEngine.sectorsFromPacenotes(
          refinedPacenotes,
          chunk.rawGeometry,
        ),
        warnings: chunkWarnings,
        notes: refinedPacenotes,
        speedLimits: chunkSpeedLimits,
      );
    } catch (e) {
      debugPrint('Error analyzing chunk $i: $e');
      _chunks[i] = RouteChunk(
        id: chunk.id,
        index: chunk.index,
        startDistance: chunk.startDistance,
        endDistance: chunk.endDistance,
        rawGeometry: chunk.rawGeometry,
        displayGeometry: chunk.displayGeometry,
        status: RouteChunkStatus.failed,
        sectors: const [],
        warnings: const [],
        notes: const [],
        speedLimits: const [],
        error: e.toString(),
      );
    }
    notifyListeners();
  }

  Future<void> runAnalysis() async {
    if (_isAnalyzing) return;
    _isAnalyzing = true;
    notifyListeners();

    try {
      for (var i = 0; i < _chunks.length; i++) {
        // Skip already ready chunks
        if (_chunks[i].status == RouteChunkStatus.ready) continue;

        await analyzeChunk(i);

        // Auto-save progress
        await saveCurrentProgress();
      }
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }
}
