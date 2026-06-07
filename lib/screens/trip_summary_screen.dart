import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../repositories/trip_repository.dart';
import '../utils/format_helpers.dart';
import '../widgets/product_components.dart';
import 'segment_creation_screen.dart';

class TripSummaryScreen extends StatelessWidget {
  const TripSummaryScreen({
    required this.repository,
    required this.tripId,
    super.key,
  });

  final TripRepository repository;
  final String tripId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TripSummary?>(
      stream: repository.watchTrip(tripId),
      builder: (context, tripSnap) {
        return FutureBuilder<(TripPointStats, List<TripPoint>)>(
          future: _loadStats(),
          builder: (context, statsSnap) {
            final trip = tripSnap.data;
            if (!tripSnap.hasData || !statsSnap.hasData) {
              return const Scaffold(body: LoadingState(label: 'Loading trip'));
            }
            if (trip == null) {
              return const Scaffold(
                body: ErrorState(message: 'Trip was not found locally.'),
              );
            }
            final pts = statsSnap.data!.$1;
            final points = statsSnap.data!.$2;
            return _TripSummaryView(
              repository: repository,
              trip: trip,
              pointStats: pts,
              points: points,
            );
          },
        );
      },
    );
  }

  Future<(TripPointStats, List<TripPoint>)> _loadStats() async {
    return (
      await repository.pointStats(tripId),
      await repository.pointsForTrip(tripId),
    );
  }
}

// ─── Main summary view ───────────────────────────────────────────────────────

class _TripSummaryView extends StatelessWidget {
  const _TripSummaryView({
    required this.repository,
    required this.trip,
    required this.pointStats,
    required this.points,
  });

  final TripRepository repository;
  final TripSummary trip;
  final TripPointStats pointStats;
  final List<TripPoint> points;

