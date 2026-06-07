import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ralroads/controllers/app_session_controller.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/online/matrix/matrix_account_service.dart';
import 'package:ralroads/online/matrix/matrix_sync_service.dart';
import 'package:ralroads/repositories/app_repositories.dart';
import 'package:ralroads/screens/onboarding_screen.dart';
import 'package:ralroads/services/route_storage_service.dart';
import 'package:ralroads/services/secure_credential_service.dart';
import 'package:ralroads/services/settings_service.dart';

void main() {
  testWidgets('successful Matrix login automatically advances onboarding', (
    tester,
  ) async {
    final harness = _OnboardingHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app());
    await _goToMatrixStep(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Homeserver'),
      'https://matrix.org',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Matrix ID or username'),
      '@alice:matrix.org',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'correct horse battery staple',
    );
    await _tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Connect Matrix'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text("You're ready!"), findsOneWidget);
    expect(
      harness.session.snapshot.matrixSession?.matrixUserId,
      '@alice:matrix.org',
    );
  });

  testWidgets('failed Matrix login remains on Matrix step with inline error', (
    tester,
  ) async {
    final harness = _OnboardingHarness(loginSucceeds: false);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app());
    await _goToMatrixStep(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Homeserver'),
      'https://matrix.org',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Matrix ID or username'),
      '@alice:matrix.org',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'bad password',
    );
    await _tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Connect Matrix'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Matrix rejected those credentials.'), findsOneWidget);
    expect(find.text('Social & sync'), findsOneWidget);
    expect(find.text("You're ready!"), findsNothing);
  });

  testWidgets('restored Matrix session skips login form on Matrix step', (
    tester,
  ) async {
    final harness = _OnboardingHarness(restored: true);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app());
    await _goToMatrixStep(tester, settleOnMatrix: false);
    await tester.pump();

    expect(find.text('Matrix connected!'), findsOneWidget);
    expect(find.text('@restored:matrix.org'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsNothing);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text("You're ready!"), findsOneWidget);
  });

  testWidgets(
    'onboarding layouts survive small, landscape, scaled and keyboard states',
    (tester) async {
      final cases = <({Size size, double textScale, double keyboard})>[
        (size: const Size(360, 640), textScale: 1, keyboard: 280),
        (size: const Size(412, 915), textScale: 1.5, keyboard: 320),
        (size: const Size(640, 360), textScale: 1, keyboard: 180),
        (size: const Size(412, 915), textScale: 2, keyboard: 340),
      ];

      for (final layout in cases) {
        final harness = _OnboardingHarness();
        await _setTestView(tester, layout.size, keyboard: layout.keyboard);
        await tester.pumpWidget(harness.app(textScale: layout.textScale));
        await _goToMatrixStep(tester);

        expect(find.text('Social & sync'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
        expect(find.text('Skip setup'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await harness.dispose();
      }
    },
  );
}

Future<void> _goToMatrixStep(
  WidgetTester tester, {
  bool settleOnMatrix = true,
}) async {
  await _tapVisible(tester, find.text('Get started'));
  await tester.pumpAndSettle();
  await _tapVisible(tester, find.text('Skip for now'));
  await tester.pumpAndSettle();
  await _tapVisible(tester, find.widgetWithText(FilledButton, 'Continue'));
  if (settleOnMatrix) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  expect(find.text('Social & sync'), findsOneWidget);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Future<void> _setTestView(
  WidgetTester tester,
  Size size, {
  double keyboard = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

class _OnboardingHarness {
  _OnboardingHarness({this.loginSucceeds = true, bool restored = false})
    : database = AppDatabase(NativeDatabase.memory()),
      settings = SettingsService(
        secureCredentials: SecureCredentialService(
          store: MemorySecureCredentialStore(),
        ),
      ),
      storage = RouteStorageService() {
    repositories = AppRepositories(routeStorage: storage, database: database);
    final matrixAccount = MatrixAccountService(
      database: database,
      secureCredentials: secureCredentials,
    );
    sync = MatrixSyncService(
      repositories: repositories,
      secureCredentials: secureCredentials,
      matrixAccount: matrixAccount,
    );
    session = _FakeSessionController(sync: sync, restored: restored);
    account = _FakeAccountConnectionController(
      session: session,
      loginSucceeds: loginSucceeds,
    );
  }

  final bool loginSucceeds;
  final AppDatabase database;
  final SettingsService settings;
  final RouteStorageService storage;
  final SecureCredentialService secureCredentials = SecureCredentialService(
    store: MemorySecureCredentialStore(),
  );
  late final AppRepositories repositories;
  late final MatrixSyncService sync;
  late final _FakeSessionController session;
  late final _FakeAccountConnectionController account;

  Widget app({double textScale = 1}) {
    return MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: OnboardingScreen(
        storage: storage,
        settings: settings,
        session: session,
        accountController: account,
        repositories: repositories,
      ),
    );
  }

  Future<void> dispose() async {
    sync.stop();
    session.dispose();
    account.dispose();
    await database.close();
  }
}

class _FakeSessionController extends ChangeNotifier
    implements AppSessionController {
  _FakeSessionController({
    required MatrixSyncService sync,
    bool restored = false,
  }) : _sync = sync {
    if (restored) {
      setConnected('@restored:matrix.org');
    }
  }

  final MatrixSyncService _sync;
  AppSessionSnapshot _snapshot = const AppSessionSnapshot(
    matrixStatus: MatrixConnectionStatus.disconnected,
    orsStatus: OrsConnectionStatus.disconnected,
    offline: false,
    onboardingComplete: false,
  );

  void setConnected(String matrixUserId) {
    final now = DateTime(2026, 1, 1, 12);
    _snapshot = _snapshot.copyWith(
      matrixStatus: MatrixConnectionStatus.connected,
      matrixSession: MatrixSession(
        id: 'matrix-primary-session',
        accountId: 'matrix-primary',
        matrixUserId: matrixUserId,
        homeserverUrl: 'https://matrix.org',
        deviceId: 'DEVICE',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    notifyListeners();
  }

  void setDisconnected() {
    _snapshot = const AppSessionSnapshot(
      matrixStatus: MatrixConnectionStatus.disconnected,
      orsStatus: OrsConnectionStatus.disconnected,
      offline: false,
      onboardingComplete: false,
    );
    notifyListeners();
  }

  @override
  AppSessionSnapshot get snapshot => _snapshot;

  @override
  MatrixSyncService get syncService => _sync;

  @override
  Future<void> completeOnboarding() async {
    _snapshot = _snapshot.copyWith(onboardingComplete: true);
    notifyListeners();
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> refreshConnections() async {}
}

class _FakeAccountConnectionController extends ChangeNotifier
    implements AccountConnectionController {
  _FakeAccountConnectionController({
    required _FakeSessionController session,
    required this.loginSucceeds,
  }) : _session = session;

  final _FakeSessionController _session;
  final bool loginSucceeds;
  bool _busy = false;
  String? _message;

  @override
  bool get busy => _busy;

  @override
  String? get message => _message;

  @override
  Future<void> connectMatrix({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    _busy = true;
    _message = null;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (loginSucceeds) {
      _message = 'Connected as $username';
      _session.setConnected(username);
    } else {
      _message = 'Matrix rejected those credentials.';
    }
    _busy = false;
    notifyListeners();
  }

  @override
  Future<void> disconnectMatrix() async {
    _busy = true;
    notifyListeners();
    _session.setDisconnected();
    _message = null;
    _busy = false;
    notifyListeners();
  }
}
