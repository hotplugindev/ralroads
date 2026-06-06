import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/speed_limit_segment.dart';
import '../services/settings_service.dart';
import 'callout_speech_service.dart';

enum CalloutPriority {
  critical,
  high,
  normal,
  low,
  informational,
}

class ScheduledCallout {
  final String id;
  final String text;
  final CalloutPriority priority;
  final double routeDistance;
  final double expirationDistance;
  final double estimatedSpeakingDuration;
  final bool canMerge;
  final bool canInterrupt;
  final dynamic source;

  ScheduledCallout({
    required this.id,
    required this.text,
    required this.priority,
    required this.routeDistance,
    required this.expirationDistance,
    required this.estimatedSpeakingDuration,
    this.canMerge = true,
    this.canInterrupt = false,
    this.source,
  });

  ScheduledCallout copyWith({
    String? id,
    String? text,
    CalloutPriority? priority,
    double? routeDistance,
    double? expirationDistance,
    double? estimatedSpeakingDuration,
    bool? canMerge,
    bool? canInterrupt,
    dynamic source,
  }) {
    return ScheduledCallout(
      id: id ?? this.id,
      text: text ?? this.text,
      priority: priority ?? this.priority,
      routeDistance: routeDistance ?? this.routeDistance,
      expirationDistance: expirationDistance ?? this.expirationDistance,
      estimatedSpeakingDuration: estimatedSpeakingDuration ?? this.estimatedSpeakingDuration,
      canMerge: canMerge ?? this.canMerge,
      canInterrupt: canInterrupt ?? this.canInterrupt,
      source: source ?? this.source,
    );
  }
}

class CalloutModeConfig {
  final Set<CalloutPriority> allowedPriorities;
  final bool allowBridges;
  final bool allowTunnels;
  final bool allowSurfaces;
  final bool allowStraights;
  final int maxCurveSeverity;

  const CalloutModeConfig({
    required this.allowedPriorities,
    required this.allowBridges,
    required this.allowTunnels,
    required this.allowSurfaces,
    required this.allowStraights,
    required this.maxCurveSeverity,
  });

  factory CalloutModeConfig.fromStyle(PacenoteStyle style) {
    switch (style) {
      case PacenoteStyle.calm:
        return const CalloutModeConfig(
          allowedPriorities: {CalloutPriority.critical, CalloutPriority.high},
          allowBridges: false,
          allowTunnels: false,
          allowSurfaces: false,
          allowStraights: false,
          maxCurveSeverity: 3,
        );
      case PacenoteStyle.balanced:
        return const CalloutModeConfig(
          allowedPriorities: {CalloutPriority.critical, CalloutPriority.high, CalloutPriority.normal},
          allowBridges: false,
          allowTunnels: true,
          allowSurfaces: true,
          allowStraights: false,
          maxCurveSeverity: 5,
        );
      case PacenoteStyle.rally:
        return const CalloutModeConfig(
          allowedPriorities: {
            CalloutPriority.critical,
            CalloutPriority.high,
            CalloutPriority.normal,
            CalloutPriority.low,
            CalloutPriority.informational
          },
          allowBridges: true,
          allowTunnels: true,
          allowSurfaces: true,
          allowStraights: true,
          maxCurveSeverity: 6,
        );
    }
  }
}

class CalloutScheduler extends ChangeNotifier {
  final CalloutSpeechService speechService;
  final SettingsService settings;
  
  List<PaceNote> allNotes = [];
  List<RoadWarning> allWarnings = [];

  final List<ScheduledCallout> _queue = [];
  List<ScheduledCallout> get queue => List.unmodifiable(_queue);

  final Set<String> _spokenIds = {};
  Set<String> get spokenIds => _spokenIds;

  final Set<String> _expiredIds = {};
  Set<String> get expiredIds => _expiredIds;

  ScheduledCallout? _activeCallout;
  ScheduledCallout? get activeCallout => _activeCallout;

