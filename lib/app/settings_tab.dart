import 'package:flutter/material.dart';

import '../controllers/app_session_controller.dart';
import '../screens/offline_maps_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/matrix_connection_screen.dart';
import '../services/settings_service.dart';
import '../services/route_storage_service.dart';
import '../widgets/product_components.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({
    required this.storage,
    required this.settings,
    required this.session,
    required this.accountController,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;
  final AppSessionController session;
  final AccountConnectionController accountController;

  @override
  Widget build(BuildContext context) {
    final snap = session.snapshot;
    return RalRoadsPage(
      title: 'Settings',
      children: [
        ConnectionCard(
          title: 'OpenRouteService',
          status: snap.orsStatus.name,
          icon: Icons.route_outlined,
          description:
              'ORS powers online route planning and place search. Offline saved routes do not require it.',
          actionLabel: 'Open settings',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(
                storage: storage,
                settings: settings,
                session: session,
                accountController: accountController,
              ),
            ),
          ),
        ),
        ConnectionCard(
          title: 'Matrix',
          status: snap.matrixStatus.name,
          icon: Icons.hub_outlined,
          description:
              'Connect a Matrix account for friends, groups, sync and challenge sharing.',
          actionLabel: 'Connect Matrix',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  MatrixConnectionScreen(controller: accountController),
            ),
          ),
        ),
        FeatureCard(
          title: 'Offline maps',
          subtitle: 'Manage local map regions.',
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
        SyncStatusIndicator(
          label: snap.matrixStatus == MatrixConnectionStatus.connected
              ? 'Ready to sync'
              : 'Local only',
        ),
      ],
    );
  }
}
