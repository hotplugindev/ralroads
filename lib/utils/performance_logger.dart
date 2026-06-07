import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class PerformanceLogger {
  static final Map<String, Stopwatch> _stopwatches = {};

  static void start(String name) {
    if (kDebugMode) {
      final stopwatch = Stopwatch()..start();
      _stopwatches[name] = stopwatch;
      developer.log('[Perf] Started: $name', name: 'Performance');
    }
  }

  static void stop(String name) {
    if (kDebugMode) {
      final stopwatch = _stopwatches.remove(name);
      if (stopwatch != null) {
        stopwatch.stop();
        developer.log(
          '[Perf] Finished: $name took ${stopwatch.elapsedMilliseconds} ms',
          name: 'Performance',
        );
      }
    }
  }

  static void logInfo(String message) {
    if (kDebugMode) {
      developer.log('[Perf] Info: $message', name: 'Performance');
    }
  }

  static void logMapState(
    String screen, {
    int? layers,
    int? sources,
    int? markers,
  }) {
    if (kDebugMode) {
      developer.log(
        '[Perf] Map State ($screen) -> Layers: ${layers ?? "N/A"}, Sources: ${sources ?? "N/A"}, Markers: ${markers ?? "N/A"}',
        name: 'Performance',
      );
    }
  }
}
