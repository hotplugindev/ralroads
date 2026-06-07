import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ralroads/controllers/app_session_controller.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/online/matrix/matrix_sync_service.dart';
import 'package:ralroads/screens/settings_screen.dart';
import 'package:ralroads/services/route_storage_service.dart';
import 'package:ralroads/services/secure_credential_service.dart';
import 'package:ralroads/services/settings_service.dart';

void main() {
  testWidgets('saving a valid ORS key updates Settings immediately', (
    tester,
  ) async {
    final settings = _TestSettingsService();

    await tester.pumpWidget(
      _settingsApp(
        settings: settings,
        validateOrsApiKey: (key) async => key == 'valid-key',
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'valid-key');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(settings.getOrsApiKey(), 'valid-key');
    expect(find.text('API key saved'), findsOneWidget);
    expect(find.text('Delete Key'), findsOneWidget);
  });

  testWidgets('invalid ORS key shows inline error and is not saved', (
    tester,
  ) async {
    final settings = _TestSettingsService();

    await tester.pumpWidget(
      _settingsApp(settings: settings, validateOrsApiKey: (_) async => false),
    );

    await tester.enterText(find.byType(TextField).first, 'bad-key');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(settings.getOrsApiKey(), isNull);
    expect(find.text('API key rejected'), findsOneWidget);
    expect(find.text('Delete Key'), findsNothing);
  });

  testWidgets('deleting an ORS key updates Settings immediately', (
    tester,
  ) async {
    final settings = _TestSettingsService();
    await settings.saveOrsApiKey('valid-key');

    await tester.pumpWidget(
      _settingsApp(settings: settings, validateOrsApiKey: (_) async => true),
    );

    expect(find.text('Delete Key'), findsOneWidget);
    await tester.tap(find.text('Delete Key'));
    await tester.pumpAndSettle();

    expect(settings.getOrsApiKey(), isNull);
    expect(find.text('No API key saved'), findsOneWidget);
    expect(find.text('Delete Key'), findsNothing);
  });

  testWidgets('warning toggle updates without a tab switch', (tester) async {
    final settings = _TestSettingsService();

    await tester.pumpWidget(
      _settingsApp(settings: settings, validateOrsApiKey: (_) async => true),
    );

    expect(settings.showTrafficLights, isTrue);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();

    expect(settings.showTrafficLights, isFalse);
  });

  testWidgets('Matrix session state updates Settings immediately', (
    tester,
  ) async {
    final settings = _TestSettingsService();
    final session = _FakeSessionController();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      _settingsApp(
        settings: settings,
        session: session,
        validateOrsApiKey: (_) async => true,
      ),
    );

    expect(find.text('disconnected'), findsOneWidget);

    final now = DateTime.now();
    session.setSnapshot(
      AppSessionSnapshot(
        matrixStatus: MatrixConnectionStatus.connected,
        orsStatus: OrsConnectionStatus.disconnected,
        offline: false,
        onboardingComplete: true,
        matrixSession: MatrixSession(
          id: 'matrix-primary-session',
          accountId: 'matrix-primary',
          matrixUserId: '@alice:matrix.org',
          homeserverUrl: 'https://matrix.org',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('connected'), findsOneWidget);
    expect(find.text('Connected as @alice:matrix.org'), findsOneWidget);
  });
}

Widget _settingsApp({
  required SettingsService settings,
  required OrsApiKeyValidator validateOrsApiKey,
  AppSessionController? session,
  AccountConnectionController? accountController,
}) {
  return MaterialApp(
    home: SettingsScreen(
      storage: RouteStorageService(),
      settings: settings,
      session: session,
      accountController: accountController,
      validateOrsApiKey: validateOrsApiKey,
    ),
  );
}

class _TestSettingsService extends SettingsService {
  String? _orsApiKey;
  bool _showTrafficLights = true;

  _TestSettingsService()
    : super(
        secureCredentials: SecureCredentialService(
          store: MemorySecureCredentialStore(),
        ),
      );

  @override
  String? getOrsApiKey() => _orsApiKey;

  @override
  String? getEffectiveOrsApiKey() => _orsApiKey;

  @override
  bool hasOrsApiKey() => _orsApiKey != null;

  @override
  bool hasEffectiveOrsApiKey() => _orsApiKey != null;

  @override
  Future<void> saveOrsApiKey(String key) async {
    final trimmed = key.trim();
    _orsApiKey = trimmed.isEmpty ? null : trimmed;
    notifyListeners();
  }

  @override
  Future<void> deleteOrsApiKey() async {
    _orsApiKey = null;
    notifyListeners();
  }

  @override
  bool get showTrafficLights => _showTrafficLights;

  @override
  Future<void> setShowTrafficLights(bool value) async {
    _showTrafficLights = value;
    notifyListeners();
  }
}

class _FakeSessionController extends ChangeNotifier
    implements AppSessionController {
  AppSessionSnapshot _snapshot = const AppSessionSnapshot(
    matrixStatus: MatrixConnectionStatus.disconnected,
    orsStatus: OrsConnectionStatus.disconnected,
    offline: false,
    onboardingComplete: true,
  );

  void setSnapshot(AppSessionSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  AppSessionSnapshot get snapshot => _snapshot;

  @override
  MatrixSyncService get syncService => throw UnimplementedError();

  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<void> load() async {}

  @override
  Future<void> refreshConnections() async {}
}
