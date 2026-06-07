import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/online/matrix/matrix_server_config.dart';

class MockInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    if (path.contains('custom-derived.org/.well-known/matrix/client') || path.contains('custom-derived.org/well-known')) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'm.homeserver': {'base_url': 'https://custom-derived.org'}
        },
      ));
    } else if (path.contains('custom-derived.org/_matrix/client/versions')) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'versions': ['v1.1']
        },
      ));
    } else if (path.contains('matrix.org/_matrix/client/versions')) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'versions': ['r0.6.0']
        },
      ));
    } else if (path.contains('.well-known/matrix/client')) {
      handler.reject(DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
        type: DioExceptionType.badResponse,
      ));
    } else {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Connection refused',
      ));
    }
  }
}

void main() {
  group('MatrixServerConfig Parser Tests', () {
    test('Empty input throws exception', () {
      expect(() => parseMatrixServer(input: ''), throwsA(isA<FormatException>()));
      expect(() => parseMatrixServer(input: '   '), throwsA(isA<FormatException>()));
    });

    test('Bare domain is converted to https', () {
      final config = parseMatrixServer(input: 'matrix.org');
      expect(config.canonicalBaseUrl, 'https://matrix.org');
      expect(config.serverName, 'matrix.org');
    });

    test('HTTPS URL is preserved', () {
      final config = parseMatrixServer(input: 'https://matrix.org');
      expect(config.canonicalBaseUrl, 'https://matrix.org');
      expect(config.serverName, 'matrix.org');
    });

    test('Trailing slash is removed', () {
      final config = parseMatrixServer(input: 'https://matrix.org/');
      expect(config.canonicalBaseUrl, 'https://matrix.org');
      expect(config.serverName, 'matrix.org');
    });

    test('Matrix ID inference', () {
      final config = parseMatrixServer(input: '@user:matrix.org');
      expect(config.canonicalBaseUrl, 'https://matrix.org');
      expect(config.serverName, 'matrix.org');
    });

    test('Inference from username and separate matrixUserId', () {
      final config = parseMatrixServer(input: 'matrix.org', matrixUserId: '@user:matrix.org');
      expect(config.canonicalBaseUrl, 'https://matrix.org');
      expect(config.serverName, 'matrix.org');
    });

    test('Localhost HTTP is preserved', () {
      final config = parseMatrixServer(input: 'http://localhost:8008');
      expect(config.canonicalBaseUrl, 'http://localhost:8008');
      expect(config.serverName, 'localhost');
    });

    test('Localhost IP HTTP is preserved', () {
      final config = parseMatrixServer(input: 'http://127.0.0.1:8008');
      expect(config.canonicalBaseUrl, 'http://127.0.0.1:8008');
      expect(config.serverName, '127.0.0.1');
    });

    test('Invalid scheme throws exception', () {
      expect(() => parseMatrixServer(input: 'ftp://matrix.org'), throwsA(isA<FormatException>()));
    });

    test('HTTP on non-localhost throws exception', () {
      expect(() => parseMatrixServer(input: 'http://matrix.org'), throwsA(isA<FormatException>()));
    });

    test('Reverse-proxy path is preserved but trailing slash is removed', () {
      final config = parseMatrixServer(input: 'https://matrix.org/matrix-proxy/');
      expect(config.canonicalBaseUrl, 'https://matrix.org/matrix-proxy');
      expect(config.serverName, 'matrix.org');
    });
  });

  group('MatrixServerConfig Discovery Tests', () {
    late Dio dio;

    setUp(() {
      dio = Dio()..interceptors.add(MockInterceptor());
    });

    test('successful discovery with direct matrix.org versions check', () async {
      final config = await discoverHomeserver(input: 'matrix.org', dio: dio);
      expect(config.canonicalBaseUrl, 'https://matrix.org');
      expect(config.serverName, 'matrix.org');
    });

    test('successful discovery with well-known redirect', () async {
      // In this test, host is derived as 'custom-derived.org'
      final config = await discoverHomeserver(input: '@alice:custom-derived.org', dio: dio);
      expect(config.canonicalBaseUrl, 'https://custom-derived.org');
      expect(config.serverName, 'custom-derived.org');
    });

    test('failed discovery due to connection refused throws', () async {
      expect(
        () => discoverHomeserver(input: 'unknown.org', dio: dio),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
