import 'package:flutter/material.dart';

import '../../../controllers/app_session_controller.dart';
import '../../../controllers/matrix_social_controller.dart';
import '../../../database/app_database.dart';
import '../../../repositories/app_repositories.dart';
import '../../../repositories/social_repository.dart';
import '../../../repositories/profile_repository.dart';
import '../../../screens/matrix_connection_screen.dart';
import '../../../widgets/product_components.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({
    required this.repositories,
    required this.session,
    required this.accountController,
    required this.socialController,
    super.key,
  });

  final AppRepositories repositories;
  final AppSessionController session;
  final AccountConnectionController accountController;
  final MatrixSocialController socialController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([session, socialController]),
      builder: (context, _) {
        final snap = session.snapshot;
        final isConnected =
            snap.matrixStatus == MatrixConnectionStatus.connected;

        return StreamBuilder<SocialSnapshot>(
          stream: repositories.social.watchLocalSnapshot(),
          builder: (context, socialSnap) {
            final social = socialSnap.data;
            final localProfile = social?.profile;

            return StreamBuilder<List<CachedDirectoryEvent>>(
              stream: repositories.directories.watchRecentEvents(),
              builder: (context, directorySnap) {
                final directories =
                    directorySnap.data ?? const <CachedDirectoryEvent>[];

                return StreamBuilder<List<LocalNotification>>(
                  stream: repositories.notifications.watchUnreadNotifications(),
                  builder: (context, notifSnap) {
                    final unreadNotifs =
                        notifSnap.data ?? const <LocalNotification>[];

                    return StreamBuilder<List<BlockedUser>>(
                      stream: repositories.friends.database
                          .select(repositories.friends.database.blockedUsers)
                          .watch(),
                      builder: (context, blockedSnap) {
                        final blockedUsers =
                            blockedSnap.data ?? const <BlockedUser>[];

                        return RalRoadsPage(
                          title: 'Community',
                          actions: [
                            if (socialController.busy)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                          ],
                          children: [
                            // 1. Connection Card
                            _buildConnectionHeader(context, snap, scheme),

                            // 2. Profile Card
                            _buildProfileSection(
                              context,
                              localProfile,
                              scheme,
                              theme,
                            ),

                            // 3. Status Stats Row
                            if (isConnected)
                              _buildStatsRow(
                                social,
                                directories,
                                unreadNotifs,
                                blockedUsers,
                              ),

                            // 4. Quick Actions
                            if (isConnected) ...[
                              const SectionHeader(title: 'Quick Actions'),
                              _buildQuickActions(context, scheme),
                            ],

                            // 5. Notifications List
                            if (unreadNotifs.isNotEmpty) ...[
                              SectionHeader(
                                title: 'Unread Notifications',
                                trailing: StatusChip(
                                  label: '${unreadNotifs.length}',
                                  color: scheme.error,
                                ),
                              ),
                              for (final notif in unreadNotifs)
                                _buildNotificationTile(
                                  context,
                                  notif,
                                  scheme,
                                  theme,
                                ),
                            ],

                            // 6. Friend Requests Section
                            if (isConnected) ...[
                              SectionHeader(
                                title: 'Friend Requests',
                                trailing: StatusChip(
                                  label:
                                      '${social?.pendingRequests.length ?? 0}',
                                ),
                              ),
                              if ((social?.pendingRequests ?? const []).isEmpty)
                                const EmptyState(
                                  title: 'No pending requests',
                                  message:
                                      'Send requests or invite people by their Matrix User ID.',
                                )
                              else
                                for (final request in social!.pendingRequests)
                                  _buildRequestCard(
                                    context,
                                    request,
                                    localProfile,
                                    scheme,
                                    theme,
                                  ),
                            ],

                            // 7. Friends Section
                            if (isConnected) ...[
                              SectionHeader(
                                title: 'Friends List',
                                trailing: StatusChip(
                                  label: '${social?.friends.length ?? 0}',
                                ),
                              ),
                              if ((social?.friends ?? const []).isEmpty)
                                const EmptyState(
                                  title: 'No friends yet',
                                  message:
                                      'Connect with other drivers to share segments and challenge attempts.',
                                )
                              else
                                for (final friendship in social!.friends)
                                  _buildFriendCard(
                                    context,
                                    friendship,
                                    localProfile,
                                    scheme,
                                    theme,
                                  ),
                            ],

                            // 8. Groups Section
                            if (isConnected) ...[
                              SectionHeader(
                                title: 'Groups & Rooms',
                                trailing: StatusChip(
                                  label: '${social?.groups.length ?? 0}',
                                ),
                              ),
                              if ((social?.groups ?? const []).isEmpty)
                                const EmptyState(
                                  title: 'No active groups',
                                  message:
                                      'Create or join private groups to validate attempts and sync leaderboards.',
                                )
                              else
                                for (final group in social!.groups)
                                  _buildGroupCard(
                                    context,
                                    group,
                                    scheme,
                                    theme,
                                  ),
                            ],

                            // 9. Blocked Users Section
                            if (isConnected && blockedUsers.isNotEmpty) ...[
                              SectionHeader(
                                title: 'Blocked Users',
                                trailing: StatusChip(
                                  label: '${blockedUsers.length}',
                                  color: Colors.grey,
                                ),
                              ),
                              for (final blocked in blockedUsers)
                                Card(
                                  elevation: 0,
                                  color: scheme.surfaceContainerLow,
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.block,
                                      color: Colors.grey,
                                    ),
                                    title: Text(blocked.matrixUserId),
                                    subtitle: Text(
                                      blocked.reason ?? 'No reason provided',
                                    ),
                                    trailing: TextButton(
                                      onPressed: () => socialController
                                          .unblockUser(blocked.matrixUserId),
                                      child: const Text('Unblock'),
                                    ),
                                  ),
                                ),
                            ],

                            // 10. Subscribed Directories
                            const SectionHeader(
                              title: 'Subscribed Directories',
                            ),
                            if (directories.isEmpty)
                              const EmptyState(
                                title: 'No directory subscriptions',
                                message:
                                    'Subscribed regional directory events appear here after Matrix sync.',
                              )
                            else
                              for (final event in directories)
                                FeatureCard(
                                  title: event.eventType,
                                  subtitle:
                                      '${event.entityId} • Room: ${event.roomId}',
                                  icon: Icons.travel_explore_outlined,
                                ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildConnectionHeader(
    BuildContext context,
    AppSessionSnapshot snap,
    ColorScheme scheme,
  ) {
    final isConnected = snap.matrixStatus == MatrixConnectionStatus.connected;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isConnected
              ? [
                  scheme.primaryContainer,
                  scheme.secondaryContainer.withValues(alpha: 0.5),
                ]
              : [scheme.surfaceContainerHigh, scheme.surfaceContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? scheme.primary.withValues(alpha: 0.3)
              : scheme.outlineVariant,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.hub_outlined,
            size: 32,
            color: isConnected ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matrix Networks',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isConnected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isConnected
                      ? 'Connected securely to Matrix. Live synchronization is active.'
                      : 'Matrix powers friends, groups, shared challenges, and E2EE.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isConnected
                        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    MatrixConnectionScreen(controller: accountController),
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: isConnected ? scheme.primary : scheme.secondary,
            ),
            child: Text(isConnected ? 'Manage' : 'Connect'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(
    BuildContext context,
    Profile? profile,
    ColorScheme scheme,
    ThemeData theme,
  ) {
    final hasProfile = profile != null;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasProfile
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHigh,
          child: Icon(
            Icons.person_outline,
            color: hasProfile
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          profile?.displayName ?? 'Local Driver Profile',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          profile?.matrixUserId != null
              ? 'Linked to Matrix: ${profile!.matrixUserId}'
              : 'Stored locally. Click to update profile name.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showProfileDialog(context, profile),
      ),
    );
  }

  Widget _buildStatsRow(
    SocialSnapshot? social,
    List<CachedDirectoryEvent> directories,
    List<LocalNotification> unreadNotifs,
    List<BlockedUser> blocked,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          StatusChip(label: '${social?.friends.length ?? 0} Friends'),
          const SizedBox(width: 8),
          StatusChip(label: '${social?.pendingRequests.length ?? 0} Requests'),
          const SizedBox(width: 8),
          StatusChip(label: '${social?.groups.length ?? 0} Groups'),
          const SizedBox(width: 8),
          StatusChip(label: '${directories.length} Directories'),
          const SizedBox(width: 8),
          if (blocked.isNotEmpty)
            StatusChip(label: '${blocked.length} Blocked', color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            label: 'Add Friend',
            icon: Icons.person_add_alt_outlined,
            color: scheme.primary,
            onTap: () => _showAddFriendDialog(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickActionButton(
            label: 'Create Group',
            icon: Icons.group_add_outlined,
            color: scheme.secondary,
            onTap: () => _showCreateGroupDialog(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickActionButton(
            label: 'Join Group',
            icon: Icons.login_outlined,
            color: scheme.tertiary,
            onTap: () => _showJoinGroupDialog(context),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationTile(
    BuildContext context,
    LocalNotification notif,
    ColorScheme scheme,
    ThemeData theme,
  ) {
    return Card(
      elevation: 0,
      color: scheme.errorContainer.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.error.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.notifications_active_outlined, color: scheme.error),
        title: Text(
          notif.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(notif.body ?? ''),
        trailing: IconButton(
          icon: const Icon(Icons.check),
          tooltip: 'Mark as read',
          onPressed: () => repositories.notifications.markAsRead(notif.id),
        ),
      ),
    );
  }

  Widget _buildRequestCard(
    BuildContext context,
    FriendRequest request,
    Profile? localProfile,
    ColorScheme scheme,
    ThemeData theme,
  ) {
    final isIncoming = request.toProfileId == localProfile?.id;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: const Icon(Icons.person_add_alt_1_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isIncoming
                        ? 'Incoming Friend Request'
                        : 'Outgoing Friend Request',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    isIncoming
                        ? 'From Profile: ${request.fromProfileId}'
                        : 'To Profile: ${request.toProfileId}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (isIncoming) ...[
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                tooltip: 'Accept',
                onPressed: () => socialController.acceptFriendRequest(request),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: 'Reject',
                onPressed: () => socialController.rejectFriendRequest(request),
              ),
            ] else
              StatusChip(label: 'Pending', color: scheme.outline),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendCard(
    BuildContext context,
    Friendship friendship,
    Profile? localProfile,
    ColorScheme scheme,
    ThemeData theme,
  ) {
    final friendId = friendship.profileId == localProfile?.id
        ? friendship.friendProfileId
        : friendship.profileId;

    return FutureBuilder<Profile?>(
      future: (repositories.profiles.database.select(
        repositories.profiles.database.profiles,
      )..where((row) => row.id.equals(friendId))).getSingleOrNull(),
      builder: (context, snap) {
        final profile = snap.data;
        return Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              child: const Icon(Icons.person),
            ),
            title: Text(profile?.displayName ?? friendId),
            subtitle: Text(profile?.matrixUserId ?? 'No linked User ID'),
            trailing: IconButton(
              icon: const Icon(Icons.block_outlined, color: Colors.grey),
              tooltip: 'Block User',
              onPressed: () => _showBlockUserDialog(
                context,
                profile?.matrixUserId ?? friendId,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupCard(
    BuildContext context,
    Group group,
    ColorScheme scheme,
    ThemeData theme,
  ) {
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: group.visibility == 'private'
              ? scheme.tertiaryContainer
              : scheme.primaryContainer,
          child: Icon(
            group.visibility == 'private' ? Icons.lock_outline : Icons.public,
          ),
        ),
        title: Text(group.name),
        subtitle: Text(group.description ?? 'Matrix Group Room'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: 'Invite Member',
              onPressed: () => _showInviteMemberDialog(context, group.roomId),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Dialog Helpers ─────────────────────────────────────────────────────────

  Future<void> _showProfileDialog(
    BuildContext context,
    Profile? profile,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) =>
          _ProfileDialog(profile: profile, repositories: repositories),
    );
  }

  Future<void> _showAddFriendDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AddFriendDialog(socialController: socialController),
    );
  }

  Future<void> _showCreateGroupDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _CreateGroupDialog(socialController: socialController),
    );
  }

  Future<void> _showJoinGroupDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _JoinGroupDialog(socialController: socialController),
    );
  }

  Future<void> _showInviteMemberDialog(
    BuildContext context,
    String roomId,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InviteMemberDialog(
        roomId: roomId,
        socialController: socialController,
      ),
    );
  }

  Future<void> _showBlockUserDialog(
    BuildContext context,
    String matrixUserId,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _BlockUserDialog(
        matrixUserId: matrixUserId,
        socialController: socialController,
      ),
    );
  }
}

// ─── Dialog Stateful Widgets ───────────────────────────────────────────────

class _ProfileDialog extends StatefulWidget {
  final Profile? profile;
  final AppRepositories repositories;

  const _ProfileDialog({required this.profile, required this.repositories});

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _regionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.profile?.displayName ?? '',
    );
    _regionController = TextEditingController(
      text: widget.profile?.homeRegion ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update Profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Display Name'),
          ),
          TextField(
            controller: _regionController,
            decoration: const InputDecoration(labelText: 'Home Region'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final newName = _nameController.text.trim();
            if (newName.isNotEmpty) {
              await widget.repositories.profiles.createOrUpdateLocalProfile(
                LocalProfileInput(
                  id: widget.profile?.id ?? 'local-profile',
                  matrixUserId: widget.profile?.matrixUserId,
                  displayName: newName,
                  homeRegion: _regionController.text.trim(),
                ),
              );
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _AddFriendDialog extends StatefulWidget {
  final MatrixSocialController socialController;
  const _AddFriendDialog({required this.socialController});

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Matrix Friend'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Matrix User ID',
          hintText: '@username:matrix.org',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final target = _controller.text.trim();
            if (target.isNotEmpty) {
              await widget.socialController.sendFriendRequest(target);
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Send Request'),
        ),
      ],
    );
  }
}

class _CreateGroupDialog extends StatefulWidget {
  final MatrixSocialController socialController;
  const _CreateGroupDialog({required this.socialController});

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  bool _encrypted = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Create Group Room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Group Name'),
            ),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            CheckboxListTile(
              title: const Text('Enable E2EE Encryption'),
              subtitle: const Text(
                'Secure all shared segment & attempt events',
              ),
              value: _encrypted,
              onChanged: (val) => setState(() => _encrypted = val ?? true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              if (name.isNotEmpty) {
                await widget.socialController.createGroup(
                  name,
                  _descController.text.trim().isEmpty
                      ? null
                      : _descController.text.trim(),
                  _encrypted,
                );
              }
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _JoinGroupDialog extends StatefulWidget {
  final MatrixSocialController socialController;
  const _JoinGroupDialog({required this.socialController});

  @override
  State<_JoinGroupDialog> createState() => _JoinGroupDialogState();
}

class _JoinGroupDialogState extends State<_JoinGroupDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join Group Room'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Room ID or Alias',
          hintText: '!roomid:matrix.org',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final target = _controller.text.trim();
            if (target.isNotEmpty) {
              await widget.socialController.joinGroup(target);
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Join'),
        ),
      ],
    );
  }
}

class _InviteMemberDialog extends StatefulWidget {
  final String roomId;
  final MatrixSocialController socialController;
  const _InviteMemberDialog({
    required this.roomId,
    required this.socialController,
  });

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite Member to Group'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Matrix User ID',
          hintText: '@username:matrix.org',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final target = _controller.text.trim();
            if (target.isNotEmpty) {
              await widget.socialController.inviteToGroup(
                widget.roomId,
                target,
              );
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Invite'),
        ),
      ],
    );
  }
}

class _BlockUserDialog extends StatefulWidget {
  final String matrixUserId;
  final MatrixSocialController socialController;
  const _BlockUserDialog({
    required this.matrixUserId,
    required this.socialController,
  });

  @override
  State<_BlockUserDialog> createState() => _BlockUserDialogState();
}

class _BlockUserDialogState extends State<_BlockUserDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Block User ${widget.matrixUserId}?'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Reason (optional)',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await widget.socialController.blockUser(
              widget.matrixUserId,
              reason: _controller.text.trim().isEmpty
                  ? null
                  : _controller.text.trim(),
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Block'),
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
