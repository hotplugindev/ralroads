import 'package:flutter/material.dart';

import '../../../database/app_database.dart';
import '../../../repositories/app_repositories.dart';
import '../../../screens/matrix_connection_screen.dart';
import '../../../screens/segment_detail_screen.dart';
import '../../../widgets/product_components.dart';
import '../../../utils/format_helpers.dart';

class ChallengesScreen extends StatelessWidget {
  const ChallengesScreen({
    required this.repositories,
    required this.session,
    super.key,
  });

  final AppRepositories repositories;
  final dynamic session;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Challenge>>(
      stream: repositories.challenges.watchActiveChallenges(),
      builder: (context, activeSnapshot) {
        return StreamBuilder<List<Challenge>>(
          stream: repositories.challenges.watchPastChallenges(),
          builder: (context, pastSnapshot) {
            return StreamBuilder<List<ChallengeSegment>>(
              stream: repositories.segments.watchLocalSegments(limit: 20),
              builder: (context, segmentsSnapshot) {
                final activeChallenges = activeSnapshot.data ?? const <Challenge>[];
                final pastChallenges = pastSnapshot.data ?? const <Challenge>[];
                final segments = segmentsSnapshot.data ?? const <ChallengeSegment>[];

                return RalRoadsPage(
                  title: 'Challenges',
                  children: [
                    PrimaryActionCard(
                      title: 'Create a challenge',
                      subtitle:
                          'Select a segment, set duration and optionally share to a Matrix group.',
                      icon: Icons.emoji_events_outlined,
                      actionLabel: 'Configure',
                      onPressed: () => _createChallenge(context, segments),
                    ),
                    const SectionHeader(title: 'Active challenges'),
                    if (activeChallenges.isEmpty)
                      EmptyState(
                        title: 'No active challenges',
                        message:
                            'Create a local challenge from a saved segment, or connect Matrix for friends and groups.',
                        action: OutlinedButton.icon(
                          onPressed: () => _connectMatrix(context),
                          icon: const Icon(Icons.hub_outlined),
                          label: const Text('Connect Matrix'),
                        ),
                      )
                    else
                      for (final challenge in activeChallenges)
                        _buildChallengeItem(context, challenge),
                    if (pastChallenges.isNotEmpty) ...[
                      const SectionHeader(title: 'Past challenges'),
                      for (final challenge in pastChallenges)
                        _buildChallengeItem(context, challenge),
                    ],
                    const SectionHeader(title: 'My segments'),
                    if (segments.isEmpty)
                      const EmptyState(
                        title: 'No local segments',
                        message:
                            'Open a completed trip summary and create a private segment.',
                      )
                    else
                      for (final segment in segments)
                        SegmentCard(
                          title: segment.name,
                          subtitle: '${segment.visibility.toUpperCase()} • local segment',
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
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildChallengeItem(BuildContext context, Challenge challenge) {
    final scheme = Theme.of(context).colorScheme;
    final starts = challenge.startsAt != null ? formatDate(challenge.startsAt!) : 'Immediate';
    final ends = challenge.endsAt != null ? formatDate(challenge.endsAt!) : 'No deadline';

    final isActive = challenge.status == 'active' || challenge.status == 'draft';
    final statusColor = isActive ? Colors.green : (challenge.status == 'ended' ? Colors.grey : Colors.orange);

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
            builder: (_) => SegmentDetailScreen(
              segmentId: challenge.segmentId,
              repositories: repositories,
              session: session,
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
              const SizedBox(height: 8),
              Text(
                'Active: $starts  ➔  $ends',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.linear_scale, size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'View Leaderboard',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  if (challenge.roomId != null && challenge.roomId!.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.groups_outlined, size: 16, color: scheme.secondary),
                        const SizedBox(width: 6),
                        Text(
                          'Shared with group',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          'Private / Local',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
        segments: segments,
      ),
    );
  }

  void _connectMatrix(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MatrixConnectionScreen(controller: session.accountController),
      ),
    );
  }
}

class _CreateChallengeDialog extends StatefulWidget {
  final AppRepositories repositories;
  final List<ChallengeSegment> segments;

  const _CreateChallengeDialog({
    required this.repositories,
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
              value: _selectedSegmentId,
              decoration: const InputDecoration(
                labelText: 'Select Segment',
                border: OutlineInputBorder(),
              ),
              items: widget.segments.map((seg) {
                return DropdownMenuItem(
                  value: seg.id,
                  child: Text(seg.name),
                );
              }).toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _selectedSegmentId = val;
                  final selectedSeg = widget.segments.firstWhere((s) => s.id == val);
                  _nameController.text = 'Challenge: ${selectedSeg.name}';
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _durationDays,
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
                value: _selectedRoomId,
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
            );

            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Rally challenge created successfully!')),
              );
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
