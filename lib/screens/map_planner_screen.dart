import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../models/route_point.dart';
import '../services/ors_service.dart';
import '../services/pacenote_generator.dart';
import '../services/route_storage_service.dart';
import '../services/settings_service.dart';
import '../utils/ui_helpers.dart';
import 'route_preview_screen.dart';
import 'settings_screen.dart';

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
            styleString: getMapStyle(context, widget.settings),
            initialCameraPosition: const maplibre.CameraPosition(
              target: maplibre.LatLng(43.8, 11.2),
              zoom: 5,
            ),
            // Hide MapLibre attribution/info button by pushing it off-screen
            attributionButtonPosition: maplibre.AttributionButtonPosition.bottomRight,
            attributionButtonMargins: const math.Point(-1000, -1000),
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
                      ),
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
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _PlannerStatusCard(
                                  icon: Icons.flag,
                                  label: 'Start',
                                  selected: _selectedPoints.isNotEmpty,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _PlannerStatusCard(
                                  icon: Icons.more_horiz,
                                  label: waypointCount == 0
                                      ? 'No waypoints'
                                      : '$waypointCount waypoint${waypointCount == 1 ? '' : 's'}',
                                  selected: waypointCount > 0,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _PlannerStatusCard(
                                  icon: Icons.place,
                                  label: 'Destination',
                                  selected: hasEnoughPoints,
                                ),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (_selectedPoints.isNotEmpty) ...[
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _building ? null : _clear,
                                  child: const Text('Clear'),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
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
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.alt_route),
                                  label: Text(
                                    !hasEnoughPoints
                                        ? 'Long-press map to add points'
                                        : hasApiKey
                                            ? 'Build Route'
                                            : 'Add API Key to Build Route',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
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
      distanceFromStart: 0,
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
    // Start, then waypoints (everything after index 1), then destination (index 1)
    return [
      _selectedPoints.first,
      ..._selectedPoints.skip(2),
      _selectedPoints[1],
    ];
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
          onPressed: _openSettings,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _pinLabelForIndex(int index) {
    if (index == 0) return 'Start';
    if (index == 1) return 'Destination';
    return '${index - 1}';
  }

  String _pinColorForIndex(int index) {
    if (index == 0) return '#2E7D32';
    if (index == 1) return '#C62828';
    return '#F9A825';
  }
}

class _PlannerStatusCard extends StatelessWidget {
  const _PlannerStatusCard({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withOpacity(0.12)
            : colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? colorScheme.primary.withOpacity(0.3)
              : colorScheme.outlineVariant.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
