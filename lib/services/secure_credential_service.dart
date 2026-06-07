import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SecureCredentialKey {
  orsApiKey('ors_api_key'),
  matrixAccessToken('matrix_access_token'),
  matrixRefreshToken('matrix_refresh_token'),
  matrixDeviceId('matrix_device_id'),
  matrixCryptoSecrets('matrix_crypto_secrets'),
  ralroadsSigningPrivateKey('ralroads_signing_private_key');

  const SecureCredentialKey(this.storageKey);

  final String storageKey;
}

abstract class SecureCredentialStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureCredentialStore implements SecureCredentialStore {
  const FlutterSecureCredentialStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecureCredentialStore implements SecureCredentialStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class SecureCredentialService {
  SecureCredentialService({
    SecureCredentialStore store = const FlutterSecureCredentialStore(),
  }) : _store = store;

  final SecureCredentialStore _store;

  Future<String?> readString(SecureCredentialKey key) async {
    final value = await _store.read(key.storageKey);
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> writeString(SecureCredentialKey key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await delete(key);
      return;
    }
    await _store.write(key.storageKey, trimmed);
  }

  Future<void> delete(SecureCredentialKey key) => _store.delete(key.storageKey);
}
