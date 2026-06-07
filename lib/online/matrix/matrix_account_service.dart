import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../../services/secure_credential_service.dart';
import 'matrix_client_service.dart';
import 'matrix_server_config.dart';

class MatrixLoginResult {
  const MatrixLoginResult({
    required this.userId,
    required this.deviceId,
    required this.homeserverUrl,
  });

  final String userId;
  final String deviceId;
  final String homeserverUrl;
}

class MatrixAccountException implements Exception {
  const MatrixAccountException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MatrixAccountService {
  MatrixAccountService({
    required AppDatabase database,
    required SecureCredentialService secureCredentials,
    MatrixClientService? clientService,
  }) : _database = database,
       _secureCredentials = secureCredentials,
       _clientService =
           clientService ??
           MatrixClientService(
             database: database,
             secureCredentials: secureCredentials,
           );

  final AppDatabase _database;
  final SecureCredentialService _secureCredentials;
  final MatrixClientService _clientService;

  MatrixClientService get clientService => _clientService;

  Future<MatrixSession?> restoreSession() {
    return (_database.select(_database.matrixSessions)
          ..where((row) => row.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<MatrixLoginResult> loginWithPassword({
    required MatrixServerConfig server,
    required String username,
    required String password,
  }) async {
    final baseUrl = server.canonicalBaseUrl;
    try {
      await _clientService.login(
        server: server,
        username: username,
        password: password,
      );

      final client = _clientService.client;
      final userId = client.userID;
      final deviceId = client.deviceID;

      if (userId == null || deviceId == null) {
        throw const MatrixAccountException(
          'Matrix login response was missing required session fields.',
        );
      }

      await _persistSession(
        homeserverUrl: baseUrl,
        matrixUserId: userId,
        deviceId: deviceId,
      );

      return MatrixLoginResult(
        userId: userId,
        deviceId: deviceId,
        homeserverUrl: baseUrl,
      );
    } catch (error) {
      throw MatrixAccountException('Matrix login failed: $error');
    }
  }

  Future<void> logout() async {
    await _clientService.logout();
    await _secureCredentials.delete(SecureCredentialKey.matrixAccessToken);
    await _secureCredentials.delete(SecureCredentialKey.matrixRefreshToken);
    await _secureCredentials.delete(SecureCredentialKey.matrixDeviceId);
    await (_database.update(_database.matrixSessions)).write(
      MatrixSessionsCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _persistSession({
    required String homeserverUrl,
    required String matrixUserId,
    required String deviceId,
  }) async {
    final now = DateTime.now();
    const accountId = 'matrix-primary';
    await _database.transaction(() async {
      await _database
          .into(_database.localAccounts)
          .insertOnConflictUpdate(
            LocalAccountsCompanion(
              id: const Value(accountId),
              mode: const Value('matrix'),
              displayName: Value(matrixUserId),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await (_database.update(_database.matrixSessions)).write(
        MatrixSessionsCompanion(
          isActive: const Value(false),
          updatedAt: Value(now),
        ),
      );
      await _database
          .into(_database.matrixSessions)
          .insertOnConflictUpdate(
            MatrixSessionsCompanion(
              id: const Value('matrix-primary-session'),
              accountId: const Value(accountId),
              matrixUserId: Value(matrixUserId),
              homeserverUrl: Value(homeserverUrl),
              deviceId: Value(deviceId),
              isActive: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });
  }
}
