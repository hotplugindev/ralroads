import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;

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
  final dynamic
  session; // dynamic to avoid strong coupling with session controller imports

  @override
  State<SegmentDetailScreen> createState() => _SegmentDetailScreenState();
}

class _SegmentDetailScreenState extends State<SegmentDetailScreen> {
  late Future<
    (ChallengeSegment, SegmentVersion, List<RoutePoint>, List<SegmentAttempt>)
  >
  _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<
    (ChallengeSegment, SegmentVersion, List<RoutePoint>, List<SegmentAttempt>)
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

    return (segment, version, points, attempts);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body:
          FutureBuilder<
            (
              ChallengeSegment,
              SegmentVersion,
              List<RoutePoint>,
              List<SegmentAttempt>,
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

              return RalRoadsPage(
                title: segment.name,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: () => setState(() => _future = _loadData()),
                  ),
                ],
                children: [
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Segment parameters',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurfaceVariant,
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
                  PrimaryActionCard(
                    title: 'Start Segment Attempt',
                    subtitle:
                        'Drive the segment starting from the start gate. RalRoads will auto-detect your approach and validate your timing.',
                    icon: Icons.sports_motorsports_outlined,
                    actionLabel: 'Go',
                    onPressed: () => _startAttempt(segment, points),
                  ),
                  const SectionHeader(title: 'Attempts history'),
                  if (attempts.isEmpty)
                    const EmptyState(
                      title: 'No attempts recorded yet',
                      message: 'Be the first to record a time on this segment.',
                    )
                  else
                    ...attempts.map((attempt) {
                      final durationStr = attempt.finishedAt != null
                          ? formatDuration(
                              attempt.finishedAt!.difference(attempt.startedAt),
                            )
                          : 'DNF';
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          leading: Icon(
                            attempt.status == 'valid_clean'
                                ? Icons.verified
                                : Icons.warning_amber_rounded,
                            color: attempt.status == 'valid_clean'
                                ? Colors.green
                                : Colors.orange,
                          ),
                          title: Text(
                            'Time: $durationStr',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Date: ${formatDate(attempt.startedAt)}',
                          ),
                          trailing: AttemptStatusBadge(status: attempt.status),
                        ),
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
}
