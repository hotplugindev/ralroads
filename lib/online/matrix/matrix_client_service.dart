import 'package:matrix/matrix.dart';
import '../../database/app_database.dart';
import '../../services/secure_credential_service.dart';
import 'matrix_server_config.dart';

class MatrixClientService {
  MatrixClientService({
    required AppDatabase database,
    required SecureCredentialService secureCredentials,
  }) : _database = database,
       _secureCredentials = secureCredentials {
    _client = Client('RalRoads');
  }

  final AppDatabase _database;
  final SecureCredentialService _secureCredentials;
  late final Client _client;

  Client get client => _client;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    final token = await _secureCredentials.readString(SecureCredentialKey.matrixAccessToken);
    final session = await (_database.select(_database.matrixSessions)
          ..where((row) => row.isActive.equals(true))
          ..limit(1))
         .getSingleOrNull();

    if (token != null && session != null) {
      _client.homeserver = Uri.parse(session.homeserverUrl);
      await _client.init(
        newToken: token,
        newHomeserver: Uri.parse(session.homeserverUrl),
        newUserID: session.matrixUserId,
        newDeviceID: session.deviceId,
        newDeviceName: 'RalRoads',
      );
      _client.backgroundSync = true;
    }

    _initialized = true;
  }

  Future<void> login({
    required MatrixServerConfig server,
    required String username,
    required String password,
  }) async {
    await init();
    _client.homeserver = server.baseUri;

    final response = await _client.login(
      LoginType.mLoginPassword,
      password: password,
      identifier: AuthenticationUserIdentifier(user: username),
      initialDeviceDisplayName: 'RalRoads',
    );

    await _secureCredentials.writeString(
      SecureCredentialKey.matrixAccessToken,
      response.accessToken ?? '',
    );
    if (response.refreshToken != null) {
      await _secureCredentials.writeString(
        SecureCredentialKey.matrixRefreshToken,
        response.refreshToken!,
      );
    }
    await _secureCredentials.writeString(
      SecureCredentialKey.matrixDeviceId,
      response.deviceId ?? '',
    );

    _client.backgroundSync = true;
  }

  Future<void> logout() async {
    if (_initialized) {
      try {
        await _client.logout();
      } catch (_) {}
    }
    await _secureCredentials.delete(SecureCredentialKey.matrixAccessToken);
    await _secureCredentials.delete(SecureCredentialKey.matrixRefreshToken);
    await _secureCredentials.delete(SecureCredentialKey.matrixDeviceId);
    _client.backgroundSync = false;
  }
}
