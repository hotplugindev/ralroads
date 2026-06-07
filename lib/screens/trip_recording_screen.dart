import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../controllers/trip_recording_controller.dart';
import '../repositories/trip_repository.dart';
import '../services/settings_service.dart';
import '../utils/format_helpers.dart';
import '../widgets/product_components.dart';
import 'trip_summary_screen.dart';

class TripRecordingScreen extends StatefulWidget {
  const TripRecordingScreen({
    required this.repository,
    required this.settings,
    super.key,
  });

  final TripRepository repository;
  final SettingsService settings;

  @override
  State<TripRecordingScreen> createState() => _TripRecordingScreenState();
}

class _TripRecordingScreenState extends State<TripRecordingScreen> {
  late final TripRecordingController _controller;
  bool _backgroundPermissionGranted = true;

  @override
  void initState() {
    super.initState();
    _controller = TripRecordingController(
      tripRepository: widget.repository,
      settings: widget.settings,
    );
    WakelockPlus.enable();
    _controller.start();
    _checkBackgroundPermission();
  }

  Future<void> _checkBackgroundPermission() async {
    final status = await Permission.locationAlways.status;
    if (mounted) {
      setState(() {
        _backgroundPermissionGranted = status.isGranted;
      });
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final snapshot = _controller.snapshot;
          return RalRoadsPage(
            title: 'Recording',
            children: [
              if (!_backgroundPermissionGranted)
                const ErrorState(
                  message:
                      'Background recording is disabled. Keep the app open and screen on to record.',
                ),
              _SpeedPanel(snapshot: snapshot),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusChip(
                    icon: Icons.gps_fixed,
                    label:
                        '${snapshot.gpsAccuracyMeters.toStringAsFixed(0)} m GPS',
                  ),
                  StatusChip(
                    icon: Icons.verified_outlined,
                    label: snapshot.cleanEligible
                        ? 'Clean eligible'
                        : 'GPS quality issue',
                  ),
                  StatusChip(
                    icon: Icons.timeline,
                    label: '${snapshot.pointCount} points',
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: snapshot.state == TripRecordingState.recording
                          ? _controller.pause
                          : snapshot.state == TripRecordingState.paused
                          ? _controller.resume
                          : null,
                      icon: Icon(
                        snapshot.state == TripRecordingState.paused
                            ? Icons.play_arrow
                            : Icons.pause,
                      ),
                      label: Text(
                        snapshot.state == TripRecordingState.paused
                            ? 'Resume'
                            : 'Pause',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          snapshot.state == TripRecordingState.recording ||
                              snapshot.state == TripRecordingState.paused
                          ? _stop
                          : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed:
                    snapshot.state == TripRecordingState.recording ||
                        snapshot.state == TripRecordingState.paused
                    ? _cancel
                    : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Cancel recording'),
              ),
              if (snapshot.errorMessage != null)
                ErrorState(message: snapshot.errorMessage!),
            ],
          );
        },
      ),
    );
  }

  Future<void> _stop() async {
    final tripId = await _controller.finish();
    if (!mounted || tripId == null) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            TripSummaryScreen(repository: widget.repository, tripId: tripId),
      ),
    );
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel recording?'),
        content: const Text('This deletes the local trip and recorded points.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep recording'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel trip'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _controller.cancel();
    if (mounted) Navigator.of(context).pop();
  }
}

class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({required this.snapshot});

  final TripRecordingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final speedKmh = (snapshot.speedMps * 3.6).clamp(0, 999).round();
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current speed', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        '$speedKmh',
                        style: Theme.of(
                          context,
                        ).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Text('km/h'),
                    ],
                  ),
                ),
                if (snapshot.speedLimitKmh != null)
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red, width: 6),
                      color: Colors.white,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${snapshot.speedLimitKmh}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text(formatDistance(snapshot.distanceMeters))),
                Expanded(child: Text(formatDuration(snapshot.elapsed))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
