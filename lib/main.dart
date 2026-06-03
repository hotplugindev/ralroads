import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/route_storage_service.dart';
import 'services/settings_service.dart';

export 'utils/ui_helpers.dart';
export 'utils/format_helpers.dart';

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
