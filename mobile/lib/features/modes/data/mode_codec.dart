/// Tolerant codec of the mode state (design 5.1). Never throws: a corrupt,
/// unknown-shape or newer-version value is reported as unreadable, never as
/// missing (RV-2).
library;

import 'dart:convert';

import 'mode_models.dart';

/// Highest stored format version this reader understands.
const int kModeFormatVersion = 1;

/// Longest raw string the decoder will parse (a real value is under 300 chars).
const int kModeMaxRawLength = 4096;

const _skippedToken = 's';
const _unansweredToken = 'u';
const _answeredPrefix = 'a:';

/// Encodes [state] to the single stored string, for example
/// `{"v":1,"mode":"train","chooser":"pending","answers":{"train":"a:gym"}}`.
/// Unanswered entries are omitted.
String encodeModeState(ModeState state) {
  final answers = <String, String>{};
  for (final e in state.answers.entries) {
    switch (e.value.kind) {
      case ModeAnswerKind.unanswered:
        break;
      case ModeAnswerKind.skipped:
        answers[e.key.name] = _skippedToken;
      case ModeAnswerKind.answered:
        answers[e.key.name] = '$_answeredPrefix${e.value.value}';
    }
  }
  return jsonEncode(<String, Object>{
    'v': kModeFormatVersion,
    'mode': state.selectedMode.name,
    'chooser': state.chooserStatus.name,
    'answers': answers,
  });
}

/// Decodes a stored string. [raw] null is the only input that maps to
/// [ModeReadMissing]. Never throws.
ModeRead decodeModeState(String? raw) {
  if (raw == null) return const ModeReadMissing();
  if (raw.isEmpty || raw.length > kModeMaxRawLength) {
    return const ModeReadUnreadable(UnreadableReason.corrupt);
  }
  try {
    return _decode(raw);
  } catch (_) {
    // Defensive: any surprise is unreadable, never missing and never thrown.
    return const ModeReadUnreadable(UnreadableReason.corrupt);
  }
}

ModeRead _decode(String raw) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException {
    return const ModeReadUnreadable(UnreadableReason.corrupt);
  }
  if (json is! Map) {
    return const ModeReadUnreadable(UnreadableReason.unknownShape);
  }
  final v = json['v'];
  if (v is! int) {
    return const ModeReadUnreadable(UnreadableReason.unknownShape);
  }
  if (v > kModeFormatVersion) {
    return const ModeReadUnreadable(UnreadableReason.newerVersion);
  }
  if (v < 1) {
    return const ModeReadUnreadable(UnreadableReason.unknownShape);
  }
  final modeRaw = json['mode'];
  final chooserRaw = json['chooser'];
  if (modeRaw is! String || chooserRaw is! String) {
    return const ModeReadUnreadable(UnreadableReason.unknownShape);
  }
  // An unknown chooser token cannot be guessed (guessing "absent" would let a
  // later initIfAbsent overwrite it): unreadable.
  final chooser = ChooserStatus.tryParse(chooserRaw);
  if (chooser == null) {
    return const ModeReadUnreadable(UnreadableReason.unknownShape);
  }
  // An unknown mode name falls back to train in memory only (design 5.1).
  final mode = AppMode.tryParse(modeRaw) ?? AppMode.train;

  final answers = <AppMode, ModeAnswer>{};
  final answersRaw = json['answers'];
  if (answersRaw != null) {
    if (answersRaw is! Map) {
      return const ModeReadUnreadable(UnreadableReason.unknownShape);
    }
    for (final e in answersRaw.entries) {
      final key = e.key;
      final m = key is String ? AppMode.tryParse(key) : null;
      if (m == null) continue; // answer of an unknown mode: ignored
      final a = _decodeAnswer(e.value);
      if (a.kind != ModeAnswerKind.unanswered) answers[m] = a;
    }
  }
  return ModeReadValue(
      ModeState(selectedMode: mode, chooserStatus: chooser, answers: answers));
}

/// Unknown answer values count as unanswered (the `TrainingContextAnswer`
/// tolerance).
ModeAnswer _decodeAnswer(Object? raw) {
  if (raw is! String) return ModeAnswer.unanswered;
  if (raw == _skippedToken) return ModeAnswer.skipped;
  if (raw == _unansweredToken) return ModeAnswer.unanswered;
  if (raw.startsWith(_answeredPrefix)) {
    return ModeAnswer.answered(raw.substring(_answeredPrefix.length));
  }
  return ModeAnswer.unanswered;
}
