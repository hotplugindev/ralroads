import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';

enum ChallengeStatus { draft, active, ended, cancelled, deleted }

enum ChallengeVisibility { local, friend, group, directory }

enum ChallengeSyncState {
  localOnly,
  queued,
  uploading,
  synced,
  failed,
  tombstoned,
}

class MatrixChallengeInput {
  const MatrixChallengeInput({
    required this.challengeId,
    required this.segmentId,
    required this.name,
    required this.status,
    required this.sourceRoomId,
    required this.authorMatrixId,
    required this.originTimestamp,
    this.revision = 1,
    this.visibility = ChallengeVisibility.group,
    this.startsAt,
    this.endsAt,
  });

  final String challengeId;
  final String segmentId;
  final String name;
  final ChallengeStatus status;
  final String sourceRoomId;
  final String authorMatrixId;
  final DateTime originTimestamp;
  final int revision;
  final ChallengeVisibility visibility;
  final DateTime? startsAt;
  final DateTime? endsAt;
}

class ChallengeRepository {
  ChallengeRepository(this.database);

  final AppDatabase database;

  Future<Challenge> createLocalChallenge({
    required String id,
    required String segmentId,
    required String name,
    String? roomId,
    DateTime? startsAt,
    DateTime? endsAt,
    String? ownerMatrixId,
  }) async {
    final now = DateTime.now();
    await database.transaction(() async {
      await _ensureRoom(roomId, now);
      await database
          .into(database.challenges)
          .insertOnConflictUpdate(
            ChallengesCompanion(
              id: Value(id),
              segmentId: Value(segmentId),
              name: Value(name),
              roomId: Value(roomId),
              status: const Value('draft'),
              startsAt: Value(startsAt),
              endsAt: Value(endsAt),
              updatedAt: Value(now),
            ),
          );
    });
    if (roomId != null && roomId.isNotEmpty) {
      final payload = _challengeEventPayload(
        id: id,
        segmentId: segmentId,
        name: name,
        roomId: roomId,
        ownerMatrixId: ownerMatrixId,
        status: ChallengeStatus.active,
        visibility: ChallengeVisibility.group,
        revision: 1,
        startsAt: startsAt,
        endsAt: endsAt,
        updatedAt: now,
      );
      await database
          .into(database.outgoingMatrixEvents)
          .insertOnConflictUpdate(
            OutgoingMatrixEventsCompanion(
              id: Value('challenge-created-$id-1'),
              eventType: const Value('org.ralroads.challenge.created.v1'),
              roomId: Value(roomId),
              entityId: Value(id),
              payloadJson: Value(jsonEncode(payload)),
              state: const Value('queued'),
              attemptCount: const Value(0),
              nextAttemptAt: Value(now),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    }
    return (database.select(
      database.challenges,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<void> ingestMatrixChallenge(MatrixChallengeInput input) async {
    final segment = await (database.select(
      database.challengeSegments,
    )..where((row) => row.id.equals(input.segmentId))).getSingleOrNull();
    if (segment == null) return;

    final existing = await getChallenge(input.challengeId);
    if (existing != null &&
        existing.updatedAt.isAfter(input.originTimestamp) &&
        existing.status == 'deleted') {
      return;
    }

    await database.transaction(() async {
      await _ensureRoom(input.sourceRoomId, input.originTimestamp);
      await database
          .into(database.challenges)
          .insertOnConflictUpdate(
            ChallengesCompanion(
              id: Value(input.challengeId),
              segmentId: Value(input.segmentId),
              roomId: Value(input.sourceRoomId),
              name: Value(input.name),
              status: Value(_statusName(input.status)),
              startsAt: Value(input.startsAt),
              endsAt: Value(input.endsAt),
              updatedAt: Value(input.originTimestamp),
            ),
          );
    });
  }

  Future<void> cancel(String id, {String? roomId, String? ownerMatrixId}) {
    return _setTerminalState(
      id,
      ChallengeStatus.cancelled,
      eventType: 'org.ralroads.challenge.cancelled.v1',
      roomId: roomId,
      ownerMatrixId: ownerMatrixId,
    );
  }

  Future<void> tombstone(String id, {String? roomId, String? ownerMatrixId}) {
    return _setTerminalState(
      id,
      ChallengeStatus.deleted,
      eventType: 'org.ralroads.challenge.deleted.v1',
      roomId: roomId,
      ownerMatrixId: ownerMatrixId,
    );
  }

  Future<void> updateState(String id, String state) {
    return (database.update(
      database.challenges,
    )..where((row) => row.id.equals(id))).write(
      ChallengesCompanion(
        status: Value(state),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> addParticipant({
    required String id,
    required String challengeId,
    required String profileId,
    String state = 'invited',
  }) {
    return database
        .into(database.challengeParticipants)
        .insertOnConflictUpdate(
          ChallengeParticipantsCompanion(
            id: Value(id),
            challengeId: Value(challengeId),
            profileId: Value(profileId),
            state: Value(state),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> removeParticipant(String id) {
    return (database.delete(
      database.challengeParticipants,
    )..where((row) => row.id.equals(id))).go();
  }

  Future<void> evaluateDeadlines() async {
    final now = DateTime.now();
    // 1. Transition draft -> active if startsAt <= now
    final toActive =
        await (database.select(database.challenges)..where(
              (row) =>
                  row.status.equals('draft') &
                  row.startsAt.isSmallerOrEqualValue(now),
            ))
            .get();
    for (final c in toActive) {
      await updateState(c.id, 'active');
    }

    // 2. Transition active -> ended if endsAt <= now
    final toEnded =
        await (database.select(database.challenges)..where(
              (row) =>
                  row.status.equals('active') &
                  row.endsAt.isSmallerOrEqualValue(now),
            ))
            .get();
    for (final c in toEnded) {
      await updateState(c.id, 'ended');
    }
  }

  Future<List<Challenge>> listActiveChallenges() async {
    await evaluateDeadlines();
    return (database.select(database.challenges)
          ..where(
            (row) => row.status.equals('active') | row.status.equals('draft'),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .get();
  }

  Future<List<Challenge>> listPastChallenges() async {
    await evaluateDeadlines();
    return (database.select(database.challenges)
          ..where(
            (row) =>
                row.status.equals('ended') | row.status.equals('cancelled'),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .get();
  }

  Stream<List<Challenge>> watchActiveChallenges() {
    return (database.select(database.challenges)
          ..where(
            (row) => row.status.equals('active') | row.status.equals('draft'),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .watch();
  }

  Stream<List<Challenge>> watchPastChallenges() {
    return (database.select(database.challenges)
          ..where(
            (row) =>
                row.status.equals('ended') | row.status.equals('cancelled'),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .watch();
  }

  Future<Challenge?> getChallenge(String id) {
    return (database.select(
      database.challenges,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Stream<Challenge?> watchChallenge(String id) {
    return (database.select(
      database.challenges,
    )..where((row) => row.id.equals(id))).watchSingleOrNull();
  }

  Future<void> _setTerminalState(
    String id,
    ChallengeStatus status, {
    required String eventType,
    String? roomId,
    String? ownerMatrixId,
  }) async {
    final now = DateTime.now();
    await updateState(id, _statusName(status));
    if (roomId == null || roomId.isEmpty) return;
    final challenge = await getChallenge(id);
    if (challenge == null) return;
    final payload = _challengeEventPayload(
      id: challenge.id,
      segmentId: challenge.segmentId,
      name: challenge.name,
      roomId: roomId,
      ownerMatrixId: ownerMatrixId,
      status: status,
      visibility: ChallengeVisibility.group,
      revision: 1,
      startsAt: challenge.startsAt,
      endsAt: challenge.endsAt,
      updatedAt: now,
    );
    await database
        .into(database.outgoingMatrixEvents)
        .insertOnConflictUpdate(
          OutgoingMatrixEventsCompanion(
            id: Value('challenge-${_statusName(status)}-$id-1'),
            eventType: Value(eventType),
            roomId: Value(roomId),
            entityId: Value(id),
            payloadJson: Value(jsonEncode(payload)),
            state: const Value('queued'),
            attemptCount: const Value(0),
            nextAttemptAt: Value(now),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Map<String, dynamic> _challengeEventPayload({
    required String id,
    required String segmentId,
    required String name,
    required String roomId,
    required String? ownerMatrixId,
    required ChallengeStatus status,
    required ChallengeVisibility visibility,
    required int revision,
    required DateTime? startsAt,
    required DateTime? endsAt,
    required DateTime updatedAt,
  }) {
    final payload = {
      'challengeId': id,
      'revision': revision,
      'segmentId': segmentId,
      'name': name,
      'status': _statusName(status),
      'visibility': _visibilityName(visibility),
      'sourceRoomId': roomId,
      'authorMatrixId': ownerMatrixId,
      'startsAt': startsAt?.toIso8601String(),
      'deadline': endsAt?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
    final payloadJson = jsonEncode(payload);
    return {
      'schemaVersion': 1,
      'entityId': id,
      'revision': revision,
      'authorMatrixId': ownerMatrixId,
      'timestamp': updatedAt.toIso8601String(),
      'payload': payload,
      'payloadHash': sha256.convert(utf8.encode(payloadJson)).toString(),
    };
  }

  String _statusName(ChallengeStatus status) => status.name;

  String _visibilityName(ChallengeVisibility visibility) => visibility.name;

  Future<void> _ensureRoom(String? roomId, DateTime updatedAt) async {
    if (roomId == null || roomId.isEmpty) return;
    await database
        .into(database.rooms)
        .insertOnConflictUpdate(
          RoomsCompanion(
            id: Value(roomId),
            matrixRoomId: Value(roomId),
            type: const Value('group'),
            updatedAt: Value(updatedAt),
          ),
        );
  }
}
