import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;

import '../controllers/matrix_social_controller.dart';
import '../database/app_database.dart';
import '../models/route_point.dart';
import '../repositories/app_repositories.dart';
import '../services/attempt_validator_service.dart';
import '../utils/format_helpers.dart';
import '../widgets/product_components.dart';
import 'attempt_recording_screen.dart';

class SegmentDetailScreen extends StatefulWidget {
  const SegmentDetailScreen({
    required this.segmentId,
    required this.repositories,
    required this.session,
    super.key,
  });

  final String segmentId;
  final AppRepositories repositories;
  final dynamic session;

  @override
  State<SegmentDetailScreen> createState() => _SegmentDetailScreenState();
}

class _SegmentDetailScreenState extends State<SegmentDetailScreen> {
  late Future<
    (
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
  }

  Future<
    (
      ChallengeSegment,
      SegmentVersion,
      List<RoutePoint>,
      List<SegmentAttempt>,
      Profile?,
    )
  >
  _loadData() async {
    final segment = await widget.repositories.segments.getSegment(
      widget.segmentId,
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
      widget.segmentId,
    );

    final localProfile = await widget.repositories.profiles
        .getCurrentLocalProfile();

    return (segment, version, points, attempts, localProfile);
  }

  MatrixSocialController? _getSocialController() {
    try {
      // Safely extract from parent RalRoadsAppShell if present
      final dynamic parent = widget.session;
      if (parent != null) {
        return parent.socialController as MatrixSocialController?;
      }
    } catch (_) {}
    return null;
  }

  Future<String> _determineTrustLabel(
    SegmentAttempt attempt,
    Profile? localProfile,
  ) async {
    if (attempt.profileId == localProfile?.id) {
      return attempt.status == 'valid_clean' ? 'Locally validated' : 'Local';
    }

    if (attempt.profileId != null) {
      // Check if profile belongs to any group in local database
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
    final socialController = _getSocialController();

    return Scaffold(
      body:
          FutureBuilder<
            (
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
                return const LoadingState(label: 'Loading segment details...');
              }
              if (snapshot.hasError) {
                return Scaffold(
                  body: ErrorState(
                    message: 'Error loading segment: ${snapshot.error}',
                    onRetry: () => setState(() => _future = _loadData()),
                  ),
                );
              }

              final data = snapshot.data;
              if (data == null) {
                return const Scaffold(
                  body: ErrorState(message: 'Segment details not found.'),
                );
              }

              final segment = data.$1;
              final version = data.$2;
              final points = data.$3;
              final attempts = data.$4;
              final localProfile = data.$5;

              // Sort attempts by duration (fastest first for valid ones)
              final sortedAttempts = List<SegmentAttempt>.from(attempts);
              sortedAttempts.sort((a, b) {
                if (a.status == 'valid_clean' && b.status != 'valid_clean') {
                  return -1;
                }
                if (a.status != 'valid_clean' && b.status == 'valid_clean') {
                  return 1;
                }
                return a.startedAt.compareTo(b.startedAt);
              });

              return RalRoadsPage(
                title: segment.name,
                actions: [
                  if (socialController != null)
                    IconButton(
                      icon: const Icon(Icons.share_outlined),
                      tooltip: 'Share Segment',
                      onPressed: () =>
                          _shareSegment(context, socialController, segment.id),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: () => setState(() => _future = _loadData()),
                  ),
                ],
                children: [
                  // 1. Segment Parameter Details
                  Card(
                    elevation: 0,
                    color: scheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Segment parameters',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Distance:'),
                              Text(
                                formatDistance(version.distanceMeters),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Visibility:'),
                              StatusChip(label: segment.visibility),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Safety status:'),
                              StatusChip(
                                label: version.safetyStatus,
                                color: version.safetyStatus == 'suitable'
                                    ? Colors.green
                                    : version.safetyStatus == 'questionable'
                                    ? Colors.orange
                                    : Colors.red,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. Primary Action Card to Start Attempt
                  PrimaryActionCard(
                    title: 'Start Segment Attempt',
                    subtitle:
                        'Drive the segment starting from the start gate. RalRoads will auto-detect your approach and validate your timing.',
                    icon: Icons.sports_motorsports_outlined,
                    actionLabel: 'Go',
                    onPressed: () => _startAttempt(segment, points),
                  ),

                  // 3. Leaderboard Section
                  SectionHeader(
                    title: 'Leaderboard',
                    trailing: StatusChip(
                      label: '${sortedAttempts.length} times',
                    ),
                  ),

                  if (sortedAttempts.isEmpty)
                    const EmptyState(
                      title: 'No attempts recorded yet',
                      message: 'Be the first to record a time on this segment.',
                    )
                  else
                    ...sortedAttempts.map((attempt) {
                      final durationStr = attempt.finishedAt != null
                          ? formatDuration(
                              attempt.finishedAt!.difference(attempt.startedAt),
                            )
                          : 'DNF';

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
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    attempt.status == 'valid_clean'
                                        ? Icons.verified_outlined
                                        : Icons.warning_amber_rounded,
                                    color: attempt.status == 'valid_clean'
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Time: $durationStr',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
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
                                                color: badgeColor.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: badgeColor.withValues(
                                                    alpha: 0.3,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                trustLabel,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
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
                                  // Attempt actions
                                  if (isLocal &&
                                      socialController != null &&
                                      attempt.status == 'valid_clean')
                                    IconButton(
                                      icon: const Icon(Icons.share_outlined),
                                      tooltip: 'Share Attempt',
                                      onPressed: () => _shareAttempt(
                                        context,
                                        socialController,
                                        attempt.id,
                                      ),
                                    ),
                                  if (!isLocal)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.report_problem_outlined,
                                        color: Colors.grey,
                                      ),
                                      tooltip: 'Report Content',
                                      onPressed: () => _reportAttempt(
                                        context,
                                        socialController,
                                        attempt.id,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }),
                ],
              );
            },
          ),
    );
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
          settings: widget.session.settings,
        ),
      ),
    );

    if (needsRefresh == true) {
      setState(() => _future = _loadData());
    }
  }

  Future<void> _shareSegment(
    BuildContext context,
    MatrixSocialController controller,
    String segmentId,
  ) async {
    final rooms = await widget.repositories.groups.database
        .select(widget.repositories.groups.database.rooms)
        .get();

    if (rooms.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join a group or add friends to share.')),
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
              'Share Segment to Room',
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
                  subtitle: Text(room.type),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await controller.shareSegment(room.matrixRoomId, segmentId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Segment sharing queued.'),
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

  Future<void> _shareAttempt(
    BuildContext context,
    MatrixSocialController controller,
    String attemptId,
  ) async {
    final rooms = await widget.repositories.groups.database
        .select(widget.repositories.groups.database.rooms)
        .get();

    if (rooms.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join a group or add friends to share.')),
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
              'Share Attempt to Room',
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
                  subtitle: Text(room.type),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await controller.shareAttempt(room.matrixRoomId, attemptId);
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

  Future<void> _reportAttempt(
    BuildContext context,
    MatrixSocialController? controller,
    String attemptId,
  ) async {
    if (controller == null) return;
    final reasonController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report Attempt'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason for report',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isNotEmpty) {
                await controller.reportContent(
                  targetType: 'attempt',
                  targetId: attemptId,
                  reason: reason,
                );
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    reasonController.dispose();
  }
}
