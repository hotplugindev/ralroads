class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lon,
    this.distanceFromStart = 0,
    this.heading = 0,
  });

  final double lat;
  final double lon;
  final double distanceFromStart;
  final double heading;

  RoutePoint copyWith({
    double? lat,
    double? lon,
    double? distanceFromStart,
    double? heading,
  }) {
    return RoutePoint(
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      distanceFromStart: distanceFromStart ?? this.distanceFromStart,
      heading: heading ?? this.heading,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lon': lon,
      'distanceFromStart': distanceFromStart,
      'heading': heading,
    };
  }

  factory RoutePoint.fromJson(Map<dynamic, dynamic> json) {
    return RoutePoint(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      distanceFromStart: (json['distanceFromStart'] as num?)?.toDouble() ?? 0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0,
    );
  }
}
