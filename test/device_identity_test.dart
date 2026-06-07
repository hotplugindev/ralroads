import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/services/secure_credential_service.dart';
import 'package:ralroads/services/device_identity_service.dart';

void main() {
  group('DeviceIdentityService', () {
    late SecureCredentialService secureCredentials;
    late DeviceIdentityService identityService;

    setUp(() {
      secureCredentials = SecureCredentialService(
        store: MemorySecureCredentialStore(),
      );
      identityService = DeviceIdentityService(
        secureCredentials: secureCredentials,
      );
    });

    test('generates, saves and restores keypair identity', () async {
      await identityService.initializeIdentity();

      final savedHex = await secureCredentials.readString(SecureCredentialKey.ralroadsSigningPrivateKey);
      expect(savedHex, isNotNull);
      expect(savedHex!.length, 64); // 32 bytes hex encoded = 64 chars

      final publicKeyHex = await identityService.getPublicKey();
      expect(publicKeyHex.length, 64); // 32 bytes hex encoded = 64 chars

      // Re-initialize to ensure it's idempotent
      await identityService.initializeIdentity();
      final restoredHex = await secureCredentials.readString(SecureCredentialKey.ralroadsSigningPrivateKey);
      expect(restoredHex, savedHex);
    });

    test('signs message and verifies signature', () async {
      await identityService.initializeIdentity();
      final publicKeyHex = await identityService.getPublicKey();

      const message = "my-test-message";
      final signature = await identityService.signMessage(message);
      expect(signature.length, 128); // 64 bytes hex encoded = 128 chars

      final isValid = await identityService.verifySignature(
        message: message,
        signatureHex: signature,
        publicKeyHex: publicKeyHex,
      );
      expect(isValid, isTrue);

      final isInvalid = await identityService.verifySignature(
        message: "different-message",
        signatureHex: signature,
        publicKeyHex: publicKeyHex,
      );
      expect(isInvalid, isFalse);
    });
  });
}
