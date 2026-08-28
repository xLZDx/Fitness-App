// GF.2 — Form coach spoken cues, platform adapter.
//
// Binds [GatedVoiceCoach] to `flutter_tts`. Split out of `voice_coach.dart`
// for the same reason `mlkit_pose_detector_service.dart` is split out of
// `pose_detector_service.dart`: the policy is pure and unit-testable, the
// plugin needs a MethodChannel and a live binding.

import 'dart:async' show unawaited;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
  TtsVoiceCoach({
    FlutterTts? tts,
    super.gate,
    super.resolveText,
    this.languageTag = 'ru-RU',
  }) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  /// BCP-47 tag for the voice, e.g. `ru-RU`.
  ///
  /// Was hardcoded `en-US`, which meant that even once the cues themselves were
  /// translated the phone would have read Russian text with an English voice.
  /// `main.dart` passes the app's active locale.
  final String languageTag;

  bool _configured = false;

  Object? _lastError;

  /// Last engine failure, or null. On the [VoiceCoach] interface so a UI can
  /// tell "nothing to say" from "the coach is broken" without a type check.
  @override
  String? get lastErrorMessage =>
      _lastError == null ? null : '$_lastError';

  void _recordError(String op, Object e, StackTrace st, {bool expected = false}) {
    _lastError = e;
    // Without this a device with no TTS voice installed produces a coach that
    // is simply silent, with nothing anywhere to explain why.
    debugPrint('TtsVoiceCoach.$op failed: $e');
    debugPrintStack(stackTrace: st);
    // `expected` (no TTS voice installed for the device's language) is a real
    // device-population fact, not a bug -- reporting it as a Crashlytics
    // non-fatal would turn "user has no Russian TTS voice" into a paged
    // operational signal, the same over-alerting GPT-PM's own OBS-1 design
    // ruling warned against for the visual_equipment catches (an expected
    // user-denied camera permission must not become an incident either).
    // Fire-and-forget, sanitized (error + stack trace only, no cue text).
    if (!expected) {
      try {
        unawaited(
          FirebaseCrashlytics.instance.recordError(
            e,
            st,
            fatal: false,
            reason: 'TtsVoiceCoach.$op failed',
          ),
        );
      } catch (_) {
        // Reporting failure is not itself reportable.
      }
    }
  }

  /// Set when the device simply cannot do this — no voice installed for
  /// [languageTag]. Distinct from a transient failure on purpose: a permanent
  /// condition must latch, or every cue re-probes the platform channel forever;
  /// a transient one must NOT latch, or a single hiccup at startup leaves the
  /// coach mis-configured for the rest of the session.
  bool _unsupportedVoice = false;

  /// True when the device has no voice for [languageTag]. The UI reads this to
  /// say "voice coaching unavailable" instead of going quietly silent.
  bool get voiceUnavailable => _unsupportedVoice;

  Future<void> _ensureConfigured() async {
    if (_configured || _unsupportedVoice) return;
    // Probe first: asking for a voice the device does not have throws on some
    // engines and silently no-ops on others.
    try {
      final available = await _tts.isLanguageAvailable(languageTag);
      if (available != true) {
        _unsupportedVoice = true;
        _recordError(
          'setLanguage',
          StateError('TTS voice for $languageTag is not installed'),
          StackTrace.current,
          expected: true,
        );
        return;
      }
    } catch (e, st) {
      // The probe itself failing is not evidence the voice is missing — treat
      // it as transient and let the setters below decide.
      _recordError('isLanguageAvailable', e, st);
    }
    try {
      await _tts.setLanguage(languageTag);
      // Slower than default: cues are read mid-effort, often at arm's length
      // from the phone.
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _configured = true;
    } catch (e, st) {
      // Deliberately leave `_configured` false so the next cue retries. This
      // used to be set true on entry, so one throw here latched a permanently
      // wrong rate/volume/language for the whole session.
      _recordError('configure', e, st);
    }
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
