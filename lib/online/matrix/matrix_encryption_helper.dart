import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';

class MatrixEncryptionHelper {
  static Uint8List generateRandomKey() {
    final key = Key.fromSecureRandom(32);
    return key.bytes;
  }

  static Uint8List encryptPayload(String jsonStr, Uint8List keyBytes) {
    final key = Key(keyBytes);
    // Use a fixed or simple IV derived from key for deterministic/simple decoding
    // or a random IV appended to the payload. A random IV is standard:
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(jsonStr, iv: iv);

    // Combine IV + CipherText
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setRange(0, iv.bytes.length, iv.bytes);
    combined.setRange(iv.bytes.length, combined.length, encrypted.bytes);
    return combined;
  }

  static String decryptPayload(Uint8List combinedBytes, Uint8List keyBytes) {
    if (combinedBytes.length < 16) {
      throw Exception('Invalid encrypted payload: too short.');
    }
    final key = Key(keyBytes);
    final ivBytes = combinedBytes.sublist(0, 16);
    final cipherBytes = combinedBytes.sublist(16);

    final iv = IV(ivBytes);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final decrypted = encrypter.decrypt(Encrypted(cipherBytes), iv: iv);
    return decrypted;
  }
}
