import '../models/pace_note.dart';
import '../models/road_warning.dart';
import '../models/speed_limit_segment.dart';
import '../services/settings_service.dart';
import '../services/callout_speech_service.dart';
import '../services/callout_scheduler.dart';

class CalloutRuntimeController {
  CalloutRuntimeController({required SettingsService settings})
    : _settings = settings {
    _speechService = CalloutSpeechService();
    _speechService.init().then((_) {
      _speechService.setEnabled(true);
    });
    _scheduler = CalloutScheduler(
      speechService: _speechService,
      settings: _settings,
    );
  }

  final SettingsService _settings;
  late final CalloutSpeechService _speechService;
  late final CalloutScheduler _scheduler;

  CalloutSpeechService get speechService => _speechService;
  CalloutScheduler get scheduler => _scheduler;

  void reset() {
    _scheduler.reset();
  }

  void loadRouteData({
    required List<PaceNote> notes,
    required List<RoadWarning> warnings,
    required List<SpeedLimitSegment> speedLimits,
  }) {
    _scheduler.loadRouteData(
      notes: notes,
      warnings: warnings,
      speedLimits: speedLimits,
    );
  }

  void update(double distanceAlong, double displaySpeedMps) {
    _scheduler.update(distanceAlong, displaySpeedMps);
  }

  void dispose() {
    // CalloutSpeechService does not have a dispose, but scheduler might.
  }
}
