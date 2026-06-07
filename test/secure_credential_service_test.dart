import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/services/secure_credential_service.dart';

void main() {
  group('SecureCredentialService', () {
    test('stores trimmed non-empty values', () async {
      final service = SecureCredentialService(
        store: MemorySecureCredentialStore(),
      );

      await service.writeString(SecureCredentialKey.orsApiKey, '  test-key  ');

      expect(
        await service.readString(SecureCredentialKey.orsApiKey),
        'test-key',
      );
    });

    test('empty writes delete the value', () async {
      final service = SecureCredentialService(
        store: MemorySecureCredentialStore(),
      );

      await service.writeString(SecureCredentialKey.orsApiKey, 'test-key');
      await service.writeString(SecureCredentialKey.orsApiKey, '   ');

      expect(await service.readString(SecureCredentialKey.orsApiKey), isNull);
    });
  });
}
