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

class NavigateScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final savedRoutes = repositories.navigation.getSavedRoutes();
    final orsConnected = settings.hasEffectiveOrsApiKey();
    return RalRoadsPage(
      title: 'Navigate',
      children: [
        PrimaryActionCard(
          title: 'Plan a route',
          subtitle: orsConnected
              ? 'Search places, add stops and start a road-aware route.'
              : 'Connect OpenRouteService for online route planning. Saved routes still work offline.',
          icon: Icons.add_road,
          actionLabel: orsConnected ? 'Plan' : 'Connect ORS',
          onPressed: () =>
              orsConnected ? _openPlanner(context) : _openSettings(context),
        ),
        const SectionHeader(title: 'Saved routes'),
        if (savedRoutes.isEmpty)
          EmptyState(
            title: 'No saved routes yet',
            message:
                'Routes you save after planning remain available locally for preview and driving.',
            action: OutlinedButton.icon(
              onPressed: () => _openSavedRoutes(context),
              icon: const Icon(Icons.bookmarks),
              label: const Text('Open saved routes'),
            ),
          )
        else
          for (final route in savedRoutes.take(3))
            RouteCard(
              title: route.name,
              subtitle: formatDistance(route.totalDistance),
              onTap: () => _openSavedRoutes(context),
            ),
        FeatureCard(
          title: 'Offline maps',
          subtitle: 'Manage downloaded map regions and offline readiness.',
          icon: Icons.map_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OfflineMapsScreen(
                storage: storage,
                settings: settings,
              ),
            ),
          ),
        ),
        FeatureCard(
          title: 'Navigation settings',
          subtitle: 'Voice, callouts, route overlays and ORS connection.',
          icon: Icons.tune,
          onTap: () => _openSettings(context),
        ),
      ],
    );
  }

  void _openPlanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapPlannerScreen(
          storage: storage,
          settings: settings,
          drivingSession: drivingSession,
        ),
      ),
    );
  }

  void _openSavedRoutes(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedRoutesScreen(
          storage: storage,
          settings: settings,
          drivingSession: drivingSession,
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          storage: storage,
          settings: settings,
          session: session,
          accountController: accountController,
        ),
      ),
    );
  }
}
