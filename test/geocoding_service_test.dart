import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/services/geocoding_service.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  MockHttpClientAdapter({this.mockResponse, this.mockStatusCode = 200});

  final Map<String, dynamic>? mockResponse;
  final int mockStatusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final jsonStr = jsonEncode(mockResponse ?? <String, dynamic>{});
    return ResponseBody.fromString(
      jsonStr,
      mockStatusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('GeocodingService Coordinates Parsing', () {
    late GeocodingService service;

    setUp(() {
      service = GeocodingService();
    });

    test('should parse valid coordinates with comma', () async {
      final results = await service.search('45.123456, 7.654321');
      expect(results.length, 1);
      expect(results[0].name, contains('Coordinates: 45.123456, 7.654321'));
      expect(results[0].lat, 45.123456);
      expect(results[0].lon, 7.654321);
    });

    test('should parse valid coordinates with space only', () async {
      final results = await service.search('-12.345  56.789');
      expect(results.length, 1);
      expect(results[0].lat, -12.345);
      expect(results[0].lon, 56.789);
    });

    test('should return empty list on invalid coordinates', () async {
      // Since coordinates invalid, it goes to Photon, which will fail/return empty list because we don't mock it here or it returns empty.
      // Let's pass a mock adapter to ensure network error returns empty list.
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter(
        mockResponse: {'features': []},
      );
      final mockService = GeocodingService(dio: dio);

      final results = await mockService.search(
        '95.0, 190.0',
      ); // out of lat/lon ranges
      expect(results, isEmpty);
    });
  });

  group('GeocodingService Photon Search', () {
    test('should parse Photon GeoJSON response successfully', () async {
      final mockData = {
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [12.496365, 41.902783],
            },
            'properties': {
              'name': 'Colosseum',
              'city': 'Rome',
              'country': 'Italy',
              'street': 'Piazza del Colosseo',
              'housenumber': '1',
            },
          },
        ],
      };

      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter(mockResponse: mockData);
      final service = GeocodingService(dio: dio);

      final results = await service.search('Colosseum');
      expect(results.length, 1);
      expect(results[0].name, 'Colosseum');
      expect(results[0].lat, 41.902783);
      expect(results[0].lon, 12.496365);
      expect(results[0].subtitle, 'Piazza del Colosseo 1, Rome, Italy');
    });

    test('should handle network/API errors gracefully', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter(mockStatusCode: 500);
      final service = GeocodingService(dio: dio);

      final results = await service.search('Error query');
      expect(results, isEmpty);
    });
  });
}
