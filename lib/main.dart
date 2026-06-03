import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models/pace_note.dart';
import 'models/road_warning.dart';
import 'models/route_point.dart';
import 'models/saved_route.dart';
import 'models/speed_limit_segment.dart';
import 'screens/settings_screen.dart';
import 'services/gps_route_matcher.dart';
import 'services/ors_service.dart';
import 'services/overpass_service.dart';
import 'services/pacenote_generator.dart';
import 'services/route_storage_service.dart';
import 'services/settings_service.dart';
import 'services/voice_service.dart';
import 'utils/geo_math.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = RouteStorageService();
  final settings = SettingsService();
  await storage.init();
  await settings.init();
  runApp(RalroadsApp(storage: storage, settings: settings));
}

class RalroadsApp extends StatelessWidget {
  const RalroadsApp({required this.storage, required this.settings, super.key});

  final RouteStorageService storage;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RalRoads',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(storage: storage, settings: settings),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.storage, required this.settings, super.key});

  final RouteStorageService storage;
  final SettingsService settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final planningReady = widget.settings.hasEffectiveOrsApiKey();

    return Scaffold(
      appBar: AppBar(
        title: const Text('RalRoads'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/branding/ralroads_logo.png',
                      width: 204,
                      height: 204,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'RalRoads',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      planningReady
                          ? 'Online route planning ready'
                          : 'Add an OpenRouteService API key to enable online route planning',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MapPlannerScreen(
                              storage: widget.storage,
                              settings: widget.settings,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_road),
                      label: const Text('Plan Route'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SavedRoutesScreen(
                              storage: widget.storage,
                              settings: widget.settings,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bookmarks),
                      label: const Text('Saved Routes'),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('Settings'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: widget.settings),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }
}

class MapPlannerScreen extends StatefulWidget {
  const MapPlannerScreen({
    required this.storage,
    required this.settings,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;

  @override
  State<MapPlannerScreen> createState() => _MapPlannerScreenState();
}

class _MapPlannerScreenState extends State<MapPlannerScreen> {
  static const _mapStyle = 'https://tiles.openfreemap.org/styles/liberty';

  late final OrsService _orsService;
  final _pacenoteGenerator = PacenoteGenerator();
  final List<RoutePoint> _selectedPoints = [];
  final List<maplibre.Circle> _pointCircles = [];
  final List<maplibre.Symbol> _pointLabels = [];
  maplibre.MapLibreMapController? _controller;
  maplibre.Line? _routeLine;
  maplibre.Circle? _currentLocationCircle;
  maplibre.Symbol? _currentLocationLabel;
  bool _building = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _orsService = OrsService(settings: widget.settings);
  }

  @override
  Widget build(BuildContext context) {
    final hasApiKey = _orsService.hasApiKey;
    final hasEnoughPoints = _selectedPoints.length >= 2;
    final waypointCount = math.max(0, _selectedPoints.length - 2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Route'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Stack(
        children: [
          maplibre.MapLibreMap(
            styleString: _mapStyle,
            initialCameraPosition: const maplibre.CameraPosition(
              target: maplibre.LatLng(43.8, 11.2),
              zoom: 5,
            ),
            myLocationEnabled: false,
            onMapCreated: (controller) {
              _controller = controller;
            },
            onMapLongClick: _handleMapLongClick,
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: FloatingActionButton.small(
                heroTag: 'locate-me',
                tooltip: 'Locate me',
                onPressed: _locateMe,
                child: const Icon(Icons.my_location),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withAlpha(242),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      color: Colors.black26,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.route,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_selectedPoints.length} point${_selectedPoints.length == 1 ? '' : 's'} selected',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          _PlannerStatusChip(
                            icon: Icons.flag,
                            label: 'Start',
                            selected: _selectedPoints.isNotEmpty,
                          ),
                          _PlannerStatusChip(
                            icon: Icons.place,
                            label: 'Destination',
                            selected: hasEnoughPoints,
                          ),
                          _PlannerStatusChip(
                            icon: Icons.more_horiz,
                            label:
                                '$waypointCount waypoint${waypointCount == 1 ? '' : 's'}',
                            selected: waypointCount > 0,
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _building ? null : _clear,
                              icon: const Icon(Icons.clear),
                              label: const Text('Clear'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _building
                                  ? null
                                  : hasEnoughPoints && hasApiKey
                                  ? _buildRoute
                                  : hasEnoughPoints
                                  ? _showMissingKeyPrompt
                                  : null,
                              icon: _building
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.alt_route),
                              label: Text(
                                !hasEnoughPoints
                                    ? 'Select start and destination'
                                    : hasApiKey
                                    ? 'Build Route'
                                    : 'Add API Key to Build Route',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMapLongClick(
    math.Point<double> _,
    maplibre.LatLng coordinates,
  ) async {
    final controller = _controller;
    if (controller == null || _building) {
      return;
    }

    final routePoint = RoutePoint(
      lat: coordinates.latitude,
      lon: coordinates.longitude,
    );
    final nextIndex = _selectedPoints.length;
    final isWaypoint = nextIndex >= 2;
    final circle = await controller.addCircle(
      maplibre.CircleOptions(
        geometry: coordinates,
        circleRadius: isWaypoint ? 10 : 9,
        circleColor: _pinColorForIndex(nextIndex),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
        circleOpacity: 0.95,
      ),
    );
    final label = await controller.addSymbol(
      maplibre.SymbolOptions(
        geometry: coordinates,
        textField: _pinLabelForIndex(nextIndex),
        textSize: isWaypoint ? 14 : 13,
        textColor: isWaypoint ? '#212121' : '#FFFFFF',
        textHaloColor: isWaypoint ? '#FFFFFF' : '#263238',
        textHaloWidth: isWaypoint ? 1 : 2,
        textAnchor: isWaypoint ? 'center' : 'top',
        textOffset: isWaypoint ? Offset.zero : const Offset(0, 1.25),
        zIndex: 10 + nextIndex,
      ),
    );

    setState(() {
      _selectedPoints.add(routePoint);
      _pointCircles.add(circle);
      _pointLabels.add(label);
      _error = null;
    });
  }

  Future<void> _clear() async {
    final controller = _controller;
    if (controller != null) {
      if (_pointLabels.isNotEmpty) {
        await controller.removeSymbols(_pointLabels);
      }
      if (_pointCircles.isNotEmpty) {
        await controller.removeCircles(_pointCircles);
      }
      final line = _routeLine;
      if (line != null) {
        await controller.removeLine(line);
      }
    }

    setState(() {
      _selectedPoints.clear();
      _pointLabels.clear();
      _pointCircles.clear();
      _routeLine = null;
      _error = null;
    });
  }

  Future<void> _buildRoute() async {
    if (_selectedPoints.length < 2) {
      setState(() {
        _error = 'Long-press at least two map points first.';
      });
      return;
    }

    setState(() {
      _building = true;
      _error = null;
    });

    try {
      final orderedPoints = _orderedRoutePlanPoints();
      _debugLogRouteOrder(orderedPoints);
      final routePoints = await _orsService.buildRoute(orderedPoints);
      final pacenotes = _pacenoteGenerator.generate(routePoints);
      await _drawRoute(routePoints);
      await _fitCameraToRoute(routePoints);

      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RoutePreviewScreen(
            storage: widget.storage,
            settings: widget.settings,
            points: routePoints,
            pacenotes: pacenotes,
          ),
        ),
      );
    } on MissingOrsApiKeyException {
      await _showMissingKeyPrompt();
    } on InvalidOrsApiKeyException {
      _showSettingsSnackBar(
        'OpenRouteService rejected your API key. Please check it in Settings.',
      );
    } on OrsRateLimitException {
      setState(() {
        _error =
            'OpenRouteService rate limit reached. Try again later or use another key.';
      });
    } on OrsNetworkException {
      setState(() {
        _error = 'Network error while building route.';
      });
    } on OrsException catch (error) {
      setState(() {
        _error = error.message;
      });
    } catch (error) {
      setState(() {
        _error = 'Could not build route: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _building = false;
        });
      }
    }
  }

  List<RoutePoint> _orderedRoutePlanPoints() {
    if (_selectedPoints.length <= 2) {
      return List<RoutePoint>.from(_selectedPoints);
    }

    return [
      _selectedPoints.first,
      ..._selectedPoints.skip(2),
      _selectedPoints[1],
    ];
  }

  void _debugLogRouteOrder(List<RoutePoint> points) {
    assert(() {
      // ignore: avoid_print
      print('Routing order:');
      for (var i = 0; i < points.length; i++) {
        final label = i == 0
            ? 'Start'
            : i == points.length - 1
            ? 'Destination'
            : 'Stop $i';
        final point = points[i];
        // ignore: avoid_print
        print('${i + 1} $label: ${point.lat}, ${point.lon}');
      }
      return true;
    }());
  }

  Future<void> _showMissingKeyPrompt() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('API Key Required'),
          content: const Text(
            'Online route planning requires an OpenRouteService API key.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: widget.settings),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _showSettingsSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () {
            _openSettings();
          },
        ),
      ),
    );
  }

  Future<void> _drawRoute(List<RoutePoint> points) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    final existingLine = _routeLine;
    if (existingLine != null) {
      await controller.removeLine(existingLine);
    }

    final line = await controller.addLine(
      maplibre.LineOptions(
        geometry: points
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

  Future<void> _fitCameraToRoute(List<RoutePoint> points) async {
    final controller = _controller;
    if (controller == null || points.isEmpty) {
      return;
    }

    if (points.length == 1) {
      await controller.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(
          maplibre.LatLng(points.first.lat, points.first.lon),
          13,
        ),
      );
      return;
    }

    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLon = points.first.lon;
    var maxLon = points.first.lon;
    for (final point in points) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLon = math.min(minLon, point.lon);
      maxLon = math.max(maxLon, point.lon);
    }

    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngBounds(
        maplibre.LatLngBounds(
          southwest: maplibre.LatLng(minLat, minLon),
          northeast: maplibre.LatLng(maxLat, maxLon),
        ),
        left: 48,
        top: 96,
        right: 48,
        bottom: 240,
      ),
    );
  }

  Future<void> _locateMe() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    try {
      final position = await _getCurrentPosition();
      if (position == null) {
        return;
      }

      final coordinates = maplibre.LatLng(
        position.latitude,
        position.longitude,
      );
      await _showCurrentLocationMarker(coordinates);
      await controller.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(coordinates, 15),
      );
    } catch (_) {
      _showSnackBar('Could not get current location.');
    }
  }

  Future<Position?> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Could not get current location.');
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showSnackBar('Location permission is required to show your position.');
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
  }

  Future<void> _showCurrentLocationMarker(maplibre.LatLng coordinates) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    final oldLabel = _currentLocationLabel;
    if (oldLabel != null) {
      await controller.removeSymbol(oldLabel);
    }
    final oldCircle = _currentLocationCircle;
    if (oldCircle != null) {
      await controller.removeCircle(oldCircle);
    }

    final circle = await controller.addCircle(
      maplibre.CircleOptions(
        geometry: coordinates,
        circleRadius: 9,
        circleColor: '#1E88E5',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
        circleOpacity: 0.95,
      ),
    );
    final label = await controller.addSymbol(
      maplibre.SymbolOptions(
        geometry: coordinates,
        textField: 'You',
        textSize: 12,
        textColor: '#FFFFFF',
        textHaloColor: '#0D47A1',
        textHaloWidth: 2,
        textAnchor: 'top',
        textOffset: const Offset(0, 1.35),
        zIndex: 50,
      ),
    );

    setState(() {
      _currentLocationCircle = circle;
      _currentLocationLabel = label;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _pinLabelForIndex(int index) {
    if (index == 0) {
      return 'Start';
    }
    if (index == 1) {
      return 'Destination';
    }
    return '${index - 1}';
  }

  String _pinColorForIndex(int index) {
    if (index == 0) {
      return '#2E7D32';
    }
    if (index == 1) {
      return '#C62828';
    }
    return '#F9A825';
  }
}

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
    _roadWarnings = widget.savedRoute?.roadWarnings ?? const [];
    _speedLimitSegments = widget.savedRoute?.speedLimitSegments ?? const [];
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

  @override
  Widget build(BuildContext context) {
    final routeName = widget.savedRoute?.name ?? 'Route preview';

    return Scaffold(
      appBar: AppBar(title: Text(routeName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                  label: const Text('Start Drive'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _saveRoute(context),
                  icon: const Icon(Icons.save),
                  label: const Text('Save Route'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Pacenotes', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _buildRoadInformation(context),
          const SizedBox(height: 24),
          if (_pacenotes.isEmpty)
            const Text('No notable corners were found for this route.')
          else
            ..._pacenotes.map(
              (note) {
                final color = Color(
                  int.parse(colorForPaceNote(note).substring(1), radix: 16) + 0xFF000000,
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    child: note.direction == 'straight'
                        ? const Icon(Icons.straight, size: 20)
                        : Text(shortCalloutLabel(note)),
                  ),
                  title: Text(note.text),
                  subtitle: Row(
                    children: [
                      Text(_formatDistance(note.distanceFromStart)),
                      if (note.recommendedSpeedKmh != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Suggested ${note.recommendedSpeedKmh} km/h',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
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
      if (!mounted) {
        return;
      }
      setState(() {
        _roadWarnings = enrichment.roadWarnings;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text('Road information', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_roadInfoLoading)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Loading road warnings...'),
          )
        else if (_roadInfoFailed)
          const Text('Road warnings unavailable.')
        else if (visibleWarnings.isEmpty && visibleSpeedLimits.isEmpty)
          const Text('No road warnings found for this route.')
        else ...[
          Text(_speedLimitSummary(visibleSpeedLimits)),
          const SizedBox(height: 8),
          Text(_warningCountSummary(visibleWarnings)),
          const SizedBox(height: 8),
          ...visibleWarnings
              .take(12)
              .map(
                (warning) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(iconForRoadWarning(warning.type)),
                  title: Text(warning.text),
                  subtitle: Text(_formatDistance(warning.distanceFromStart)),
                ),
              ),
        ],
      ],
    );
  }

  String _speedLimitSummary(List<SpeedLimitSegment> segments) {
    if (segments.isEmpty) {
      return 'Speed limits: none found';
    }
    final values = <String>{};
    for (final segment in segments) {
      values.add(
        segment.parsedKmh == null
            ? segment.rawMaxspeed
            : '${segment.parsedKmh} km/h',
      );
    }
    return 'Speed limits: ${values.join(', ')}';
  }

  String _warningCountSummary(List<RoadWarning> warnings) {
    final counts = <RoadWarningType, int>{};
    for (final warning in warnings) {
      counts[warning.type] = (counts[warning.type] ?? 0) + 1;
    }

    if (counts.isEmpty) {
      return 'Warnings: none';
    }

    return counts.entries
        .map((entry) => '${labelForRoadWarningType(entry.key)}: ${entry.value}')
        .join(' • ');
  }

  Future<void> _saveRoute(BuildContext context) async {
    final now = DateTime.now();
    final route = SavedRoute(
      id: widget.savedRoute?.id ?? now.microsecondsSinceEpoch.toString(),
      name: widget.savedRoute?.name ?? 'Route ${_formatDate(now)}',
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

class SavedRoutesScreen extends StatefulWidget {
  const SavedRoutesScreen({
    required this.storage,
    required this.settings,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;

  @override
  State<SavedRoutesScreen> createState() => _SavedRoutesScreenState();
}

class _SavedRoutesScreenState extends State<SavedRoutesScreen> {
  late List<SavedRoute> _routes;
  bool _renameDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _routes = widget.storage.getRoutes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Routes')),
      body: _routes.isEmpty
          ? const Center(child: Text('No saved routes yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final route = _routes[index];
                return ListTile(
                  title: Text(route.name),
                  subtitle: Text(
                    '${_formatDate(route.createdAt)} • ${_formatDistance(route.totalDistance)} • ${route.pacenotes.length} notes',
                  ),
                  leading: const Icon(Icons.route),
                  trailing: PopupMenuButton<_SavedRouteAction>(
                    tooltip: 'Route actions',
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _SavedRouteAction.rename,
                        onTap: () {
                          if (_renameDialogOpen) {
                            return;
                          }
                          // Defer until the popup menu route is fully dismissed.
                          Future<void>.microtask(() {
                            if (!mounted) {
                              return;
                            }
                            _renameRoute(route);
                          });
                        },
                        child: const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit),
                          title: Text('Rename'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _SavedRouteAction.delete,
                        onTap: () {
                          Future<void>.microtask(() {
                            if (!mounted) {
                              return;
                            }
                            _deleteRoute(route);
                          });
                        },
                        child: const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RoutePreviewScreen(
                          storage: widget.storage,
                          settings: widget.settings,
                          points: route.points,
                          pacenotes: route.pacenotes,
                          savedRoute: route,
                        ),
                      ),
                    );
                  },
                );
              },
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemCount: _routes.length,
            ),
    );
  }

  Future<void> _deleteRoute(SavedRoute route) async {
    await widget.storage.deleteRoute(route.id);
    setState(() {
      _routes = widget.storage.getRoutes();
    });
  }

  Future<void> _renameRoute(SavedRoute route) async {
    if (_renameDialogOpen) {
      return;
    }
    _renameDialogOpen = true;
    String? newName;
    try {
      newName = await showDialog<String>(
        context: context,
        builder: (_) => _RenameRouteDialog(initialName: route.name),
      );
    } finally {
      _renameDialogOpen = false;
    }

    if (!mounted) {
      return;
    }

    if (newName == null || newName.isEmpty) {
      return;
    }

    await widget.storage.renameRoute(route.id, newName);
    if (!mounted) {
      return;
    }
    setState(() {
      _routes = widget.storage.getRoutes();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Route renamed')));
    });
  }
}

class _RenameRouteDialog extends StatefulWidget {
  const _RenameRouteDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameRouteDialog> createState() => _RenameRouteDialogState();
}

class _RenameRouteDialogState extends State<_RenameRouteDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final candidate = _controller.text.trim();
    if (candidate.isEmpty) {
      setState(() {
        _errorText = 'Enter a route name';
      });
      return;
    }
    Navigator.of(context).pop(candidate);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename route'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Route name',
          errorText: _errorText,
        ),
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (_errorText == null) {
            return;
          }
          setState(() {
            _errorText = null;
          });
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

enum _SavedRouteAction { rename, delete }

class DriveScreen extends StatefulWidget {
  const DriveScreen({
    required this.routePoints,
    required this.pacenotes,
    required this.roadWarnings,
    required this.speedLimitSegments,
    required this.settings,
    super.key,
  });

  final List<RoutePoint> routePoints;
  final List<PaceNote> pacenotes;
  final List<RoadWarning> roadWarnings;
  final List<SpeedLimitSegment> speedLimitSegments;
  final SettingsService settings;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> with WidgetsBindingObserver {
  static const _mapStyle = 'https://tiles.openfreemap.org/styles/liberty';

  final _matcher = GpsRouteMatcher();
  final _voice = VoiceService();
  late List<PaceNote> _notes;
  StreamSubscription<Position>? _positionSubscription;
  maplibre.MapLibreMapController? _controller;
  maplibre.Line? _baseRouteLine;
  final List<maplibre.Line> _dangerLines = [];
  final List<maplibre.Circle> _noteMarkers = [];
  final List<maplibre.Symbol> _noteLabels = [];
  final List<maplibre.Circle> _warningMarkers = [];
  final List<maplibre.Symbol> _warningLabels = [];
  maplibre.Circle? _currentOuterCircle;
  maplibre.Circle? _currentInnerCircle;
  maplibre.Symbol? _currentArrow;
  Position? _lastPosition;
  Position? _previousPosition;
  int _lastMatchedIndex = 0;
  double _distanceAlongRoute = 0;
  double _distanceFromRoute = 0;
  double _speedMps = 0;
  String? _permissionMessage;
  bool _voiceEnabled = true;
  bool _followLocation = true;
  bool _staticMapDrawn = false;
  double _lastGoodHeading = 0;
  double? _lastVisualLat;
  double? _lastVisualLon;
  bool _gpsWeak = false;

  PaceNote? get _nextNote {
    for (final note in _notes) {
      if (!note.spoken && note.distanceFromStart >= _distanceAlongRoute) {
        return note;
      }
    }
    return null;
  }

  List<RoadWarning> get _visibleRoadWarnings =>
      filterRoadWarnings(widget.roadWarnings, widget.settings);

  List<SpeedLimitSegment> get _visibleSpeedLimitSegments =>
      widget.settings.showSpeedLimits ? widget.speedLimitSegments : const [];

  RoadWarning? get _nextRoadWarning {
    for (final warning in _visibleRoadWarnings) {
      if (warning.distanceFromStart >= _distanceAlongRoute) {
        return warning;
      }
    }
    return null;
  }

  SpeedLimitSegment? get _currentSpeedLimit {
    for (final segment in _visibleSpeedLimitSegments) {
      if (_distanceAlongRoute >= segment.startDistance &&
          _distanceAlongRoute <= segment.endDistance) {
        return segment;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock enable failed: $e');
    }
    _notes = widget.pacenotes
        .map((note) => note.copyWith(spoken: false))
        .toList();
    _voice.init();
    _startLocationTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock disable failed: $e');
    }
    _positionSubscription?.cancel();
    _voice.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      if (state == AppLifecycleState.resumed) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('Wakelock toggle on lifecycle failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextNote = _nextNote;
    final nextWarning = _nextRoadWarning;
    final currentLimit = _currentSpeedLimit;
    final distanceToNote = nextNote == null
        ? null
        : math.max(0.0, nextNote.distanceFromStart - _distanceAlongRoute);
    final distanceToWarning = nextWarning == null
        ? null
        : math.max(0.0, nextWarning.distanceFromStart - _distanceAlongRoute);
    final offRoute = _distanceFromRoute > 60 && _lastPosition != null;

    return Scaffold(
      body: Stack(
        children: [
          maplibre.MapLibreMap(
            styleString: _mapStyle,
            initialCameraPosition: _initialDriveCameraPosition(),
            myLocationEnabled: false,
            onMapCreated: (controller) {
              _controller = controller;
            },
            onStyleLoadedCallback: _drawStaticMapLayers,
            onCameraTrackingDismissed: () {
              setState(() {
                _followLocation = false;
              });
            },
          ),
          if (widget.routePoints.isEmpty)
            Positioned(
              top: 96,
              left: 16,
              right: 16,
              child: SafeArea(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No route geometry available.'),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: FloatingActionButton.small(
                heroTag: 'drive-back',
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                child: const Icon(Icons.arrow_back),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 72,
            child: SafeArea(
              child: _SpeedCard(speedMps: _speedMps, speedLimit: currentLimit, gpsWeak: _gpsWeak),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: Column(
                children: [
                  _DriveRoundButton(
                    heroTag: 'drive-follow',
                    tooltip: _followLocation ? 'Disable follow' : 'Recenter',
                    icon: _followLocation ? Icons.gps_fixed : Icons.my_location,
                    active: _followLocation,
                    onPressed: _toggleFollowMode,
                  ),
                  const SizedBox(height: 10),
                  _DriveRoundButton(
                    heroTag: 'drive-voice',
                    tooltip: _voiceEnabled ? 'Pause voice' : 'Resume voice',
                    icon: _voiceEnabled ? Icons.volume_up : Icons.volume_off,
                    active: _voiceEnabled,
                    onPressed: _toggleVoice,
                  ),
                  const SizedBox(height: 10),
                  _DriveRoundButton(
                    heroTag: 'drive-reset',
                    tooltip: 'Reset callouts',
                    icon: Icons.restart_alt,
                    active: false,
                    onPressed: _resetNotes,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withAlpha(238),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 14,
                      color: Colors.black38,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_permissionMessage != null) ...[
                        Text(
                          _permissionMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (offRoute) ...[
                        Text(
                          'Off route',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      _CalloutRow(
                        note: nextNote,
                        distanceMeters: distanceToNote,
                      ),
                      if (nextWarning != null && distanceToWarning != null) ...[
                        const SizedBox(height: 10),
                        _WarningRow(
                          warning: nextWarning,
                          distanceMeters: distanceToWarning,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  maplibre.CameraPosition _initialDriveCameraPosition() {
    if (widget.routePoints.isEmpty) {
      return const maplibre.CameraPosition(
        target: maplibre.LatLng(43.8, 11.2),
        zoom: 5,
      );
    }

    final first = widget.routePoints.first;
    return maplibre.CameraPosition(
      target: maplibre.LatLng(first.lat, first.lon),
      zoom: 12,
    );
  }

  Future<void> _startLocationTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _permissionMessage = 'Location services are disabled.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _permissionMessage = 'Location permission is required for drive mode.';
      });
      return;
    }

    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        intervalDuration: const Duration(milliseconds: 500),
        forceLocationManager: false,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      );
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_handlePosition);
  }

  void _handlePosition(Position position) {
    final match = _matcher.match(
      lat: position.latitude,
      lon: position.longitude,
      routePoints: widget.routePoints,
      lastMatchedIndex: _lastMatchedIndex,
    );

    // Calculate speed fallback and smoothing
    double calculatedSpeed = position.speed;
    final prevPos = _lastPosition;
    if (calculatedSpeed < 0 || calculatedSpeed.isNaN || !calculatedSpeed.isFinite) {
      if (prevPos != null) {
        final timeDiffSec = position.timestamp.difference(prevPos.timestamp).inMilliseconds / 1000.0;
        if (timeDiffSec > 0.05) {
          final dist = haversineDistanceMeters(
            prevPos.latitude,
            prevPos.longitude,
            position.latitude,
            position.longitude,
          );
          calculatedSpeed = dist / timeDiffSec;
        } else {
          calculatedSpeed = _speedMps;
        }
      } else {
        calculatedSpeed = 0.0;
      }
    }

    if (prevPos != null) {
      final timeDiffSec = position.timestamp.difference(prevPos.timestamp).inMilliseconds / 1000.0;
      if (timeDiffSec > 0.05) {
        final acceleration = (calculatedSpeed - _speedMps).abs() / timeDiffSec;
        if (acceleration > 15.0) {
          calculatedSpeed = _speedMps + (calculatedSpeed > _speedMps ? 15.0 : -15.0) * timeDiffSec;
          if (calculatedSpeed < 0) calculatedSpeed = 0;
        }
      }
    }

    final newSpeed = _speedMps * 0.65 + calculatedSpeed * 0.35;

    // Smooth visual location marker position and filter out extreme GPS jumps
    double visualLat = position.latitude;
    double visualLon = position.longitude;
    if (_lastVisualLat != null && _lastVisualLon != null) {
      final dist = haversineDistanceMeters(
        _lastVisualLat!,
        _lastVisualLon!,
        position.latitude,
        position.longitude,
      );
      if (dist > 150.0) {
        final fraction = 150.0 / dist;
        visualLat = _lastVisualLat! + (position.latitude - _lastVisualLat!) * fraction;
        visualLon = _lastVisualLon! + (position.longitude - _lastVisualLon!) * fraction;
      }
      visualLat = _lastVisualLat! * 0.55 + visualLat * 0.45;
      visualLon = _lastVisualLon! * 0.55 + visualLon * 0.45;
    }
    _lastVisualLat = visualLat;
    _lastVisualLon = visualLon;

    setState(() {
      _previousPosition = _lastPosition;
      _lastPosition = position;
      _lastMatchedIndex = match.nearestIndex;
      _distanceAlongRoute = match.distanceAlongRoute;
      _distanceFromRoute = match.distanceFromRoute;
      _speedMps = newSpeed;
      _gpsWeak = position.accuracy > 20.0;
    });

    _updateCurrentLocationMarker(position, visualLat, visualLon);
    if (_followLocation) {
      _followPosition(visualLat, visualLon);
    }
    _maybeSpeakNextNote();
  }

  void _maybeSpeakNextNote() {
    final note = _nextNote;
    if (note == null) {
      return;
    }

    final distanceToNote = note.distanceFromStart - _distanceAlongRoute;
    final triggerDistance = _speedMps > 1
        ? math.max(80.0, _speedMps * 6.0)
        : 80.0;

    if (distanceToNote > triggerDistance) {
      return;
    }

    final noteIndex = _notes.indexWhere((candidate) => candidate.id == note.id);
    if (noteIndex == -1) {
      return;
    }

    String speakText = note.text;
    if (note.recommendedSpeedKmh != null) {
      speakText = '$speakText, suggested ${note.recommendedSpeedKmh}';
    }

    final List<int> spokenIndices = [noteIndex];
    var currentIdx = noteIndex;
    var linkCount = 0;

    while (currentIdx < _notes.length - 1 && linkCount < 2) {
      final nextNote = _notes[currentIdx + 1];
      final gap = nextNote.distanceFromStart - _notes[currentIdx].distanceFromStart;

      if (gap <= 80.0 &&
          _notes[currentIdx].type == PaceNoteType.corner &&
          nextNote.type == PaceNoteType.corner) {
        String nextText = nextNote.text;
        if (nextNote.recommendedSpeedKmh != null) {
          nextText = '$nextText, suggested ${nextNote.recommendedSpeedKmh}';
        }
        speakText = '$speakText into $nextText';
        currentIdx++;
        spokenIndices.add(currentIdx);
        linkCount++;
      } else {
        break;
      }
    }

    _voice.speak(speakText);

    setState(() {
      for (final idx in spokenIndices) {
        _notes[idx] = _notes[idx].copyWith(spoken: true);
      }
    });
  }

  void _resetNotes() {
    setState(() {
      _notes = _notes.map((note) => note.copyWith(spoken: false)).toList();
      _lastMatchedIndex = 0;
    });
  }

  void _toggleVoice() {
    setState(() {
      _voiceEnabled = !_voiceEnabled;
    });
    _voice.setEnabled(_voiceEnabled);
  }

  Future<void> _drawNavigationRoute() async {
    final controller = _controller;
    if (controller == null || widget.routePoints.length < 2) {
      return;
    }

    final oldBaseLine = _baseRouteLine;
    if (oldBaseLine != null) {
      await controller.removeLine(oldBaseLine);
    }
    if (_dangerLines.isNotEmpty) {
      await controller.removeLines(_dangerLines);
      _dangerLines.clear();
    }
    if (_noteLabels.isNotEmpty) {
      await controller.removeSymbols(_noteLabels);
      _noteLabels.clear();
    }
    if (_noteMarkers.isNotEmpty) {
      await controller.removeCircles(_noteMarkers);
      _noteMarkers.clear();
    }
    if (_warningLabels.isNotEmpty) {
      await controller.removeSymbols(_warningLabels);
      _warningLabels.clear();
    }
    if (_warningMarkers.isNotEmpty) {
      await controller.removeCircles(_warningMarkers);
      _warningMarkers.clear();
    }

    _baseRouteLine = await controller.addLine(
      maplibre.LineOptions(
        geometry: widget.routePoints
            .map((point) => maplibre.LatLng(point.lat, point.lon))
            .toList(),
        lineColor: '#607D8B',
        lineWidth: 6,
        lineOpacity: 0.85,
      ),
    );

    for (final note in widget.pacenotes) {
      final segment = routeSegmentBetweenDistances(
        widget.routePoints,
        note.distanceFromStart - 25,
        note.distanceFromStart + 45,
      );
      if (segment.length >= 2) {
        final line = await controller.addLine(
          maplibre.LineOptions(
            geometry: segment
                .map((point) => maplibre.LatLng(point.lat, point.lon))
                .toList(),
            lineColor: colorForPaceNote(note),
            lineWidth: 8,
            lineOpacity: 0.95,
          ),
        );
        _dangerLines.add(line);
      }

      final markerPoint = nearestRoutePointAtDistance(
        widget.routePoints,
        note.distanceFromStart,
      );
      if (markerPoint != null) {
        final coordinates = maplibre.LatLng(markerPoint.lat, markerPoint.lon);
        final circle = await controller.addCircle(
          maplibre.CircleOptions(
            geometry: coordinates,
            circleRadius: 8,
            circleColor: colorForPaceNote(note),
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2,
          ),
        );
        final label = await controller.addSymbol(
          maplibre.SymbolOptions(
            geometry: coordinates,
            textField: shortCalloutLabel(note),
            textSize: 11,
            textColor: '#FFFFFF',
            textHaloColor: '#263238',
            textHaloWidth: 2,
            textAnchor: 'top',
            textOffset: const Offset(0, 1.2),
            zIndex: 20,
          ),
        );
        _noteMarkers.add(circle);
        _noteLabels.add(label);
      }
    }

    for (final warning in _visibleRoadWarnings) {
      final coordinates = maplibre.LatLng(warning.lat, warning.lon);
      final circle = await controller.addCircle(
        maplibre.CircleOptions(
          geometry: coordinates,
          circleRadius: 7,
          circleColor: colorForRoadWarning(warning.type),
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      );
      final label = await controller.addSymbol(
        maplibre.SymbolOptions(
          geometry: coordinates,
          textField: shortRoadWarningLabel(warning.type),
          textSize: 11,
          textColor: '#FFFFFF',
          textHaloColor: '#263238',
          textHaloWidth: 2,
          textAnchor: 'top',
          textOffset: const Offset(0, 1.1),
          zIndex: 30,
        ),
      );
      _warningMarkers.add(circle);
      _warningLabels.add(label);
    }

    await _fitNavigationCameraToRoute();
  }

  Future<void> _drawStaticMapLayers() async {
    if (_staticMapDrawn) {
      return;
    }
    _staticMapDrawn = true;

    try {
      await _drawNavigationRoute();
      final position = _lastPosition;
      if (position != null) {
        final lat = _lastVisualLat ?? position.latitude;
        final lon = _lastVisualLon ?? position.longitude;
        await _updateCurrentLocationMarker(position, lat, lon);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _permissionMessage = 'Map route drawing failed.';
      });
    }
  }

  Future<void> _fitNavigationCameraToRoute() async {
    final controller = _controller;
    if (controller == null || widget.routePoints.isEmpty) {
      return;
    }

    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngBounds(
        routeBoundsFromPoints(widget.routePoints),
        left: 48,
        top: 80,
        right: 48,
        bottom: 260,
      ),
    );
  }

  Future<void> _updateCurrentLocationMarker(Position position, double visualLat, double visualLon) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    final coordinates = maplibre.LatLng(visualLat, visualLon);
    final heading = _headingForPosition(position);

    final existingOuter = _currentOuterCircle;
    final existingInner = _currentInnerCircle;
    final existingArrow = _currentArrow;
    if (existingOuter != null &&
        existingInner != null &&
        existingArrow != null) {
      await controller.updateCircle(
        existingOuter,
        maplibre.CircleOptions(geometry: coordinates),
      );
      await controller.updateCircle(
        existingInner,
        maplibre.CircleOptions(geometry: coordinates),
      );
      await controller.updateSymbol(
        existingArrow,
        maplibre.SymbolOptions(geometry: coordinates, textRotate: heading),
      );
      return;
    }

    final outer = await controller.addCircle(
      maplibre.CircleOptions(
        geometry: coordinates,
        circleRadius: 25,
        circleColor: '#00A876',
        circleOpacity: 0.94,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
    );
    final inner = await controller.addCircle(
      maplibre.CircleOptions(
        geometry: coordinates,
        circleRadius: 18,
        circleColor: '#1565C0',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 1,
      ),
    );
    final arrow = await controller.addSymbol(
      maplibre.SymbolOptions(
        geometry: coordinates,
        textField: '▲',
        textSize: 34,
        textColor: '#FFFFFF',
        textHaloColor: '#0D47A1',
        textHaloWidth: 2,
        textRotate: heading,
        textAnchor: 'center',
        zIndex: 100,
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _currentOuterCircle = outer;
      _currentInnerCircle = inner;
      _currentArrow = arrow;
    });
  }

  Future<void> _followPosition(double lat, double lon) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    // Direct camera move or extremely short animation to avoid stacking and lag
    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngZoom(
        maplibre.LatLng(lat, lon),
        16,
      ),
      duration: const Duration(milliseconds: 150),
    );
  }

  void _toggleFollowMode() {
    if (_followLocation) {
      setState(() {
        _followLocation = false;
      });
      return;
    }

    setState(() {
      _followLocation = true;
    });

    if (_lastVisualLat != null && _lastVisualLon != null) {
      _followPosition(_lastVisualLat!, _lastVisualLon!);
    } else {
      _fitNavigationCameraToRoute();
    }
  }

  double _headingForPosition(Position position) {
    double? candidate;
    // 1. GPS heading if available and valid
    if (_speedMps > 0.8 && position.heading.isFinite && position.heading >= 0 && position.heading <= 360) {
      candidate = position.heading;
    }

    // 2. Movement bearing between previous and current if distance > 3m
    final previous = _previousPosition;
    if (candidate == null && previous != null) {
      final movementMeters = haversineDistanceMeters(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
      if (movementMeters >= 3.0) {
        candidate = bearingDegrees(
          previous.latitude,
          previous.longitude,
          position.latitude,
          position.longitude,
        );
      }
    }

    // 3. Nearest route segment bearing
    if (candidate == null &&
        _lastMatchedIndex >= 0 &&
        _lastMatchedIndex < widget.routePoints.length) {
      final routeHeading = widget.routePoints[_lastMatchedIndex].heading;
      if (routeHeading.isFinite) {
        candidate = routeHeading;
      }
    }

    // 4. Last good heading is candidate ?? _lastGoodHeading
    if (candidate != null) {
      // if stopped/very slow, keep last good heading
      if (_speedMps > 0.3) {
        _lastGoodHeading = smoothHeading(_lastGoodHeading, candidate, 0.4);
      }
    }
    return _lastGoodHeading;
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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SummaryRow(
              label: 'Total distance',
              value: _formatDistance(totalDistance),
            ),
            _SummaryRow(label: 'Route points', value: '$pointCount'),
            _SummaryRow(label: 'Pacenotes', value: '$pacenoteCount'),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _PlannerStatusChip extends StatelessWidget {
  const _PlannerStatusChip({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: selected
          ? colorScheme.primaryContainer.withAlpha(170)
          : colorScheme.surfaceContainerHighest.withAlpha(150),
      side: BorderSide(color: colorScheme.outlineVariant),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({
    required this.speedMps,
    required this.speedLimit,
    required this.gpsWeak,
  });

  final double speedMps;
  final SpeedLimitSegment? speedLimit;
  final bool gpsWeak;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 108, maxWidth: 132),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withAlpha(238),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              color: Colors.black26,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatCurrentSpeed(speedMps),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 0.95,
                  ),
                ),
              ),
              Text(
                'km/h',
                maxLines: 1,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Limit ${formatSpeedLimitSegment(speedLimit)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (gpsWeak) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gps_off, size: 12, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      'GPS WEAK',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DriveRoundButton extends StatelessWidget {
  const _DriveRoundButton({
    required this.heroTag,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String heroTag;
  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      heroTag: heroTag,
      tooltip: tooltip,
      backgroundColor: active
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest.withAlpha(235),
      foregroundColor: active
          ? colorScheme.onPrimary
          : colorScheme.onSurfaceVariant,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}

class _CalloutRow extends StatelessWidget {
  const _CalloutRow({required this.note, required this.distanceMeters});

  final PaceNote? note;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (note != null) _CalloutBadge(note: note),
        if (note != null) const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                note?.text ?? 'No more callouts',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    distanceMeters == null
                        ? 'Route complete'
                        : '${_formatDistance(distanceMeters!)} to callout',
                  ),
                  if (note != null && note.recommendedSpeedKmh != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Suggested ${note.recommendedSpeedKmh}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalloutBadge extends StatelessWidget {
  const _CalloutBadge({required this.note});

  final PaceNote note;

  @override
  Widget build(BuildContext context) {
    final color = Color(
      int.parse(colorForPaceNote(note).substring(1), radix: 16) + 0xFF000000,
    );
    final icon = switch (note.type) {
      PaceNoteType.roundabout => Icons.roundabout_right,
      PaceNoteType.junction => Icons.turn_right,
      PaceNoteType.hairpin => Icons.warning_amber_rounded,
      PaceNoteType.warning => Icons.warning_rounded,
      PaceNoteType.corner => note.direction == 'straight' ? Icons.straight : null,
    };

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: icon == null
          ? Text(
              '${note.severity}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            )
          : Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.warning, required this.distanceMeters});

  final RoadWarning warning;
  final double distanceMeters;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          iconForRoadWarning(warning.type),
          color: colorScheme.primary,
          size: 22,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${warning.text} in ${_formatDistance(distanceMeters)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

maplibre.LatLngBounds routeBoundsFromPoints(List<RoutePoint> points) {
  var minLat = points.first.lat;
  var maxLat = points.first.lat;
  var minLon = points.first.lon;
  var maxLon = points.first.lon;

  for (final point in points) {
    minLat = math.min(minLat, point.lat);
    maxLat = math.max(maxLat, point.lat);
    minLon = math.min(minLon, point.lon);
    maxLon = math.max(maxLon, point.lon);
  }

  return maplibre.LatLngBounds(
    southwest: maplibre.LatLng(minLat, minLon),
    northeast: maplibre.LatLng(maxLat, maxLon),
  );
}

List<RoutePoint> routeSegmentBetweenDistances(
  List<RoutePoint> points,
  double startMeters,
  double endMeters,
) {
  if (points.isEmpty) {
    return const [];
  }

  final start = math.min(startMeters, endMeters);
  final end = math.max(startMeters, endMeters);
  final segment = points
      .where(
        (point) =>
            point.distanceFromStart >= start && point.distanceFromStart <= end,
      )
      .toList();

  if (segment.length >= 2) {
    return segment;
  }

  RoutePoint? before;
  RoutePoint? after;
  for (final point in points) {
    if (point.distanceFromStart <= start) {
      before = point;
    }
    if (point.distanceFromStart >= end) {
      after = point;
      break;
    }
  }

  final fallback = <RoutePoint>[];
  if (before != null) {
    fallback.add(before);
  }
  fallback.addAll(segment);
  if (after != null && after != before) {
    fallback.add(after);
  }

  if (fallback.length >= 2) {
    return fallback;
  }

  final nearest = nearestRoutePointAtDistance(points, (start + end) / 2);
  final nearestIndex = nearest == null ? -1 : points.indexOf(nearest);
  if (nearestIndex <= 0 && points.length >= 2) {
    return points.take(2).toList();
  }
  if (nearestIndex >= points.length - 1 && points.length >= 2) {
    return points.skip(points.length - 2).toList();
  }
  if (nearestIndex > 0) {
    return points.sublist(nearestIndex - 1, nearestIndex + 1);
  }
  return fallback;
}

RoutePoint? nearestRoutePointAtDistance(
  List<RoutePoint> points,
  double distanceMeters,
) {
  if (points.isEmpty) {
    return null;
  }

  var nearest = points.first;
  var nearestDelta = (nearest.distanceFromStart - distanceMeters).abs();
  for (final point in points.skip(1)) {
    final delta = (point.distanceFromStart - distanceMeters).abs();
    if (delta < nearestDelta) {
      nearest = point;
      nearestDelta = delta;
    }
  }
  return nearest;
}

String colorForPaceNoteSeverity(int severity) {
  switch (severity) {
    case 1:
      return '#D50000';
    case 2:
      return '#FF3D00';
    case 3:
      return '#FF9800';
    case 4:
      return '#FFC107';
    case 5:
      return '#8BC34A';
    case 6:
      return '#2E7D32';
    default:
      return '#FF9800';
  }
}

String colorForPaceNote(PaceNote note) {
  if (note.direction == 'straight') {
    return '#9E9E9E';
  }
  return switch (note.type) {
    PaceNoteType.roundabout => '#7E57C2',
    PaceNoteType.junction => '#03A9F4',
    PaceNoteType.warning => '#1976D2',
    PaceNoteType.corner ||
    PaceNoteType.hairpin => colorForPaceNoteSeverity(note.severity),
  };
}

double smoothHeading(double previous, double next, double factor) {
  final delta = normalizeAngleDeltaDegrees(previous, next);
  return (previous + delta * factor + 360) % 360;
}

String shortCalloutLabel(PaceNote note) {
  if (note.direction == 'straight') {
    return 'STR';
  }
  if (note.type == PaceNoteType.roundabout) {
    return 'RAB';
  }
  if (note.type == PaceNoteType.junction) {
    return 'JCT';
  }
  final direction = note.direction.toLowerCase().startsWith('l') ? 'L' : 'R';
  if (note.severity == 1) {
    return '${direction}H';
  }
  return '$direction${note.severity}';
}

List<RoadWarning> filterRoadWarnings(
  List<RoadWarning> warnings,
  SettingsService settings,
) {
  return warnings
      .where((warning) => settings.isWarningTypeEnabled(warning.type))
      .toList()
    ..sort((a, b) => a.distanceFromStart.compareTo(b.distanceFromStart));
}

String formatSpeedLimitSegment(SpeedLimitSegment? segment) {
  if (segment == null) {
    return '—';
  }
  if (segment.parsedKmh != null) {
    return '${segment.parsedKmh}';
  }
  return segment.rawMaxspeed;
}

IconData iconForRoadWarning(RoadWarningType type) {
  return switch (type) {
    RoadWarningType.speedCamera => Icons.camera_alt,
    RoadWarningType.speedBump => Icons.speed,
    RoadWarningType.trafficLight => Icons.traffic,
    RoadWarningType.stopSign => Icons.back_hand,
    RoadWarningType.giveWay => Icons.change_history,
    RoadWarningType.surfaceChange => Icons.terrain,
    RoadWarningType.tunnel => Icons.dark_mode,
    RoadWarningType.bridge => Icons.water,
    RoadWarningType.roundabout => Icons.roundabout_right,
    RoadWarningType.speedLimitChange => Icons.speed,
  };
}

String labelForRoadWarningType(RoadWarningType type) {
  return switch (type) {
    RoadWarningType.speedCamera => 'Speed cameras',
    RoadWarningType.speedBump => 'Speed bumps',
    RoadWarningType.trafficLight => 'Traffic lights',
    RoadWarningType.stopSign => 'Stop signs',
    RoadWarningType.giveWay => 'Give way',
    RoadWarningType.surfaceChange => 'Surface changes',
    RoadWarningType.tunnel => 'Tunnels',
    RoadWarningType.bridge => 'Bridges',
    RoadWarningType.roundabout => 'Roundabouts',
    RoadWarningType.speedLimitChange => 'Speed limits',
  };
}

String colorForRoadWarning(RoadWarningType type) {
  return switch (type) {
    RoadWarningType.speedCamera => '#D50000',
    RoadWarningType.speedBump => '#FF9800',
    RoadWarningType.trafficLight => '#7E57C2',
    RoadWarningType.stopSign => '#D50000',
    RoadWarningType.giveWay => '#FFC107',
    RoadWarningType.surfaceChange => '#795548',
    RoadWarningType.tunnel => '#616161',
    RoadWarningType.bridge => '#607D8B',
    RoadWarningType.roundabout => '#009688',
    RoadWarningType.speedLimitChange => '#1976D2',
  };
}

String shortRoadWarningLabel(RoadWarningType type) {
  return switch (type) {
    RoadWarningType.speedCamera => 'CAM',
    RoadWarningType.speedBump => 'BUMP',
    RoadWarningType.trafficLight => 'TL',
    RoadWarningType.stopSign => 'STOP',
    RoadWarningType.giveWay => 'YIELD',
    RoadWarningType.surfaceChange => 'SURF',
    RoadWarningType.tunnel => 'TUN',
    RoadWarningType.bridge => 'BR',
    RoadWarningType.roundabout => 'RAB',
    RoadWarningType.speedLimitChange => 'LIM',
  };
}

String _formatDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
  return '${meters.round()} m';
}

String formatSpeed(double metersPerSecond) {
  return '${(metersPerSecond * 3.6).toStringAsFixed(0)} km/h';
}

String formatCurrentSpeed(double metersPerSecond) {
  return (metersPerSecond * 3.6).round().toString();
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}
