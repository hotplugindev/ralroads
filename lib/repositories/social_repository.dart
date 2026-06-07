import 'dart:async';
import '../database/app_database.dart';
import 'friend_repository.dart';
import 'group_repository.dart';
import 'profile_repository.dart';

class SocialSnapshot {
  const SocialSnapshot({
    required this.profile,
    required this.friends,
    required this.pendingRequests,
    required this.groups,
  });

  final Profile? profile;
  final List<Friendship> friends;
  final List<FriendRequest> pendingRequests;
  final List<Group> groups;
}

class SocialRepository {
  SocialRepository({
    required ProfileRepository profiles,
    required FriendRepository friends,
    required GroupRepository groups,
  }) : _profiles = profiles,
       _friends = friends,
       _groups = groups;

  final ProfileRepository _profiles;
  final FriendRepository _friends;
  final GroupRepository _groups;

  Future<SocialSnapshot> loadLocalSnapshot() async {
    final profile = await _profiles.getCurrentLocalProfile();
    return SocialSnapshot(
      profile: profile,
      friends: profile == null
          ? const []
          : await _friends.listCachedFriends(profile.id),
      pendingRequests: profile == null
          ? const []
          : await _friends.listPendingRequests(profile.id),
      groups: await _groups.listCachedGroups(),
    );
  }

  Stream<SocialSnapshot> watchLocalSnapshot() {
    late StreamController<SocialSnapshot> controller;
    StreamSubscription? profileSub;
    StreamSubscription? friendsSub;
    StreamSubscription? requestSub;
    StreamSubscription? groupsSub;

    void update() async {
      if (controller.isClosed) return;
      try {
        final profile = await _profiles.getCurrentLocalProfile();
        final friends = profile == null
            ? const <Friendship>[]
            : await _friends.listCachedFriends(profile.id);
        final requests = profile == null
            ? const <FriendRequest>[]
            : await _friends.listPendingRequests(profile.id);
        final groups = await _groups.listCachedGroups();
        if (!controller.isClosed) {
          controller.add(SocialSnapshot(
            profile: profile,
            friends: friends,
            pendingRequests: requests,
            groups: groups,
          ));
        }
      } catch (e) {
        // Ignored
      }
    }

    controller = StreamController<SocialSnapshot>(
      onListen: () {
        profileSub = _profiles.database.select(_profiles.database.profiles).watch().listen((_) => update());
        friendsSub = _friends.database.select(_friends.database.friendships).watch().listen((_) => update());
        requestSub = _friends.database.select(_friends.database.friendRequests).watch().listen((_) => update());
        groupsSub = _groups.database.select(_groups.database.groups).watch().listen((_) => update());
        update();
      },
      onCancel: () {
        profileSub?.cancel();
        friendsSub?.cancel();
        requestSub?.cancel();
        groupsSub?.cancel();
      },
    );
    return controller.stream;
  }
}
