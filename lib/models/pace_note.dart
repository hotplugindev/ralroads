enum PaceNoteType {
  left,
  right,
  hairpinLeft,
  hairpinRight,
  straight,
  roundabout,
  keepLeft,
  keepRight,
  junction,
  warning,
  corner,
  hairpin,
}

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
    this.isShort = false,
    this.isLong = false,
    this.distanceMeters,
    this.intoNoteId,
    this.startDistance,
    this.endDistance,
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
  final bool isShort;
  final bool isLong;
  final int? distanceMeters;
  final String? intoNoteId;
  final double? startDistance;
  final double? endDistance;

  String get rallyText {
    if (type == PaceNoteType.roundabout) {
      return text.trim().isNotEmpty ? text : 'Roundabout ahead';
    }
    if (type == PaceNoteType.junction) {
      final dirStr = direction.toLowerCase().startsWith('l') ? 'left' : 'right';
      return 'At junction, $dirStr';
    }
    if (type == PaceNoteType.warning) {
      return text;
    }

    if (type == PaceNoteType.straight) {
      return 'straight ${distanceMeters ?? 0}';
    }

    final String typeStr;
    if (type == PaceNoteType.hairpinLeft) {
      typeStr = 'hairpin left';
    } else if (type == PaceNoteType.hairpinRight) {
      typeStr = 'hairpin right';
    } else if (type == PaceNoteType.keepLeft) {
      typeStr = 'keep left';
    } else if (type == PaceNoteType.keepRight) {
      typeStr = 'keep right';
    } else if (type == PaceNoteType.hairpin) {
      typeStr = 'hairpin $direction';
    } else if (type == PaceNoteType.left) {
      typeStr = 'left $severity';
    } else if (type == PaceNoteType.right) {
      typeStr = 'right $severity';
    } else {
      typeStr = '$direction $severity';
    }

    final parts = <String>[typeStr];
    if (isShort) parts.add('short');
    if (isLong) parts.add('long');
    if (opens) parts.add('opens');
    if (tightens) parts.add('tightens');

    return parts.join(' ');
  }

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
    bool? isShort,
    bool? isLong,
    int? distanceMeters,
    String? intoNoteId,
    double? startDistance,
    double? endDistance,
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
      isShort: isShort ?? this.isShort,
      isLong: isLong ?? this.isLong,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      intoNoteId: intoNoteId ?? this.intoNoteId,
      startDistance: startDistance ?? this.startDistance,
      endDistance: endDistance ?? this.endDistance,
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
      'isShort': isShort,
      'isLong': isLong,
      'distanceMeters': distanceMeters,
      'intoNoteId': intoNoteId,
      'startDistance': startDistance,
      'endDistance': endDistance,
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
      text: json['text'] as String? ?? '',
      spoken: json['spoken'] as bool? ?? false,
      recommendedSpeedKmh: json['recommendedSpeedKmh'] != null
          ? (json['recommendedSpeedKmh'] as num).toInt()
          : null,
      isShort: json['isShort'] as bool? ?? false,
      isLong: json['isLong'] as bool? ?? false,
      distanceMeters: json['distanceMeters'] != null
          ? (json['distanceMeters'] as num).toInt()
          : null,
      intoNoteId: json['intoNoteId'] as String?,
      startDistance: json['startDistance'] != null
          ? (json['startDistance'] as num).toDouble()
          : null,
      endDistance: json['endDistance'] != null
          ? (json['endDistance'] as num).toDouble()
          : null,
    );
  }
}
