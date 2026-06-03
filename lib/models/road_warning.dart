enum RoadWarningType {
  speedCamera,
  speedBump,
  trafficLight,
  stopSign,
  giveWay,
  surfaceChange,
  tunnel,
  bridge,
  roundabout,
  speedLimitChange,
}

class RoadWarning {
  const RoadWarning({
    required this.id,
    required this.type,
    required this.lat,
    required this.lon,
    required this.distanceFromStart,
    required this.text,
    this.tags = const {},
  });

  final String id;
  final RoadWarningType type;
  final double lat;
  final double lon;
  final double distanceFromStart;
  final String text;
  final Map<String, dynamic> tags;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'lat': lat,
      'lon': lon,
      'distanceFromStart': distanceFromStart,
      'text': text,
      'tags': tags,
    };
  }

  factory RoadWarning.fromJson(Map<dynamic, dynamic> json) {
    final typeName = json['type'] as String? ?? RoadWarningType.speedBump.name;
    return RoadWarning(
      id: json['id'] as String,
      type: RoadWarningType.values.firstWhere(
        (type) => type.name == typeName,
        orElse: () => RoadWarningType.speedBump,
      ),
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      distanceFromStart: (json['distanceFromStart'] as num).toDouble(),
      text: json['text'] as String,
      tags: Map<String, dynamic>.from(
        json['tags'] as Map<dynamic, dynamic>? ?? const {},
      ),
    );
  }
}
