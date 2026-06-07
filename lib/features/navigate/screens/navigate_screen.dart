import 'package:flutter/material.dart';

import '../../../controllers/app_session_controller.dart';
import '../../../controllers/driving_session_controller.dart';
import '../../../repositories/app_repositories.dart';
import '../../../services/route_storage_service.dart';
import '../../../services/settings_service.dart';
import '../../../utils/format_helpers.dart';
import '../../../widgets/product_components.dart';
import '../../../screens/map_planner_screen.dart';
import '../../../screens/offline_maps_screen.dart';
import '../../../screens/saved_routes_screen.dart';
import '../../../screens/settings_screen.dart';
import '../../../screens/route_preview_screen.dart';
import '../../../models/saved_route.dart';

class NavigateScreen extends StatefulWidget {
  const NavigateScreen({
    required this.storage,
    required this.settings,
    required this.repositories,
    required this.session,
    required this.accountController,
    required this.drivingSession,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;
  final AppRepositories repositories;
  final AppSessionController session;
  final AccountConnectionController accountController;
  final DrivingSessionController drivingSession;

  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen> {
  bool _renameDialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final orsConnected = widget.settings.hasEffectiveOrsApiKey();

    return StreamBuilder<List<SavedRoute>>(
      stream: widget.repositories.navigation.watchSavedRoutes(),
      builder: (context, snapshot) {
        final savedRoutes = snapshot.data ?? [];

        return RalRoadsPage(
          title: 'Navigate',
          children: [
            // 1. Prominent Primary Action Card
            PrimaryActionCard(
              title: 'Plan a new route',
              subtitle: orsConnected
                  ? 'Search places, add custom waypoints, and start a road-aware route.'
                  : 'Connect OpenRouteService for online route planning. Saved routes remain functional offline.',
              icon: Icons.add_road_rounded,
              actionLabel: orsConnected ? 'Plan' : 'Connect ORS',
              onPressed: () =>
                  orsConnected ? _openPlanner(context) : _openSettings(context),
            ),

            // 2. Navigation Actions Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 3 : 1,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: isWide ? 2.5 : 4.5,
                  children: [
                    _buildNavQuickCard(
                      context,
                      title: 'Offline Maps',
                      subtitle: 'Download & manage regions',
                      icon: Icons.map_outlined,
                      color: scheme.primary,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OfflineMapsScreen(
                            storage: widget.storage,
                            settings: widget.settings,
                          ),
                        ),
                      ),
                    ),
                    _buildNavQuickCard(
                      context,
                      title: 'Saved Routes',
                      subtitle: '${savedRoutes.length} saved routes',
                      icon: Icons.bookmarks_outlined,
                      color: scheme.secondary,
                      onTap: () => _openSavedRoutes(context),
                    ),
                    _buildNavQuickCard(
                      context,
                      title: 'Navigation Settings',
                      subtitle: 'Voice, overlays & ORS connection',
                      icon: Icons.tune_rounded,
                      color: scheme.tertiary,
                      onTap: () => _openSettings(context),
                    ),
                  ],
                );
              },
            ),

            // 3. Saved Routes List Header
            SectionHeader(
              title: 'Recent saved routes',
              trailing: TextButton.icon(
                onPressed: () => _openSavedRoutes(context),
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Manage'),
              ),
            ),

            // 4. Saved Routes List
            if (savedRoutes.isEmpty)
              EmptyState(
                title: 'No saved routes yet',
                message:
                    'Routes you save after planning remain available locally for preview and driving.',
                action: OutlinedButton.icon(
                  onPressed: () => _openPlanner(context),
                  icon: const Icon(Icons.add_road),
                  label: const Text('Plan one now'),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: savedRoutes.take(5).length,
                itemBuilder: (context, index) {
                  final route = savedRoutes[index];
                  return _buildRouteItem(context, route);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildNavQuickCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteItem(BuildContext context, SavedRoute route) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = route.startName?.trim();
    final dest = route.destinationName?.trim();
    final hasEndpoints = start != null && start.isNotEmpty && dest != null && dest.isNotEmpty;
    final endpointsLabel = hasEndpoints ? '$start to $dest' : null;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RoutePreviewScreen(
                storage: widget.storage,
                settings: widget.settings,
                drivingSession: widget.drivingSession,
                points: route.points,
                pacenotes: route.pacenotes,
                savedRoute: route,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.route_outlined, color: scheme.onPrimaryContainer, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (endpointsLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        endpointsLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildRouteBadge(
                          context,
                          icon: Icons.calendar_today_outlined,
                          label: formatDate(route.createdAt),
                        ),
                        _buildRouteBadge(
                          context,
                          icon: Icons.straighten_outlined,
                          label: formatDistance(route.totalDistance),
                        ),
                        _buildRouteBadge(
                          context,
                          icon: Icons.comment_bank_outlined,
                          label: '${route.pacenotes.length} notes',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Route Actions',
                icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'rename') {
                    await _renameRoute(route);
                  } else if (value == 'delete') {
                    await _deleteRoute(route);
                  }
                },
              ),
            ],
          ),
        ),
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
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRoute(SavedRoute route) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete route?'),
        content: Text('Are you sure you want to delete "${route.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.repositories.navigation.deleteRoute(route.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route deleted.')),
        );
      }
    }
  }

  Future<void> _renameRoute(SavedRoute route) async {
    if (_renameDialogOpen) return;
    setState(() => _renameDialogOpen = true);

    String? newName;
    try {
      newName = await showDialog<String>(
        context: context,
        builder: (_) => _RenameRouteDialog(initialName: route.name),
      );
    } finally {
      if (mounted) setState(() => _renameDialogOpen = false);
    }

    if (newName != null && newName.trim().isNotEmpty && mounted) {
      await widget.repositories.navigation.renameRoute(route.id, newName.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route renamed.')),
        );
      }
    }
  }

  void _openPlanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapPlannerScreen(
          storage: widget.storage,
          settings: widget.settings,
          drivingSession: widget.drivingSession,
        ),
      ),
    );
  }

  void _openSavedRoutes(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedRoutesScreen(
          storage: widget.storage,
          settings: widget.settings,
          drivingSession: widget.drivingSession,
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          storage: widget.storage,
          settings: widget.settings,
          session: widget.session,
          accountController: widget.accountController,
        ),
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
