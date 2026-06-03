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
  runApp(RoadNotesApp(storage: storage, settings: settings));
}

class RoadNotesApp extends StatelessWidget {
  const RoadNotesApp({
    required this.storage,
    required this.settings,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoadNotes',
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
        title: const Text('RoadNotes'),
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
                Icon(
                  Icons.route,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'RoadNotes',
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
  final List<maplibre.Symbol> _symbols = [];
  maplibre.MapLibreMapController? _controller;
  maplibre.Line? _routeLine;
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
            myLocationEnabled: true,
            onMapCreated: (controller) {
              _controller = controller;
            },
            onMapLongClick: _handleMapLongClick,
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
                                  : hasApiKey
                                  ? _buildRoute
                                  : _showMissingKeyPrompt,
                              icon: _building
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.alt_route),
                              label: Text(
                                hasApiKey
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
    math.Point<double> point,
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
    final symbol = await controller.addSymbol(
      maplibre.SymbolOptions(
        geometry: coordinates,
        textField: '${_selectedPoints.length + 1}',
        textColor: '#FFFFFF',
        textHaloColor: '#00695C',
        textHaloWidth: 2,
        iconImage: 'marker-15',
        iconSize: 1.6,
      ),
    );

    setState(() {
      _selectedPoints.add(routePoint);
      _symbols.add(symbol);
      _error = null;
    });
  }

  Future<void> _clear() async {
    final controller = _controller;
    if (controller != null) {
      if (_symbols.isNotEmpty) {
        await controller.removeSymbols(_symbols);
      }
      final line = _routeLine;
      if (line != null) {
        await controller.removeLine(line);
      }
    }

    setState(() {
      _selectedPoints.clear();
      _symbols.clear();
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
        action: SnackBarAction(label: 'Settings', onPressed: _openSettings),
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
  final _matcher = GpsRouteMatcher();
  final _voice = VoiceService();
  late List<PaceNote> _notes;
  StreamSubscription<Position>? _positionSubscription;
  int _lastMatchedIndex = 0;
  double _distanceAlongRoute = 0;
  double _distanceFromRoute = 0;
  double _speedMps = 0;
  String? _permissionMessage;
  bool _voiceEnabled = true;

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

    return Scaffold(
      appBar: AppBar(title: const Text('Drive')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_permissionMessage != null) ...[
            Text(
              _permissionMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
          ],
          _DriveMetric(
            label: 'Distance along route',
            value: _formatDistance(_distanceAlongRoute),
          ),
          _DriveMetric(
            label: 'Distance from route',
            value: _formatDistance(_distanceFromRoute),
          ),
          _DriveMetric(label: 'Speed', value: _formatSpeed(_speedMps)),
          const SizedBox(height: 16),
          Text('Next pacenote', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            nextNote?.text ?? 'No upcoming notes',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            distanceToNote == null
                ? 'Route complete'
                : '${_formatDistance(distanceToNote)} to note',
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetNotes,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _toggleVoice,
                  icon: Icon(
                    _voiceEnabled ? Icons.volume_up : Icons.volume_off,
                  ),
                  label: Text(_voiceEnabled ? 'Pause Voice' : 'Resume Voice'),
                ),
              ),
            ],
          ),
        ],
      ),
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
      _lastMatchedIndex = match.nearestIndex;
      _distanceAlongRoute = match.distanceAlongRoute;
      _distanceFromRoute = match.distanceFromRoute;
      _speedMps = position.speed.isFinite ? math.max(0, position.speed) : 0;
    });

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

class _DriveMetric extends StatelessWidget {
  const _DriveMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
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
