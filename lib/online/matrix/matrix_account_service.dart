import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../services/secure_credential_service.dart';

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
    Dio? dio,
  }) : _database = database,
       _secureCredentials = secureCredentials,
       _dio = dio ?? Dio();

  final AppDatabase _database;
  final SecureCredentialService _secureCredentials;
  final Dio _dio;

  Future<MatrixSession?> restoreSession() {
    return (_database.select(_database.matrixSessions)
          ..where((row) => row.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<MatrixLoginResult> loginWithPassword({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    final baseUrl = _normalizeHomeserver(homeserver);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/_matrix/client/v3/login',
        data: {
          'type': 'm.login.password',
          'identifier': {'type': 'm.id.user', 'user': username},
          'password': password,
          'initial_device_display_name': 'RalRoads',
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final data = response.data;
      final accessToken = data?['access_token'] as String?;
      final userId = data?['user_id'] as String?;
      final deviceId = data?['device_id'] as String?;
      final refreshToken = data?['refresh_token'] as String?;
      if (accessToken == null || userId == null || deviceId == null) {
        throw const MatrixAccountException(
          'Matrix login response was missing required session fields.',
        );
      }

      await _secureCredentials.writeString(
        SecureCredentialKey.matrixAccessToken,
        accessToken,
      );
      if (refreshToken != null) {
        await _secureCredentials.writeString(
          SecureCredentialKey.matrixRefreshToken,
          refreshToken,
        );
      }
      await _secureCredentials.writeString(
        SecureCredentialKey.matrixDeviceId,
        deviceId,
      );
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
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final err = error.response?.data;
      if (status == 403) {
        throw const MatrixAccountException(
          'Matrix rejected those credentials.',
        );
      }
      if (status == 429) {
        throw const MatrixAccountException(
          'Matrix login is rate-limited. Try again later.',
        );
      }
      throw MatrixAccountException(
        'Matrix login failed${status == null ? '' : ' ($status)'}: $err',
      );
    }
  }

  Future<void> logout() async {
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

  String _normalizeHomeserver(Uri homeserver) {
    final withScheme = homeserver.hasScheme
        ? homeserver
        : Uri.parse('https://${homeserver.toString()}');
    return withScheme
        .replace(path: '')
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }
}
