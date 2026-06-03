import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'models/pace_note.dart';
import 'models/route_point.dart';
import 'models/saved_route.dart';
import 'screens/settings_screen.dart';
import 'services/gps_route_matcher.dart';
import 'services/ors_service.dart';
import 'services/pacenote_generator.dart';
import 'services/route_storage_service.dart';
import 'services/settings_service.dart';
import 'services/voice_service.dart';

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/branding/ralroads_logo.png',
                  width: 160,
                  height: 160,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
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
                        builder: (_) =>
                            SavedRoutesScreen(storage: widget.storage),
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
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 12,
                      color: Colors.black26,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_selectedPoints.length} point${_selectedPoints.length == 1 ? '' : 's'} selected',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Start ${_selectedPoints.isNotEmpty ? 'selected' : 'not selected'} • Destination ${hasEnoughPoints ? 'selected' : 'not selected'} • $waypointCount waypoint${waypointCount == 1 ? '' : 's'}',
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
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
    final circle = await controller.addCircle(
      maplibre.CircleOptions(
        geometry: coordinates,
        circleRadius: nextIndex < 2 ? 9 : 7,
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
        textSize: nextIndex < 2 ? 13 : 12,
        textColor: '#FFFFFF',
        textHaloColor: '#263238',
        textHaloWidth: 2,
        textAnchor: 'top',
        textOffset: const Offset(0, 1.25),
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
      final routePoints = await _orsService.buildRoute(_selectedPoints);
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

class RoutePreviewScreen extends StatelessWidget {
  const RoutePreviewScreen({
    required this.storage,
    required this.points,
    required this.pacenotes,
    this.savedRoute,
    super.key,
  });

  final RouteStorageService storage;
  final List<RoutePoint> points;
  final List<PaceNote> pacenotes;
  final SavedRoute? savedRoute;

  double get _totalDistance =>
      points.isEmpty ? 0 : points.last.distanceFromStart;

  @override
  Widget build(BuildContext context) {
    final routeName = savedRoute?.name ?? 'Route preview';

    return Scaffold(
      appBar: AppBar(title: Text(routeName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryPanel(
            totalDistance: _totalDistance,
            pointCount: points.length,
            pacenoteCount: pacenotes.length,
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
                          routePoints: points,
                          pacenotes: pacenotes,
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
          if (pacenotes.isEmpty)
            const Text('No notable corners were found for this route.')
          else
            ...pacenotes.map(
              (note) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${note.severity}')),
                title: Text(note.text),
                subtitle: Text(_formatDistance(note.distanceFromStart)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveRoute(BuildContext context) async {
    final now = DateTime.now();
    final route = SavedRoute(
      id: savedRoute?.id ?? now.microsecondsSinceEpoch.toString(),
      name: savedRoute?.name ?? 'Route ${_formatDate(now)}',
      createdAt: savedRoute?.createdAt ?? now,
      totalDistance: _totalDistance,
      points: points,
      pacenotes: pacenotes,
    );

    await storage.saveRoute(route);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Route saved')));
    }
  }
}

class SavedRoutesScreen extends StatefulWidget {
  const SavedRoutesScreen({required this.storage, super.key});

  final RouteStorageService storage;

  @override
  State<SavedRoutesScreen> createState() => _SavedRoutesScreenState();
}

class _SavedRoutesScreenState extends State<SavedRoutesScreen> {
  late List<SavedRoute> _routes;

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
                  trailing: IconButton(
                    tooltip: 'Delete route',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteRoute(route),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RoutePreviewScreen(
                          storage: widget.storage,
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
}

class DriveScreen extends StatefulWidget {
  const DriveScreen({
    required this.routePoints,
    required this.pacenotes,
    super.key,
  });

  final List<RoutePoint> routePoints;
  final List<PaceNote> pacenotes;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
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
  maplibre.Circle? _currentOuterCircle;
  maplibre.Circle? _currentInnerCircle;
  maplibre.Symbol? _currentArrow;
  Position? _lastPosition;
  int _lastMatchedIndex = 0;
  double _distanceAlongRoute = 0;
  double _distanceFromRoute = 0;
  double _speedMps = 0;
  String? _permissionMessage;
  bool _voiceEnabled = true;
  bool _followLocation = true;
  PaceNote? _lastSpokenNote;

  PaceNote? get _nextNote {
    for (final note in _notes) {
      if (!note.spoken && note.distanceFromStart >= _distanceAlongRoute) {
        return note;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _notes = widget.pacenotes
        .map((note) => note.copyWith(spoken: false))
        .toList();
    _voice.init();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _voice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nextNote = _nextNote;
    final distanceToNote = nextNote == null
        ? null
        : math.max(0.0, nextNote.distanceFromStart - _distanceAlongRoute);
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
              _drawNavigationRoute();
              final position = _lastPosition;
              if (position != null) {
                _updateCurrentLocationMarker(position);
              }
            },
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SafeArea(
              child: Row(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'drive-back',
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const Spacer(),
                  FloatingActionButton.small(
                    heroTag: 'drive-follow',
                    tooltip: _followLocation ? 'Disable follow' : 'Recenter',
                    onPressed: _toggleFollowMode,
                    child: Icon(
                      _followLocation ? Icons.gps_fixed : Icons.my_location,
                    ),
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
                  color: Theme.of(context).colorScheme.surface.withAlpha(235),
                  borderRadius: BorderRadius.circular(8),
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
                      Text(
                        _lastSpokenNote == null
                            ? 'Current callout: none'
                            : 'Current callout: ${_lastSpokenNote!.text}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        nextNote?.text ?? 'No upcoming callouts',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              distanceToNote == null
                                  ? 'Route complete'
                                  : '${_formatDistance(distanceToNote)} to callout',
                            ),
                          ),
                          Text(_formatSpeed(_speedMps)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'RalRoads is only an assistance tool. Always follow traffic laws and road conditions.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _resetNotes,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _toggleVoice,
                              icon: Icon(
                                _voiceEnabled
                                    ? Icons.volume_up
                                    : Icons.volume_off,
                              ),
                              label: Text(_voiceEnabled ? 'Pause' : 'Resume'),
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

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(_handlePosition);
  }

  void _handlePosition(Position position) {
    final match = _matcher.match(
      lat: position.latitude,
      lon: position.longitude,
      routePoints: widget.routePoints,
      lastMatchedIndex: _lastMatchedIndex,
    );

    setState(() {
      _lastPosition = position;
      _lastMatchedIndex = match.nearestIndex;
      _distanceAlongRoute = match.distanceAlongRoute;
      _distanceFromRoute = match.distanceFromRoute;
      _speedMps = position.speed.isFinite ? math.max(0, position.speed) : 0;
    });

    _updateCurrentLocationMarker(position);
    if (_followLocation) {
      _followPosition(position);
    }
    _maybeSpeakNextNote();
  }

  void _maybeSpeakNextNote() {
    final note = _nextNote;
    if (note == null) {
      return;
    }

    final distanceToNote = note.distanceFromStart - _distanceAlongRoute;
    final shouldSpeak = _speedMps > 1
        ? distanceToNote / _speedMps <= 6
        : distanceToNote <= 80;

    if (!shouldSpeak) {
      return;
    }

    final noteIndex = _notes.indexWhere((candidate) => candidate.id == note.id);
    if (noteIndex == -1) {
      return;
    }

    _voice.speak(note.text);
    setState(() {
      _notes[noteIndex] = note.copyWith(spoken: true);
      _lastSpokenNote = note;
    });
  }

  void _resetNotes() {
    setState(() {
      _notes = _notes.map((note) => note.copyWith(spoken: false)).toList();
      _lastMatchedIndex = 0;
      _lastSpokenNote = null;
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
            lineColor: colorForPaceNoteSeverity(note.severity),
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
            circleColor: colorForPaceNoteSeverity(note.severity),
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

    await _fitNavigationCameraToRoute();
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

  Future<void> _updateCurrentLocationMarker(Position position) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    final coordinates = maplibre.LatLng(position.latitude, position.longitude);
    final oldArrow = _currentArrow;
    if (oldArrow != null) {
      await controller.removeSymbol(oldArrow);
    }
    final oldInner = _currentInnerCircle;
    if (oldInner != null) {
      await controller.removeCircle(oldInner);
    }
    final oldOuter = _currentOuterCircle;
    if (oldOuter != null) {
      await controller.removeCircle(oldOuter);
    }

    final outer = await controller.addCircle(
      maplibre.CircleOptions(
        geometry: coordinates,
        circleRadius: 13,
        circleColor: '#1E88E5',
        circleOpacity: 0.28,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );
    final inner = await controller.addCircle(
      maplibre.CircleOptions(
        geometry: coordinates,
        circleRadius: 7,
        circleColor: '#1565C0',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );
    final arrow = await controller.addSymbol(
      maplibre.SymbolOptions(
        geometry: coordinates,
        textField: '▲',
        textSize: 18,
        textColor: '#FFFFFF',
        textHaloColor: '#0D47A1',
        textHaloWidth: 2,
        textRotate: _headingForPosition(position),
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

  Future<void> _followPosition(Position position) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngZoom(
        maplibre.LatLng(position.latitude, position.longitude),
        16,
      ),
      duration: const Duration(milliseconds: 450),
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

    final position = _lastPosition;
    if (position != null) {
      _followPosition(position);
    } else {
      _fitNavigationCameraToRoute();
    }
  }

  double _headingForPosition(Position position) {
    if (position.heading.isFinite && position.heading >= 0) {
      return position.heading;
    }
    if (_lastMatchedIndex >= 0 &&
        _lastMatchedIndex < widget.routePoints.length) {
      return widget.routePoints[_lastMatchedIndex].heading;
    }
    return 0;
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

String shortCalloutLabel(PaceNote note) {
  final direction = note.direction.toLowerCase().startsWith('l') ? 'L' : 'R';
  if (note.severity == 1) {
    return '${direction}H';
  }
  return '$direction${note.severity}';
}

String _formatDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
  return '${meters.round()} m';
}

String _formatSpeed(double metersPerSecond) {
  return '${(metersPerSecond * 3.6).toStringAsFixed(0)} km/h';
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
