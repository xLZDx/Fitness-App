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
  // `unawaited` silences the lint, not the error -- without an explicit
  // handler a failed load left `l10n` null forever and every cue resolved to
  // nothing. A coach that goes permanently, invisibly mute is the exact defect
  // this wiring exists to remove. A failed load falls back to English text;
  // if even that fails the coach stays silent -- it never reads an internal
  // identifier (a cue key) aloud.
  final load = loadLocalizations ?? AppLocalizations.delegate.load;
  Future<void> bind(Locale locale, {required bool allowFallback}) async {
    try {
      l10n = await load(locale);
    } catch (e) {
      debugPrint('form-coach localisation failed to load ($locale): $e');
      if (allowFallback && locale.languageCode != 'en') {
        await bind(const Locale('en'), allowFallback: false);
      }
    }
  }

  unawaited(bind(Locale(lang), allowFallback: true));
  return TtsVoiceCoach(
    tts: tts,
    languageTag: lang == 'ru' ? 'ru-RU' : 'en-US',
    // Empty until the bundle lands (a few milliseconds at startup).
    // GatedVoiceCoach skips empty text, so the coach is briefly silent rather
    // than reading a raw key out loud.
    resolveText: (key) {
      final loaded = l10n;
      // Still loading, or nothing loaded at all: stay quiet (empty text is
      // skipped by `GatedVoiceCoach`). The visible banner and the voice-error
      // card carry the failure; an identifier read aloud helps nobody.
      return loaded == null ? '' : formCueText(loaded, key);
    },
  );
}