  // Key used to capture the shareable card
  final GlobalKey _shareKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final duration = (trip.endedAt ?? DateTime.now()).difference(trip.startedAt);
    final scheme = Theme.of(context).colorScheme;
    final speedPoints = points
        .where((p) => p.speedMps != null && p.speedMps! >= 0)
        .toList();
    final maxSpeedMps = speedPoints.isEmpty
        ? 0.0
        : speedPoints.map((p) => p.speedMps!).reduce((a, b) => a > b ? a : b);
    final avgSpeedMps = speedPoints.isEmpty
        ? 0.0
        : speedPoints.map((p) => p.speedMps!).reduce((a, b) => a + b) /
            speedPoints.length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(trip.name ?? 'Trip'),
            floating: true,
            actions: [
              IconButton(
                tooltip: 'Share trip card',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => _shareCard(context),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _onMenu(context, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'privacy', child: Text('Set privacy')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList.separated(
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemCount: 8,
              itemBuilder: (context, index) {
                return switch (index) {
                  0 => _ShareableCard(
                      repaintKey: _shareKey,
                      trip: trip,
                      duration: duration,
                      maxSpeedMps: maxSpeedMps,
                      avgSpeedMps: avgSpeedMps,
                    ),
                  1 => _StatsGrid(
                      trip: trip,
                      duration: duration,
                      pointStats: pointStats,
                      maxSpeedMps: maxSpeedMps,
                      avgSpeedMps: avgSpeedMps,
                    ),
                  2 => speedPoints.length > 2
                      ? _SpeedGraph(points: speedPoints)
                      : const SizedBox.shrink(),
                  3 => _GpsQualityBar(pointStats: pointStats),
                  4 => const _LegalDisclaimer(),
                  5 => FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SegmentCreationScreen(
                            tripRepository: repository,
                            tripId: trip.id,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.linear_scale),
                      label: const Text('Create segment from this trip'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  6 => OutlinedButton.icon(
                      onPressed: () => _shareCard(context),
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Share trip card as image'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  7 => TextButton.icon(
                      onPressed: () => _delete(context),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete this trip'),
                      style: TextButton.styleFrom(foregroundColor: scheme.error),
                    ),
                  _ => const SizedBox.shrink(),
                };
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareCard(BuildContext context) async {
    try {
      final boundary = _shareKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not capture card.')),
          );
        }
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final name = (trip.name ?? 'trip').replaceAll(RegExp(r'[^\w]'), '_');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: '$name.png', mimeType: 'image/png')],
          text: 'Trip: ${trip.name ?? 'Trip'} — ${formatDistance(trip.distanceMeters)}',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }
  }

  void _onMenu(BuildContext context, String action) {
    switch (action) {
      case 'rename':
        _rename(context);
      case 'privacy':
        _privacy(context);
      case 'delete':
        _delete(context);
    }
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: trip.name ?? 'Trip');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename trip'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await repository.renameTrip(trip.id, name);
    // The stream from watchTrip will auto-update the screen title.
  }

  Future<void> _privacy(BuildContext context) async {
    await repository.updatePrivacy(trip.id, 'private');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip privacy is local/private.')),
      );
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete trip?'),
        content: const Text(
          'This removes the local trip and all its recorded GPS points.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await repository.deleteTrip(trip.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

// ─── Shareable card (also captured for PNG export) ───────────────────────────

class _ShareableCard extends StatelessWidget {
  const _ShareableCard({
    required this.repaintKey,
    required this.trip,
    required this.duration,
    required this.maxSpeedMps,
    required this.avgSpeedMps,
  });

  final GlobalKey repaintKey;
  final TripSummary trip;
  final Duration duration;
  final double maxSpeedMps;
  final double avgSpeedMps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clean = trip.cleanEligible;

    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer,
              scheme.secondaryContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_road, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'RalRoads',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: scheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: clean ? Colors.green.withValues(alpha: 0.2) : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: clean ? Colors.green : scheme.error,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    clean ? 'Clean eligible' : 'Not clean',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: clean ? Colors.green : scheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              trip.name ?? 'Trip',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              formatDate(trip.startedAt),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CardStat(
                  label: 'Distance',
                  value: formatDistance(trip.distanceMeters),
                  icon: Icons.straighten,
                ),
                _CardStat(
                  label: 'Duration',
                  value: formatDuration(duration),
                  icon: Icons.timer_outlined,
                ),
                _CardStat(
                  label: 'Top speed',
                  value: maxSpeedMps > 0
                      ? formatSpeed(maxSpeedMps)
                      : '—',
                  icon: Icons.speed,
                ),
                _CardStat(
                  label: 'Avg speed',
                  value: avgSpeedMps > 0
                      ? formatSpeed(avgSpeedMps)
                      : '—',
                  icon: Icons.avg_pace,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  const _CardStat({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─── Stats grid ──────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.trip,
    required this.duration,
    required this.pointStats,
    required this.maxSpeedMps,
    required this.avgSpeedMps,
  });

  final TripSummary trip;
  final Duration duration;
  final TripPointStats pointStats;
  final double maxSpeedMps;
  final double avgSpeedMps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (Icons.straighten, 'Distance', formatDistance(trip.distanceMeters)),
      (Icons.timer_outlined, 'Duration', formatDuration(duration)),
      (Icons.speed, 'Top speed', maxSpeedMps > 0 ? formatSpeed(maxSpeedMps) : '—'),
      (Icons.avg_pace, 'Avg speed', avgSpeedMps > 0 ? formatSpeed(avgSpeedMps) : '—'),
      (Icons.gps_fixed, 'GPS points', '${pointStats.pointCount}'),
      (
        Icons.location_searching,
        'Avg accuracy',
        pointStats.averageGpsAccuracyMeters != null
            ? '${pointStats.averageGpsAccuracyMeters!.toStringAsFixed(1)} m'
            : '—'
      ),
      (
        Icons.speed_outlined,
        'Limit coverage',
        '${((pointStats.speedLimitCoverage * 100).round())}%'
      ),
      (
        Icons.verified_outlined,
        'Status',
        trip.cleanEligible ? 'Clean eligible' : 'Not clean'
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: [
        for (final item in items)
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(item.$1, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.$3,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.$2,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Speed graph ─────────────────────────────────────────────────────────────

class _SpeedGraph extends StatelessWidget {
  const _SpeedGraph({required this.points});

  final List<TripPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Speed profile',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: CustomPaint(
            painter: _SpeedPainter(points: points, color: scheme.primary),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }
}

class _SpeedPainter extends CustomPainter {
  _SpeedPainter({required this.points, required this.color});

  final List<TripPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final speeds = points.map((p) => p.speedMps ?? 0.0).toList();
    final maxSpeed = speeds.reduce((a, b) => a > b ? a : b);
    if (maxSpeed <= 0) return;

    final path = Path();
    final fillPath = Path();
    final step = size.width / (speeds.length - 1).clamp(1, 10000);

    for (var i = 0; i < speeds.length; i++) {
      final x = i * step;
      final y = size.height - (speeds[i] / maxSpeed) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()..color = color.withValues(alpha: 0.15),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedPainter old) =>
      old.points != points || old.color != color;
}

// ─── GPS quality bar ─────────────────────────────────────────────────────────

class _GpsQualityBar extends StatelessWidget {
  const _GpsQualityBar({required this.pointStats});

  final TripPointStats pointStats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final acc = pointStats.averageGpsAccuracyMeters;
    // Quality: <5 m = great, <15 m = good, <30 m = fair, else poor
    final (label, frac, color) = acc == null
        ? ('Unknown', 0.5, scheme.outline)
        : acc < 5
            ? ('Excellent (${acc.toStringAsFixed(1)} m)', 1.0, Colors.green)
            : acc < 15
                ? ('Good (${acc.toStringAsFixed(1)} m)', 0.75, Colors.lightGreen)
                : acc < 30
                    ? ('Fair (${acc.toStringAsFixed(1)} m)', 0.45, Colors.orange)
                    : ('Poor (${acc.toStringAsFixed(1)} m)', 0.2, scheme.error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GPS quality',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                  Text(
                    '${((pointStats.speedLimitCoverage * 100).round())}% speed limit coverage',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHigh,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Legal disclaimer ────────────────────────────────────────────────────────

class _LegalDisclaimer extends StatelessWidget {
  const _LegalDisclaimer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This local summary does not claim independent validation or complete speed-limit coverage. '
              'Legal certainty depends on road data quality at the time of recording.',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
