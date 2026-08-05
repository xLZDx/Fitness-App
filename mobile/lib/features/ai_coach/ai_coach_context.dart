/// What the AI coach is being asked about, and from where.
///
/// ## Why this type exists
///
/// The sheet used to take one `String machineName`, and that string did three
/// jobs at once: it was the cache key, the prompt subject, and the title. Each
/// of them was wrong in a different way.
///
/// * **As a cache key** it is a *display* name. `aiCoachAdviceProvider` is keyed
///   on it, so two catalog entries that happen to share a label — the catalog
///   holds 1,887 rows drawn from a vendor list, and duplicate labels across
///   manufacturers are ordinary — served each other's answer. A stable id
///   cannot collide that way.
/// * **As a prompt subject** it carried no indication of what it names. The
///   prompt opened with "The user is standing at:" whether the subject was a
///   leg press or a Romanian deadlift, and a movement is not a place to stand.
/// * **As an API** it could not grow. Master prompt §23 requires structured
///   context — source screen, subject id, locale — rather than "only a long
///   free-form string", and every added field would have been another
///   positional argument threaded through every call site.
///
/// ## What it deliberately does NOT carry
///
/// §23 also lists history and recovery data, "subject to privacy constraints".
/// Those constraints are now sharp: gate H1a moved the health questionnaire off
/// the server entirely, so injuries, conditions, medications, smoking and
/// alcohol exist only in `PrefsSensitiveStore` on the phone. Sending any of it
/// into a prompt would hand it to a cloud model and undo that gate silently.
/// Nothing here reaches for it, and the omission is the design, not an oversight.
///
/// Training history and active-workout state are absent for a duller reason:
/// no caller has one to give yet. They arrive with the entry points in R8, and
/// adding empty fields now would only invite a prompt that describes data it
/// does not have.
library;

import 'package:flutter/foundation.dart';

/// Which screen asked, which decides what question is worth asking.
enum AiCoachSource {
  /// A machine the user is standing at. Setup, technique, beginner volume.
  equipment,

  /// A movement the user is about to perform. Execution, cues, mistakes.
  exercise,
}

/// One coaching request, fully described.
///
/// Value equality is load-bearing: this is the key of an `autoDispose.family`,
/// so reopening the sheet for the same subject within a session must reuse the
/// cached answer rather than re-bill the free-tier quota. A class without `==`
/// would miss on every rebuild and bill every time.
@immutable
class AiCoachContext {
  const AiCoachContext({
    required this.source,
    required this.subjectId,
    required this.subjectName,
    required this.languageCode,
  });

  /// Where the request came from.
  final AiCoachSource source;

  /// Stable catalog id — the cache key that a display name could not be.
  final String subjectId;

  /// Human-readable label, for the prompt and the sheet title.
  final String subjectName;

  /// `ru` or anything else, matching `effectiveLanguageCodeProvider`.
  final String languageCode;

  @override
  bool operator ==(Object other) =>
      other is AiCoachContext &&
      other.source == source &&
      other.subjectId == subjectId &&
      other.subjectName == subjectName &&
      other.languageCode == languageCode;

  @override
  int get hashCode =>
      Object.hash(source, subjectId, subjectName, languageCode);

  @override
  String toString() =>
      'AiCoachContext(${source.name}, $subjectId, $languageCode)';
}

/// The question, built from the context.
///
/// A pure function on purpose: the prompt is the part of this feature most
/// likely to be edited and the part hardest to see the effect of, and this is
/// the only way to assert on it without a network call or a fake model.
String buildCoachPrompt(AiCoachContext ctx) {
  final language = ctx.languageCode == 'ru' ? 'Russian' : 'English';
  final subject = switch (ctx.source) {
    // "Standing at" is right for a machine and wrong for a movement — the
    // distinction this type was introduced to make.
    AiCoachSource.equipment => 'The user is standing at the machine:',
    AiCoachSource.exercise => 'The user is about to perform the exercise:',
  };
  final third = switch (ctx.source) {
    AiCoachSource.equipment => 'A sensible beginner volume (sets x reps or minutes).',
    AiCoachSource.exercise => 'A sensible beginner volume (sets x reps) and a starting load cue.',
  };
  return '''
You are a concise, safety-first gym coach. $subject
"${ctx.subjectName}".

In $language, give:
1. Correct setup and technique (3-5 short bullet points).
2. The 2-3 most common mistakes and how to avoid them.
3. $third

Plain text with simple dashes for bullets — no markdown headers, no tables.
Under 180 words. Do not invent features or variations it does not have. End
with one line reminding to stop on sharp pain.''';
}
