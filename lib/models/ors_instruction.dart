/// Parsed turn-by-turn instruction step from the OpenRouteService directions API.
///
/// Each instruction maps to a maneuver along the route. The [type] integer
/// encodes the maneuver kind using the ORS encoding:
///   0 = Left, 1 = Right, 2 = Sharp left, 3 = Sharp right,
///   4 = Slight left, 5 = Slight right, 6 = Continue (straight),
///   7 = Enter roundabout, 8 = Exit roundabout, 9 = U-turn,
///   10 = Goal, 11 = Depart, 12 = Keep left, 13 = Keep right, 14 = Unknown
class OrsInstruction {
  const OrsInstruction({
    required this.type,
    required this.instruction,
    required this.name,
    required this.distance,
    required this.duration,
    required this.startWaypoint,
    required this.endWaypoint,
    required this.distanceFromStart,
  });

  /// ORS maneuver type integer (0-14).
  final int type;

  /// Human-readable instruction text from ORS (e.g. "Turn left onto Via Roma").
  final String instruction;

  /// Road/street name for this step.
  final String name;

  /// Distance covered by this step in meters.
  final double distance;

  /// Duration of this step in seconds.
  final double duration;

  /// Index into the route geometry array where this step begins.
  final int startWaypoint;

  /// Index into the route geometry array where this step ends.
  final int endWaypoint;

  /// Cumulative distance from route start to the beginning of this step.
  final double distanceFromStart;

  /// Whether this instruction represents a turn maneuver (left, right, sharp, slight).
  bool get isTurn => type >= 0 && type <= 5;

  /// Whether this instruction is a roundabout entry or exit.
  bool get isRoundabout => type == 7 || type == 8;

  /// Whether this instruction is a roundabout entry specifically.
  bool get isRoundaboutEntry => type == 7;

  /// Whether this instruction is a U-turn.
  bool get isUturn => type == 9;

  /// Whether this instruction is a continuation (straight).
  bool get isContinue => type == 6;

  /// Whether this instruction is a keep-left or keep-right.
  bool get isKeep => type == 12 || type == 13;

  /// Whether this is a depart or arrival instruction (not a real maneuver).
  bool get isTerminal => type == 10 || type == 11;

  /// Whether the turn direction is leftward (left, sharp left, slight left, keep left).
  bool get isLeftward => type == 0 || type == 2 || type == 4 || type == 12;

  /// Whether the turn direction is rightward (right, sharp right, slight right, keep right).
  bool get isRightward => type == 1 || type == 3 || type == 5 || type == 13;

  Map<String, dynamic> toJson() => {
        'type': type,
        'instruction': instruction,
        'name': name,
        'distance': distance,
        'duration': duration,
        'startWaypoint': startWaypoint,
        'endWaypoint': endWaypoint,
        'distanceFromStart': distanceFromStart,
      };

  factory OrsInstruction.fromJson(Map<String, dynamic> json) {
    return OrsInstruction(
      type: (json['type'] as num).toInt(),
      instruction: json['instruction'] as String? ?? '',
      name: json['name'] as String? ?? '',
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      startWaypoint: (json['startWaypoint'] as num).toInt(),
      endWaypoint: (json['endWaypoint'] as num).toInt(),
      distanceFromStart: (json['distanceFromStart'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  String toString() =>
      'OrsInstruction(type=$type, name=$name, dist=${distance.toStringAsFixed(0)}m, wp=$startWaypoint→$endWaypoint)';
}
