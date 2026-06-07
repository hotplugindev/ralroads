import 'package:flutter/material.dart';

import '../../../database/app_database.dart';
import '../../../repositories/app_repositories.dart';
import '../../../repositories/trip_repository.dart';
import '../../../services/settings_service.dart';
import '../../../utils/format_helpers.dart';
import '../../../widgets/product_components.dart';
import '../../../screens/trip_recording_screen.dart';
import '../../../screens/trip_summary_screen.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({
    required this.repositories,
    required this.settings,
    super.key,
  });

  final AppRepositories repositories;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<TripStats>(
      stream: repositories.trips.watchStats(),
      builder: (context, statsSnapshot) {
        return StreamBuilder<List<TripSummary>>(
          stream: repositories.trips.watchTrips(limit: 20),
          builder: (context, tripsSnapshot) {
            final stats = statsSnapshot.data;
            final trips = tripsSnapshot.data;
            if (stats == null || trips == null) {
              return const LoadingState(label: 'Loading trips');
            }

            return RalRoadsPage(
              title: 'Trips',
              children: [
                PrimaryActionCard(
                  title: 'Record a local trip',
                  subtitle:
                      'Trips are private by default and can later become legal challenge attempts.',
                  icon: Icons.fiber_manual_record,
                  actionLabel: 'Start',
                  onPressed: () => _startRecording(context),
                ),
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
                          label: 'Total Runs',
                          value: '${stats.totalTrips}',
                          icon: Icons.timeline,
                          color: scheme.primary,
                        ),
                        _buildStatCard(
                          context,
                          label: 'Total Distance',
                          value: formatDistance(stats.totalDistanceMeters),
                          icon: Icons.explore_outlined,
                          color: scheme.secondary,
                        ),
                        _buildStatCard(
                          context,
                          label: 'Clean Runs',
                          value: '${stats.cleanEligibleTrips}',
                          icon: Icons.verified_outlined,
                          color: Colors.green,
                        ),
                        _buildStatCard(
                          context,
                          label: 'Default Privacy',
                          value: 'Private',
                          icon: Icons.lock_outline,
                          color: Colors.blue,
                        ),
                      ],
                    );
                  },
                ),
                const SectionHeader(title: 'Recent trips'),
                if (trips.isEmpty)
                  const EmptyState(
                    title: 'No trips recorded',
                    message:
                        'Start a local recording to build history, summaries and private segments.',
                  )
                else
                  for (final trip in trips) _buildTripItem(context, trip),
              ],
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
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
                          color: scheme.onSurfaceVariant,
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
    );
  }

  Widget _buildTripItem(BuildContext context, TripSummary trip) {
    final scheme = Theme.of(context).colorScheme;
    final dateStr = formatDate(trip.startedAt);
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
            builder: (_) => TripSummaryScreen(
              repository: repositories.trips,
              tripId: trip.id,
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
                      trip.name ?? 'Unnamed Run',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  AttemptStatusBadge(
                    status: trip.cleanEligible ? 'finished' : 'gps_quality',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Started on $dateStr',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTripDetailInfo(
                    context,
                    Icons.straighten,
                    'Distance',
                    formatDistance(trip.distanceMeters),
                  ),
                  _buildTripDetailInfo(
                    context,
                    Icons.lock_outline,
                    'Privacy',
                    'Private',
                  ),
                  _buildTripDetailInfo(
                    context,
                    Icons.check_circle_outline,
                    'Clean Run',
                    trip.cleanEligible ? 'Eligible' : 'No',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripDetailInfo(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _startRecording(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripRecordingScreen(
          repository: repositories.trips,
          settings: settings,
        ),
      ),
    );
  }
}
