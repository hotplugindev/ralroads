import 'package:drift/drift.dart';

import '../database/app_database.dart';

class LocalProfileInput {
  const LocalProfileInput({
    required this.id,
    required this.displayName,
    this.avatarUri,
    this.homeRegion,
    this.matrixUserId,
    this.visibility = 'private',
  });

  final String id;
  final String displayName;
  final String? avatarUri;
  final String? homeRegion;
  final String? matrixUserId;
  final String visibility;
}

class ProfileRepository {
  ProfileRepository(this.database);

  final AppDatabase database;

  Future<Profile> createOrUpdateLocalProfile(LocalProfileInput input) async {
    final now = DateTime.now();
    await database
        .into(database.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion(
            id: Value(input.id),
            matrixUserId: Value(input.matrixUserId),
            displayName: Value(input.displayName),
            avatarUri: Value(input.avatarUri),
            homeRegion: Value(input.homeRegion),
            visibility: Value(input.visibility),
            updatedAt: Value(now),
          ),
        );
    return (database.select(
      database.profiles,
    )..where((row) => row.id.equals(input.id))).getSingle();
  }

  Future<Profile?> getCurrentLocalProfile() {
    return (database.select(database.profiles)
          ..where((row) => row.matrixUserId.isNull())
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<Profile?> watchCurrentLocalProfile() {
    return (database.select(database.profiles)
          ..where((row) => row.matrixUserId.isNull())
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<void> updateProfileDetails({
    required String id,
    String? displayName,
    String? avatarUri,
    String? homeRegion,
  }) {
    return (database.update(
      database.profiles,
    )..where((row) => row.id.equals(id))).write(
      ProfilesCompanion(
        displayName: displayName == null
            ? const Value.absent()
            : Value(displayName),
        avatarUri: avatarUri == null ? const Value.absent() : Value(avatarUri),
        homeRegion: homeRegion == null
            ? const Value.absent()
            : Value(homeRegion),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