  double _currentRouteDistance = 0.0;
  double get currentRouteDistance => _currentRouteDistance;

  double _currentSpeedMps = 0.0;
  double get currentSpeedMps => _currentSpeedMps;

  CalloutScheduler({
    required this.speechService,
    required this.settings,
  });

  void loadRouteData({
    required List<PaceNote> notes,
    required List<RoadWarning> warnings,
  }) {
    allNotes = notes;
    allWarnings = warnings;
    _queue.clear();
    _spokenIds.clear();
    _expiredIds.clear();
    _activeCallout = null;
    notifyListeners();
  }

  void reset() {
    _queue.clear();
    _spokenIds.clear();
    _expiredIds.clear();
    _activeCallout = null;
    speechService.stop();
    notifyListeners();
  }

  // Calculate dynamic lead time in seconds
  double _calculateLeadTime(ScheduledCallout callout) {
    double baseLead = 1.5;
    switch (callout.priority) {
      case CalloutPriority.critical:
        baseLead = callout.estimatedSpeakingDuration + 3.0;
        break;
      case CalloutPriority.high:
        baseLead = callout.estimatedSpeakingDuration + 2.0;
        break;
      case CalloutPriority.normal:
        baseLead = callout.estimatedSpeakingDuration + 1.5;
        break;
      case CalloutPriority.low:
      case CalloutPriority.informational:
        baseLead = callout.estimatedSpeakingDuration + 0.8;
        break;
    }
    return baseLead;
  }

  double _estimateSpeechDuration(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return (words * (60.0 / 140.0)) + 0.5; // Words at 140 WPM plus padding
  }

  // Maps PaceNote to ScheduledCallout
  ScheduledCallout? _mapPaceNote(PaceNote note) {
    final config = CalloutModeConfig.fromStyle(settings.pacenoteStyle);
    
    // Filter curves by maximum severity in Calm/Balanced modes
    if (note.type == PaceNoteType.left || note.type == PaceNoteType.right) {
      if (note.severity > config.maxCurveSeverity) {
        return null;
      }
    }

    CalloutPriority priority = CalloutPriority.normal;
    switch (note.type) {
      case PaceNoteType.hairpinLeft:
      case PaceNoteType.hairpinRight:
        priority = CalloutPriority.critical;
        break;
      case PaceNoteType.left:
      case PaceNoteType.right:
        if (note.severity <= 2) {
          priority = CalloutPriority.high;
        } else if (note.severity <= 4) {
          priority = CalloutPriority.normal;
        } else {
          priority = CalloutPriority.low;
        }
        break;
      case PaceNoteType.roundabout:
      case PaceNoteType.junction:
        priority = CalloutPriority.normal;
        break;
      case PaceNoteType.keepLeft:
      case PaceNoteType.keepRight:
        priority = CalloutPriority.normal;
        break;
      case PaceNoteType.straight:
        priority = CalloutPriority.informational;
        if (!config.allowStraights) return null;
        break;
      default:
        priority = CalloutPriority.normal;
    }

    if (!config.allowedPriorities.contains(priority)) {
      return null;
    }

    final speechText = note.text.isNotEmpty ? note.text : note.rallyText;
    final duration = _estimateSpeechDuration(speechText);
    
    return ScheduledCallout(
      id: note.id,
      text: speechText,
      priority: priority,
      routeDistance: note.distanceFromStart,
      expirationDistance: note.distanceFromStart + 15.0, // Expire 15m after the geometry start
      estimatedSpeakingDuration: duration,
      canMerge: note.type != PaceNoteType.roundabout && note.type != PaceNoteType.junction,
      canInterrupt: priority == CalloutPriority.critical || priority == CalloutPriority.high,
      source: note,
    );
  }

