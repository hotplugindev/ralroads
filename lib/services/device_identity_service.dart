import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'secure_credential_service.dart';

class DeviceIdentityService {
  DeviceIdentityService({required this.secureCredentials});

  final SecureCredentialService secureCredentials;
  final _algorithm = Ed25519();

  // Helper to convert list of bytes to a hex string
  String _toHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // Helper to convert hex string back to a list of bytes
  List<int> _fromHex(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  /// Checks if a private key exists. If not, generates a new Ed25519 keypair and writes it to secure storage.
  Future<void> initializeIdentity() async {
    final existingKey = await secureCredentials.readString(
      SecureCredentialKey.ralroadsSigningPrivateKey,
    );
    if (existingKey == null || existingKey.isEmpty) {
      final keyPair = await _algorithm.newKeyPair();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final hexKey = _toHex(privateKeyBytes);
      await secureCredentials.writeString(
        SecureCredentialKey.ralroadsSigningPrivateKey,
        hexKey,
      );
    }
  }

  /// Returns the hex-encoded Ed25519 public key.
  Future<String> getPublicKey() async {
    final hexKey = await secureCredentials.readString(
      SecureCredentialKey.ralroadsSigningPrivateKey,
    );
    if (hexKey == null || hexKey.isEmpty) {
      throw StateError('Signing identity not initialized.');
    }
    final privateKeyBytes = _fromHex(hexKey);
    final keyPair = await _algorithm.newKeyPairFromSeed(privateKeyBytes);
    final publicKey = await keyPair.extractPublicKey();
    return _toHex(publicKey.bytes);
  }

  /// Signs a message string, returning the hex-encoded signature.
  Future<String> signMessage(String message) async {
    final hexKey = await secureCredentials.readString(
      SecureCredentialKey.ralroadsSigningPrivateKey,
    );
    if (hexKey == null || hexKey.isEmpty) {
      throw StateError('Signing identity not initialized.');
    }
    final privateKeyBytes = _fromHex(hexKey);
    final keyPair = await _algorithm.newKeyPairFromSeed(privateKeyBytes);
    final messageBytes = utf8.encode(message);
    final signature = await _algorithm.sign(messageBytes, keyPair: keyPair);
    return _toHex(signature.bytes);
  }

  /// Verifies a hex signature against the message and hex public key.
  Future<bool> verifySignature({
    required String message,
    required String signatureHex,
    required String publicKeyHex,
  }) async {
    try {
      final messageBytes = utf8.encode(message);
      final signatureBytes = _fromHex(signatureHex);
      final publicKeyBytes = _fromHex(publicKeyHex);

      final signatureObj = Signature(
        signatureBytes,
        publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      );

      return await _algorithm.verify(messageBytes, signature: signatureObj);
    } catch (_) {
      return false;
    }
  }
}
