import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import '../models/saved_route.dart';
import '../services/route_storage_service.dart';
import '../services/offline_map_service.dart';
import '../services/settings_service.dart';
import '../utils/ui_helpers.dart';

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({
    required this.storage,
    required this.settings,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  List<maplibre.OfflineRegion> _downloadedRegions = [];
  List<SavedRoute> _savedRoutes = [];
  bool _isLoading = true;

  // Track downloading states by routeId
  final Map<String, bool> _downloadingRoutes = {};
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final regions = await OfflineMapService.instance.getRegions();
      final routes = widget.storage.getRoutes();

      setState(() {
        _downloadedRegions = regions;
        _savedRoutes = routes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading offline maps data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteRegion(maplibre.OfflineRegion region) async {
    final name = region.metadata['name'] ?? 'Unnamed Region';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Offline Map'),
        content: Text(
          'Are you sure you want to delete cached map for "$name"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });
      await OfflineMapService.instance.deleteRegion(region.id);
      await _loadData();
    }
  }

  Future<void> _downloadRoute(SavedRoute route) async {
    final confirmed = await _confirmDownload(route);
    if (!mounted || !confirmed) {
      return;
    }

    setState(() {
      _downloadingRoutes[route.id] = true;
      _downloadProgress[route.id] = 0.0;
    });

    try {
      final styleUrl = getMapStyle(context, widget.settings);
      await OfflineMapService.instance.downloadRouteRegion(
        route: route,
        mapStyleUrl: styleUrl,
        minZoom: 11.0,
        maxZoom: 15.0,
        onProgress: (status) {
          if (status is maplibre.InProgress) {
            if (mounted) {
              setState(() {
                _downloadProgress[route.id] = status.progress;
              });
            }
          } else if (status is maplibre.Success) {
            if (mounted) {
              setState(() {
                _downloadingRoutes[route.id] = false;
                _downloadProgress.remove(route.id);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Offline map for "${route.name}" downloaded!'),
                ),
              );
              _loadData();
            }
          } else if (status is maplibre.Error) {
            if (mounted) {
              setState(() {
                _downloadingRoutes[route.id] = false;
                _downloadProgress.remove(route.id);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to download: ${status.cause}')),
              );
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingRoutes[route.id] = false;
          _downloadProgress.remove(route.id);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<bool> _confirmDownload(SavedRoute route) async {
    final estimatedTiles = OfflineMapService.instance.estimateTileCountForRoute(
      route: route,
      minZoom: 11,
      maxZoom: 15,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Route Map'),
        content: Text(
          'Route data is already saved locally. This downloads base map tiles only for "${route.name}".\n\nEstimated tiles: $estimatedTiles\nZoom: 11-15',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  bool _isRouteDownloaded(String routeId) {
    return _downloadedRegions.any((r) => r.metadata['routeId'] == routeId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Maps'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  // Section: Cached regions
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Downloaded Map Regions',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  if (_downloadedRegions.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 24,
                        ),
                        child: Center(
                          child: Text(
                            'No downloaded map regions found.\nYou can download maps from your saved routes below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final region = _downloadedRegions[index];
                        final name =
                            region.metadata['name'] ?? 'Unnamed Region';
                        final dateStr = region.metadata['createdAt'] != null
                            ? DateTime.parse(
                                region.metadata['createdAt'],
                              ).toLocal().toString().split('.').first
                            : 'Unknown Date';
                        final styleStr = region.definition.mapStyleUrl
                            .split('/')
                            .last;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                                child: const Icon(Icons.offline_pin_outlined),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Style: $styleStr\nDownloaded: $dateStr\nZoom: ${region.definition.minZoom.round()} - ${region.definition.maxZoom.round()}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: theme.colorScheme.error,
                                ),
                                onPressed: () => _deleteRegion(region),
                              ),
                            ),
                          ),
                        );
                      }, childCount: _downloadedRegions.length),
                    ),

                  // Section: Saved routes to download
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Text(
                        'Saved Routes Maps',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  if (_savedRoutes.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 24,
                        ),
                        child: Center(
                          child: Text(
                            'No saved routes yet.\nGo to Planner to plan and save some routes first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final route = _savedRoutes[index];
                        final isDownloaded = _isRouteDownloaded(route.id);
                        final isDownloading =
                            _downloadingRoutes[route.id] ?? false;
                        final progress = _downloadProgress[route.id] ?? 0.0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              title: Text(
                                route.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${(route.totalDistance / 1000).toStringAsFixed(1)} km · ${route.points.length} points',
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: isDownloaded
                                  ? Chip(
                                      avatar: const Icon(Icons.check, size: 16),
                                      label: const Text('Downloaded'),
                                      backgroundColor:
                                          theme.colorScheme.secondaryContainer,
                                      labelStyle: TextStyle(
                                        color: theme
                                            .colorScheme
                                            .onSecondaryContainer,
                                        fontSize: 12,
                                      ),
                                    )
                                  : isDownloading
                                  ? SizedBox(
                                      width: 100,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          LinearProgressIndicator(
                                            value: progress > 0
                                                ? progress / 100
                                                : null,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            progress > 0
                                                ? '${progress.toStringAsFixed(0)}%'
                                                : 'Starting...',
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ElevatedButton.icon(
                                      onPressed: () => _downloadRoute(route),
                                      icon: const Icon(
                                        Icons.download,
                                        size: 16,
                                      ),
                                      label: const Text('Download'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      }, childCount: _savedRoutes.length),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
    );
  }
}
