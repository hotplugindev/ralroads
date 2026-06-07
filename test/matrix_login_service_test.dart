import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/online/matrix/matrix_account_service.dart';
import 'package:ralroads/online/matrix/matrix_client_service.dart';
import 'package:ralroads/online/matrix/matrix_server_config.dart';
import 'package:ralroads/services/secure_credential_service.dart';

class FakeClient implements Client {
  @override
  String? get userID => '@alice:matrix.org';

  @override
  String? get deviceID => 'DEVICE_ID';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeClientService extends MatrixClientService {
  FakeClientService({
    required super.database,
    required super.secureCredentials,
  });

  bool loginCalled = false;
  MatrixServerConfig? lastServer;

  @override
  Future<void> login({
    required MatrixServerConfig server,
    required String username,
    required String password,
  }) async {
    loginCalled = true;
    lastServer = server;
    if (password == 'wrong') {
      throw Exception('M_FORBIDDEN');
    }
  }

  @override
  Client get client => FakeClient();
}

void main() {
  late AppDatabase database;
  late SecureCredentialService secureCredentials;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    secureCredentials = SecureCredentialService(
      store: MemorySecureCredentialStore(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('MatrixAccountService Login Tests', () {
    test('successful login persists session and returns result', () async {
      final fakeClientService = FakeClientService(
        database: database,
        secureCredentials: secureCredentials,
      );

      final accountService = MatrixAccountService(
        database: database,
        secureCredentials: secureCredentials,
        clientService: fakeClientService,
      );

      final serverConfig = parseMatrixServer(input: 'matrix.org');

      final result = await accountService.loginWithPassword(
        server: serverConfig,
        username: '@alice:matrix.org',
        password: 'correct_password',
      );

      expect(fakeClientService.loginCalled, isTrue);
      expect(
        fakeClientService.lastServer?.canonicalBaseUrl,
        'https://matrix.org',
      );
      expect(result.userId, '@alice:matrix.org');
      expect(result.deviceId, 'DEVICE_ID');

      // Check that the session was restored successfully
      final restored = await accountService.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.matrixUserId, '@alice:matrix.org');
      expect(restored.homeserverUrl, 'https://matrix.org');
      expect(restored.deviceId, 'DEVICE_ID');
      expect(restored.isActive, isTrue);
    });

    test('failed login throws MatrixAccountException', () async {
      final fakeClientService = FakeClientService(
        database: database,
        secureCredentials: secureCredentials,
      );

      final accountService = MatrixAccountService(
        database: database,
        secureCredentials: secureCredentials,
        clientService: fakeClientService,
      );

      final serverConfig = parseMatrixServer(input: 'matrix.org');

      expect(
        () => accountService.loginWithPassword(
          server: serverConfig,
          username: '@alice:matrix.org',
          password: 'wrong',
        ),
        throwsA(isA<MatrixAccountException>()),
      );
    });
  });
}
