import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../online/matrix/matrix_account_service.dart';
import '../online/matrix/matrix_sync_service.dart';
import '../repositories/app_repositories.dart';
import '../services/secure_credential_service.dart';
import '../services/settings_service.dart';

enum MatrixConnectionStatus {
  disconnected,
  connecting,
  connected,
  syncing,
  error,
}

enum OrsConnectionStatus {
  disconnected,
  validating,
  connected,
  invalid,
  rateLimited,
  error,
}

class AppSessionSnapshot {
  const AppSessionSnapshot({
    required this.matrixStatus,
    required this.orsStatus,
    required this.offline,
    required this.onboardingComplete,
    this.localProfile,
    this.matrixSession,
    this.errorMessage,
  });

  final MatrixConnectionStatus matrixStatus;
  final OrsConnectionStatus orsStatus;
  final bool offline;
  final bool onboardingComplete;
  final Profile? localProfile;
  final MatrixSession? matrixSession;
  final String? errorMessage;

  AppSessionSnapshot copyWith({
    MatrixConnectionStatus? matrixStatus,
    OrsConnectionStatus? orsStatus,
    bool? offline,
    bool? onboardingComplete,
    Profile? localProfile,
    MatrixSession? matrixSession,
    String? errorMessage,
  }) {
    return AppSessionSnapshot(
      matrixStatus: matrixStatus ?? this.matrixStatus,
      orsStatus: orsStatus ?? this.orsStatus,
      offline: offline ?? this.offline,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      localProfile: localProfile ?? this.localProfile,
      matrixSession: matrixSession ?? this.matrixSession,
      errorMessage: errorMessage,
    );
  }
}

class AppSessionController extends ChangeNotifier {
  AppSessionController({
    required SettingsService settings,
    required AppRepositories repositories,
    required MatrixAccountService matrixAccountService,
    required SecureCredentialService secureCredentials,
  }) : _settings = settings,
       _repositories = repositories,
       _matrixAccountService = matrixAccountService,
       _syncService = MatrixSyncService(
         repositories: repositories,
         secureCredentials: secureCredentials,
         matrixAccount: matrixAccountService,
       ),
       _snapshot = AppSessionSnapshot(
         matrixStatus: MatrixConnectionStatus.disconnected,
         orsStatus: settings.hasEffectiveOrsApiKey()
             ? OrsConnectionStatus.connected
             : OrsConnectionStatus.disconnected,
         offline: false,
         onboardingComplete: settings.onboardingComplete,
       ) {
    _settings.addListener(_onSettingsChanged);
  }

  final SettingsService _settings;
  final AppRepositories _repositories;
  final MatrixAccountService _matrixAccountService;
  final MatrixSyncService _syncService;
  AppSessionSnapshot _snapshot;

  AppSessionSnapshot get snapshot => _snapshot;
  MatrixSyncService get syncService => _syncService;

  void _onSettingsChanged() {
    _snapshot = _snapshot.copyWith(
      orsStatus: _settings.hasEffectiveOrsApiKey()
          ? OrsConnectionStatus.connected
          : OrsConnectionStatus.disconnected,
      onboardingComplete: _settings.onboardingComplete,
    );
    notifyListeners();
  }

  Future<void> load() async {
    final profile = await _repositories.profiles.getCurrentLocalProfile();
    final matrixSession = await _matrixAccountService.restoreSession();
    final isConnected = matrixSession != null;

    _snapshot = _snapshot.copyWith(
      localProfile: profile,
      matrixSession: matrixSession,
      matrixStatus: isConnected
          ? MatrixConnectionStatus.connected
          : MatrixConnectionStatus.disconnected,
      orsStatus: _settings.hasEffectiveOrsApiKey()
          ? OrsConnectionStatus.connected
          : OrsConnectionStatus.disconnected,
      onboardingComplete: _settings.onboardingComplete,
    );

    if (isConnected) {
      _syncService.start();
    } else {
      _syncService.stop();
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _syncService.stop();
    super.dispose();
  }

  Future<void> completeOnboarding() async {
    await _settings.setOnboardingComplete(true);
    _snapshot = _snapshot.copyWith(onboardingComplete: true);
    notifyListeners();
  }

  Future<void> refreshConnections() => load();
}

class AccountConnectionController extends ChangeNotifier {
  AccountConnectionController({
    required AppSessionController session,
    required MatrixAccountService matrixAccountService,
  }) : _session = session,
       _matrixAccountService = matrixAccountService;

  final AppSessionController _session;
  final MatrixAccountService _matrixAccountService;

  bool _busy = false;
  String? _message;

  bool get busy => _busy;
  String? get message => _message;

  Future<void> connectMatrix({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      final result = await _matrixAccountService.loginWithPassword(
        homeserver: homeserver,
        username: username,
        password: password,
      );
      _message = 'Connected as ${result.userId}';
      await _session.refreshConnections();
    } on MatrixAccountException catch (error) {
      _message = error.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectMatrix() async {
    _busy = true;
    notifyListeners();
    await _matrixAccountService.logout();
    await _session.refreshConnections();
    _busy = false;
    notifyListeners();
  }
}
