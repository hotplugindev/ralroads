import 'package:flutter/material.dart';

import '../models/saved_route.dart';
import '../services/route_storage_service.dart';
import '../services/settings_service.dart';
import '../utils/format_helpers.dart';
import 'route_preview_screen.dart';

enum _SavedRouteAction { rename, delete }

enum _SavedRouteFilter { all, today, week, long, warnings }

enum _SavedRouteSort { newest, oldest, distance, name }

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
  final _searchController = TextEditingController();
  _SavedRouteFilter _filter = _SavedRouteFilter.all;
  _SavedRouteSort _sort = _SavedRouteSort.newest;
  bool _renameDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _routes = widget.storage.getRoutes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routes = _filteredRoutes();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Saved Routes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: _routes.isEmpty
          ? const Center(child: Text('No saved routes yet.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search routes',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _filterChip('All', _SavedRouteFilter.all),
                      _filterChip('Today', _SavedRouteFilter.today),
                      _filterChip('7 days', _SavedRouteFilter.week),
                      _filterChip('10 km+', _SavedRouteFilter.long),
                      _filterChip('Warnings', _SavedRouteFilter.warnings),
                      const SizedBox(width: 8),
                      _sortChip('Newest', _SavedRouteSort.newest),
                      _sortChip('Oldest', _SavedRouteSort.oldest),
                      _sortChip('Distance', _SavedRouteSort.distance),
                      _sortChip('Name', _SavedRouteSort.name),
                    ],
                  ),
                ),
                Expanded(
                  child: routes.isEmpty
                      ? const Center(child: Text('No routes match.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: routes.length,
                          itemBuilder: (context, index) {
                            final route = routes[index];
                            return _SavedRouteCard(
                              route: route,
                              storage: widget.storage,
                              settings: widget.settings,
                              onRename: _renameRoute,
                              onDelete: _deleteRoute,
                              renameDialogOpen: _renameDialogOpen,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _filterChip(String label, _SavedRouteFilter value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _sortChip(String label, _SavedRouteSort value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _sort == value,
        onSelected: (_) => setState(() => _sort = value),
      ),
    );
  }

  List<SavedRoute> _filteredRoutes() {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    final filtered = _routes.where((route) {
      if (query.isNotEmpty) {
        final haystack = [
          route.name,
          route.startName,
          route.destinationName,
          formatDate(route.createdAt),
        ].whereType<String>().join(' ').toLowerCase();
        if (!haystack.contains(query)) {
          return false;
        }
      }

      return switch (_filter) {
        _SavedRouteFilter.all => true,
        _SavedRouteFilter.today => _isSameLocalDay(route.createdAt, now),
        _SavedRouteFilter.week => now.difference(route.createdAt).inDays <= 7,
        _SavedRouteFilter.long => route.totalDistance >= 10000,
        _SavedRouteFilter.warnings => route.roadWarnings.isNotEmpty,
      };
    }).toList();

    filtered.sort((a, b) {
      return switch (_sort) {
        _SavedRouteSort.newest => b.createdAt.compareTo(a.createdAt),
        _SavedRouteSort.oldest => a.createdAt.compareTo(b.createdAt),
        _SavedRouteSort.distance => b.totalDistance.compareTo(a.totalDistance),
        _SavedRouteSort.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      };
    });
    return filtered;
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
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

class _SavedRouteCard extends StatelessWidget {
  const _SavedRouteCard({
    required this.route,
    required this.storage,
    required this.settings,
    required this.onRename,
    required this.onDelete,
    required this.renameDialogOpen,
  });

  final SavedRoute route;
  final RouteStorageService storage;
  final SettingsService settings;
  final Future<void> Function(SavedRoute route) onRename;
  final Future<void> Function(SavedRoute route) onDelete;
  final bool renameDialogOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final endpointText = _endpointText();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RoutePreviewScreen(
                storage: storage,
                settings: settings,
                points: route.points,
                pacenotes: route.pacenotes,
                savedRoute: route,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.route, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (endpointText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        endpointText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildRouteBadge(
                          context,
                          icon: Icons.calendar_today,
                          label: formatDate(route.createdAt),
                        ),
                        _buildRouteBadge(
                          context,
                          icon: Icons.straighten,
                          label: formatDistance(route.totalDistance),
                        ),
                        _buildRouteBadge(
                          context,
                          icon: Icons.speaker_notes_outlined,
                          label: '${route.pacenotes.length} notes',
                        ),
                        if (route.roadWarnings.isNotEmpty)
                          _buildRouteBadge(
                            context,
                            icon: Icons.warning_amber_rounded,
                            label: '${route.roadWarnings.length} warnings',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_SavedRouteAction>(
                tooltip: 'Route actions',
                icon: Icon(
                  Icons.more_vert,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _SavedRouteAction.rename,
                    onTap: () {
                      if (renameDialogOpen) {
                        return;
                      }
                      Future<void>.microtask(() => onRename(route));
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
                      Future<void>.microtask(() => onDelete(route));
                    },
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _endpointText() {
    final start = route.startName?.trim();
    final destination = route.destinationName?.trim();
    if (start == null ||
        start.isEmpty ||
        destination == null ||
        destination.isEmpty) {
      return null;
    }
    return '$start to $destination';
  }

  Widget _buildRouteBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
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
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
