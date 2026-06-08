import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import '../../database/app_database.dart';
import '../../services/secure_credential_service.dart';
import 'matrix_server_config.dart';

enum MatrixConnectionState {
  disconnected,
  restoring,
  connecting,
  connected,
  authenticationRequired,
  offline,
  error,
}

enum MatrixSyncState { idle, initialSync, syncing, upToDate, offline, error }

class MatrixClientService {
  MatrixClientService({
    required AppDatabase database,
    required SecureCredentialService secureCredentials,
  }) : _database = database,
       _secureCredentials = secureCredentials {
    _client = Client(
      'RalRoads',
      databaseBuilder: (_) async {
        final dir = await getApplicationSupportDirectory();
        final db = HiveCollectionsDatabase('ralroads_matrix_sdk', dir.path);
        await db.open();
        return db;
      },
    );
  }

  final AppDatabase _database;
  final SecureCredentialService _secureCredentials;
  late final Client _client;

  Client get client => _client;

  bool _initialized = false;
  bool _syncRunning = false;
  final _connectionState = StreamController<MatrixConnectionState>.broadcast();
  final _syncState = StreamController<MatrixSyncState>.broadcast();

  bool get isInitialized => _initialized;
  bool get isSyncRunning => _syncRunning;
  Stream<MatrixConnectionState> get connectionState => _connectionState.stream;
  Stream<MatrixSyncState> get syncState => _syncState.stream;

  void _emitConnection(MatrixConnectionState state) {
    if (!_connectionState.isClosed) _connectionState.add(state);
  }

  void _emitSync(MatrixSyncState state) {
    if (!_syncState.isClosed) _syncState.add(state);
  }

  Future<void> init() async {
    if (_initialized) return;

    _emitConnection(MatrixConnectionState.restoring);
    final token = await _secureCredentials.readString(
      SecureCredentialKey.matrixAccessToken,
    );
    final session =
        await (_database.select(_database.matrixSessions)
              ..where((row) => row.isActive.equals(true))
              ..limit(1))
            .getSingleOrNull();

    if (token != null && session != null) {
      _client.homeserver = Uri.parse(session.homeserverUrl);
      try {
        await _client.init(
          newToken: token,
          newHomeserver: Uri.parse(session.homeserverUrl),
          newUserID: session.matrixUserId,
          newDeviceID: session.deviceId,
          newDeviceName: 'RalRoads',
          waitForFirstSync: false,
        );
        await _client.getProfileFromUserId(session.matrixUserId);
        _emitConnection(MatrixConnectionState.connected);
      } catch (_) {
        _emitConnection(MatrixConnectionState.authenticationRequired);
      }
    } else {
      await _client.init(waitForFirstSync: false);
      _emitConnection(MatrixConnectionState.authenticationRequired);
    }

    _initialized = true;
  }

  Future<void> login({
    required MatrixServerConfig server,
    required String username,
    required String password,
  }) async {
    await init();
    _emitConnection(MatrixConnectionState.connecting);
    _client.homeserver = server.baseUri;

    final response = await _client.login(
      LoginType.mLoginPassword,
      password: password,
      identifier: AuthenticationUserIdentifier(user: username),
      initialDeviceDisplayName: 'RalRoads',
    );

    await _secureCredentials.writeString(
      SecureCredentialKey.matrixAccessToken,
      response.accessToken,
    );
    if (response.refreshToken != null) {
      await _secureCredentials.writeString(
        SecureCredentialKey.matrixRefreshToken,
        response.refreshToken!,
      );
    }
    await _secureCredentials.writeString(
      SecureCredentialKey.matrixDeviceId,
      response.deviceId,
    );

    _emitConnection(MatrixConnectionState.connected);
    startSync();
  }

  void startSync() {
    if (_syncRunning) return;
    if (_client.userID == null || _client.accessToken == null) {
      _emitSync(MatrixSyncState.error);
      return;
    }
    _syncRunning = true;
    _emitSync(MatrixSyncState.initialSync);
    _client.backgroundSync = true;
  }

  void stopSync() {
    if (!_syncRunning) return;
    _client.backgroundSync = false;
    _syncRunning = false;
    _emitSync(MatrixSyncState.idle);
  }

  bool isRoomEncrypted(String roomId) {
    final room = _client.getRoomById(roomId);
    return room?.encrypted ?? false;
  }

  Future<void> logout() async {
    if (_initialized) {
      stopSync();
      try {
        await _client.logout();
      } catch (_) {
        _emitConnection(MatrixConnectionState.error);
      }
    }
    await _secureCredentials.delete(SecureCredentialKey.matrixAccessToken);
    await _secureCredentials.delete(SecureCredentialKey.matrixRefreshToken);
    await _secureCredentials.delete(SecureCredentialKey.matrixDeviceId);
    _emitConnection(MatrixConnectionState.disconnected);
  }
}