  // Maps RoadWarning to ScheduledCallout
  ScheduledCallout? _mapWarning(RoadWarning warning) {
    final config = CalloutModeConfig.fromStyle(settings.pacenoteStyle);

    CalloutPriority priority = CalloutPriority.normal;
    switch (warning.type) {
      case RoadWarningType.speedCamera:
        priority = CalloutPriority.high;
        break;
      case RoadWarningType.stopSign:
      case RoadWarningType.giveWay:
        priority = CalloutPriority.critical;
        break;
      case RoadWarningType.speedBump:
      case RoadWarningType.trafficLight:
        priority = CalloutPriority.normal;
        break;
      case RoadWarningType.crest:
      case RoadWarningType.dip:
        priority = CalloutPriority.normal;
        break;
      case RoadWarningType.tunnel:
        priority = CalloutPriority.low;
        if (!config.allowTunnels) return null;
        break;
      case RoadWarningType.bridge:
        priority = CalloutPriority.informational;
        if (!config.allowBridges) return null;
        break;
      case RoadWarningType.surfaceChange:
        priority = CalloutPriority.low;
        if (!config.allowSurfaces) return null;
        break;
      default:
        priority = CalloutPriority.normal;
    }

    if (!config.allowedPriorities.contains(priority)) {
      return null;
    }

    final duration = _estimateSpeechDuration(warning.text);

    return ScheduledCallout(
      id: warning.id,
      text: warning.text,
      priority: priority,
      routeDistance: warning.distanceFromStart,
      expirationDistance: warning.distanceFromStart + 10.0,
      estimatedSpeakingDuration: duration,
      canMerge: warning.type != RoadWarningType.stopSign && warning.type != RoadWarningType.giveWay,
      canInterrupt: priority == CalloutPriority.critical || priority == CalloutPriority.high,
      source: warning,
    );
  }

  // Update loop called with current vehicle progress
  void update(double routeDistance, double speedMps) {
    _currentRouteDistance = routeDistance;
    _currentSpeedMps = speedMps;

    // 1. Process Expiration of queued and active items
    _queue.removeWhere((item) {
      final expired = routeDistance > item.routeDistance;
      if (expired) {
        _expiredIds.add(item.id);
      }
      return expired;
    });

    if (_activeCallout != null && routeDistance > _activeCallout!.expirationDistance) {
      _expiredIds.add(_activeCallout!.id);
      _activeCallout = null;
    }

    // 2. Scan for and trigger upcoming callouts
    final scanHorizon = 300.0;
    
    // Process Pacenotes
    for (final note in allNotes) {
      if (_spokenIds.contains(note.id) || _expiredIds.contains(note.id)) continue;
      
      final mapped = _mapPaceNote(note);
      if (mapped == null) {
        _expiredIds.add(note.id); // Filtered out by mode config
        continue;
      }

      final leadTime = _calculateLeadTime(mapped);
      final triggerDistance = (speedMps * leadTime).clamp(35.0, scanHorizon);

      if (routeDistance >= mapped.routeDistance - triggerDistance) {
        if (routeDistance <= mapped.routeDistance) {
          _queueCallout(mapped);
        } else {
          _expiredIds.add(note.id); // Already passed it before speaking
        }
      }
    }

    // Process Warnings
    for (final warning in allWarnings) {
      if (_spokenIds.contains(warning.id) || _expiredIds.contains(warning.id)) continue;

      final mapped = _mapWarning(warning);
      if (mapped == null) {
        _expiredIds.add(warning.id);
        continue;
      }

      final leadTime = _calculateLeadTime(mapped);
      final triggerDistance = (speedMps * leadTime).clamp(35.0, scanHorizon);

      if (routeDistance >= mapped.routeDistance - triggerDistance) {
        if (routeDistance <= mapped.routeDistance) {
          _queueCallout(mapped);
        } else {
          _expiredIds.add(warning.id);
        }
      }
    }

    // 3. Process Merge Rules
    _processQueueMerge();

    // 4. Trigger Queue Playback / Interruption
    _processSpeechPlayback();
  }

