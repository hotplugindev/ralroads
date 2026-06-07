import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;

import '../../../controllers/app_session_controller.dart';
import '../../../controllers/matrix_social_controller.dart';
import '../../../database/app_database.dart';
import '../../../models/route_point.dart';
import '../../../repositories/app_repositories.dart';
import '../../../services/attempt_validator_service.dart';
import '../../../utils/format_helpers.dart';
import '../../../widgets/product_components.dart';
import '../../../services/settings_service.dart';
import '../../../screens/attempt_recording_screen.dart';

class ChallengeDetailScreen extends StatefulWidget {
  const ChallengeDetailScreen({
    required this.challengeId,
    required this.repositories,
    required this.session,
    required this.socialController,
    required this.settings,
    super.key,
  });

  final String challengeId;
  final AppRepositories repositories;
  final AppSessionController session;
  final MatrixSocialController socialController;
  final SettingsService settings;

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  late Future<
    (
      Challenge,
      ChallengeSegment,
      SegmentVersion,
      List<RoutePoint>,
      List<SegmentAttempt>,
      Profile?,
    )
  >
  _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
    // Periodically update active/ended statuses
    widget.repositories.challenges.evaluateDeadlines();
  }

  Future<
    (
      Challenge,
      ChallengeSegment,
      SegmentVersion,
      List<RoutePoint>,
      List<SegmentAttempt>,
      Profile?,
    )
  >
  _loadData() async {
    final challenge = await widget.repositories.challenges.getChallenge(
      widget.challengeId,
    );
    if (challenge == null) {
      throw Exception('Challenge not found.');
    }

    final segment = await widget.repositories.segments.getSegment(
      challenge.segmentId,
    );
    if (segment == null) {
      throw Exception('Segment not found.');
    }

    final versionId = segment.currentVersionId;
    if (versionId == null) {
      throw Exception('Segment currentVersionId is null.');
    }

    final version = await (widget.repositories.segments.database.select(
      widget.repositories.segments.database.segmentVersions,
    )..where((row) => row.id.equals(versionId))).getSingle();

    final geomList =
        await (widget.repositories.segments.database.select(
                widget.repositories.segments.database.segmentGeometry,
              )
              ..where((row) => row.versionId.equals(versionId))
              ..orderBy([(row) => drift.OrderingTerm.asc(row.pointIndex)]))
            .get();

    final points = geomList
        .map(
          (g) => RoutePoint(
            lat: g.lat,
            lon: g.lon,
            distanceFromStart: g.distanceFromStart,
          ),
        )
        .toList();

    final attempts = await widget.repositories.attempts.listAttemptsForSegment(
      challenge.segmentId,
    );

    final localProfile = await widget.repositories.profiles
        .getCurrentLocalProfile();

    return (challenge, segment, version, points, attempts, localProfile);
  }

  Future<String> _determineTrustLabel(
    SegmentAttempt attempt,
    Profile? localProfile,
  ) async {
    if (attempt.profileId == localProfile?.id) {
      return attempt.status == 'valid_clean' ? 'Locally validated' : 'Local';
    }

    if (attempt.profileId != null) {
      final groupMembership = await (widget.repositories.groups.database.select(
        widget.repositories.groups.database.groupMembers,
      )..where((row) => row.profileId.equals(attempt.profileId!))).get();

      if (groupMembership.isNotEmpty) {
        return 'Group trusted';
      }
    }

    return 'Shared / Unverified';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Rally Challenge Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body:
          FutureBuilder<
            (
              Challenge,
              ChallengeSegment,
              SegmentVersion,
              List<RoutePoint>,
              List<SegmentAttempt>,
              Profile?,
            )
          >(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingState(
                  label: 'Loading challenge details...',
                );
              }
              if (snapshot.hasError) {
                return ErrorState(
                  message: 'Error loading challenge: ${snapshot.error}',
                  onRetry: () => setState(() => _future = _loadData()),
                );
              }

              final data = snapshot.data;
              if (data == null) {
                return const ErrorState(
                  message: 'Challenge details not found.',
                );
              }

              final (
                challenge,
                segment,
                version,
                points,
                allAttempts,
                localProfile,
              ) = data;

              // Filter attempts to only match the challenge window
              final challengeAttempts = allAttempts.where((attempt) {
                if (challenge.startsAt != null &&
                    attempt.startedAt.isBefore(challenge.startsAt!)) {
                  return false;
                }
                if (challenge.endsAt != null &&
                    attempt.startedAt.isAfter(challenge.endsAt!)) {
                  return false;
                }
                return true;
              }).toList();

              // Sort attempts: valid/clean completions first, then duration ascending
              final validAttempts = challengeAttempts
                  .where((a) => a.finishedAt != null)
                  .toList();
              validAttempts.sort((a, b) {
                final durA = a.finishedAt!.difference(a.startedAt);
                final durB = b.finishedAt!.difference(b.startedAt);
                return durA.compareTo(durB);
              });

              final starts = challenge.startsAt != null
                  ? formatDate(challenge.startsAt!)
                  : 'Immediate';
              final ends = challenge.endsAt != null
                  ? formatDate(challenge.endsAt!)
                  : 'No deadline';
              final isActive =
                  challenge.status == 'active' || challenge.status == 'draft';
              final timeLabel = isActive
                  ? (challenge.endsAt != null
                        ? '${challenge.endsAt!.difference(DateTime.now()).inDays} days remaining'
                        : 'Active')
                  : 'Ended';

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Challenge Hero Card
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: scheme.primaryContainer.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: scheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                StatusChip(
                                  label: challenge.status.toUpperCase(),
                                  color: isActive ? Colors.green : Colors.grey,
                                ),
                                if (challenge.roomId != null)
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.groups_outlined,
                                        size: 16,
                                        color: scheme.secondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Group Shared',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
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
                                      const SizedBox(width: 4),
                                      Text(
                                        'Local Only',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              challenge.name,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Segment: ${segment.name}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Distance',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      formatDistance(version.distanceMeters),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Time Remaining',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      timeLabel,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: isActive
                                                ? Colors.green
                                                : Colors.grey,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Timeline: $starts ➔ $ends',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. Play / Attempt Primary CTA Card
                    if (isActive)
                      PrimaryActionCard(
                        title: 'Drive & Attempt Challenge',
                        subtitle:
                            'Launch rally-assistant and complete the segment within target speed limits to qualify.',
                        icon: Icons.sports_motorsports_outlined,
                        actionLabel: 'Go',
                        onPressed: () => _startAttempt(segment, points),
                      ),

                    const SizedBox(height: 16),

                    // 3. Challenge Leaderboard Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SectionHeader(title: 'Challenge Leaderboard'),
                        if (challenge.roomId != null && localProfile != null)
                          IconButton(
                            icon: const Icon(Icons.share_outlined),
                            tooltip: 'Share Challenge Link',
                            onPressed: () =>
                                _shareChallenge(context, challenge),
                          ),
                      ],
                    ),

                    if (validAttempts.isEmpty)
                      const EmptyState(
                        title: 'No attempts recorded during challenge',
                        message:
                            'Drive this segment to post the first time on the leaderboard!',
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: validAttempts.length,
                        itemBuilder: (context, index) {
                          final attempt = validAttempts[index];
                          final duration = attempt.finishedAt!.difference(
                            attempt.startedAt,
                          );
                          final isLocal = attempt.profileId == localProfile?.id;

                          return FutureBuilder<String>(
                            future: _determineTrustLabel(attempt, localProfile),
                            builder: (context, labelSnap) {
                              final trustLabel = labelSnap.data ?? 'Local';

                              Color badgeColor;
                              switch (trustLabel) {
                                case 'Locally validated':
                                  badgeColor = Colors.teal;
                                  break;
                                case 'Group trusted':
                                  badgeColor = Colors.blue;
                                  break;
                                case 'Shared / Unverified':
                                  badgeColor = Colors.orange;
                                  break;
                                default:
                                  badgeColor = Colors.grey;
                              }

                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 8),
                                color: scheme.surfaceContainerLow,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: isLocal
                                        ? scheme.primary.withValues(alpha: 0.3)
                                        : scheme.outlineVariant.withValues(
                                            alpha: 0.4,
                                          ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      // Rank Icon or number
                                      _buildRankWidget(context, index + 1),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  formatDuration(duration),
                                                  style: theme
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: isLocal
                                                            ? scheme.primary
                                                            : null,
                                                      ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: badgeColor
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                    border: Border.all(
                                                      color: badgeColor
                                                          .withValues(
                                                            alpha: 0.3,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    trustLabel,
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: badgeColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Driver: ${attempt.profileId ?? "Unknown"} • ${formatDate(attempt.startedAt)}',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isLocal &&
                                          attempt.status == 'valid_clean')
                                        IconButton(
                                          icon: const Icon(
                                            Icons.share_outlined,
                                          ),
                                          tooltip: 'Share Attempt',
                                          onPressed: () => _shareAttempt(
                                            context,
                                            attempt.id,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _buildRankWidget(BuildContext context, int rank) {
    final scheme = Theme.of(context).colorScheme;
    if (rank == 1) {
      return const CircleAvatar(
        radius: 16,
        backgroundColor: Colors.amber,
        child: Icon(Icons.emoji_events, color: Colors.white, size: 18),
      );
    } else if (rank == 2) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey.shade400,
        child: const Icon(Icons.emoji_events, color: Colors.white, size: 18),
      );
    } else if (rank == 3) {
      return const CircleAvatar(
        radius: 16,
        backgroundColor: Colors.brown,
        child: Icon(Icons.emoji_events, color: Colors.white, size: 18),
      );
    } else {
      return CircleAvatar(
        radius: 16,
        backgroundColor: scheme.surfaceContainerHigh,
        child: Text(
          '$rank',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
  }

  Future<void> _startAttempt(
    ChallengeSegment segment,
    List<RoutePoint> points,
  ) async {
    final validatorService = AttemptValidatorService(
      attemptRepository: widget.repositories.attempts,
      segmentRepository: widget.repositories.segments,
    );

    final needsRefresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AttemptRecordingScreen(
          segmentId: segment.id,
          segmentName: segment.name,
          segmentPoints: points,
          attemptRepository: widget.repositories.attempts,
          validatorService: validatorService,
          settings: widget.settings,
        ),
      ),
    );

    if (needsRefresh == true) {
      setState(() => _future = _loadData());
    }
  }

  Future<void> _shareAttempt(BuildContext context, String attemptId) async {
    final rooms = await widget.repositories.groups.database
        .select(widget.repositories.groups.database.rooms)
        .get();

    if (rooms.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join a group to share this attempt.')),
      );
      return;
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Share Attempt to Group',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                return ListTile(
                  leading: Icon(
                    room.type == 'group'
                        ? Icons.groups_outlined
                        : Icons.person_outline,
                  ),
                  title: Text(room.name ?? room.matrixRoomId),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await widget.socialController.shareAttempt(
                      room.matrixRoomId,
                      attemptId,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Attempt sharing queued.'),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareChallenge(
    BuildContext context,
    Challenge challenge,
  ) async {
    // If the challenge is already shared to a room, copy details or notify user
    if (challenge.roomId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Challenge is active in group: ${challenge.roomId}'),
        ),
      );
    }
  }
}
