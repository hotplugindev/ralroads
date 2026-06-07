import 'package:flutter/material.dart';

import '../controllers/app_session_controller.dart';
import '../controllers/driving_session_controller.dart';
import '../database/app_database.dart';
import '../repositories/app_repositories.dart';
import '../repositories/profile_repository.dart';
import '../repositories/social_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/route_storage_service.dart';
import '../services/settings_service.dart';
import '../utils/format_helpers.dart';
import '../widgets/product_components.dart';
import 'map_planner_screen.dart';
import 'matrix_connection_screen.dart';
import 'offline_maps_screen.dart';
import 'onboarding_screen.dart';
import 'saved_routes_screen.dart';
import 'settings_screen.dart';
import 'trip_recording_screen.dart';
import 'trip_summary_screen.dart';
import 'segment_detail_screen.dart';
import 'drive_screen.dart';

class RalRoadsAppShell extends StatefulWidget {
  const RalRoadsAppShell({
    required this.storage,
    required this.settings,
    required this.repositories,
    required this.session,
    required this.accountController,
    required this.drivingSession,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;
  final AppRepositories repositories;
  final AppSessionController session;
  final AccountConnectionController accountController;
  final DrivingSessionController drivingSession;

  @override
  State<RalRoadsAppShell> createState() => _RalRoadsAppShellState();
}

class _RalRoadsAppShellState extends State<RalRoadsAppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.session.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        if (!widget.session.snapshot.onboardingComplete) {
          return OnboardingScreen(
            storage: widget.storage,
            settings: widget.settings,
            session: widget.session,
            accountController: widget.accountController,
            repositories: widget.repositories,
          );
        }

        final tabs = [
          _NavigateTab(parent: widget),
          _ChallengesTab(parent: widget),
          _TripsTab(parent: widget),
          _CommunityTab(parent: widget),
          _SettingsTab(parent: widget),
        ];
        final destinations = const [
          NavigationDestination(
            icon: Icon(Icons.navigation),
            label: 'Navigate',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            label: 'Challenges',
          ),
          NavigationDestination(icon: Icon(Icons.timeline), label: 'Trips'),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            label: 'Community',
          ),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 800) {
              return Scaffold(
                body: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: (value) =>
                          setState(() => _index = value),
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.navigation),
                          label: Text('Navigate'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.emoji_events_outlined),
                          label: Text('Challenges'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.timeline),
                          label: Text('Trips'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.groups_outlined),
                          label: Text('Community'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings),
                          label: Text('Settings'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: IndexedStack(index: _index, children: tabs),
                          ),
                          _ActiveSessionBar(
                            drivingSession: widget.drivingSession,
                            settings: widget.settings,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            return Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: IndexedStack(index: _index, children: tabs),
                  ),
                  _ActiveSessionBar(
                    drivingSession: widget.drivingSession,
                    settings: widget.settings,
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _index,
                destinations: destinations,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
              ),
            );
          },
        );
      },
    );
  }
}

class _NavigateTab extends StatelessWidget {
  const _NavigateTab({required this.parent});

  final RalRoadsAppShell parent;

  @override
  Widget build(BuildContext context) {
    final savedRoutes = parent.repositories.navigation.getSavedRoutes();
    final orsConnected = parent.settings.hasEffectiveOrsApiKey();
    return RalRoadsPage(
      title: 'Navigate',
      children: [
        PrimaryActionCard(
          title: 'Plan a route',
          subtitle: orsConnected
              ? 'Search places, add stops and start a road-aware route.'
              : 'Connect OpenRouteService for online route planning. Saved routes still work offline.',
          icon: Icons.add_road,
          actionLabel: orsConnected ? 'Plan' : 'Connect ORS',
          onPressed: () =>
              orsConnected ? _openPlanner(context) : _openSettings(context),
        ),
        const SectionHeader(title: 'Saved routes'),
        if (savedRoutes.isEmpty)
          EmptyState(
            title: 'No saved routes yet',
            message:
                'Routes you save after planning remain available locally for preview and driving.',
            action: OutlinedButton.icon(
              onPressed: () => _openSavedRoutes(context),
              icon: const Icon(Icons.bookmarks),
              label: const Text('Open saved routes'),
            ),
          )
        else
          for (final route in savedRoutes.take(3))
            RouteCard(
              title: route.name,
              subtitle: formatDistance(route.totalDistance),
              onTap: () => _openSavedRoutes(context),
            ),
        FeatureCard(
          title: 'Offline maps',
          subtitle: 'Manage downloaded map regions and offline readiness.',
          icon: Icons.map_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OfflineMapsScreen(
                storage: parent.storage,
                settings: parent.settings,
              ),
            ),
          ),
        ),
        FeatureCard(
          title: 'Navigation settings',
          subtitle: 'Voice, callouts, route overlays and ORS connection.',
          icon: Icons.tune,
          onTap: () => _openSettings(context),
        ),
      ],
    );
  }

  void _openPlanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapPlannerScreen(
          storage: parent.storage,
          settings: parent.settings,
          drivingSession: parent.drivingSession,
        ),
      ),
    );
  }

  void _openSavedRoutes(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedRoutesScreen(
          storage: parent.storage,
          settings: parent.settings,
          drivingSession: parent.drivingSession,
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          storage: parent.storage,
          settings: parent.settings,
          session: parent.session,
          accountController: parent.accountController,
        ),
      ),
    );
  }
}

