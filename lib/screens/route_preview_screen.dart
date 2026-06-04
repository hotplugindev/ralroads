import 'package:flutter/material.dart';

import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'dart:math' as math;
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
  late final PacenoteGenerator _pacenoteGenerator;
  late List<PaceNote> _pacenotes;
  late List<RoadWarning> _roadWarnings;
  late List<SpeedLimitSegment> _speedLimitSegments;
  bool _roadInfoLoading = false;
  bool _roadInfoFailed = false;

  maplibre.MapLibreMapController? _mapController;
  maplibre.Line? _routeLine;
  maplibre.Circle? _highlightCircle;
  maplibre.Symbol? _highlightLabel;
  final List<maplibre.Circle> _pacenoteCircles = [];
  final List<maplibre.Symbol> _pacenoteLabels = [];

  double get _totalDistance =>
      widget.points.isEmpty ? 0 : widget.points.last.distanceFromStart;

  List<RoadWarning> get _visibleRoadWarnings =>
      filterRoadWarnings(_roadWarnings, widget.settings);

  List<SpeedLimitSegment> get _visibleSpeedLimitSegments =>
      widget.settings.showSpeedLimits ? _speedLimitSegments : const [];

  @override
  void initState() {
    super.initState();
    _pacenoteGenerator = PacenoteGenerator(settings: widget.settings);
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
          Container(
            height: 220,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: maplibre.MapLibreMap(
              styleString: getMapStyle(context, widget.settings),
              initialCameraPosition: const maplibre.CameraPosition(
                target: maplibre.LatLng(43.8, 11.2),
                zoom: 5,
              ),
              attributionButtonPosition: maplibre.AttributionButtonPosition.bottomRight,
              attributionButtonMargins: const math.Point(-1000, -1000),
              myLocationEnabled: false,
              onMapCreated: (controller) async {
                _mapController = controller;
                await _drawRouteLine();
                await _drawPacenoteMarkers();
                await _fitCameraToRoute();
              },
            ),
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size.fromHeight(48),
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
                    isSimulation: true,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Simulate Drive', style: TextStyle(fontWeight: FontWeight.bold)),
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
            ..._pacenotes.asMap().entries.map(
              (entry) {
                final index = entry.key;
                final note = entry.value;
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
                    trailing: const Icon(Icons.edit, size: 16),
                    onTap: () => _editPacenote(context, note, index),
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

  Future<void> _drawRouteLine() async {
    final controller = _mapController;
    if (controller == null || widget.points.isEmpty) return;

    final existingLine = _routeLine;
    if (existingLine != null) {
      await controller.removeLine(existingLine);
    }

    final line = await controller.addLine(
      maplibre.LineOptions(
        geometry: widget.points
            .map((point) => maplibre.LatLng(point.lat, point.lon))
            .toList(),
        lineColor: '#00897B',
        lineWidth: 5,
        lineOpacity: 0.9,
      ),
    );

    setState(() {
      _routeLine = line;
    });
  }

  Future<void> _fitCameraToRoute() async {
    final controller = _mapController;
    if (controller == null || widget.points.isEmpty) return;

    if (widget.points.length == 1) {
      await controller.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(widget.points.first.lat, widget.points.first.lon),
          14,
        ),
      );
      return;
    }

    var minLat = widget.points.first.lat;
    var maxLat = widget.points.first.lat;
    var minLon = widget.points.first.lon;
    var maxLon = widget.points.first.lon;

    for (final pt in widget.points) {
      if (pt.lat < minLat) minLat = pt.lat;
      if (pt.lat > maxLat) maxLat = pt.lat;
      if (pt.lon < minLon) minLon = pt.lon;
      if (pt.lon > maxLon) maxLon = pt.lon;
    }

    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngBounds(
        maplibre.LatLngBounds(
          southwest: maplibre.LatLng(minLat, minLon),
          northeast: maplibre.LatLng(maxLat, maxLon),
        ),
        left: 30,
        right: 30,
        top: 30,
        bottom: 30,
      ),
    );
  }

  RoutePoint _findPointAtDistance(double distance) {
    if (widget.points.isEmpty) {
      return const RoutePoint(lat: 0, lon: 0);
    }
    RoutePoint closest = widget.points.first;
    double minDiff = (closest.distanceFromStart - distance).abs();

    for (final pt in widget.points) {
      final diff = (pt.distanceFromStart - distance).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = pt;
      }
    }
    return closest;
  }

  Future<void> _highlightNoteOnMap(PaceNote note) async {
    final controller = _mapController;
    if (controller == null) return;

    final pt = _findPointAtDistance(note.distanceFromStart);
    final coordinates = maplibre.LatLng(pt.lat, pt.lon);

    // Remove existing highlights
    final oldLabel = _highlightLabel;
    if (oldLabel != null) {
      await controller.removeSymbol(oldLabel);
    }
    final oldCircle = _highlightCircle;
    if (oldCircle != null) {
      await controller.removeCircle(oldCircle);
    }

    final circle = await controller.addCircle(
      maplibre.CircleOptions(
        geometry: coordinates,
        circleRadius: 10,
        circleColor: '#FF1744',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
        circleOpacity: 0.95,
      ),
    );

    final label = await controller.addSymbol(
      maplibre.SymbolOptions(
        geometry: coordinates,
        textField: note.rallyText,
        textSize: 12,
        textColor: '#FF1744',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 2.5,
        textOffset: const Offset(0, -2.0),
      ),
    );

    setState(() {
      _highlightCircle = circle;
      _highlightLabel = label;
    });

    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngZoom(coordinates, 15.5),
    );
  }

  void _editPacenote(BuildContext context, PaceNote note, int index) {
    _highlightNoteOnMap(note);

    final textController = TextEditingController(text: note.text);
    String direction = note.direction;
    int severity = note.severity;
    PaceNoteType noteType = note.type;
    bool isShort = note.isShort;
    bool isLong = note.isLong;
    bool opens = note.opens;
    bool tightens = note.tightens;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Edit Pacenote',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // Note type / Direction selection
                  Text(
                    'DIRECTION & TYPE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<PaceNoteType>(
                    initialValue: noteType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: PaceNoteType.values.map((type) {
                      return DropdownMenuItem<PaceNoteType>(
                        value: type,
                        child: Text(type.name.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          noteType = val;
                          if (val == PaceNoteType.straight) {
                            direction = 'straight';
                          } else if (val == PaceNoteType.left || val == PaceNoteType.hairpinLeft || val == PaceNoteType.keepLeft) {
                            direction = 'left';
                          } else if (val == PaceNoteType.right || val == PaceNoteType.hairpinRight || val == PaceNoteType.keepRight) {
                            direction = 'right';
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  if (noteType != PaceNoteType.straight &&
                      noteType != PaceNoteType.warning &&
                      noteType != PaceNoteType.roundabout) ...[
                    // Severity
                    Text(
                      'SEVERITY (1-6, 1 is sharpest)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: List.generate(6, (i) {
                        final val = i + 1;
                        return ButtonSegment<int>(
                          value: val,
                          label: Text('$val'),
                        );
                      }),
                      selected: {severity},
                      onSelectionChanged: (Set<int> selection) {
                        setModalState(() {
                          severity = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Modifiers
                    Row(
                      children: [
                        Expanded(
                          child: FilterChip(
                            label: const Text('Short'),
                            selected: isShort,
                            onSelected: (val) => setModalState(() => isShort = val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilterChip(
                            label: const Text('Long'),
                            selected: isLong,
                            onSelected: (val) => setModalState(() => isLong = val),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: FilterChip(
                            label: const Text('Opens'),
                            selected: opens,
                            onSelected: (val) => setModalState(() => opens = val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilterChip(
                            label: const Text('Tightens'),
                            selected: tightens,
                            onSelected: (val) => setModalState(() => tightens = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Custom text / description
                  Text(
                    'CUSTOM CALLOUT TEXT (OPTIONAL)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Caution, gravel on corner',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            final updatedNote = note.copyWith(
                              direction: direction,
                              severity: severity,
                              type: noteType,
                              isShort: isShort,
                              isLong: isLong,
                              opens: opens,
                              tightens: tightens,
                              text: textController.text,
                            );
                            setState(() {
                              _pacenotes[index] = updatedNote;
                            });
                            Navigator.pop(context);
                            _highlightNoteOnMap(updatedNote);
                            _drawPacenoteMarkers();
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _drawPacenoteMarkers() async {
    final controller = _mapController;
    if (controller == null) return;

    // Clear existing
    for (final circle in _pacenoteCircles) {
      await controller.removeCircle(circle);
    }
    _pacenoteCircles.clear();
    for (final label in _pacenoteLabels) {
      await controller.removeSymbol(label);
    }
    _pacenoteLabels.clear();

    for (final note in _pacenotes) {
      final pt = _findPointAtDistance(note.distanceFromStart);
      final coordinates = maplibre.LatLng(pt.lat, pt.lon);
      final colorHex = colorForPaceNote(note);

      final circle = await controller.addCircle(
        maplibre.CircleOptions(
          geometry: coordinates,
          circleRadius: 8,
          circleColor: colorHex,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
          circleOpacity: 0.9,
        ),
      );
      _pacenoteCircles.add(circle);

      if (note.type != PaceNoteType.straight) {
        final label = await controller.addSymbol(
          maplibre.SymbolOptions(
            geometry: coordinates,
            textField: shortCalloutLabel(note),
            textSize: 10,
            textColor: '#FFFFFF',
            textHaloColor: colorHex,
            textHaloWidth: 1.5,
            textOffset: const Offset(0, 0),
          ),
        );
        _pacenoteLabels.add(label);
      }
    }
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
