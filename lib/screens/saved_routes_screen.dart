import 'package:flutter/material.dart';

import '../models/saved_route.dart';
import '../services/route_storage_service.dart';
import '../services/settings_service.dart';
import '../utils/format_helpers.dart';
import 'route_preview_screen.dart';

enum _SavedRouteAction { rename, delete }

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
    final theme = Theme.of(context);
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _routes.length,
              itemBuilder: (context, index) {
                final route = _routes[index];
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.primary,
                                  theme.colorScheme.primary.withValues(
                                    alpha: 0.7,
                                  ),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.2,
                                  ),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.route,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  route.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  formatDate(route.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    _buildRouteBadge(
                                      context,
                                      icon: Icons.straighten,
                                      label: formatDistance(
                                        route.totalDistance,
                                      ),
                                    ),
                                    _buildRouteBadge(
                                      context,
                                      icon: Icons.speaker_notes_outlined,
                                      label: '${route.pacenotes.length} notes',
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
                                  if (_renameDialogOpen) {
                                    return;
                                  }
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
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
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
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
