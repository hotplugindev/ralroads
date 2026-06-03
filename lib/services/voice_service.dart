import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final FlutterTts _tts = FlutterTts();
  bool _enabled = true;

  Future<void> init() async {
    await _tts.setSpeechRate(0.46);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
  }

  Future<void> speak(String text) async {
    if (!_enabled || text.trim().isEmpty) {
      return;
    }
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();

  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      _tts.stop();
    }
  }
}