class _TripsTab extends StatelessWidget {
  const _TripsTab({required this.parent});

  final RalRoadsAppShell parent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TripStats>(
      stream: parent.repositories.trips.watchStats(),
      builder: (context, statsSnapshot) {
        return StreamBuilder<List<TripSummary>>(
          stream: parent.repositories.trips.watchTrips(limit: 20),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusChip(label: '${stats.totalTrips} trips'),
                    StatusChip(
                      label: formatDistance(stats.totalDistanceMeters),
                    ),
                    StatusChip(
                      label: '${stats.cleanEligibleTrips} clean local',
                    ),
                    const StatusChip(label: 'Private by default'),
                  ],
                ),
                const SectionHeader(title: 'Recent trips'),
                if (trips.isEmpty)
                  const EmptyState(
                    title: 'No trips recorded',
                    message:
                        'Start a local recording to build history, summaries and private segments.',
                  )
                else
                  for (final trip in trips)
                    TripCard(
                      title: trip.name ?? 'Trip',
                      subtitle:
                          '${formatDistance(trip.distanceMeters)} • ${trip.status} • private',
                      trailing: AttemptStatusBadge(
                        status: trip.cleanEligible ? 'finished' : 'gps_quality',
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TripSummaryScreen(
                            repository: parent.repositories.trips,
                            tripId: trip.id,
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
  }

  Future<void> _startRecording(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripRecordingScreen(
          repository: parent.repositories.trips,
          settings: parent.settings,
        ),
      ),
    );
  }
}

class _ChallengesTab extends StatelessWidget {
  const _ChallengesTab({required this.parent});

