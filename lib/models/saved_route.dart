import 'pace_note.dart';
import 'road_warning.dart';
import 'route_point.dart';
import 'speed_limit_segment.dart';

class SavedRoute {
  const SavedRoute({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.totalDistance,
    required this.points,
    required this.pacenotes,
    this.roadWarnings = const [],
    this.speedLimitSegments = const [],
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final double totalDistance;
  final List<RoutePoint> points;
  final List<PaceNote> pacenotes;
  final List<RoadWarning> roadWarnings;
  final List<SpeedLimitSegment> speedLimitSegments;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'totalDistance': totalDistance,
      'points': points.map((point) => point.toJson()).toList(),
      'pacenotes': pacenotes.map((note) => note.toJson()).toList(),
      'roadWarnings': roadWarnings.map((warning) => warning.toJson()).toList(),
      'speedLimitSegments': speedLimitSegments
          .map((segment) => segment.toJson())
          .toList(),
    };
  }

  factory SavedRoute.fromJson(Map<dynamic, dynamic> json) {
    final pointsJson = json['points'] as List<dynamic>? ?? const [];
    final notesJson = json['pacenotes'] as List<dynamic>? ?? const [];
    final warningsJson = json['roadWarnings'] as List<dynamic>? ?? const [];
    final speedLimitsJson =
        json['speedLimitSegments'] as List<dynamic>? ?? const [];

    return SavedRoute(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      totalDistance: (json['totalDistance'] as num).toDouble(),
      points: pointsJson
          .map((point) => RoutePoint.fromJson(point as Map<dynamic, dynamic>))
          .toList(),
      pacenotes: notesJson
          .map((note) => PaceNote.fromJson(note as Map<dynamic, dynamic>))
          .toList(),
      roadWarnings: warningsJson
          .map(
            (warning) => RoadWarning.fromJson(warning as Map<dynamic, dynamic>),
          )
          .toList(),
      speedLimitSegments: speedLimitsJson
          .map(
            (segment) =>
                SpeedLimitSegment.fromJson(segment as Map<dynamic, dynamic>),
          )
          .toList(),
    );
  }
}
