class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lon,
    this.distanceFromStart = 0,
    this.heading = 0,
    this.elevation,
  });

  final double lat;
  final double lon;
  final double distanceFromStart;
  final double heading;
  final double? elevation;

  RoutePoint copyWith({
    double? lat,
    double? lon,
    double? distanceFromStart,
    double? heading,
    double? elevation,
  }) {
    return RoutePoint(
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      distanceFromStart: distanceFromStart ?? this.distanceFromStart,
      heading: heading ?? this.heading,
      elevation: elevation ?? this.elevation,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lon': lon,
      'distanceFromStart': distanceFromStart,
      'heading': heading,
      if (elevation != null) 'elevation': elevation,
    };
  }

  factory RoutePoint.fromJson(Map<dynamic, dynamic> json) {
    return RoutePoint(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      distanceFromStart: (json['distanceFromStart'] as num?)?.toDouble() ?? 0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0,
      elevation: (json['elevation'] as num?)?.toDouble(),
    );
  }
}
