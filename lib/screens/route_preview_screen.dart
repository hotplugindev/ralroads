import 'package:flutter/material.dart';

import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/saved_route.dart';
import '../models/speed_limit_segment.dart';
import '../services/overpass_service.dart';
import '../services/pacenote_generator.dart';
import '../services/route_storage_service.dart';
import '../services/settings_service.dart';
import '../utils/format_helpers.dart';
import '../utils/ui_helpers.dart';
import 'drive_screen.dart';

class RoutePreviewScreen extends StatefulWidget {
  const RoutePreviewScreen({
    required this.storage,
    required this.settings,
    required this.points,
    required this.pacenotes,
    this.savedRoute,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;
  final List<RoutePoint> points;
  final List<PaceNote> pacenotes;
  final SavedRoute? savedRoute;

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  final _overpassService = OverpassService();
  final _pacenoteGenerator = PacenoteGenerator();
  late List<PaceNote> _pacenotes;
  late List<RoadWarning> _roadWarnings;
  late List<SpeedLimitSegment> _speedLimitSegments;
  bool _roadInfoLoading = false;
  bool _roadInfoFailed = false;

  double get _totalDistance =>
      widget.points.isEmpty ? 0 : widget.points.last.distanceFromStart;

  List<RoadWarning> get _visibleRoadWarnings =>
      filterRoadWarnings(_roadWarnings, widget.settings);

  List<SpeedLimitSegment> get _visibleSpeedLimitSegments =>
      widget.settings.showSpeedLimits ? _speedLimitSegments : const [];

  @override
  void initState() {
    super.initState();
    _pacenotes = widget.pacenotes;
    _roadWarnings = List<RoadWarning>.from(widget.savedRoute?.roadWarnings ?? const []);
    _speedLimitSegments = widget.savedRoute?.speedLimitSegments ?? const [];

    final hasElevationWarnings = _roadWarnings.any(
      (w) => w.type == RoadWarningType.crest || w.type == RoadWarningType.dip,
    );
    if (!hasElevationWarnings && widget.points.isNotEmpty) {
      final elevWarnings = _pacenoteGenerator.detectElevationFeatures(widget.points);
      if (elevWarnings.isNotEmpty) {
        _roadWarnings = [..._roadWarnings, ...elevWarnings];
      }
    }

    if (_roadWarnings.isNotEmpty || _speedLimitSegments.isNotEmpty) {
      _pacenotes = _pacenoteGenerator.refinePacenotesWithRoadContext(
        notes: _pacenotes,
        routePoints: widget.points,
        warnings: _roadWarnings,
        speedLimits: _speedLimitSegments,
      );
    }
    if (widget.savedRoute == null && widget.points.length >= 2) {
      _loadRoadInformation();
    }
  }

  Color _parseHexColor(String hex) {
    return Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routeName = widget.savedRoute?.name ?? 'Route preview';

    return Scaffold(
      appBar: AppBar(
        title: Text(routeName, style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _SummaryPanel(
            totalDistance: _totalDistance,
            pointCount: widget.points.length,
            pacenoteCount: _pacenotes.length,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DriveScreen(
                          routePoints: widget.points,
                          pacenotes: _pacenotes,
                          roadWarnings: _visibleRoadWarnings,
                          speedLimitSegments: _visibleSpeedLimitSegments,
                          settings: widget.settings,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.navigation),
                  label: const Text('Start Drive', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                  ),
                  onPressed: () => _saveRoute(context),
                  icon: const Icon(Icons.save),
                  label: const Text('Save Route', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildRoadInformation(context),
          const SizedBox(height: 24),
          Text(
            'Pacenotes',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_pacenotes.isEmpty)
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No notable curves were found for this route.'),
              ),
            )
          else
            ..._pacenotes.map(
              (note) {
                final color = Color(
                  int.parse(colorForPaceNote(note).substring(1), radix: 16) + 0xFF000000,
                );
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: theme.colorScheme.surfaceContainerLow.withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: note.type == PaceNoteType.straight
                          ? Icon(Icons.straight, size: 20, color: color)
                          : Text(
                              shortCalloutLabel(note),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                    ),
                    title: Text(
                      note.rallyText,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(
                      'At ${formatDistance(note.distanceFromStart)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _loadRoadInformation() async {
    setState(() {
      _roadInfoLoading = true;
      _roadInfoFailed = false;
    });

    try {
      final enrichment = await _overpassService.enrichRoute(widget.points);
      final elevationWarnings = _pacenoteGenerator.detectElevationFeatures(widget.points);
      if (!mounted) {
        return;
      }
      setState(() {
        _roadWarnings = [...enrichment.roadWarnings, ...elevationWarnings];
        _speedLimitSegments = enrichment.speedLimitSegments;
        _pacenotes = _pacenoteGenerator.refinePacenotesWithRoadContext(
          notes: widget.pacenotes,
          routePoints: widget.points,
          warnings: _roadWarnings,
          speedLimits: _speedLimitSegments,
        );
        _roadInfoLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _roadInfoLoading = false;
        _roadInfoFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Road warnings could not be loaded.')),
      );
    }
  }

  Widget _buildRoadInformation(BuildContext context) {
    final visibleWarnings = _visibleRoadWarnings;
    final visibleSpeedLimits = _visibleSpeedLimitSegments;
    final theme = Theme.of(context);

    if (_roadInfoLoading) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading road details...'),
            ],
          ),
        ),
      );
    }

    if (_roadInfoFailed) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Road information unavailable.'),
        ),
      );
    }

    if (visibleWarnings.isEmpty && visibleSpeedLimits.isEmpty) {
      return const SizedBox.shrink();
    }

    // Parse speed limits
    final speedLimits = <int>{};
    for (final segment in visibleSpeedLimits) {
      if (segment.parsedKmh != null) {
        speedLimits.add(segment.parsedKmh!);
      }
    }

    // Count warnings
    final warningCounts = <RoadWarningType, int>{};
    for (final warning in visibleWarnings) {
      warningCounts[warning.type] = (warningCounts[warning.type] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Speed limits section
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.speed, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'SPEED LIMITS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (speedLimits.isEmpty)
                  Text(
                    'No speed limits found',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: speedLimits.map((speed) {
                      return _SpeedLimitSign(speed: speed);
                    }).toList(),
                  ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),

                // Warning Counts summary
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'ROAD WARNINGS & FEATURES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (warningCounts.isEmpty)
                  Text(
                    'No warnings or features detected',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: warningCounts.entries.map((entry) {
                      final color = _parseHexColor(colorForRoadWarning(entry.key));
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withOpacity(0.2), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(iconForRoadWarning(entry.key), size: 12, color: color),
                            const SizedBox(width: 4),
                            Text(
                              '${entry.value} ${shortRoadWarningLabel(entry.key)}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        
        // Detailed warnings list
        if (visibleWarnings.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Road Details',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...visibleWarnings.take(12).map((warning) {
            final color = _parseHexColor(colorForRoadWarning(warning.type));
            return Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: theme.colorScheme.surfaceContainerLow.withOpacity(0.6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                ),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    iconForRoadWarning(warning.type),
                    color: color,
                    size: 16,
                  ),
                ),
                title: Text(
                  warning.text,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                subtitle: Text(
                  'At ${formatDistance(warning.distanceFromStart)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Future<void> _saveRoute(BuildContext context) async {
    final now = DateTime.now();
    final route = SavedRoute(
      id: widget.savedRoute?.id ?? now.microsecondsSinceEpoch.toString(),
      name: widget.savedRoute?.name ?? 'Route ${formatDate(now)}',
      createdAt: widget.savedRoute?.createdAt ?? now,
      totalDistance: _totalDistance,
      points: widget.points,
      pacenotes: _pacenotes,
      roadWarnings: _roadWarnings,
      speedLimitSegments: _speedLimitSegments,
    );

    await widget.storage.saveRoute(route);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Route saved')));
    }
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.totalDistance,
    required this.pointCount,
    required this.pacenoteCount,
  });

  final double totalDistance;
  final int pointCount;
  final int pacenoteCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: IntrinsicHeight(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMetricColumn(
                context,
                icon: Icons.straighten,
                label: 'DISTANCE',
                value: formatDistance(totalDistance),
              ),
              _buildVerticalDivider(theme),
              _buildMetricColumn(
                context,
                icon: Icons.analytics_outlined,
                label: 'POINTS',
                value: '$pointCount',
              ),
              _buildVerticalDivider(theme),
              _buildMetricColumn(
                context,
                icon: Icons.speaker_notes_outlined,
                label: 'PACENOTES',
                value: '$pacenoteCount',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalDivider(ThemeData theme) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      color: theme.colorScheme.outlineVariant.withOpacity(0.3),
    );
  }

  Widget _buildMetricColumn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SpeedLimitSign extends StatelessWidget {
  const _SpeedLimitSign({required this.speed});
  final int speed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.red, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$speed',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
