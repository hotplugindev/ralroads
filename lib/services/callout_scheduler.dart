import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/speed_limit_segment.dart';
import '../services/settings_service.dart';
import 'callout_speech_service.dart';
import 'route_event_scorer.dart';

enum CalloutPriority { critical, high, normal, low, informational }

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
  final double compositeScore;

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
    this.compositeScore = 0.5,
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
    double? compositeScore,
  }) {
    return ScheduledCallout(
      id: id ?? this.id,
      text: text ?? this.text,
      priority: priority ?? this.priority,
      routeDistance: routeDistance ?? this.routeDistance,
      expirationDistance: expirationDistance ?? this.expirationDistance,
      estimatedSpeakingDuration:
          estimatedSpeakingDuration ?? this.estimatedSpeakingDuration,
      canMerge: canMerge ?? this.canMerge,
      canInterrupt: canInterrupt ?? this.canInterrupt,
      source: source ?? this.source,
      compositeScore: compositeScore ?? this.compositeScore,
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
          allowedPriorities: {
            CalloutPriority.critical,
            CalloutPriority.high,
            CalloutPriority.normal,
          },
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
            CalloutPriority.informational,
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
  List<SpeedLimitSegment> allSpeedLimits = [];

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

  CalloutScheduler({required this.speechService, required this.settings});

  void loadRouteData({
    required List<PaceNote> notes,
    required List<RoadWarning> warnings,
    List<SpeedLimitSegment> speedLimits = const [],
  }) {
    allNotes = notes;
    allWarnings = warnings;
    allSpeedLimits = speedLimits;
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

  double _getSpeedLimitAt(double distance) {
    if (allSpeedLimits.isEmpty) return 80.0;
    for (final limit in allSpeedLimits) {
      if (distance >= limit.startDistance && distance <= limit.endDistance) {
        return limit.parsedKmh?.toDouble() ?? 80.0;
      }
    }
    return 80.0;
  }

  double _calculatePrecedingStraight(double fromDistance) {
    double lastEventDistance = 0.0;
    for (final note in allNotes) {
      if (note.distanceFromStart >= fromDistance) break;
      if (note.type != PaceNoteType.straight) {
        lastEventDistance = note.distanceFromStart;
      }
    }
    return fromDistance - lastEventDistance;
  }

  // Calculate dynamic lead time in seconds
  double _calculateLeadTime(ScheduledCallout callout) {
    double baseLead = 4.0;
    switch (callout.priority) {
      case CalloutPriority.critical:
        baseLead = callout.estimatedSpeakingDuration + 2.0;
        break;
      case CalloutPriority.high:
        baseLead = callout.estimatedSpeakingDuration + 1.6;
        break;
      case CalloutPriority.normal:
        baseLead = callout.estimatedSpeakingDuration + 1.2;
        break;
      case CalloutPriority.low:
      case CalloutPriority.informational:
        baseLead = callout.estimatedSpeakingDuration + 0.8;
        break;
    }
    return baseLead;
  }

  double _calculateTriggerDistance(ScheduledCallout callout, double speedMps) {
    final effectiveSpeed = speedMps.clamp(2.0, 38.0).toDouble();
    final speechAndReactionDistance =
        effectiveSpeed * _calculateLeadTime(callout);
    final baseDistance = switch (callout.priority) {
      CalloutPriority.critical => 38.0,
      CalloutPriority.high => 34.0,
      CalloutPriority.normal => 30.0,
      CalloutPriority.low => 26.0,
      CalloutPriority.informational => 24.0,
    };
    final source = callout.source;
    var semanticBoost = 0.0;
    if (source is PaceNote) {
      if (source.type == PaceNoteType.roundabout ||
          source.type == PaceNoteType.junction ||
          source.type == PaceNoteType.hairpinLeft ||
          source.type == PaceNoteType.hairpinRight ||
          source.type == PaceNoteType.hairpin) {
        semanticBoost = 12.0;
      } else if (source.severity <= 2) {
        semanticBoost = 16.0;
      }
    }
    final maxDistance = switch (effectiveSpeed) {
      < 8.0 => 55.0,
      < 14.0 => 80.0,
      < 22.0 => 115.0,
      _ => 170.0,
    };
    return math
        .max(baseDistance + semanticBoost, speechAndReactionDistance)
        .clamp(25.0, maxDistance);
  }

  double _estimateSpeechDuration(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return (words * (60.0 / 140.0)) + 0.5; // Words at 140 WPM plus padding
  }

  // Maps PaceNote to ScheduledCallout
  ScheduledCallout? _mapPaceNote(PaceNote note) {
    final config = CalloutModeConfig.fromStyle(settings.pacenoteStyle);
    final modeStr = settings.pacenoteStyle.name;

    final speedLimit = _getSpeedLimitAt(note.distanceFromStart);
    final straightBefore = _calculatePrecedingStraight(note.distanceFromStart);

    final scoreResult = RouteEventScorer.scorePaceNote(
      note,
      speedLimit,
      straightBefore,
      modeStr,
    );

    int calculatedPriority = 3;
    if (scoreResult.finalScore >= 0.7) {
      calculatedPriority = 1;
    } else if (scoreResult.finalScore >= 0.45) {
      calculatedPriority = 2;
    }

    if (settings.pacenoteStyle == PacenoteStyle.calm) {
      if (calculatedPriority != 1 && scoreResult.finalScore < 0.7) {
        return null;
      }
    }

    if (settings.pacenoteStyle == PacenoteStyle.balanced) {
      if (calculatedPriority == 3 || scoreResult.finalScore < 0.4) {
        return null;
      }
      if (note.type == PaceNoteType.left ||
          note.type == PaceNoteType.right ||
          note.type == PaceNoteType.corner) {
        if (note.severity >= 5) {
          return null;
        }
      }
    }

    CalloutPriority priority = CalloutPriority.normal;
    if (calculatedPriority == 1) {
      priority = CalloutPriority.critical;
    } else if (calculatedPriority == 2) {
      priority = CalloutPriority.high;
    } else if (note.type == PaceNoteType.straight) {
      priority = CalloutPriority.informational;
    } else {
      priority = CalloutPriority.low;
    }

    if (!config.allowedPriorities.contains(priority)) {
      if (note.type == PaceNoteType.straight && !config.allowStraights) {
        return null;
      }
    }

    final speechText = note.text.isNotEmpty ? note.text : note.rallyText;
    final duration = _estimateSpeechDuration(speechText);

    return ScheduledCallout(
      id: note.id,
      text: speechText,
      priority: priority,
      routeDistance: note.distanceFromStart,
      expirationDistance: note.distanceFromStart + 15.0,
      estimatedSpeakingDuration: duration,
      canMerge:
          note.type != PaceNoteType.roundabout &&
          note.type != PaceNoteType.junction,
      canInterrupt:
          priority == CalloutPriority.critical ||
          priority == CalloutPriority.high,
      source: note,
      compositeScore: scoreResult.finalScore,
    );
  }

  // Maps RoadWarning to ScheduledCallout
  ScheduledCallout? _mapWarning(RoadWarning warning) {
    final config = CalloutModeConfig.fromStyle(settings.pacenoteStyle);
    final modeStr = settings.pacenoteStyle.name;

    final speedLimit = _getSpeedLimitAt(warning.distanceFromStart);
    final straightBefore = _calculatePrecedingStraight(
      warning.distanceFromStart,
    );

    final scoreResult = RouteEventScorer.scoreRoadWarning(
      warning,
      speedLimit,
      straightBefore,
      modeStr,
    );

    int calculatedPriority = 3;
    if (scoreResult.finalScore >= 0.7) {
      calculatedPriority = 1;
    } else if (scoreResult.finalScore >= 0.45) {
      calculatedPriority = 2;
    }

    if (settings.pacenoteStyle == PacenoteStyle.calm) {
      if (calculatedPriority != 1 && scoreResult.finalScore < 0.7) {
        return null;
      }
    }

    if (settings.pacenoteStyle == PacenoteStyle.balanced) {
      if (calculatedPriority == 3 || scoreResult.finalScore < 0.4) {
        return null;
      }
    }

    CalloutPriority priority = CalloutPriority.normal;
    if (calculatedPriority == 1) {
      priority = CalloutPriority.critical;
    } else if (calculatedPriority == 2) {
      priority = CalloutPriority.high;
    } else {
      priority = CalloutPriority.low;
    }

    if (warning.type == RoadWarningType.tunnel && !config.allowTunnels) {
      return null;
    }
    if (warning.type == RoadWarningType.bridge && !config.allowBridges) {
      return null;
    }
    if (warning.type == RoadWarningType.surfaceChange &&
        !config.allowSurfaces) {
      return null;
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
      canMerge:
          warning.type != RoadWarningType.stopSign &&
          warning.type != RoadWarningType.giveWay,
      canInterrupt:
          priority == CalloutPriority.critical ||
          priority == CalloutPriority.high,
      source: warning,
      compositeScore: scoreResult.finalScore,
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

    if (_activeCallout != null &&
        routeDistance > _activeCallout!.expirationDistance) {
      _expiredIds.add(_activeCallout!.id);
      _activeCallout = null;
    }

    // 2. Scan for and trigger upcoming callouts
    final scanHorizon = 300.0;

    // Process Pacenotes
    for (final note in allNotes) {
      if (_spokenIds.contains(note.id) || _expiredIds.contains(note.id)) {
        continue;
      }

      final mapped = _mapPaceNote(note);
      if (mapped == null) {
        _expiredIds.add(note.id); // Filtered out by mode config
        continue;
      }

      final triggerDistance = math.min(
        scanHorizon,
        _calculateTriggerDistance(mapped, speedMps),
      );

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
      if (_spokenIds.contains(warning.id) || _expiredIds.contains(warning.id)) {
        continue;
      }

      final mapped = _mapWarning(warning);
      if (mapped == null) {
        _expiredIds.add(warning.id);
        continue;
      }

      final triggerDistance = math.min(
        scanHorizon,
        _calculateTriggerDistance(mapped, speedMps),
      );

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

    // 4. Prune Queue if too dense
    _pruneQueueIfDense();

    // 5. Trigger Queue Playback / Interruption
    _processSpeechPlayback();
  }

  void _queueCallout(ScheduledCallout callout) {
    if (_queue.any((q) => q.id == callout.id)) return;
    _queue.add(callout);
    _sortQueue();
  }

  void _sortQueue() {
    _queue.sort((a, b) {
      final prioDiff = a.priority.index.compareTo(b.priority.index);
      if (prioDiff != 0) return prioDiff;
      final scoreDiff = b.compositeScore.compareTo(a.compositeScore);
      if (scoreDiff != 0) return scoreDiff;
      return a.routeDistance.compareTo(b.routeDistance);
    });
  }

  // Prune lower composite scores when queue is crowded
  void _pruneQueueIfDense() {
    if (_queue.length < 2) return;
    final totalSpeechDuration = _queue.fold<double>(
      0.0,
      (sum, item) => sum + item.estimatedSpeakingDuration,
    );
    final maxDist = _queue.map((q) => q.routeDistance).reduce(math.max);
    final distRemaining = maxDist - _currentRouteDistance;
    final speed = math.max(5.0, _currentSpeedMps);
    final availableTime = distRemaining / speed;

    if (availableTime > 0) {
      final density = totalSpeechDuration / availableTime;
      if (density > 0.90) {
        _queue.removeWhere((item) {
          if (item.priority == CalloutPriority.critical ||
              item.compositeScore >= 0.7) {
            return false;
          }
          return item.compositeScore < 0.4;
        });
      }
    }
  }

  // Merge nearby callouts
  void _processQueueMerge() {
    if (_queue.length < 2) return;

    var i = 0;
    while (i < _queue.length - 1) {
      final first = _queue[i];
      final second = _queue[i + 1];

      final distDiff = (second.routeDistance - first.routeDistance).abs();
      final timeDiff = _currentSpeedMps > 1.0
          ? distDiff / _currentSpeedMps
          : 999.0;

      final isClose = distDiff <= 85.0 || timeDiff <= 3.5;
      final bothMergeable = first.canMerge && second.canMerge;

      if (isClose && bothMergeable) {
        String mergedText = '';
        if (first.source is PaceNote && second.source is RoadWarning) {
          final warning = second.source as RoadWarning;
          if (warning.type == RoadWarningType.crest) {
            mergedText = '${first.text} over crest';
          } else if (warning.type == RoadWarningType.dip) {
            mergedText = '${first.text} through dip';
          }
        } else if (first.source is RoadWarning && second.source is PaceNote) {
          final warning = first.source as RoadWarning;
          if (warning.type == RoadWarningType.crest) {
            mergedText = 'crest into ${second.text}';
          } else if (warning.type == RoadWarningType.dip) {
            mergedText = 'dip into ${second.text}';
          }
        }

        if (mergedText.isEmpty) {
          mergedText = '${first.text} into ${second.text}';
        }

        final mergedPriority = first.priority.index < second.priority.index
            ? first.priority
            : second.priority;
        final mergedCallout = ScheduledCallout(
          id: '${first.id}+${second.id}',
          text: mergedText,
          priority: mergedPriority,
          routeDistance: first.routeDistance,
          expirationDistance: second.expirationDistance,
          estimatedSpeakingDuration: _estimateSpeechDuration(mergedText),
          canMerge: false,
          canInterrupt: first.canInterrupt || second.canInterrupt,
          source: first.source,
          compositeScore: math.max(first.compositeScore, second.compositeScore),
        );

        _spokenIds.add(first.id);
        _spokenIds.add(second.id);

        _queue.removeAt(i + 1);
        _queue[i] = mergedCallout;

        _sortQueue();
        notifyListeners();
      } else {
        i++;
      }
    }
  }

  void _processSpeechPlayback() {
    if (_queue.isEmpty) return;

    final nextCallout = _queue.first;

    if (speechService.isSpeaking && _activeCallout != null) {
      final canInterrupt =
          nextCallout.priority.index < _activeCallout!.priority.index &&
          nextCallout.canInterrupt;
      if (canInterrupt) {
        debugPrint(
          'Interrupting active speech: "${_activeCallout!.text}" (priority ${_activeCallout!.priority}) with "${nextCallout.text}" (priority ${nextCallout.priority})',
        );
        speechService.stop();
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
    _processSpeechPlayback();
  }
}
