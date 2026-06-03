enum PaceNoteType { corner, hairpin, roundabout, junction, warning }

class PaceNote {
  const PaceNote({
    required this.id,
    required this.distanceFromStart,
    required this.direction,
    required this.severity,
    required this.text,
    this.type = PaceNoteType.corner,
    this.tightens = false,
    this.opens = false,
    this.spoken = false,
    this.recommendedSpeedKmh,
  });

  final String id;
  final double distanceFromStart;
  final String direction;
  final int severity;
  final PaceNoteType type;
  final bool tightens;
  final bool opens;
  final String text;
  final bool spoken;
  final int? recommendedSpeedKmh;

  PaceNote copyWith({
    String? id,
    double? distanceFromStart,
    String? direction,
    int? severity,
    PaceNoteType? type,
    bool? tightens,
    bool? opens,
    String? text,
    bool? spoken,
    int? recommendedSpeedKmh,
  }) {
    return PaceNote(
      id: id ?? this.id,
      distanceFromStart: distanceFromStart ?? this.distanceFromStart,
      direction: direction ?? this.direction,
      severity: severity ?? this.severity,
      type: type ?? this.type,
      tightens: tightens ?? this.tightens,
      opens: opens ?? this.opens,
      text: text ?? this.text,
      spoken: spoken ?? this.spoken,
      recommendedSpeedKmh: recommendedSpeedKmh ?? this.recommendedSpeedKmh,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'distanceFromStart': distanceFromStart,
      'direction': direction,
      'severity': severity,
      'type': type.name,
      'tightens': tightens,
      'opens': opens,
      'text': text,
      'spoken': spoken,
      'recommendedSpeedKmh': recommendedSpeedKmh,
    };
  }

  factory PaceNote.fromJson(Map<dynamic, dynamic> json) {
    final typeName = json['type'] as String? ?? PaceNoteType.corner.name;
    return PaceNote(
      id: json['id'] as String,
      distanceFromStart: (json['distanceFromStart'] as num).toDouble(),
      direction: json['direction'] as String,
      severity: (json['severity'] as num).toInt(),
      type: PaceNoteType.values.firstWhere(
        (type) => type.name == typeName,
        orElse: () => PaceNoteType.corner,
      ),
      tightens: json['tightens'] as bool? ?? false,
      opens: json['opens'] as bool? ?? false,
      text: json['text'] as String,
      spoken: json['spoken'] as bool? ?? false,
      recommendedSpeedKmh: json['recommendedSpeedKmh'] != null
          ? (json['recommendedSpeedKmh'] as num).toInt()
          : null,
    );
  }
}
