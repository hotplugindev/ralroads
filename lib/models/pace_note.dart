class PaceNote {
  const PaceNote({
    required this.id,
    required this.distanceFromStart,
    required this.direction,
    required this.severity,
    required this.text,
    this.tightens = false,
    this.opens = false,
    this.spoken = false,
  });

  final String id;
  final double distanceFromStart;
  final String direction;
  final int severity;
  final bool tightens;
  final bool opens;
  final String text;
  final bool spoken;

  PaceNote copyWith({
    String? id,
    double? distanceFromStart,
    String? direction,
    int? severity,
    bool? tightens,
    bool? opens,
    String? text,
    bool? spoken,
  }) {
    return PaceNote(
      id: id ?? this.id,
      distanceFromStart: distanceFromStart ?? this.distanceFromStart,
      direction: direction ?? this.direction,
      severity: severity ?? this.severity,
      tightens: tightens ?? this.tightens,
      opens: opens ?? this.opens,
      text: text ?? this.text,
      spoken: spoken ?? this.spoken,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'distanceFromStart': distanceFromStart,
      'direction': direction,
      'severity': severity,
      'tightens': tightens,
      'opens': opens,
      'text': text,
      'spoken': spoken,
    };
  }

  factory PaceNote.fromJson(Map<dynamic, dynamic> json) {
    return PaceNote(
      id: json['id'] as String,
      distanceFromStart: (json['distanceFromStart'] as num).toDouble(),
      direction: json['direction'] as String,
      severity: (json['severity'] as num).toInt(),
      tightens: json['tightens'] as bool? ?? false,
      opens: json['opens'] as bool? ?? false,
      text: json['text'] as String,
      spoken: json['spoken'] as bool? ?? false,
    );
  }
}