  void _queueCallout(ScheduledCallout callout) {
    if (_queue.any((q) => q.id == callout.id)) return;
    _queue.add(callout);
    _sortQueue();
  }

  void _sortQueue() {
    _queue.sort((a, b) {
      // Sort by priority (higher priority first)
      final prioDiff = a.priority.index.compareTo(b.priority.index);
      if (prioDiff != 0) return prioDiff;
      // If same priority, sort by distance (closer first)
      return a.routeDistance.compareTo(b.routeDistance);
    });
  }

  // Merge nearby callouts
  void _processQueueMerge() {
    if (_queue.length < 2) return;

    var i = 0;
    while (i < _queue.length - 1) {
      final first = _queue[i];
      final second = _queue[i + 1];

      // Rules:
      // 1. Must be close (within 85 meters or 3.5 seconds)
      final distDiff = (second.routeDistance - first.routeDistance).abs();
      final timeDiff = _currentSpeedMps > 1.0 ? distDiff / _currentSpeedMps : 999.0;

      final isClose = distDiff <= 85.0 || timeDiff <= 3.5;
      final bothMergeable = first.canMerge && second.canMerge;

      if (isClose && bothMergeable) {
        // Build merged text
        String mergedText;
        if (first.source is PaceNote && (first.source as PaceNote).type == PaceNoteType.straight) {
          mergedText = '${first.text} into ${second.text}';
        } else if (first.source is RoadWarning && (first.source as RoadWarning).type == RoadWarningType.speedBump) {
          mergedText = '${first.text}, then ${second.text}';
        } else {
          mergedText = '${first.text} into ${second.text}';
        }

        final mergedPriority = first.priority.index < second.priority.index ? first.priority : second.priority;
        final mergedCallout = ScheduledCallout(
          id: '${first.id}+${second.id}',
          text: mergedText,
          priority: mergedPriority,
          routeDistance: first.routeDistance,
          expirationDistance: second.expirationDistance,
          estimatedSpeakingDuration: _estimateSpeechDuration(mergedText),
          canMerge: false, // Don't merge a merged note again
          canInterrupt: first.canInterrupt || second.canInterrupt,
          source: first.source,
        );

        // Mark both original notes as spoken
        _spokenIds.add(first.id);
        _spokenIds.add(second.id);

        // Replace both in queue with merged note
        _queue.removeAt(i + 1); // remove second
        _queue[i] = mergedCallout; // replace first

        _sortQueue();
        notifyListeners();
        // Check same index again in case another merge is possible (limit to 3 chained notes in reality)
      } else {
        i++;
      }
    }
  }

  void _processSpeechPlayback() {
    if (_queue.isEmpty) return;

    final nextCallout = _queue.first;

    // Check interruption
    if (speechService.isSpeaking && _activeCallout != null) {
      final canInterrupt = nextCallout.priority.index < _activeCallout!.priority.index && nextCallout.canInterrupt;
      if (canInterrupt) {
        debugPrint('Interrupting active speech: "${_activeCallout!.text}" (priority ${_activeCallout!.priority}) with "${nextCallout.text}" (priority ${nextCallout.priority})');
        speechService.stop(); // This will trigger cleanup and callback
        _queue.removeAt(0);
        _activeCallout = nextCallout;
        _spokenIds.add(nextCallout.id);
        speechService.speak(nextCallout.text, _onSpeechComplete);
        notifyListeners();
      }
      return;
    }

    if (!speechService.isSpeaking) {
      _queue.removeAt(0);
      _activeCallout = nextCallout;
      _spokenIds.add(nextCallout.id);
      speechService.speak(nextCallout.text, _onSpeechComplete);
      notifyListeners();
    }
  }

  void _onSpeechComplete() {
    _activeCallout = null;
    notifyListeners();
    // Check if there are other items waiting in the queue
    _processSpeechPlayback();
  }
}
