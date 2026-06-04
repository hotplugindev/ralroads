import 'dart:async';
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
    final bounds = maplibre.LatLngBounds(southwest: southwest, northeast: northeast);

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
}
