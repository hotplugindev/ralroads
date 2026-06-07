import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/route_point.dart';

class SegmentRuleInput {
  const SegmentRuleInput({
    this.policyVersion = 'local-v1',
    this.hardSpeedToleranceKmh = 8,
    this.hardSpeedDurationSeconds = 2,
    this.minRouteMatchScore = 0.85,
    this.minGpsQualityScore = 0.7,
  });

  final String policyVersion;
  final int hardSpeedToleranceKmh;
  final int hardSpeedDurationSeconds;
  final double minRouteMatchScore;
  final double minGpsQualityScore;
}

class LocalSegmentInput {
  const LocalSegmentInput({
    required this.id,
    required this.versionId,
    required this.name,
    required this.geometry,
    required this.distanceMeters,
    this.description,
    this.creatorProfileId,
    this.visibility = 'private',
    this.region,
    this.safetyStatus = 'questionable',
    this.contentHash = 'local-unhashed',
    this.signature,
    this.rules = const SegmentRuleInput(),
  });

  final String id;
  final String versionId;
  final String name;
  final String? description;
  final List<RoutePoint> geometry;
  final double distanceMeters;
  final String? creatorProfileId;
  final String visibility;
  final String? region;
  final String safetyStatus;
  final String contentHash;
  final String? signature;
  final SegmentRuleInput rules;
}

class SegmentRepository {
  SegmentRepository(this.database);

  final AppDatabase database;

  Future<ChallengeSegment> createLocalSegment(LocalSegmentInput input) async {
    final now = DateTime.now();
    await database.transaction(() async {
      await database
          .into(database.challengeSegments)
          .insertOnConflictUpdate(
            ChallengeSegmentsCompanion(
              id: Value(input.id),
              currentVersionId: Value(input.versionId),
              name: Value(input.name),
              creatorProfileId: Value(input.creatorProfileId),
              visibility: Value(input.visibility),
              region: Value(input.region),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await database
          .into(database.segmentVersions)
          .insertOnConflictUpdate(
            SegmentVersionsCompanion(
              id: Value(input.versionId),
              segmentId: Value(input.id),
              version: const Value(1),
              previousVersionHash: const Value(null),
              distanceMeters: Value(input.distanceMeters),
              safetyStatus: Value(input.safetyStatus),
              contentHash: Value(input.contentHash),
              signature: Value(input.signature),
              createdAt: Value(now),
            ),
          );
      await _replaceGeometry(input.versionId, input.geometry);
      await database
          .into(database.segmentRules)
          .insertOnConflictUpdate(
            SegmentRulesCompanion(
              id: Value('${input.versionId}-rules'),
              versionId: Value(input.versionId),
              policyVersion: Value(input.rules.policyVersion),
              hardSpeedToleranceKmh: Value(input.rules.hardSpeedToleranceKmh),
              hardSpeedDurationSeconds: Value(
                input.rules.hardSpeedDurationSeconds,
              ),
              minRouteMatchScore: Value(input.rules.minRouteMatchScore),
              minGpsQualityScore: Value(input.rules.minGpsQualityScore),
            ),
          );
    });
    return getSegment(input.id).then((segment) => segment!);
  }

  Future<List<ChallengeSegment>> listLocalSegments({int limit = 50}) {
    return (database.select(database.challengeSegments)
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
          ..limit(limit))
        .get();
  }

  Future<ChallengeSegment?> getSegment(String id) {
    return (database.select(
      database.challengeSegments,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Stream<List<ChallengeSegment>> watchLocalSegments({int limit = 50}) {
    return (database.select(database.challengeSegments)
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
          ..limit(limit))
        .watch();
  }

  Stream<ChallengeSegment?> watchSegment(String id) {
    return (database.select(
      database.challengeSegments,
    )..where((row) => row.id.equals(id))).watchSingleOrNull();
  }

  Future<void> updateVisibility(String id, String visibility) {
    return (database.update(
      database.challengeSegments,
    )..where((row) => row.id.equals(id))).write(
      ChallengeSegmentsCompanion(
        visibility: Value(visibility),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markPublished(String id, {required bool published}) {
    return updateVisibility(id, published ? 'public' : 'private');
  }

  Future<SegmentVersion> versionSegment({
    required String segmentId,
    required String versionId,
    required int version,
    required double distanceMeters,
    required String safetyStatus,
    required String contentHash,
    required List<RoutePoint> geometry,
    String? previousVersionHash,
    String? signature,
  }) async {
    final now = DateTime.now();
    await database.transaction(() async {
      await database
          .into(database.segmentVersions)
          .insertOnConflictUpdate(
            SegmentVersionsCompanion(
              id: Value(versionId),
              segmentId: Value(segmentId),
              version: Value(version),
              previousVersionHash: Value(previousVersionHash),
              distanceMeters: Value(distanceMeters),
              safetyStatus: Value(safetyStatus),
              contentHash: Value(contentHash),
              signature: Value(signature),
              createdAt: Value(now),
            ),
          );
      await _replaceGeometry(versionId, geometry);
      await (database.update(
        database.challengeSegments,
      )..where((row) => row.id.equals(segmentId))).write(
        ChallengeSegmentsCompanion(
          currentVersionId: Value(versionId),
          updatedAt: Value(now),
        ),
      );
    });
    return (database.select(
      database.segmentVersions,
    )..where((row) => row.id.equals(versionId))).getSingle();
  }

  Future<void> _replaceGeometry(
    String versionId,
    List<RoutePoint> geometry,
  ) async {
    await (database.delete(
      database.segmentGeometry,
    )..where((row) => row.versionId.equals(versionId))).go();
    await database.batch((batch) {
      batch.insertAll(database.segmentGeometry, [
        for (final point in geometry.indexed)
          SegmentGeometryCompanion.insert(
            versionId: versionId,
            pointIndex: point.$1,
            lat: point.$2.lat,
            lon: point.$2.lon,
            distanceFromStart: point.$2.distanceFromStart,
          ),
      ]);
    });
  }

  Future<SegmentRule?> getRulesForVersion(String versionId) {
    return (database.select(
      database.segmentRules,
    )..where((row) => row.versionId.equals(versionId))).getSingleOrNull();
  }
}
