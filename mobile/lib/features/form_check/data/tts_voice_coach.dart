// GF.2 — Form coach spoken cues, platform adapter.
//
// Binds [GatedVoiceCoach] to `flutter_tts`. Split out of `voice_coach.dart`
// for the same reason `mlkit_pose_detector_service.dart` is split out of
// `pose_detector_service.dart`: the policy is pure and unit-testable, the
// plugin needs a MethodChannel and a live binding.

import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:flutter_tts/flutter_tts.dart';

import 'voice_coach.dart';

/// Speaks cues through the device's text-to-speech engine.
///
/// Engine calls are best-effort. A phone with no TTS voice installed throws
/// on `speak`, and a form coach that crashes the camera pipeline because the
/// speaker is unavailable is worse than one that goes quiet — so failures are
/// captured in [lastError] rather than propagated.
class TtsVoiceCoach extends GatedVoiceCoach {
  TtsVoiceCoach({FlutterTts? tts, super.gate}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  bool _configured = false;

  Object? _lastError;

  /// Last engine failure, or null. On the [VoiceCoach] interface so a UI can
  /// tell "nothing to say" from "the coach is broken" without a type check.
  @override
  String? get lastErrorMessage =>
      _lastError == null ? null : '$_lastError';

  void _recordError(String op, Object e, StackTrace st) {
    _lastError = e;
    // Without this a device with no TTS voice installed produces a coach that
    // is simply silent, with nothing anywhere to explain why.
    debugPrint('TtsVoiceCoach.$op failed: $e');
    debugPrintStack(stackTrace: st);
  }

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    _configured = true;
    await _tts.setLanguage('en-US');
    // Slower than default: cues are read mid-effort, often at arm's length
    // from the phone.
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  @override
  Future<void> utter(String text) async {
    try {
      await _ensureConfigured();
      await _tts.speak(text);
    } catch (e, st) {
      _recordError('utter', e, st);
    }
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (e, st) {
      // A failed stop matters more than a failed speak: cue() treats
      // stopSpeaking() as the preempt for a severity-2 cue, so if this fails
      // silently the "stop, protect your back" cue can overlap the nudge it
      // was supposed to cut off.
      _recordError('stopSpeaking(preempt)', e, st);
    }
  }

  @override
  Future<void> dispose() async {
    await stopSpeaking();
  }
}
