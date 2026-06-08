import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class MatrixEncryptionHelper {
  static Uint8List generateRandomKey() {
    return Uint8List.fromList(SecretKeyData.random(length: 32).bytes);
  }

  static Future<Uint8List> encryptPayload(
    String jsonStr,
    Uint8List keyBytes,
  ) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(keyBytes);
    final nonce = algorithm.newNonce();
    final secretBox = await algorithm.encrypt(
      utf8.encode(jsonStr),
      secretKey: secretKey,
      nonce: nonce,
    );

    final combined = Uint8List(
      nonce.length + secretBox.mac.bytes.length + secretBox.cipherText.length,
    );
    combined.setRange(0, nonce.length, nonce);
    combined.setRange(
      nonce.length,
      nonce.length + secretBox.mac.bytes.length,
      secretBox.mac.bytes,
    );
    combined.setRange(
      nonce.length + secretBox.mac.bytes.length,
      combined.length,
      secretBox.cipherText,
    );
    return combined;
  }

  static Future<String> decryptPayload(
    Uint8List combinedBytes,
    Uint8List keyBytes,
  ) async {
    const nonceLength = 12;
    const macLength = 16;
    if (combinedBytes.length < nonceLength + macLength) {
      throw Exception('Invalid encrypted payload: too short.');
    }
    final algorithm = AesGcm.with256bits();
    final nonce = combinedBytes.sublist(0, nonceLength);
    final mac = Mac(
      combinedBytes.sublist(nonceLength, nonceLength + macLength),
    );
    final cipherText = combinedBytes.sublist(nonceLength + macLength);
    final clearBytes = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: SecretKey(keyBytes),
    );
    return utf8.decode(clearBytes);
  }
}
