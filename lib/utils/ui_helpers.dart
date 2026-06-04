import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/route_point.dart';
import '../models/speed_limit_segment.dart';
import '../services/settings_service.dart';
import 'geo_math.dart';

RoutePoint? findNearestPoint(List<RoutePoint> points, double distanceMeters) {
  if (points.isEmpty) {
    return null;
  }

  var nearest = points.first;
  var nearestDelta = (nearest.distanceFromStart - distanceMeters).abs();
  for (final point in points.skip(1)) {
    final delta = (point.distanceFromStart - distanceMeters).abs();
    if (delta < nearestDelta) {
      nearest = point;
      nearestDelta = delta;
    }
  }
  return nearest;
}

String colorForPaceNoteSeverity(int severity) {
  switch (severity) {
    case 1:
      return '#D50000';
    case 2:
      return '#FF3D00';
    case 3:
      return '#FF9800';
    case 4:
      return '#FFC107';
    case 5:
      return '#8BC34A';
    case 6:
      return '#2E7D32';
    default:
      return '#FF9800';
  }
}

String colorForPaceNote(PaceNote note) {
  if (note.type == PaceNoteType.straight) {
    return '#9E9E9E';
  }
  return switch (note.type) {
    PaceNoteType.roundabout => '#7E57C2',
    PaceNoteType.junction => '#03A9F4',
    PaceNoteType.warning => '#1976D2',
    PaceNoteType.keepLeft || PaceNoteType.keepRight => '#8E24AA',
    _ => colorForPaceNoteSeverity(note.severity),
  };
}

double smoothHeading(double previous, double next, double factor) {
  final delta = normalizeAngleDeltaDegrees(previous, next);
  return (previous + delta * factor + 360) % 360;
}

String shortCalloutLabel(PaceNote note) {
  if (note.type == PaceNoteType.straight) {
    return 'STR';
  }
  if (note.type == PaceNoteType.roundabout) {
    return 'RAB';
  }
  if (note.type == PaceNoteType.junction) {
    return 'JCT';
  }
  if (note.type == PaceNoteType.keepLeft) {
    return 'KPL';
  }
  if (note.type == PaceNoteType.keepRight) {
    return 'KPR';
  }
  final direction = note.direction.toLowerCase().startsWith('l') ? 'L' : 'R';
  if (note.type == PaceNoteType.hairpinLeft ||
      note.type == PaceNoteType.hairpinRight ||
      note.type == PaceNoteType.hairpin ||
      note.severity == 1) {
    return '${direction}H';
  }
  return '$direction${note.severity}';
}

List<RoadWarning> filterRoadWarnings(
  List<RoadWarning> warnings,
  SettingsService settings,
) {
  return warnings
      .where((warning) => settings.isWarningTypeEnabled(warning.type))
      .toList()
    ..sort((a, b) => a.distanceFromStart.compareTo(b.distanceFromStart));
}

String formatSpeedLimitSegment(SpeedLimitSegment? segment) {
  if (segment == null) {
    return '—';
  }
  if (segment.parsedKmh != null) {
    return '${segment.parsedKmh}';
  }
  return segment.rawMaxspeed;
}

IconData iconForRoadWarning(RoadWarningType type) {
  return switch (type) {
    RoadWarningType.speedCamera => Icons.camera_alt,
    RoadWarningType.speedBump => Icons.speed,
    RoadWarningType.trafficLight => Icons.traffic,
    RoadWarningType.stopSign => Icons.back_hand,
    RoadWarningType.giveWay => Icons.change_history,
    RoadWarningType.surfaceChange => Icons.terrain,
    RoadWarningType.tunnel => Icons.dark_mode,
    RoadWarningType.bridge => Icons.water,
    RoadWarningType.roundabout => Icons.roundabout_right,
    RoadWarningType.speedLimitChange => Icons.speed,
    RoadWarningType.crest => Icons.landscape,
    RoadWarningType.dip => Icons.trending_down,
  };
}

String labelForRoadWarningType(RoadWarningType type) {
  return switch (type) {
    RoadWarningType.speedCamera => 'Speed cameras',
    RoadWarningType.speedBump => 'Speed bumps',
    RoadWarningType.trafficLight => 'Traffic lights',
    RoadWarningType.stopSign => 'Stop signs',
    RoadWarningType.giveWay => 'Give way',
    RoadWarningType.surfaceChange => 'Surface changes',
    RoadWarningType.tunnel => 'Tunnels',
    RoadWarningType.bridge => 'Bridges',
    RoadWarningType.roundabout => 'Roundabouts',
    RoadWarningType.speedLimitChange => 'Speed limits',
    RoadWarningType.crest => 'Crests',
    RoadWarningType.dip => 'Dips',
  };
}

String colorForRoadWarning(RoadWarningType type) {
  return switch (type) {
    RoadWarningType.speedCamera => '#D50000',
    RoadWarningType.speedBump => '#FF9800',
    RoadWarningType.trafficLight => '#7E57C2',
    RoadWarningType.stopSign => '#D50000',
    RoadWarningType.giveWay => '#FFC107',
    RoadWarningType.surfaceChange => '#795548',
    RoadWarningType.tunnel => '#616161',
    RoadWarningType.bridge => '#607D8B',
    RoadWarningType.roundabout => '#009688',
    RoadWarningType.speedLimitChange => '#1976D2',
    RoadWarningType.crest => '#4CAF50',
    RoadWarningType.dip => '#00BCD4',
  };
}

String shortRoadWarningLabel(RoadWarningType type) {
  return switch (type) {
    RoadWarningType.speedCamera => 'CAM',
    RoadWarningType.speedBump => 'BUMP',
    RoadWarningType.trafficLight => 'TL',
    RoadWarningType.stopSign => 'STOP',
    RoadWarningType.giveWay => 'YIELD',
    RoadWarningType.surfaceChange => 'SURF',
    RoadWarningType.tunnel => 'TUN',
    RoadWarningType.bridge => 'BR',
    RoadWarningType.roundabout => 'RAB',
    RoadWarningType.speedLimitChange => 'LIM',
    RoadWarningType.crest => 'CRST',
    RoadWarningType.dip => 'DIP',
  };
}

String getMapStyle(BuildContext context, SettingsService settings) {
  if (settings.useCleanMap) {
    return 'https://tiles.openfreemap.org/styles/dark';
  } else {
    return 'https://tiles.openfreemap.org/styles/liberty';
  }
}

class OverlapSymbolOptions extends maplibre.SymbolOptions {
  const OverlapSymbolOptions({
    super.iconSize,
    super.iconImage,
    super.iconRotate,
    super.iconOffset,
    super.iconAnchor,
    super.fontNames,
    super.textField,
    super.textSize,
    super.textMaxWidth,
    super.textLetterSpacing,
    super.textJustify,
    super.textAnchor,
    super.textRotate,
    super.textTransform,
    super.textOffset,
    super.iconOpacity,
    super.iconColor,
    super.iconHaloColor,
    super.iconHaloWidth,
    super.iconHaloBlur,
    super.textOpacity,
    super.textColor,
    super.textHaloColor,
    super.textHaloWidth,
    super.textHaloBlur,
    super.geometry,
    super.zIndex,
    super.draggable,
  });

  @override
  Map<String, dynamic> toJson([bool addGeometry = true]) {
    final Map<String, dynamic> json = Map<String, dynamic>.from(super.toJson(addGeometry));
    json['iconAllowOverlap'] = true;
    json['iconIgnorePlacement'] = true;
    json['textAllowOverlap'] = true;
    json['textIgnorePlacement'] = true;
    return json;
  }
}
