import 'package:dio/dio.dart';
import '../models/geocoding_result.dart';

class GeocodingService {
  GeocodingService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _photonEndpoint = 'https://photon.komoot.io/api/';

  /// Searches for places matching the query, or parses coordinate input.
  Future<List<GeocodingResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    // 1. Try parsing coordinates
    final parsedCoords = _parseCoordinates(trimmed);
    if (parsedCoords != null) {
      return [parsedCoords];
    }

    // 2. Fetch from Photon Komoot API
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _photonEndpoint,
        queryParameters: {
          'q': trimmed,
          'limit': 8,
        },
      );

      final features = response.data?['features'] as List<dynamic>? ?? const [];
      final results = <GeocodingResult>[];

      for (final feature in features) {
        if (feature is! Map<String, dynamic>) continue;
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        final coordinates = geometry?['coordinates'] as List<dynamic>?;
        final properties = feature['properties'] as Map<String, dynamic>?;

        if (coordinates == null || coordinates.length < 2 || properties == null) {
          continue;
        }

        final lon = (coordinates[0] as num).toDouble();
        final lat = (coordinates[1] as num).toDouble();

        // Photon uses properties: name, city, state, country, street, housenumber
        results.add(GeocodingResult(
          name: properties['name']?.toString() ?? 'Unknown Place',
          city: properties['city']?.toString(),
          state: properties['state']?.toString(),
          country: properties['country']?.toString(),
          street: properties['street']?.toString(),
          houseNumber: properties['housenumber']?.toString(),
          lat: lat,
          lon: lon,
        ));
      }

      return results;
    } catch (e) {
      // Return empty list on failure, or could rethrow
      return const [];
    }
  }

  GeocodingResult? _parseCoordinates(String text) {
    // Matches "lat, lon" or "lat lon"
    // e.g. 45.123, 7.456 or -12.34 -45.67
    final regExp = RegExp(
      r'^\s*([+-]?\d+(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d+(?:\.\d+)?)\s*$',
    );
    final match = regExp.firstMatch(text);
    if (match == null) {
      return null;
    }

    final lat = double.tryParse(match.group(1) ?? '');
    final lon = double.tryParse(match.group(2) ?? '');

    if (lat != null && lon != null) {
      if (lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0) {
        return GeocodingResult(
          name: 'Coordinates: ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
          lat: lat,
          lon: lon,
        );
      }
    }
    return null;
  }
}
