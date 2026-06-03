import 'package:dio/dio.dart';

import '../models/route_point.dart';
import 'pacenote_generator.dart';
import 'settings_service.dart';

class OrsService {
  OrsService({required SettingsService settings, Dio? dio})
    : _settings = settings,
      _dio = dio ?? Dio();

  static const _endpoint =
      'https://api.openrouteservice.org/v2/directions/driving-car/geojson';

  final SettingsService _settings;
  final Dio _dio;
  final PacenoteGenerator _pacenoteGenerator = PacenoteGenerator();

  bool get hasApiKey => _settings.hasEffectiveOrsApiKey();

  Future<List<RoutePoint>> buildRoute(List<RoutePoint> points) async {
    if (points.length < 2) {
      throw const OrsRequestException('Add at least a start and destination.');
    }

    final apiKey = _settings.getEffectiveOrsApiKey();
    if (apiKey == null) {
      throw const MissingOrsApiKeyException();
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        data: {
          'coordinates': points.map((point) => [point.lon, point.lat]).toList(),
          'instructions': false,
          'geometry': true,
          'elevation': false,
        },
        options: Options(
          headers: {
            'Authorization': apiKey,
            'Content-Type': 'application/json',
          },
        ),
      );

      final features = response.data?['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) {
        throw const OrsRequestException('OpenRouteService returned no route.');
      }

      final geometry =
          (features.first as Map<String, dynamic>)['geometry']
              as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List<dynamic>?;
      if (coordinates == null || coordinates.isEmpty) {
        throw const OrsRequestException(
          'OpenRouteService returned an empty route geometry.',
        );
      }

      final routePoints = coordinates.map((coordinate) {
        final pair = coordinate as List<dynamic>;
        return RoutePoint(
          lon: (pair[0] as num).toDouble(),
          lat: (pair[1] as num).toDouble(),
        );
      }).toList();

      return _pacenoteGenerator.enrichRoutePoints(routePoints);
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<bool> validateApiKey(String key) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        _endpoint,
        data: const {
          'coordinates': [
            [11.6572, 46.7150],
            [11.6600, 46.7160],
          ],
          'instructions': false,
          'geometry': true,
          'elevation': false,
        },
        options: Options(
          headers: {
            'Authorization': key.trim(),
            'Content-Type': 'application/json',
          },
        ),
      );
      return true;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        return false;
      }
      if (error.response == null) {
        throw const OrsNetworkException('Network error while testing key.');
      }
      throw _mapDioException(error);
    }
  }

  OrsException _mapDioException(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return const InvalidOrsApiKeyException();
    }
    if (status == 429) {
      return const OrsRateLimitException();
    }
    if (error.response == null) {
      return const OrsNetworkException('Network error while building route.');
    }

    final details = error.response?.data?.toString() ?? error.message;
    return OrsRequestException(
      'Route request failed${status == null ? '' : ' ($status)'}: $details',
    );
  }
}

class OrsException implements Exception {
  const OrsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MissingOrsApiKeyException extends OrsException {
  const MissingOrsApiKeyException()
    : super('Online route planning requires an OpenRouteService API key.');
}

class InvalidOrsApiKeyException extends OrsException {
  const InvalidOrsApiKeyException()
    : super(
        'OpenRouteService rejected your API key. Please check it in Settings.',
      );
}

class OrsRateLimitException extends OrsException {
  const OrsRateLimitException()
    : super(
        'OpenRouteService rate limit reached. Try again later or use another key.',
      );
}

class OrsNetworkException extends OrsException {
  const OrsNetworkException(super.message);
}

class OrsRequestException extends OrsException {
  const OrsRequestException(super.message);
}
