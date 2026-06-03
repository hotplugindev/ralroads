import 'package:flutter/material.dart';

import '../services/route_storage_service.dart';
import '../services/settings_service.dart';
import 'map_planner_screen.dart';
import 'saved_routes_screen.dart';
import 'settings_screen.dart';

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
