import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/app_session_controller.dart';
import 'controllers/driving_session_controller.dart';
import 'database/app_database.dart';
import 'online/matrix/matrix_account_service.dart';
import 'repositories/app_repositories.dart';
import 'screens/app_shell.dart';
import 'services/route_storage_service.dart';
import 'services/secure_credential_service.dart';
import 'services/settings_service.dart';
import 'services/attempt_validator_service.dart';

export 'utils/ui_helpers.dart';
export 'utils/format_helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = RouteStorageService();
  final settings = SettingsService();
  final database = AppDatabase(openRalRoadsDatabase());
  final secureCredentials = SecureCredentialService();
  await storage.init();
  await settings.init();
  final repositories = AppRepositories(
    routeStorage: storage,
    database: database,
  );
  await repositories.navigation.migrateLegacySavedRoutes();
  final matrixAccountService = MatrixAccountService(
    database: database,
    secureCredentials: secureCredentials,
  );
  final session = AppSessionController(
    settings: settings,
    repositories: repositories,
    matrixAccountService: matrixAccountService,
    secureCredentials: secureCredentials,
  );
  final accountController = AccountConnectionController(
    session: session,
    matrixAccountService: matrixAccountService,
  );
  final validatorService = AttemptValidatorService(
    attemptRepository: repositories.attempts,
    segmentRepository: repositories.segments,
  );
  final drivingSession = DrivingSessionController(
    tripRepository: repositories.trips,
    attemptRepository: repositories.attempts,
    validatorService: validatorService,
    settings: settings,
  );
  runApp(
    RalroadsApp(
      storage: storage,
      settings: settings,
      database: database,
      repositories: repositories,
      session: session,
      accountController: accountController,
      drivingSession: drivingSession,
    ),
  );
}

class RalroadsApp extends StatelessWidget {
  const RalroadsApp({
    required this.storage,
    required this.settings,
    required this.database,
    required this.repositories,
    required this.session,
    required this.accountController,
    required this.drivingSession,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;
  final AppDatabase database;
  final AppRepositories repositories;
  final AppSessionController session;
  final AccountConnectionController accountController;
  final DrivingSessionController drivingSession;

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
      home: RalRoadsAppShell(
        storage: storage,
        settings: settings,
        repositories: repositories,
        session: session,
        accountController: accountController,
        drivingSession: drivingSession,
      ),
    );
  }
}
