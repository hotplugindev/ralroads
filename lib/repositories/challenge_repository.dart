import 'package:drift/drift.dart';

import '../database/app_database.dart';

class ChallengeRepository {
  ChallengeRepository(this.database);

  final AppDatabase database;

  Future<Challenge> createLocalChallenge({
    required String id,
    required String segmentId,
    required String name,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final now = DateTime.now();
    await database
        .into(database.challenges)
        .insertOnConflictUpdate(
          ChallengesCompanion(
            id: Value(id),
            segmentId: Value(segmentId),
            name: Value(name),
            status: const Value('draft'),
            startsAt: Value(startsAt),
            endsAt: Value(endsAt),
            updatedAt: Value(now),
          ),
        );
    return (database.select(
      database.challenges,
    )..where((row) => row.id.equals(id))).getSingle();
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
}
