// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:ralroads/controllers/app_session_controller.dart';
import 'package:ralroads/controllers/driving_session_controller.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/main.dart';
import 'package:ralroads/online/matrix/matrix_account_service.dart';
import 'package:ralroads/repositories/app_repositories.dart';
import 'package:ralroads/services/attempt_validator_service.dart';
import 'package:ralroads/services/route_storage_service.dart';
import 'package:ralroads/services/secure_credential_service.dart';
import 'package:ralroads/services/settings_service.dart';

void main() {
  testWidgets('RalRoads home shows primary actions', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final routeStorage = RouteStorageService();
    final settings = SettingsService();
    final repositories = AppRepositories(
      routeStorage: routeStorage,
      database: database,
    );
    final secureCredentials = SecureCredentialService(
      store: MemorySecureCredentialStore(),
    );
    final matrix = MatrixAccountService(
      database: database,
      secureCredentials: secureCredentials,
    );
    final session = AppSessionController(
      settings: settings,
      repositories: repositories,
      matrixAccountService: matrix,
      secureCredentials: secureCredentials,
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
    addTearDown(database.close);

    await tester.pumpWidget(
      RalroadsApp(
        storage: routeStorage,
        settings: settings,
        database: database,
        repositories: repositories,
        session: session,
        accountController: AccountConnectionController(
          session: session,
          matrixAccountService: matrix,
        ),
        drivingSession: drivingSession,
      ),
    );

    expect(find.text('RalRoads'), findsWidgets);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Use offline without setup'), findsOneWidget);
  });
}
