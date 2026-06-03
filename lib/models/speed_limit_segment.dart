class SpeedLimitSegment {
  const SpeedLimitSegment({
    required this.id,
    required this.startDistance,
    required this.endDistance,
    required this.rawMaxspeed,
    required this.parsedKmh,
    this.tags = const {},
  });

  final String id;
  final double startDistance;
  final double endDistance;
  final String rawMaxspeed;
  final int? parsedKmh;
  final Map<String, dynamic> tags;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startDistance': startDistance,
      'endDistance': endDistance,
      'rawMaxspeed': rawMaxspeed,
      'parsedKmh': parsedKmh,
      'tags': tags,
    };
  }

  factory SpeedLimitSegment.fromJson(Map<dynamic, dynamic> json) {
    return SpeedLimitSegment(
      id: json['id'] as String,
      startDistance: (json['startDistance'] as num).toDouble(),
      endDistance: (json['endDistance'] as num).toDouble(),
      rawMaxspeed: json['rawMaxspeed'] as String,
      parsedKmh: (json['parsedKmh'] as num?)?.toInt(),
      tags: Map<String, dynamic>.from(
        json['tags'] as Map<dynamic, dynamic>? ?? const {},
      ),
    );
  }
}
