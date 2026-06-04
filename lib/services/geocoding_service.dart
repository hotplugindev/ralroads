import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../models/geocoding_result.dart';
import 'settings_service.dart';

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lon,
    required this.distanceMeters,
    required this.source,
    required this.raw,
  });

  final String id;
  final String title;
  final String subtitle;
  final double lat;
  final double lon;
  final double? distanceMeters;
  final String source;
  final Map<String, dynamic> raw;
}

class GeocodingService {
  GeocodingService({SettingsService? settings, Dio? dio})
    : _settings = settings,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );

  final SettingsService? _settings;
  final Dio _dio;

  static const _orsEndpoint = 'https://api.openrouteservice.org/geocode/search';
  static const _photonEndpoint = 'https://photon.komoot.io/api/';

  Future<List<GeocodingResult>> search(String query) async {
    try {
      final places = await searchPlaces(query: query);
      return places.map(_toLegacyResult).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<PlaceSearchResult>> searchPlaces({
    required String query,
    double? nearLat,
    double? nearLon,
    int limit = 8,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final parsedCoords = _parseCoordinates(
      trimmed,
      nearLat: nearLat,
      nearLon: nearLon,
    );
    if (parsedCoords != null) {
      return [parsedCoords];
    }

    final boundedLimit = limit.clamp(1, 12);
    final apiKey = _settings?.getEffectiveOrsApiKey();

    if (apiKey != null) {
      try {
        return await _searchOpenRouteService(
          apiKey: apiKey,
          query: trimmed,
          nearLat: nearLat,
          nearLon: nearLon,
          limit: boundedLimit,
        );
      } on DioException {
        // Fall through to Photon so a temporary ORS issue does not disable
        // search entirely.
      }
    }

    try {
      return await _searchPhoton(
        query: trimmed,
        nearLat: nearLat,
        nearLon: nearLon,
        limit: boundedLimit,
      );
    } on DioException catch (error) {
      if (error.response == null) {
        throw const GeocodingException('Place search requires internet.');
      }
      throw const GeocodingException('Place search unavailable.');
    }
  }

  Future<List<PlaceSearchResult>> _searchOpenRouteService({
    required String apiKey,
    required String query,
    required double? nearLat,
    required double? nearLon,
    required int limit,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _orsEndpoint,
      queryParameters: {
        'text': query,
        'size': limit,
        if (nearLat != null && nearLon != null) ...{
          'focus.point.lat': nearLat,
          'focus.point.lon': nearLon,
        },
      },
      options: Options(headers: {'Authorization': apiKey}),
    );

    final features = response.data?['features'] as List<dynamic>? ?? const [];
    final results = <PlaceSearchResult>[];

    for (var i = 0; i < features.length; i++) {
      final feature = _stringMap(features[i]);
      if (feature == null) continue;

      final geometry = _stringMap(feature['geometry']);
      final properties = _stringMap(feature['properties']) ?? const {};
      final coordinates = geometry?['coordinates'] as List<dynamic>?;
      if (coordinates == null || coordinates.length < 2) continue;

      final lon = _toDouble(coordinates[0]);
      final lat = _toDouble(coordinates[1]);
      if (lat == null || lon == null) continue;

      final distance = _distanceFrom(nearLat, nearLon, lat, lon);
      final title = _orsTitle(properties);
      final subtitle = _orsSubtitle(properties, lat, lon);
      results.add(
        PlaceSearchResult(
          id:
              properties['id']?.toString() ??
              properties['gid']?.toString() ??
              'ors-$i-$lat-$lon',
          title: title,
          subtitle: subtitle,
          lat: lat,
          lon: lon,
          distanceMeters: distance,
          source: 'openrouteservice',
          raw: feature,
        ),
      );
    }

    return _rankResults(results, query, nearLat, nearLon);
  }

  Future<List<PlaceSearchResult>> _searchPhoton({
    required String query,
    required double? nearLat,
    required double? nearLon,
    required int limit,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _photonEndpoint,
      queryParameters: {
        'q': query,
        'limit': limit,
        if (nearLat != null && nearLon != null) ...{
          'lat': nearLat,
          'lon': nearLon,
        },
      },
    );

    final features = response.data?['features'] as List<dynamic>? ?? const [];
    final results = <PlaceSearchResult>[];

    for (var i = 0; i < features.length; i++) {
      final feature = _stringMap(features[i]);
      if (feature == null) continue;

      final geometry = _stringMap(feature['geometry']);
      final properties = _stringMap(feature['properties']) ?? const {};
      final coordinates = geometry?['coordinates'] as List<dynamic>?;
      if (coordinates == null || coordinates.length < 2) continue;

      final lon = _toDouble(coordinates[0]);
      final lat = _toDouble(coordinates[1]);
      if (lat == null || lon == null) continue;

      final distance = _distanceFrom(nearLat, nearLon, lat, lon);
      final title = _photonTitle(properties);
      final subtitle = _photonSubtitle(properties, lat, lon);
      results.add(
        PlaceSearchResult(
          id:
              properties['osm_id']?.toString() ??
              properties['id']?.toString() ??
              'photon-$i-$lat-$lon',
          title: title,
          subtitle: subtitle,
          lat: lat,
          lon: lon,
          distanceMeters: distance,
          source: 'photon',
          raw: feature,
        ),
      );
    }

    return _rankResults(results, query, nearLat, nearLon);
  }

  PlaceSearchResult? _parseCoordinates(
    String text, {
    required double? nearLat,
    required double? nearLon,
  }) {
    final regExp = RegExp(
      r'^\s*([+-]?\d+(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d+(?:\.\d+)?)\s*$',
    );
    final match = regExp.firstMatch(text);
    if (match == null) {
      return null;
    }

    final lat = double.tryParse(match.group(1) ?? '');
    final lon = double.tryParse(match.group(2) ?? '');
    if (lat == null ||
        lon == null ||
        lat < -90.0 ||
        lat > 90.0 ||
        lon < -180.0 ||
        lon > 180.0) {
      return null;
    }

    return PlaceSearchResult(
      id: 'coordinates-$lat-$lon',
      title: 'Coordinates',
      subtitle: '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
      lat: lat,
      lon: lon,
      distanceMeters: _distanceFrom(nearLat, nearLon, lat, lon),
      source: 'coordinates',
      raw: {'query': text},
    );
  }

  List<PlaceSearchResult> _rankResults(
    List<PlaceSearchResult> results,
    String query,
    double? nearLat,
    double? nearLon,
  ) {
    if (nearLat == null || nearLon == null) {
      return results;
    }

    final scored = [
      for (var i = 0; i < results.length; i++)
        _ScoredPlace(
          result: results[i],
          index: i,
          textScore: _textScore(results[i], query),
        ),
    ];

    scored.sort((a, b) {
      final textDelta = b.textScore.compareTo(a.textScore);
      if (textDelta != 0 && (a.textScore - b.textScore).abs() >= 2) {
        return textDelta;
      }

      final aDistance = a.result.distanceMeters ?? double.infinity;
      final bDistance = b.result.distanceMeters ?? double.infinity;
      final distanceDelta = aDistance.compareTo(bDistance);
      if (distanceDelta != 0) {
        return distanceDelta;
      }

      if (textDelta != 0) {
        return textDelta;
      }
      return a.index.compareTo(b.index);
    });

    return [for (final item in scored) item.result];
  }

  int _textScore(PlaceSearchResult result, String query) {
    final normalizedQuery = query.toLowerCase();
    final normalizedTitle = result.title.toLowerCase();
    final normalizedSubtitle = result.subtitle.toLowerCase();

    if (normalizedTitle == normalizedQuery) return 6;
    if (normalizedTitle.startsWith(normalizedQuery)) return 5;
    if (normalizedTitle.contains(normalizedQuery)) return 4;

    var score = 0;
    for (final token in normalizedQuery.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      if (normalizedTitle.contains(token)) {
        score += 2;
      } else if (normalizedSubtitle.contains(token)) {
        score += 1;
      }
    }
    return score;
  }

  String _orsTitle(Map<String, dynamic> properties) {
    return _firstNonBlank([
          properties['name'],
          properties['label'],
          _joinParts([properties['street'], properties['housenumber']], ' '),
          properties['locality'],
          properties['region'],
          properties['country'],
        ]) ??
        'Unknown place';
  }

  String _orsSubtitle(Map<String, dynamic> properties, double lat, double lon) {
    final parts = <String>[
      if (_asString(properties['street']) != null)
        _joinParts([properties['street'], properties['housenumber']], ' ')!,
      if (_asString(properties['postalcode']) != null)
        _asString(properties['postalcode'])!,
      if (_asString(properties['locality']) != null)
        _asString(properties['locality'])!,
      if (_asString(properties['region']) != null)
        _asString(properties['region'])!,
      if (_asString(properties['country']) != null)
        _asString(properties['country'])!,
    ];

    if (parts.isNotEmpty) {
      return _dedupe(parts).join(', ');
    }
    return 'OpenRouteService - ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
  }

  String _photonTitle(Map<String, dynamic> properties) {
    return _firstNonBlank([
          properties['name'],
          _joinParts([properties['street'], properties['housenumber']], ' '),
          properties['city'],
          properties['state'],
          properties['country'],
        ]) ??
        'Unknown place';
  }

  String _photonSubtitle(
    Map<String, dynamic> properties,
    double lat,
    double lon,
  ) {
    final parts = <String>[
      if (_asString(properties['street']) != null)
        _joinParts([properties['street'], properties['housenumber']], ' ')!,
      if (_asString(properties['postcode']) != null)
        _asString(properties['postcode'])!,
      if (_asString(properties['city']) != null) _asString(properties['city'])!,
      if (_asString(properties['state']) != null)
        _asString(properties['state'])!,
      if (_asString(properties['country']) != null)
        _asString(properties['country'])!,
    ];

    if (parts.isNotEmpty) {
      return _dedupe(parts).join(', ');
    }
    return 'Photon - ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
  }

  double? _distanceFrom(
    double? fromLat,
    double? fromLon,
    double toLat,
    double toLon,
  ) {
    if (fromLat == null || fromLon == null) {
      return null;
    }
    return _haversineDistanceMeters(fromLat, fromLon, toLat, toLon);
  }

  double _haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final phi1 = _degreesToRadians(lat1);
    final phi2 = _degreesToRadians(lat2);
    final deltaPhi = _degreesToRadians(lat2 - lat1);
    final deltaLambda = _degreesToRadians(lon2 - lon1);

    final a =
        math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(deltaLambda / 2) *
            math.sin(deltaLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  double _degreesToRadians(double degrees) => degrees * math.pi / 180;

  String? _firstNonBlank(List<Object?> values) {
    for (final value in values) {
      final text = _asString(value);
      if (text != null) {
        return text;
      }
    }
    return null;
  }

  String? _joinParts(List<Object?> values, String separator) {
    final parts = [
      for (final value in values)
        if (_asString(value) != null) _asString(value)!,
    ];
    if (parts.isEmpty) return null;
    return parts.join(separator);
  }

  String? _asString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final deduped = <String>[];
    for (final value in values) {
      final key = value.toLowerCase();
      if (seen.add(key)) {
        deduped.add(value);
      }
    }
    return deduped;
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  GeocodingResult _toLegacyResult(PlaceSearchResult result) {
    final properties = _stringMap(result.raw['properties']) ?? const {};
    return GeocodingResult(
      name: result.source == 'coordinates'
          ? 'Coordinates: ${result.subtitle}'
          : result.title,
      city: _asString(properties['city'] ?? properties['locality']),
      state: _asString(properties['state'] ?? properties['region']),
      country: _asString(properties['country']),
      street: _asString(properties['street']),
      houseNumber: _asString(properties['housenumber']),
      lat: result.lat,
      lon: result.lon,
    );
  }

  Map<String, dynamic>? _stringMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}

class GeocodingException implements Exception {
  const GeocodingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ScoredPlace {
  const _ScoredPlace({
    required this.result,
    required this.index,
    required this.textScore,
  });

  final PlaceSearchResult result;
  final int index;
  final int textScore;
}
