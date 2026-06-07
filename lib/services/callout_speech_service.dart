import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class CalloutSpeechService {
  final FlutterTts _tts = FlutterTts();
  bool _enabled = true;
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  Timer? _safetyTimeoutTimer;
  VoidCallback? _activeCompleteCallback;

  Future<void> init() async {
    await _tts.setSpeechRate(0.46);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      _isSpeaking = true;
    });

    _tts.setCompletionHandler(() {
      _handleSpeechFinished();
    });

    _tts.setCancelHandler(() {
      _handleSpeechFinished();
    });

    _tts.setErrorHandler((dynamic msg) {
      debugPrint('TTS Error: $msg');
      _handleSpeechFinished();
    });
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      stop();
    }
  }

  double _estimateSpeechDuration(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    // Assume 140 WPM, plus a 1.2s buffer for initialization and natural pauses.
    return (words * (60.0 / 140.0)) + 1.2;
  }

  Future<void> speak(String text, VoidCallback onComplete) async {
    _safetyTimeoutTimer?.cancel();
    if (!_enabled || text.trim().isEmpty) {
      _isSpeaking = false;
      onComplete();
      return;
    }

    _activeCompleteCallback = onComplete;
    _isSpeaking = true;

    // Set safety timeout to unlock scheduler in case native platform fails to callback
    final durationSeconds = _estimateSpeechDuration(text);
    _safetyTimeoutTimer = Timer(
      Duration(milliseconds: (durationSeconds * 1000).round()),
      () {
        if (_isSpeaking) {
          debugPrint(
            'TTS safety timeout triggered after ${durationSeconds.toStringAsFixed(1)}s',
          );
          _handleSpeechFinished();
        }
      },
    );

    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
      _handleSpeechFinished();
    }
  }

  Future<void> stop() async {
    _safetyTimeoutTimer?.cancel();
    _isSpeaking = false;
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TTS stop failed: $e');
    }
    final callback = _activeCompleteCallback;
    _activeCompleteCallback = null;
    callback?.call();
  }

  void _handleSpeechFinished() {
    _safetyTimeoutTimer?.cancel();
    if (_isSpeaking) {
      _isSpeaking = false;
      final callback = _activeCompleteCallback;
      _activeCompleteCallback = null;
      callback?.call();
    }
  }
}
