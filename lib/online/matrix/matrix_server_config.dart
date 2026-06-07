import 'dart:core';
import 'package:dio/dio.dart';

class MatrixServerConfig {
  final Uri baseUri;
  final String canonicalBaseUrl;
  final String serverName;

  const MatrixServerConfig({
    required this.baseUri,
    required this.canonicalBaseUrl,
    required this.serverName,
  });

  @override
  String toString() => 'MatrixServerConfig(baseUri: $baseUri, canonicalBaseUrl: $canonicalBaseUrl, serverName: $serverName)';
}

MatrixServerConfig parseMatrixServer({
  required String input,
  String? matrixUserId,
}) {
  final cleaned = input.trim();
  if (cleaned.isEmpty) {
    throw const FormatException('Empty homeserver');
  }

  // Derive server name from input if it is a Matrix ID
  String? derivedServer;
  if (cleaned.startsWith('@')) {
    final parts = cleaned.split(':');
    if (parts.length >= 2) {
      derivedServer = parts.sublist(1).join(':');
    }
  }

  // Otherwise, fallback to matrixUserId if provided
  if (derivedServer == null && matrixUserId != null) {
    final cleanUserId = matrixUserId.trim();
    if (cleanUserId.startsWith('@')) {
      final parts = cleanUserId.split(':');
      if (parts.length >= 2) {
        derivedServer = parts.sublist(1).join(':');
      }
    }
  }

  String serverInput = (derivedServer ?? cleaned).trim();
  if (serverInput.isEmpty) {
    throw const FormatException('Invalid server name');
  }

  // Add https:// if no scheme is specified
  String withScheme = serverInput;
  if (!withScheme.contains('://')) {
    withScheme = 'https://$withScheme';
  }

  final parsedUri = Uri.parse(withScheme);
  final host = parsedUri.host.trim();
  if (host.isEmpty) {
    throw const FormatException('Invalid URL');
  }

  final scheme = parsedUri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw const FormatException('Unsupported scheme');
  }

  // Preserve localhost HTTP for development, reject HTTP for other hosts
  final isLocalhost = host == 'localhost' || host == '127.0.0.1' || host.startsWith('192.168.') || host.startsWith('10.');
  if (scheme == 'http' && !isLocalhost) {
    throw const FormatException('TLS/certificate error: secure connection required');
  }

  // Remove unnecessary trailing slash on path but keep intentional reverse proxy prefixes
  var path = parsedUri.path;
  if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  final cleanedUri = parsedUri.replace(path: path);
  final canonicalUrl = cleanedUri.toString();

  // Determine logical server name
  final serverName = host;

  return MatrixServerConfig(
    baseUri: cleanedUri,
    canonicalBaseUrl: canonicalUrl,
    serverName: serverName,
  );
}

Future<MatrixServerConfig> discoverHomeserver({
  required String input,
  String? matrixUserId,
  Dio? dio,
}) async {
  final initialConfig = parseMatrixServer(input: input, matrixUserId: matrixUserId);
  final client = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));

  final host = initialConfig.serverName;
  MatrixServerConfig resolvedConfig = initialConfig;

  if (host.isNotEmpty && !host.contains('localhost') && !host.contains('127.0.0.1')) {
    try {
      final wellKnownUrl = 'https://$host/.well-known/matrix/client';
      final response = await client.get<Map<String, dynamic>>(wellKnownUrl);
      if (response.statusCode == 200 && response.data != null) {
        final homeserver = response.data!['m.homeserver'];
        if (homeserver is Map<String, dynamic>) {
          final baseUrl = homeserver['base_url'] as String?;
          if (baseUrl != null && baseUrl.isNotEmpty) {
            resolvedConfig = parseMatrixServer(input: baseUrl, matrixUserId: matrixUserId);
          }
        }
      }
    } catch (_) {
      // Well-known lookup failed, continue with direct config
    }
  }

  // Verify the homeserver
  try {
    final verifyUrl = '${resolvedConfig.canonicalBaseUrl}/_matrix/client/versions';
    final response = await client.get<Map<String, dynamic>>(verifyUrl);
    if (response.statusCode != 200 || response.data == null) {
      throw const FormatException('Matrix endpoint unavailable');
    }
    final versions = response.data!['versions'];
    if (versions is! List) {
      throw const FormatException('Login unsupported');
    }
  } on DioException catch (e) {
    if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
      throw const FormatException('Timeout');
    }
    final errorMsg = e.message?.toLowerCase() ?? '';
    if (errorMsg.contains('cert') || errorMsg.contains('handshake')) {
      throw const FormatException('TLS/certificate error');
    }
    throw const FormatException('Server unavailable');
  } catch (e) {
    if (e is FormatException) rethrow;
    throw const FormatException('Server unavailable');
  }

  return resolvedConfig;
}
