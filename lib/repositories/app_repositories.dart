import '../database/app_database.dart';
import '../services/route_storage_service.dart';
import 'attempt_repository.dart';
import 'challenge_repository.dart';
import 'directory_repository.dart';
import 'friend_repository.dart';
import 'group_repository.dart';
import 'moderation_repository.dart';
import 'navigation_repository.dart';
import 'notification_repository.dart';
import 'offline_map_repository.dart';
import 'privacy_repository.dart';
import 'profile_repository.dart';
import 'segment_repository.dart';
import 'social_repository.dart';
import 'sync_repository.dart';
import 'trip_repository.dart';

class AppRepositories {
  AppRepositories({
    required RouteStorageService routeStorage,
    required AppDatabase database,
  }) : navigation = NavigationRepository(
         routeStorage: routeStorage,
         database: database,
       ),
       trips = TripRepository(database),
       profiles = ProfileRepository(database),
       friends = FriendRepository(database),
       groups = GroupRepository(database),
       segments = SegmentRepository(database),
       attempts = AttemptRepository(database),
       challenges = ChallengeRepository(database),
       sync = SyncRepository(database),
       offlineMaps = OfflineMapRepository(database),
       privacy = PrivacyRepository(database),
       moderation = ModerationRepository(database),
       notifications = NotificationRepository(database),
       directories = DirectoryRepository(database) {
    social = SocialRepository(
      profiles: profiles,
      friends: friends,
      groups: groups,
    );
  }

  final NavigationRepository navigation;
  final TripRepository trips;
  final ProfileRepository profiles;
  final FriendRepository friends;
  final GroupRepository groups;
  final SegmentRepository segments;
  final AttemptRepository attempts;
  final ChallengeRepository challenges;
  final SyncRepository sync;
  final OfflineMapRepository offlineMaps;
  final PrivacyRepository privacy;
  final ModerationRepository moderation;
  final NotificationRepository notifications;
  final DirectoryRepository directories;
  late final SocialRepository social;
}
