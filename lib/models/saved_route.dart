import 'pace_note.dart';
import 'route_point.dart';

class SavedRoute {
  const SavedRoute({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.totalDistance,
    required this.points,
    required this.pacenotes,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final double totalDistance;
  final List<RoutePoint> points;
  final List<PaceNote> pacenotes;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'totalDistance': totalDistance,
      'points': points.map((point) => point.toJson()).toList(),
      'pacenotes': pacenotes.map((note) => note.toJson()).toList(),
    };
  }

  factory SavedRoute.fromJson(Map<dynamic, dynamic> json) {
    final pointsJson = json['points'] as List<dynamic>? ?? const [];
    final notesJson = json['pacenotes'] as List<dynamic>? ?? const [];

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
    );
  }
}
