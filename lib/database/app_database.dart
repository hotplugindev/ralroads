import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

LazyDatabase openRalRoadsDatabase() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(path.join(dir.path, 'ralroads.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

class LocalAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get mode => text()();
  TextColumn get displayName => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'matrix_sessions_user_id', columns: {#matrixUserId})
class MatrixSessions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().references(LocalAccounts, #id)();
  TextColumn get matrixUserId => text()();
  TextColumn get homeserverUrl => text()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get syncCursor => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'matrix_devices_user_device',
  columns: {#matrixUserId, #deviceId},
)
class MatrixDevices extends Table {
  TextColumn get id => text()();
  TextColumn get matrixUserId => text()();
  TextColumn get deviceId => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get publicKey => text().nullable()();
  BoolColumn get verified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PublicSigningKeys extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get keyType => text()();
  TextColumn get publicKey => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get revokedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'profiles_matrix_user_id', columns: {#matrixUserId})
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get matrixUserId => text().nullable()();
  TextColumn get displayName => text()();
  TextColumn get avatarUri => text().nullable()();
  TextColumn get homeRegion => text().nullable()();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'friendships_profile_friend',
  columns: {#profileId, #friendProfileId},
)
class Friendships extends Table {
  TextColumn get id => text()();
  @ReferenceName('profileFriendships')
  TextColumn get profileId => text().references(Profiles, #id)();
  @ReferenceName('friendProfileFriendships')
  TextColumn get friendProfileId => text().references(Profiles, #id)();
  TextColumn get state => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class FriendRequests extends Table {
  TextColumn get id => text()();
  @ReferenceName('sentFriendRequests')
  TextColumn get fromProfileId => text().references(Profiles, #id)();
  @ReferenceName('receivedFriendRequests')
  TextColumn get toProfileId => text().references(Profiles, #id)();
  TextColumn get roomId => text().nullable()();
  TextColumn get state => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Rooms extends Table {
  TextColumn get id => text()();
  TextColumn get matrixRoomId => text().unique()();
  TextColumn get type => text()();
  TextColumn get name => text().nullable()();
  BoolColumn get encrypted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get roomId => text().references(Rooms, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class GroupMembers extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text().references(Groups, #id)();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get role => text()();
  DateTimeColumn get joinedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'trips_started_at', columns: {#startedAt})
class Trips extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  RealColumn get distanceMeters => real().withDefault(const Constant(0))();
  TextColumn get privacy => text().withDefault(const Constant('private'))();
  TextColumn get status => text().withDefault(const Constant('recording'))();
  BoolColumn get cleanEligible => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'trip_points_trip_time', columns: {#tripId, #recordedAt})
class TripPoints extends Table {
  TextColumn get tripId => text().references(Trips, #id)();
  IntColumn get pointIndex => integer()();
  DateTimeColumn get recordedAt => dateTime()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get altitudeMeters => real().nullable()();
  RealColumn get accuracyMeters => real().nullable()();
  RealColumn get speedMps => real().nullable()();
  RealColumn get headingDegrees => real().nullable()();
  TextColumn get matchedEdgeId => text().nullable()();
  IntColumn get speedLimitKmh => integer().nullable()();
  BoolColumn get speedCompliant => boolean().nullable()();
  BoolColumn get mockLocation => boolean().nullable()();
  RealColumn get distanceFromStart => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {tripId, pointIndex};
}

class RoutePlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get profile => text()();
  TextColumn get avoidOptions => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'saved_routes_created_at', columns: {#createdAt})
class SavedRouteRecords extends Table {
  TextColumn get id => text()();
  TextColumn get routePlanId => text().nullable().references(RoutePlans, #id)();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  RealColumn get totalDistance => real()();
  TextColumn get startName => text().nullable()();
  TextColumn get destinationName => text().nullable()();
  DateTimeColumn get migratedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'saved_route_points_route_distance',
  columns: {#routeId, #distanceFromStart},
)
class SavedRoutePoints extends Table {
  TextColumn get routeId => text().references(SavedRouteRecords, #id)();
  IntColumn get pointIndex => integer()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get elevation => real().nullable()();
  RealColumn get distanceFromStart => real()();
  RealColumn get heading => real()();
  RealColumn get curvature => real()();

  @override
  Set<Column<Object>> get primaryKey => {routeId, pointIndex};
}

@TableIndex(name: 'route_chunks_route_status', columns: {#routeId, #status})
class RouteChunks extends Table {
  TextColumn get id => text()();
  TextColumn get routeId => text().references(SavedRouteRecords, #id)();
  IntColumn get chunkIndex => integer()();
  RealColumn get startDistance => real()();
  RealColumn get endDistance => real()();
  TextColumn get status => text()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MatchedRouteEdges extends Table {
  TextColumn get id => text()();
  TextColumn get routeId => text().references(SavedRouteRecords, #id)();
  TextColumn get chunkId => text().nullable().references(RouteChunks, #id)();
  IntColumn get edgeIndex => integer()();
  TextColumn get osmWayId => text().nullable()();
  TextColumn get roadName => text().nullable()();
  TextColumn get roadClass => text().nullable()();
  RealColumn get startDistance => real()();
  RealColumn get endDistance => real()();
  RealColumn get confidence => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'route_maneuvers_route_distance',
  columns: {#routeId, #distanceFromStart},
)
class RouteManeuverRows extends Table {
  TextColumn get id => text()();
  TextColumn get routeId => text().references(SavedRouteRecords, #id)();
  TextColumn get type => text()();
  RealColumn get distanceFromStart => real()();
  IntColumn get fromEdgeIndex => integer().nullable()();
  IntColumn get toEdgeIndex => integer().nullable()();
  TextColumn get instruction => text().nullable()();
  IntColumn get roundaboutExit => integer().nullable()();
  RealColumn get confidence => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'semantic_sectors_route_distance',
  columns: {#routeId, #startDistance},
)
class SemanticSectors extends Table {
  TextColumn get id => text()();
  TextColumn get routeId => text().references(SavedRouteRecords, #id)();
  TextColumn get type => text()();
  RealColumn get startDistance => real()();
  RealColumn get endDistance => real()();
  RealColumn get confidence => real().nullable()();
  TextColumn get sourceId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'pacenotes_route_distance',
  columns: {#routeId, #distanceFromStart},
)
class PacenoteRows extends Table {
  TextColumn get id => text()();
  TextColumn get routeId => text().references(SavedRouteRecords, #id)();
  RealColumn get distanceFromStart => real()();
  TextColumn get direction => text()();
  IntColumn get severity => integer()();
  TextColumn get type => text()();
  TextColumn get textValue => text()();
  BoolColumn get tightens => boolean().withDefault(const Constant(false))();
  BoolColumn get opens => boolean().withDefault(const Constant(false))();
  IntColumn get recommendedSpeedKmh => integer().nullable()();
  BoolColumn get isShort => boolean().withDefault(const Constant(false))();
  BoolColumn get isLong => boolean().withDefault(const Constant(false))();
  IntColumn get distanceMeters => integer().nullable()();
  TextColumn get intoNoteId => text().nullable()();
  RealColumn get startDistance => real().nullable()();
  RealColumn get endDistance => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'road_warnings_route_distance',
  columns: {#routeId, #distanceFromStart},
)
class RoadWarningRows extends Table {
  TextColumn get id => text()();
  TextColumn get routeId => text().references(SavedRouteRecords, #id)();
  RealColumn get distanceFromStart => real()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  TextColumn get type => text()();
  TextColumn get textValue => text()();
  TextColumn get tagsJson => text().nullable()();
  RealColumn get confidence => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'speed_limit_segments_route_distance',
  columns: {#routeId, #startDistance},
)
class SpeedLimitSegmentRows extends Table {
  TextColumn get id => text()();
  TextColumn get routeId => text().references(SavedRouteRecords, #id)();
  RealColumn get startDistance => real()();
  RealColumn get endDistance => real()();
  TextColumn get rawMaxspeed => text()();
  IntColumn get parsedKmh => integer().nullable()();
  TextColumn get tagsJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class OfflineMapRegions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get provider => text()();
  TextColumn get uri => text().nullable()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get status => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'challenge_segments_region_visibility',
  columns: {#region, #visibility},
)
class ChallengeSegments extends Table {
  TextColumn get id => text()();
  TextColumn get currentVersionId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get creatorProfileId =>
      text().nullable().references(Profiles, #id)();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
  TextColumn get region => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SegmentVersions extends Table {
  TextColumn get id => text()();
  TextColumn get segmentId => text().references(ChallengeSegments, #id)();
  IntColumn get version => integer()();
  TextColumn get previousVersionHash => text().nullable()();
  RealColumn get distanceMeters => real()();
  TextColumn get safetyStatus => text()();
  TextColumn get contentHash => text()();
  TextColumn get signature => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SegmentGeometry extends Table {
  TextColumn get versionId => text().references(SegmentVersions, #id)();
  IntColumn get pointIndex => integer()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get distanceFromStart => real()();

  @override
  Set<Column<Object>> get primaryKey => {versionId, pointIndex};
}

class SegmentRules extends Table {
  TextColumn get id => text()();
  TextColumn get versionId => text().references(SegmentVersions, #id)();
  TextColumn get policyVersion => text()();
  IntColumn get hardSpeedToleranceKmh => integer()();
  IntColumn get hardSpeedDurationSeconds => integer()();
  RealColumn get minRouteMatchScore => real()();
  RealColumn get minGpsQualityScore => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'segment_attempts_segment_started',
  columns: {#segmentId, #startedAt},
)
class SegmentAttempts extends Table {
  TextColumn get id => text()();
  TextColumn get segmentId => text().references(ChallengeSegments, #id)();
  TextColumn get tripId => text().nullable().references(Trips, #id)();
  TextColumn get profileId => text().nullable().references(Profiles, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  TextColumn get status => text()();
  BoolColumn get officialEligible =>
      boolean().withDefault(const Constant(false))();
  TextColumn get supersedesAttemptId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'attempt_points_attempt_index',
  columns: {#attemptId, #pointIndex},
)
class AttemptPoints extends Table {
  TextColumn get attemptId => text().references(SegmentAttempts, #id)();
  IntColumn get pointIndex => integer()();
  DateTimeColumn get recordedAt => dateTime()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get speedMps => real().nullable()();
  RealColumn get accuracyMeters => real().nullable()();
  IntColumn get speedLimitKmh => integer().nullable()();
  BoolColumn get speedCompliant => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {attemptId, pointIndex};
}

class LocalValidationResults extends Table {
  TextColumn get id => text()();
  TextColumn get attemptId => text().references(SegmentAttempts, #id)();
  TextColumn get engineVersion => text()();
  TextColumn get status => text()();
  RealColumn get durationSeconds => real().nullable()();
  RealColumn get routeMatchScore => real().nullable()();
  RealColumn get gpsQualityScore => real().nullable()();
  TextColumn get resultHash => text()();
  TextColumn get reasonsJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ValidatorAttestations extends Table {
  TextColumn get id => text()();
  TextColumn get attemptId => text().references(SegmentAttempts, #id)();
  TextColumn get validatorId => text()();
  TextColumn get validatorPublicKey => text()();
  TextColumn get status => text()();
  TextColumn get engineVersion => text()();
  TextColumn get resultHash => text()();
  TextColumn get signature => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Challenges extends Table {
  TextColumn get id => text()();
  TextColumn get segmentId => text().references(ChallengeSegments, #id)();
  TextColumn get roomId => text().nullable().references(Rooms, #id)();
  TextColumn get name => text()();
  TextColumn get status => text()();
  DateTimeColumn get startsAt => dateTime().nullable()();
  DateTimeColumn get endsAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ChallengeParticipants extends Table {
  TextColumn get id => text()();
  TextColumn get challengeId => text().references(Challenges, #id)();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get state => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalNotifications extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get body => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get readAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Reports extends Table {
  TextColumn get id => text()();
  TextColumn get reporterProfileId =>
      text().nullable().references(Profiles, #id)();
  TextColumn get targetType => text()();
  TextColumn get targetId => text()();
  TextColumn get reason => text()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ModerationState extends Table {
  TextColumn get id => text()();
  TextColumn get targetType => text()();
  TextColumn get targetId => text()();
  TextColumn get action => text()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PrivateZones extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  RealColumn get radiusMeters => real()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'outgoing_matrix_events_state',
  columns: {#state, #nextAttemptAt},
)
class OutgoingMatrixEvents extends Table {
  TextColumn get id => text()();
  TextColumn get eventType => text()();
  TextColumn get roomId => text().nullable()();
  TextColumn get entityId => text()();
  TextColumn get payloadJson => text()();
  TextColumn get state => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'pending_media_uploads_state',
  columns: {#state, #nextAttemptAt},
)
class PendingMediaUploads extends Table {
  TextColumn get id => text()();
  TextColumn get localPath => text()();
  TextColumn get sha256 => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get state => text()();
  TextColumn get matrixUri => text().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MatrixSyncCursors extends Table {
  TextColumn get id => text()();
  TextColumn get scope => text()();
  TextColumn get cursor => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'cached_directory_events_room_time',
  columns: {#roomId, #originTimestamp},
)
class CachedDirectoryEvents extends Table {
  TextColumn get id => text()();
  TextColumn get roomId => text()();
  TextColumn get eventType => text()();
  TextColumn get entityId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get originTimestamp => dateTime()();
  DateTimeColumn get ingestedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class BlockedUsers extends Table {
  TextColumn get id => text()();
  TextColumn get matrixUserId => text()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    LocalAccounts,
    MatrixSessions,
    MatrixDevices,
    PublicSigningKeys,
    Profiles,
    Friendships,
    FriendRequests,
    Rooms,
    Groups,
    GroupMembers,
    Trips,
    TripPoints,
    RoutePlans,
    SavedRouteRecords,
    SavedRoutePoints,
    RouteChunks,
    MatchedRouteEdges,
    RouteManeuverRows,
    SemanticSectors,
    PacenoteRows,
    RoadWarningRows,
    SpeedLimitSegmentRows,
    OfflineMapRegions,
    ChallengeSegments,
    SegmentVersions,
    SegmentGeometry,
    SegmentRules,
    SegmentAttempts,
    AttemptPoints,
    LocalValidationResults,
    ValidatorAttestations,
    Challenges,
    ChallengeParticipants,
    LocalNotifications,
    Reports,
    ModerationState,
    PrivateZones,
    OutgoingMatrixEvents,
    PendingMediaUploads,
    MatrixSyncCursors,
    CachedDirectoryEvents,
    BlockedUsers,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await m.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<int> savedRouteCount() {
    return (selectOnly(savedRouteRecords)
          ..addColumns([savedRouteRecords.id.count()]))
        .map((row) => row.read(savedRouteRecords.id.count()) ?? 0)
        .getSingle();
  }
}
