import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../controllers/attempt_recording_controller.dart';
import '../models/route_point.dart';
import '../repositories/attempt_repository.dart';
import '../services/settings_service.dart';
import '../services/attempt_validator_service.dart';
import '../utils/format_helpers.dart';
import '../widgets/product_components.dart';

class AttemptRecordingScreen extends StatefulWidget {
  const AttemptRecordingScreen({
    required this.segmentId,
    required this.segmentName,
    required this.segmentPoints,
    required this.attemptRepository,
    required this.validatorService,
    required this.settings,
    super.key,
  });

  final String segmentId;
  final String segmentName;
  final List<RoutePoint> segmentPoints;
  final AttemptRepository attemptRepository;
  final AttemptValidatorService validatorService;
  final SettingsService settings;

  @override
  State<AttemptRecordingScreen> createState() => _AttemptRecordingScreenState();
}

class _AttemptRecordingScreenState extends State<AttemptRecordingScreen> {
  late final AttemptRecordingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AttemptRecordingController(
      segmentId: widget.segmentId,
      segmentPoints: widget.segmentPoints,
      attemptRepository: widget.attemptRepository,
      validatorService: widget.validatorService,
      settings: widget.settings,
    );
    WakelockPlus.enable();
    _controller.start();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final snapshot = _controller.snapshot;
          final isWaiting = snapshot.state == AttemptRecordingState.waitingToStart;
          final isRecording = snapshot.state == AttemptRecordingState.recording;
          final isFinished = snapshot.state == AttemptRecordingState.finished;
          final isAborted = snapshot.state == AttemptRecordingState.aborted;

          String statusTitle = 'Attempt';
          if (isWaiting) statusTitle = 'Approach Start';
          if (isRecording) statusTitle = 'Active Attempt';
          if (isFinished) statusTitle = 'Attempt Finished';
          if (isAborted) statusTitle = 'Attempt Aborted';

          return RalRoadsPage(
            title: statusTitle,
            children: [
              if (isWaiting) ...[
                Card(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Drive to segment start gate',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Distance to start: ${snapshot.distanceToStart.toStringAsFixed(0)} m',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'The recording will automatically start once you are within 35 meters of the start gate.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (isRecording) ...[
                Card(
                  color: Colors.green.withValues(alpha: 0.1),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Colors.green, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'RECORDING ATTEMPT',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.segmentName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _SpeedPanel(snapshot: snapshot),
                _ProgressPanel(
                  snapshot: snapshot,
                  totalDistance: widget.segmentPoints.isEmpty
                      ? 0
                      : widget.segmentPoints.last.distanceFromStart,
                ),
              ],
              if (isFinished) ...[
                Card(
                  color: theme.colorScheme.surfaceContainerHigh,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: Colors.green,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Processing and validating attempt...',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (snapshot.errorMessage != null)
                          Text(
                            snapshot.errorMessage!,
                            style: TextStyle(color: theme.colorScheme.error),
                          )
                        else
                          const Text(
                            'Please wait. Do not close the application.',
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Back to Segment'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (isAborted) ...[
                Card(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          size: 64,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Attempt Aborted',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.errorMessage ?? 'Driver cancelled the attempt.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Go Back'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (isWaiting || isRecording)
                OutlinedButton.icon(
                  onPressed: () => _confirmAbort(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Abort Attempt'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAbort(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abort attempt?'),
        content: const Text(
          'Abort current attempt? All current progress will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue driving'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abort'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _controller.abort();
      if (mounted) {
        Navigator.of(this.context).pop();
      }
    }
  }
}

class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({required this.snapshot});

  final AttemptRecordingSnapshot snapshot;

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
            Text('Current speed', style: Theme.of(context).textTheme.bodySmall),
            Text(
              '$speedKmh',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Text('km/h'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Distance: ${formatDistance(snapshot.distanceMeters)}')),
                Expanded(child: Text('Time: ${formatDuration(snapshot.elapsed)}')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.snapshot, required this.totalDistance});

  final AttemptRecordingSnapshot snapshot;
  final double totalDistance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = totalDistance > 0
        ? (snapshot.distanceMeters / totalDistance).clamp(0.0, 1.0)
        : 0.0;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progress',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Distance to Finish:',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '${snapshot.distanceToFinish.toStringAsFixed(0)} m',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
