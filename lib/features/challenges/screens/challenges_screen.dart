import 'package:flutter/material.dart';

import '../../../database/app_database.dart';
import '../../../repositories/app_repositories.dart';
import '../../../controllers/app_session_controller.dart';
import '../../../controllers/matrix_social_controller.dart';
import '../../../screens/matrix_connection_screen.dart';
import '../../../screens/segment_detail_screen.dart';
import '../../../widgets/product_components.dart';
import '../../../utils/format_helpers.dart';
import '../../../services/settings_service.dart';
import 'challenge_detail_screen.dart';

class ChallengesScreen extends StatelessWidget {
  const ChallengesScreen({
    required this.repositories,
    required this.session,
    required this.socialController,
    required this.accountController,
    required this.settings,
    super.key,
  });

  final AppRepositories repositories;
  final AppSessionController session;
  final MatrixSocialController socialController;
  final AccountConnectionController accountController;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return StreamBuilder<List<Challenge>>(
      stream: repositories.challenges.watchActiveChallenges(),
      builder: (context, activeSnapshot) {
        return StreamBuilder<List<Challenge>>(
          stream: repositories.challenges.watchPastChallenges(),
          builder: (context, pastSnapshot) {
            return StreamBuilder<List<ChallengeSegment>>(
              stream: repositories.segments.watchLocalSegments(limit: 20),
              builder: (context, segmentsSnapshot) {
                return StreamBuilder<List<SegmentAttempt>>(
                  stream: repositories.attempts.database
                      .select(repositories.attempts.database.segmentAttempts)
                      .watch(),
                  builder: (context, attemptsSnapshot) {
                    final activeChallenges =
                        activeSnapshot.data ?? const <Challenge>[];
                    final pastChallenges =
                        pastSnapshot.data ?? const <Challenge>[];
                    final segments =
                        segmentsSnapshot.data ?? const <ChallengeSegment>[];
                    final totalAttempts =
                        attemptsSnapshot.data ?? const <SegmentAttempt>[];

                    final matrixStatus = session.snapshot.matrixStatus;
                    final matrixSession = session.snapshot.matrixSession;
                    final isConnected =
                        matrixStatus == MatrixConnectionStatus.connected ||
                        matrixStatus == MatrixConnectionStatus.syncing;
                    final matrixUsername =
                        matrixSession?.matrixUserId ?? 'Offline';

                    return RalRoadsPage(
                      title: 'Challenges',
                      children: [
                        // 1. Primary Create Challenge CTA Card
                        PrimaryActionCard(
                          title: 'Create a Rally Challenge',
                          subtitle:
                              'Select a saved segment, configure a duration, and invite group members or run locally.',
                          icon: Icons.emoji_events_outlined,
                          actionLabel: 'Configure',
                          onPressed: () => _createChallenge(context, segments),
                        ),

                        // 2. Stats Dashboard Grid
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 600;
                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: isWide ? 4 : 2,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: isWide ? 2.5 : 2.0,
                              children: [
                                _buildStatCard(
                                  context,
                                  label: 'Active Rally',
                                  value: '${activeChallenges.length}',
                                  icon: Icons.tour_outlined,
                                  color: scheme.primary,
                                ),
                                _buildStatCard(
                                  context,
                                  label: 'Completed Runs',
                                  value: '${totalAttempts.length}',
                                  icon: Icons.sports_score_outlined,
                                  color: Colors.green,
                                ),
                                _buildStatCard(
                                  context,
                                  label: 'My Segments',
                                  value: '${segments.length}',
                                  icon: Icons.map_outlined,
                                  color: scheme.secondary,
                                ),
                                _buildStatCard(
                                  context,
                                  label: isConnected
                                      ? 'Matrix Connected'
                                      : 'Matrix Offline',
                                  value: isConnected
                                      ? matrixUsername.split(':').first
                                      : 'Local Only',
                                  icon: isConnected
                                      ? Icons.cloud_done_outlined
                                      : Icons.cloud_off_outlined,
                                  color: isConnected
                                      ? Colors.blue
                                      : Colors.orange,
                                  onTap: () => _connectMatrix(context),
                                ),
                              ],
                            );
                          },
                        ),

                        // 3. Active Challenges List
                        const SectionHeader(title: 'Active challenges'),
                        if (activeChallenges.isEmpty)
                          EmptyState(
                            title: 'No active challenges',
                            message:
                                'Create a local challenge from a segment or connect Matrix to federate and compete with others.',
                            action: !isConnected
                                ? OutlinedButton.icon(
                                    onPressed: () => _connectMatrix(context),
                                    icon: const Icon(Icons.hub_outlined),
                                    label: const Text('Connect Matrix'),
                                  )
                                : null,
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: activeChallenges.length,
                            itemBuilder: (context, index) {
                              final challenge = activeChallenges[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _buildChallengeItem(context, challenge),
                              );
                            },
                          ),

                        // 4. Past Challenges
                        if (pastChallenges.isNotEmpty) ...[
                          const SectionHeader(title: 'Past challenges'),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: pastChallenges.length,
                            itemBuilder: (context, index) {
                              final challenge = pastChallenges[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _buildChallengeItem(context, challenge),
                              );
                            },
                          ),
                        ],

                        // 5. My Segments Section
                        const SectionHeader(title: 'My segments'),
                        if (segments.isEmpty)
                          const EmptyState(
                            title: 'No segments created yet',
                            message:
                                'Open a completed trip summary and crop it to save your first private segment.',
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: segments.length,
                            itemBuilder: (context, index) {
                              final segment = segments[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SegmentCard(
                                  title: segment.name,
                                  subtitle:
                                      '${segment.visibility.toUpperCase()} • Local segment',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => SegmentDetailScreen(
                                        segmentId: segment.id,
                                        repositories: repositories,
                                        session: session,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
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
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChallengeItem(BuildContext context, Challenge challenge) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final starts = challenge.startsAt != null
        ? formatDate(challenge.startsAt!)
        : 'Immediate';
    final ends = challenge.endsAt != null
        ? formatDate(challenge.endsAt!)
        : 'No deadline';

    final isActive =
        challenge.status == 'active' || challenge.status == 'draft';
    final statusColor = isActive ? Colors.green : Colors.grey;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChallengeDetailScreen(
              challengeId: challenge.id,
              repositories: repositories,
              session: session,
              socialController: socialController,
              settings: settings,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      challenge.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  StatusChip(
                    label: challenge.status.toUpperCase(),
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Active: $starts ➔ $ends',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.emoji_events_outlined,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'View Leaderboard',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (challenge.roomId != null && challenge.roomId!.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.groups_outlined,
                          size: 16,
                          color: scheme.secondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Shared with group',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Private / Local',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createChallenge(
    BuildContext context,
    List<ChallengeSegment> segments,
  ) async {
    if (segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a segment from a trip first.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => _CreateChallengeDialog(
        repositories: repositories,
        session: session,
        segments: segments,
      ),
    );
  }

  void _connectMatrix(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MatrixConnectionScreen(controller: accountController),
      ),
    );
  }
}

class _CreateChallengeDialog extends StatefulWidget {
  final AppRepositories repositories;
  final AppSessionController session;
  final List<ChallengeSegment> segments;

  const _CreateChallengeDialog({
    required this.repositories,
    required this.session,
    required this.segments,
  });

  @override
  State<_CreateChallengeDialog> createState() => _CreateChallengeDialogState();
}

class _CreateChallengeDialogState extends State<_CreateChallengeDialog> {
  late final TextEditingController _nameController;
  late String _selectedSegmentId;
  int _durationDays = 7;
  String? _selectedRoomId;
  List<Group> _groups = [];
  bool _loadingGroups = true;

  @override
  void initState() {
    super.initState();
    _selectedSegmentId = widget.segments.first.id;
    _nameController = TextEditingController(
      text: 'Challenge: ${widget.segments.first.name}',
    );
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await widget.repositories.groups.listCachedGroups();
      if (mounted) {
        setState(() {
          _groups = groups;
          _loadingGroups = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingGroups = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Rally Challenge'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Challenge Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedSegmentId,
              decoration: const InputDecoration(
                labelText: 'Select Segment',
                border: OutlineInputBorder(),
              ),
              items: widget.segments.map((seg) {
                return DropdownMenuItem(value: seg.id, child: Text(seg.name));
              }).toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _selectedSegmentId = val;
                  final selectedSeg = widget.segments.firstWhere(
                    (s) => s.id == val,
                  );
                  _nameController.text = 'Challenge: ${selectedSeg.name}';
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _durationDays,
              decoration: const InputDecoration(
                labelText: 'Duration',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 Day')),
                DropdownMenuItem(value: 3, child: Text('3 Days')),
                DropdownMenuItem(value: 7, child: Text('7 Days')),
                DropdownMenuItem(value: 14, child: Text('14 Days')),
                DropdownMenuItem(value: 30, child: Text('30 Days')),
              ],
              onChanged: (val) {
                if (val == null) return;
                setState(() => _durationDays = val);
              },
            ),
            const SizedBox(height: 12),
            if (_loadingGroups)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<String?>(
                initialValue: _selectedRoomId,
                decoration: const InputDecoration(
                  labelText: 'Target Group (Optional)',
                  border: OutlineInputBorder(),
                  helperText: 'Private/Local challenge if left empty',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Private / Local Only'),
                  ),
                  ..._groups.map((group) {
                    return DropdownMenuItem<String?>(
                      value: group.roomId,
                      child: Text(group.name),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() => _selectedRoomId = val);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;

            final now = DateTime.now();
            final endsAt = now.add(Duration(days: _durationDays));

            await widget.repositories.challenges.createLocalChallenge(
              id: 'challenge-${now.microsecondsSinceEpoch}',
              segmentId: _selectedSegmentId,
              name: name,
              roomId: _selectedRoomId,
              startsAt: now,
              endsAt: endsAt,
              ownerMatrixId:
                  widget.session.snapshot.matrixSession?.matrixUserId,
            );

            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Rally challenge created successfully!'),
                ),
              );
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
