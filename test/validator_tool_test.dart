import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/services/secure_credential_service.dart';
import 'package:ralroads/services/device_identity_service.dart';

void main() {
  group('Validator CLI Tool', () {
    late Directory tempDir;
    late File segmentFile;
    late File traceFile;
    late DeviceIdentityService identityService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ralroads_validator_test');
      segmentFile = File('${tempDir.path}/segment.json');
      traceFile = File('${tempDir.path}/trace.json');
      identityService = DeviceIdentityService(
        secureCredentials: SecureCredentialService(
          store: MemorySecureCredentialStore(),
        ),
      );
      await identityService.initializeIdentity();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('validates and signs segment attempt via CLI process', () async {
      // 1. Create a dummy segment file
      final segmentPayload = {
        'geometry': [
          {'lat': 45.0, 'lon': 10.0, 'distanceFromStart': 0.0},
          {'lat': 45.01, 'lon': 10.01, 'distanceFromStart': 100.0},
        ]
      };
      await segmentFile.writeAsString(jsonEncode(segmentPayload));

      // 2. Create a dummy trace file
      final tracePayload = {
        'id': 'att-cli-test',
        'points': [
          {
            'recordedAt': '2026-06-07T12:00:00.000Z',
            'lat': 45.0,
            'lon': 10.0,
            'accuracyMeters': 5.0,
          },
          {
            'recordedAt': '2026-06-07T12:01:00.000Z',
            'lat': 45.01,
            'lon': 10.01,
            'accuracyMeters': 5.0,
          }
        ]
      };
      await traceFile.writeAsString(jsonEncode(tracePayload));

      // 3. Obtain private key to pass to the CLI tool
      final hexKey = await identityService.secureCredentials.readString(
        SecureCredentialKey.ralroadsSigningPrivateKey,
      );
      expect(hexKey, isNotNull);

      // 4. Run CLI tool via dart
      final processResult = await Process.run('dart', [
        'tools/ralroads_validator/bin/main.dart',
        '--segment',
        segmentFile.path,
        '--trace',
        traceFile.path,
        '--private-key',
        hexKey!,
        '--validator-id',
        'val-cli-1',
      ], workingDirectory: '/home/hotplugin/GIT/ralroads');

      expect(processResult.exitCode, 0, reason: 'Stderr: ${processResult.stderr}');

      final stdoutStr = processResult.stdout.toString().trim();
      final jsonStart = stdoutStr.indexOf('{');
      final jsonEnd = stdoutStr.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) {
        fail('No JSON object found in stdout: $stdoutStr');
      }
      final jsonStr = stdoutStr.substring(jsonStart, jsonEnd + 1);
      final outputMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(outputMap['attemptId'], 'att-cli-test');
      expect(outputMap['status'], 'validClean');
      expect(outputMap['validatorId'], 'val-cli-1');
      expect(outputMap['signature'], isNotNull);
      expect(outputMap['validatorPublicKey'], isNotNull);

      // 5. Verify the signature using our DeviceIdentityService
      final canonicalMessage = 'att-cli-test|${outputMap['resultHash']}|validClean|${outputMap['durationMs']}|0.1.0|val-cli-1|${outputMap['validatorPublicKey']}';
      final isSignatureValid = await identityService.verifySignature(
        message: canonicalMessage,
        signatureHex: outputMap['signature'] as String,
        publicKeyHex: outputMap['validatorPublicKey'] as String,
      );
      expect(isSignatureValid, isTrue);
    });
  });
}
