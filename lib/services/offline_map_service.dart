import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../models/saved_route.dart';

class OfflineMapService {
  static final OfflineMapService instance = OfflineMapService._();
  OfflineMapService._();

  /// Gets all downloaded offline regions on the device.
  Future<List<maplibre.OfflineRegion>> getRegions() async {
    try {
      return await maplibre.getListOfRegions();
    } catch (e) {
      debugPrint('Error listing offline regions: $e');
      return [];
    }
  }

  /// Deletes an offline region by its ID.
  Future<void> deleteRegion(int id) async {
    try {
      await maplibre.deleteOfflineRegion(id);
    } catch (e) {
      debugPrint('Error deleting offline region $id: $e');
    }
  }

  /// Downloads map tiles for a SavedRoute.
  /// Generates a bounding box around the route points with padding.
  Future<maplibre.OfflineRegion> downloadRouteRegion({
    required SavedRoute route,
    required String mapStyleUrl,
    required double minZoom,
    required double maxZoom,
    required void Function(maplibre.DownloadRegionStatus status) onProgress,
  }) async {
    if (route.points.isEmpty) {
      throw ArgumentError('Cannot download offline region for an empty route');
    }

    // 1. Calculate Latitude/Longitude bounding box
    double minLat = route.points.first.lat;
    double maxLat = route.points.first.lat;
    double minLon = route.points.first.lon;
    double maxLon = route.points.first.lon;

    for (final pt in route.points) {
      if (pt.lat < minLat) minLat = pt.lat;
      if (pt.lat > maxLat) maxLat = pt.lat;
      if (pt.lon < minLon) minLon = pt.lon;
      if (pt.lon > maxLon) maxLon = pt.lon;
    }

    // Add padding (approx 0.015 degrees is ~1.6km)
    const double padding = 0.015;
    final southwest = maplibre.LatLng(minLat - padding, minLon - padding);
    final northeast = maplibre.LatLng(maxLat + padding, maxLon + padding);
    final bounds = maplibre.LatLngBounds(
      southwest: southwest,
      northeast: northeast,
    );

    final definition = maplibre.OfflineRegionDefinition(
      bounds: bounds,
      mapStyleUrl: mapStyleUrl,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    final metadata = {
      'routeId': route.id,
      'name': route.name,
      'createdAt': DateTime.now().toIso8601String(),
    };

    return await maplibre.downloadOfflineRegion(
      definition,
      metadata: metadata,
      onEvent: onProgress,
    );
  }

  int estimateTileCountForRoute({
    required SavedRoute route,
    required int minZoom,
    required int maxZoom,
  }) {
    if (route.points.isEmpty) {
      return 0;
    }

    var minLat = route.points.first.lat;
    var maxLat = route.points.first.lat;
    var minLon = route.points.first.lon;
    var maxLon = route.points.first.lon;

    for (final pt in route.points) {
      if (pt.lat < minLat) minLat = pt.lat;
      if (pt.lat > maxLat) maxLat = pt.lat;
      if (pt.lon < minLon) minLon = pt.lon;
      if (pt.lon > maxLon) maxLon = pt.lon;
    }

    const padding = 0.015;
    minLat = (minLat - padding).clamp(-85.05112878, 85.05112878).toDouble();
    maxLat = (maxLat + padding).clamp(-85.05112878, 85.05112878).toDouble();
    minLon = (minLon - padding).clamp(-180.0, 180.0).toDouble();
    maxLon = (maxLon + padding).clamp(-180.0, 180.0).toDouble();

    var total = 0;
    for (var zoom = minZoom; zoom <= maxZoom; zoom++) {
      final west = _lonToTileX(minLon, zoom);
      final east = _lonToTileX(maxLon, zoom);
      final north = _latToTileY(maxLat, zoom);
      final south = _latToTileY(minLat, zoom);
      total += (east - west + 1) * (south - north + 1);
    }
    return total;
  }

  int _lonToTileX(double lon, int zoom) {
    final scale = 1 << zoom;
    return (((lon + 180.0) / 360.0) * scale).floor().clamp(0, scale - 1);
  }

  int _latToTileY(double lat, int zoom) {
    final scale = 1 << zoom;
    final latRad = lat * math.pi / 180.0;
    final y =
        (1 - math.log(math.tan(latRad) + (1 / math.cos(latRad))) / math.pi) /
        2 *
        scale;
    return y.floor().clamp(0, scale - 1);
  }
}
