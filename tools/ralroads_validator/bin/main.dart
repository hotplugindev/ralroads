// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:ralroads_validation/ralroads_validation.dart';

void main(List<String> args) async {
  String? segmentPath;
  String? tracePath;
  String? privateKeyHex;
  String? validatorId;
  String? attemptIdOverride;
  double? policyCorridor;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--segment' && i + 1 < args.length) {
      segmentPath = args[i + 1];
    } else if (args[i] == '--trace' && i + 1 < args.length) {
      tracePath = args[i + 1];
    } else if (args[i] == '--private-key' && i + 1 < args.length) {
      privateKeyHex = args[i + 1];
    } else if (args[i] == '--validator-id' && i + 1 < args.length) {
      validatorId = args[i + 1];
    } else if (args[i] == '--attempt-id' && i + 1 < args.length) {
      attemptIdOverride = args[i + 1];
    } else if (args[i] == '--policy-corridor' && i + 1 < args.length) {
      policyCorridor = double.tryParse(args[i + 1]);
    }
  }

  if (segmentPath == null || tracePath == null || privateKeyHex == null || validatorId == null) {
    print('Usage: dart bin/main.dart --segment <segment.json> --trace <trace.json> --private-key <hex_key> --validator-id <id> [--attempt-id <attempt_id>] [--policy-corridor <double>]');
    exit(1);
  }

  try {
    // 1. Read segment
    final segmentFile = File(segmentPath);
    if (!segmentFile.existsSync()) {
      print('Error: Segment file not found.');
      exit(1);
    }
    final segmentData = jsonDecode(segmentFile.readAsStringSync());
    final List<dynamic> geomList = segmentData is Map 
        ? (segmentData['geometry'] as List<dynamic>? ?? []) 
        : (segmentData as List<dynamic>);

    final segmentPoints = geomList.map((item) {
      final map = item as Map<String, dynamic>;
      return SegmentPoint(
        lat: (map['lat'] as num).toDouble(),
        lon: (map['lon'] as num).toDouble(),
        distanceFromStart: (map['distanceFromStart'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    // 2. Read trace
    final traceFile = File(tracePath);
    if (!traceFile.existsSync()) {
      print('Error: Trace file not found.');
      exit(1);
    }
    final traceData = jsonDecode(traceFile.readAsStringSync());
    List<dynamic> pointsList = [];
    String? parsedAttemptId;
    if (traceData is Map) {
      parsedAttemptId = (traceData['id'] ?? traceData['attemptId'])?.toString();
      pointsList = (traceData['points'] ?? traceData['trace'] ?? []) as List<dynamic>;
    } else if (traceData is List) {
      pointsList = traceData;
    }

    final attemptId = attemptIdOverride ?? parsedAttemptId ?? 'unknown-attempt';

    final tracePoints = pointsList.map((item) {
      final map = item as Map<String, dynamic>;
      final timestampStr = map['recordedAt'] ?? map['timestamp'];
      return ValidationPoint(
        timestamp: DateTime.parse(timestampStr.toString()),
        lat: (map['lat'] as num).toDouble(),
        lon: (map['lon'] as num).toDouble(),
        speedMps: (map['speedMps'] as num?)?.toDouble(),
        accuracyMeters: (map['accuracyMeters'] as num?)?.toDouble(),
        speedLimitKmh: (map['speedLimitKmh'] as num?)?.toInt(),
      );
    }).toList();

    // 3. Run Validation
    final policy = policyCorridor != null 
        ? ValidationPolicy(corridorMeters: policyCorridor) 
        : const ValidationPolicy();

    final validator = const AttemptValidator();
    final result = validator.validate(
      segment: segmentPoints,
      trace: tracePoints,
      policy: policy,
    );

    // 4. Cryptographic attestation
    final algorithm = Ed25519();
    
    // Hex helper
    List<int> fromHex(String hex) {
      final bytes = <int>[];
      for (var i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return bytes;
    }
    String toHex(List<int> bytes) {
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }

    final privateKeyBytes = fromHex(privateKeyHex);
    final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyHex = toHex(publicKey.bytes);

    // Canonical message payload: attemptId|resultHash|status|durationMs|engineVersion|validatorId|validatorPublicKey
    final durationMs = result.duration?.inMilliseconds ?? 0;
    const engineVersion = '0.1.0';
    final canonicalMessage = '$attemptId|${result.resultHash}|${result.status.name}|$durationMs|$engineVersion|$validatorId|$publicKeyHex';
    
    final signature = await algorithm.sign(utf8.encode(canonicalMessage), keyPair: keyPair);
    final signatureHex = toHex(signature.bytes);

    // 5. Output result
    final attestation = {
      'attemptId': attemptId,
      'resultHash': result.resultHash,
      'status': result.status.name,
      'durationMs': durationMs,
      'engineVersion': engineVersion,
      'validatorId': validatorId,
      'validatorPublicKey': publicKeyHex,
      'signature': signatureHex,
    };

    print(jsonEncode(attestation));
    exit(0);
  } catch (e) {
    print('Error executing validator tool: $e');
    exit(1);
  }
}