  final RalRoadsAppShell parent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Challenge>>(
      stream: parent.repositories.challenges.watchActiveChallenges(),
      builder: (context, challengesSnapshot) {
        return StreamBuilder<List<ChallengeSegment>>(
          stream: parent.repositories.segments.watchLocalSegments(limit: 20),
          builder: (context, segmentsSnapshot) {
            final challenges = challengesSnapshot.data ?? const <Challenge>[];
            final segments =
                segmentsSnapshot.data ?? const <ChallengeSegment>[];
            return RalRoadsPage(
              title: 'Challenges',
              children: [
                PrimaryActionCard(
                  title: 'Create a local challenge',
                  subtitle:
                      'Use a private local segment now. Friend and group sharing require Matrix.',
                  icon: Icons.emoji_events_outlined,
                  actionLabel: 'Create',
                  onPressed: () => _createChallenge(context, segments),
                ),
                const SectionHeader(title: 'Active challenges'),
                if (challenges.isEmpty)
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
                  for (final challenge in challenges)
                    ChallengeCard(
                      title: challenge.name,
                      subtitle: '${challenge.status} • local results',
                    ),
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
                      subtitle: '${segment.visibility} • local segment',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SegmentDetailScreen(
                            segmentId: segment.id,
                            repositories: parent.repositories,
                            session: parent,
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
    final now = DateTime.now();
    final segment = segments.first;
    await parent.repositories.challenges.createLocalChallenge(
      id: 'challenge-${now.microsecondsSinceEpoch}',
      segmentId: segment.id,
      name: 'Local challenge',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Local challenge created.')));
  }

  void _connectMatrix(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MatrixConnectionScreen(controller: parent.accountController),
      ),
    );
  }
}

class _CommunityTab extends StatelessWidget {
  const _CommunityTab({required this.parent});

  final RalRoadsAppShell parent;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: parent.session,
      builder: (context, _) {
        final session = parent.session.snapshot;
        return StreamBuilder<SocialSnapshot>(
          stream: parent.repositories.social.watchLocalSnapshot(),
          builder: (context, snapshot) {
            final social = snapshot.data;
            return RalRoadsPage(
              title: 'Community',
              children: [
                ConnectionCard(
                  title: 'Matrix',
                  status: session.matrixStatus.name,
                  icon: Icons.hub_outlined,
                  description:
                      'Matrix powers friends, groups, shared challenges, sync and moderation. No fake users are shown while disconnected.',
                  actionLabel:
                      session.matrixStatus == MatrixConnectionStatus.connected
                      ? 'Manage'
                      : 'Connect Matrix',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MatrixConnectionScreen(
                        controller: parent.accountController,
                      ),
                    ),
                  ),
                ),
                FeatureCard(
                  title: social?.profile?.displayName ?? 'Local profile',
                  subtitle: social?.profile == null
                      ? 'Create a local-only profile for trips and private segments.'
                      : 'Stored locally${social!.profile!.matrixUserId == null ? '' : ' and linked to Matrix'}.',
                  icon: Icons.person_outline,
                  onTap: () => _createLocalProfile(context),
                ),
                SectionHeader(
                  title: 'Friends',
                  trailing: StatusChip(label: '${social?.friends.length ?? 0}'),
                ),
                if ((social?.friends ?? const []).isEmpty)
                  const EmptyState(
                    title: 'No cached friends',
                    message:
                        'Friend data appears here after Matrix connection and sync.',
                  ),
                SectionHeader(
                  title: 'Groups',
                  trailing: StatusChip(label: '${social?.groups.length ?? 0}'),
                ),
                if ((social?.groups ?? const []).isEmpty)
                  EmptyState(
                    title: 'No local groups',
                    message:
                        'Create a private local draft, then connect Matrix to invite others.',
                    action: OutlinedButton.icon(
                      onPressed: () => _createLocalGroup(context),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Create local group'),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createLocalProfile(BuildContext context) async {
    await parent.repositories.profiles.createOrUpdateLocalProfile(
      LocalProfileInput(
        id: 'local-profile',
        displayName: 'Local driver',
        homeRegion: 'Local',
      ),
    );
  }

  Future<void> _createLocalGroup(BuildContext context) async {
    final now = DateTime.now();
    await parent.repositories.groups.createLocalDraftGroup(
      id: 'local-group-${now.microsecondsSinceEpoch}',
      name: 'Local group',
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.parent});

  final RalRoadsAppShell parent;

  @override
  Widget build(BuildContext context) {
    final session = parent.session.snapshot;
    return RalRoadsPage(
      title: 'Settings',
      children: [
        ConnectionCard(
          title: 'OpenRouteService',
          status: session.orsStatus.name,
          icon: Icons.route_outlined,
          description:
              'ORS powers online route planning and place search. Offline saved routes do not require it.',
          actionLabel: 'Open settings',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(
                storage: parent.storage,
                settings: parent.settings,
                session: parent.session,
                accountController: parent.accountController,
              ),
            ),
          ),
        ),
        ConnectionCard(
          title: 'Matrix',
          status: session.matrixStatus.name,
          icon: Icons.hub_outlined,
          description:
              'Connect a Matrix account for friends, groups, sync and challenge sharing.',
          actionLabel: 'Connect Matrix',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  MatrixConnectionScreen(controller: parent.accountController),
            ),
          ),
        ),
        FeatureCard(
          title: 'Offline maps',
          subtitle: 'Manage local map regions.',
          icon: Icons.map_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OfflineMapsScreen(
                storage: parent.storage,
                settings: parent.settings,
              ),
            ),
          ),
        ),
        SyncStatusIndicator(
          label: session.matrixStatus == MatrixConnectionStatus.connected
              ? 'Ready to sync'
              : 'Local only',
        ),
      ],
    );
  }
}

class _ActiveSessionBar extends StatelessWidget {
  const _ActiveSessionBar({
    required this.drivingSession,
    required this.settings,
  });

  final DrivingSessionController drivingSession;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: drivingSession,
      builder: (context, _) {
        final snap = drivingSession.snapshot;
        if (snap.state != DrivingSessionState.active &&
            snap.state != DrivingSessionState.paused) {
          return const SizedBox.shrink();
        }

        final isAttempt = snap.config?.attemptMode == true;
        final title = isAttempt
            ? 'Segment Attempt: ${snap.config?.segmentName ?? "Active"}'
            : 'Active Driving Session';

        final recordingText = snap.recording ? 'Recording' : 'Navigation Only';
        final elapsedStr = _formatDuration(snap.elapsed);
        final distStr = (snap.distanceMeters / 1000.0).toStringAsFixed(2);
        final subtitle = '$recordingText • $distStr km • $elapsedStr';

        return Material(
          elevation: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: Theme.of(context).brightness == Brightness.dark
                    ? [Colors.teal.withValues(alpha: 0.2), Colors.black87]
                    : [Colors.teal.shade50, Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DriveScreen(
                      routePoints: drivingSession.activeRoutePoints,
                      pacenotes: drivingSession.activeNotes,
                      roadWarnings: drivingSession.visibleRoadWarnings,
                      speedLimitSegments:
                          drivingSession.visibleSpeedLimitSegments,
                      settings: settings,
                      drivingSession: drivingSession,
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  if (snap.recording) ...[
                    const _PulsingDot(),
                    const SizedBox(width: 12),
                  ] else ...[
                    Icon(
                      Icons.navigation,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      snap.state == DrivingSessionState.paused
                          ? Icons.play_arrow
                          : Icons.pause,
                    ),
                    onPressed: () {
                      if (snap.state == DrivingSessionState.paused) {
                        drivingSession.resumeSession();
                      } else {
                        drivingSession.pauseSession();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop, color: Colors.red),
                    onPressed: () async {
                      final tripId = await drivingSession.finishSession();
                      if (context.mounted && tripId != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TripSummaryScreen(
                              repository: drivingSession.tripRepository,
                              tripId: tripId,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '$hh:$mm:$ss';
    return '$mm:$ss';
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  _PulsingDotState createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
