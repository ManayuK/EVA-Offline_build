// lib/core/services/tts_service.dart
//
// EVA Text-to-Speech Service
// Wraps flutter_tts to speak EVA's assistant responses aloud.
// Uses the device's native TTS engine — fully offline, no extra model download.
//
// Usage:
//   final tts = getIt<TtsService>();
//   await tts.speak("Hello, how are you?");
//   await tts.stop();

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TtsState { idle, speaking, paused, stopped }

class TtsService extends ChangeNotifier {
  TtsService(this._prefs) {
    _init();
  }

  final SharedPreferences _prefs;
  final FlutterTts _tts = FlutterTts();

  TtsState _state     = TtsState.idle;
  bool     _autoSpeak = false;   // user toggle: speak every new EVA reply
  String   _speakingMsgId = '';  // tracks which bubble is currently speaking

  // ── Public getters ──────────────────────────────────────────────────────────

  TtsState get state          => _state;
  bool     get isSpeaking     => _state == TtsState.speaking;
  bool     get autoSpeak      => _autoSpeak;
  String   get speakingMsgId  => _speakingMsgId;

  static const _kAutoSpeakKey = 'eva_tts_auto_speak';

  // ── Init ────────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    _autoSpeak = _prefs.getBool(_kAutoSpeakKey) ?? false;

    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);   // slightly slower — warm, conversational pace
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.05);        // slightly higher — softer, feminine tone

    _tts.setStartHandler(() {
      _state = TtsState.speaking;
      notifyListeners();
    });

    _tts.setCompletionHandler(() {
      _state          = TtsState.idle;
      _speakingMsgId  = '';
      notifyListeners();
    });

    _tts.setCancelHandler(() {
      _state          = TtsState.idle;
      _speakingMsgId  = '';
      notifyListeners();
    });

    _tts.setErrorHandler((msg) {
      debugPrint('[TtsService] error: $msg');
      _state          = TtsState.idle;
      _speakingMsgId  = '';
      notifyListeners();
    });

    notifyListeners();
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> speak(String text, {String msgId = ''}) async {
    if (text.trim().isEmpty) return;

    // If already speaking this same message → stop (toggle off)
    if (isSpeaking && _speakingMsgId == msgId) {
      await stop();
      return;
    }

    // Stop any current speech before starting new
    if (isSpeaking) await _tts.stop();

    _speakingMsgId = msgId;

    // Strip markdown-style asterisks, hashes etc. that don't read well aloud
    final cleaned = _cleanForSpeech(text);
    await _tts.speak(cleaned);
  }

  Future<void> stop() async {
    await _tts.stop();
    _state         = TtsState.idle;
    _speakingMsgId = '';
    notifyListeners();
  }

  Future<void> toggleAutoSpeak() async {
    _autoSpeak = !_autoSpeak;
    await _prefs.setBool(_kAutoSpeakKey, _autoSpeak);
    if (!_autoSpeak) await stop();
    notifyListeners();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _cleanForSpeech(String raw) {
    return raw
        .replaceAll(RegExp(r'\*{1,3}'), '')   // bold / italic markdown
        .replaceAll(RegExp(r'#{1,6}\s'), '')  // headings
        .replaceAll(RegExp(r'`{1,3}'), '')    // code ticks
        .replaceAll(RegExp(r'\n{2,}'), '. ')  // paragraph breaks → pause
        .replaceAll('\n', ' ')
        .trim();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
