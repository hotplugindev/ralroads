import 'package:flutter/material.dart';

import '../controllers/driving_session_controller.dart';
import '../services/settings_service.dart';
import '../screens/drive_screen.dart';
import '../screens/trip_summary_screen.dart';

class ActiveSessionBar extends StatelessWidget {
  const ActiveSessionBar({
    required this.drivingSession,
    required this.settings,
    super.key,
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
                    const PulsingDot(),
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

class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  PulsingDotState createState() => PulsingDotState();
}

class PulsingDotState extends State<PulsingDot>
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
