import 'dart:async' show unawaited;
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'cue_text.dart';
import 'tts_voice_coach.dart';

/// The production speech coach for the form coach: [TtsVoiceCoach] bound to the
/// app's language, with cue keys resolved through the same `formCueText` the
/// on-screen card uses.
///
/// Extracted from `main.dart` so the real wiring (language tag, text
/// resolution, gate) can be driven by a test with a fake engine -- the operator
/// reported on a real phone that a squat cue was WRITTEN on screen but never
/// SPOKEN, and the only way to pin that is to run the actual resolver rather
/// than a mock coach with an identity resolver.
///
/// Both halves of the language matter and both were broken once: the cues were
/// English literals baked into the classifiers, and the engine was pinned to
/// en-US, so even translated text would have been read by an English voice.
TtsVoiceCoach buildLocalizedTtsVoiceCoach(
  String lang, {
  FlutterTts? tts,
  Future<AppLocalizations> Function(Locale locale)? loadLocalizations,
}) {
  AppLocalizations? l10n;
  Object? l10nError;
  // `unawaited` silences the lint, not the error -- without an explicit
  // handler a failed load left `l10n` null forever and every cue resolved to
  // nothing. A coach that goes permanently, invisibly mute is the exact defect
  // this wiring exists to remove.
  final load = loadLocalizations ?? AppLocalizations.delegate.load;
  unawaited(load(Locale(lang)).then(
    (loaded) => l10n = loaded,
    onError: (Object e, StackTrace st) {
      l10nError = e;
      debugPrint('form-coach localisation failed to load: $e');
    },
  ));
  return TtsVoiceCoach(
    tts: tts,
    languageTag: lang == 'ru' ? 'ru-RU' : 'en-US',
    // Empty until the bundle lands (a few milliseconds at startup).
    // GatedVoiceCoach skips empty text, so the coach is briefly silent rather
    // than reading a raw key out loud.
    resolveText: (key) {
      final loaded = l10n;
      if (loaded != null) return formCueText(loaded, key);
      // Still loading: stay quiet, the next cue will resolve. Failed outright:
      // say the key. It is ugly on purpose -- a broken coach the user can hear
      // is recoverable, a silent one is not.
      return l10nError == null ? '' : key.name;
    },
  );
}
