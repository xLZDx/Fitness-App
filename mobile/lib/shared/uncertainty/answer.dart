/// A closed-set way to say "I have a confident value" or "I don't, and here
/// is why" — never a fabricated value, never a bare `null` with no reason.
///
/// ## Why this exists
///
/// Three independent parts of this app already reinvented the same shape
/// without ever referencing each other: `ScanOutcome`
/// (`features/visual_equipment/data/scan_outcome.dart`), `PoseGateVerdict`
/// (`features/form_check/data/pose_gate.dart`), and `VideoFailureReason`
/// (`features/equipment/data/video_failure.dart`) are all a prioritized,
/// closed-set "why can't I give you one confident answer" enum, with
/// absence/null treated as a first-class non-answer rather than a
/// fabricated guess. That three-times convergence — not any single one of
/// them — is the evidence this type formalizes. Full reconnaissance:
/// `core/product/GATE_E_SHARED_UNCERTAINTY_D0_NOTE_2026-08-19.md`.
///
/// ## What this deliberately is not
///
/// Not a numeric confidence score. This codebase already tried a single
/// numeric scale once and rejected it: `VisualMatch.confidence` and
/// `TextAnchorMatch.confidence` are two *different* 0..1 scales inside the
/// same feature, and the second is explicitly documented as not comparable
/// to the first. [R] stays a domain-owned enum on purpose — `T`/`R` are
/// generic so each domain keeps its own closed set of reasons
/// (`PoseGateVerdict` and `VideoFailureReason` should never be unified into
/// one enum; that would be the same universal-model mistake one level
/// down), while every domain gets the same *shape*: confident-or-why-not,
/// sealed so a consumer's `switch` cannot forget a case.
///
/// Also not a fit for a ranked list of candidates (`ScanResult`'s
/// "alternatives" case) — "one confident value, or a reason" does not
/// represent "here are 3 plausible options, you pick." That case keeps its
/// own richer type; forcing it through this contract would either drop the
/// list or misrepresent the shape.
///
/// `T` and `R` are bounded to `Object` (non-nullable) on purpose (Gate E
/// review, 2026-08-19): an unbounded `T` would let `T` itself be nullable
/// and reopen the exact ambiguity this type exists to close — `Answer<
/// String?, R>.confident(null)` ("I confidently know there is nothing")
/// would become indistinguishable from an uncertain answer through
/// `valueOrNull`, and an omitted `bestGuess` would become indistinguishable
/// from an explicitly-given `null` guess. A domain whose confident value is
/// naturally optional should express that as its own state (e.g. a
/// dedicated "confidently empty" case), not by instantiating `T` as
/// nullable.
sealed class Answer<T extends Object, R extends Object> {
  const Answer();

  /// A confident value. There is no reason to give, because there isn't one.
  const factory Answer.confident(T value) = ConfidentAnswer<T, R>;

  /// No confident value. [reason] must name a real, closed-set cause —
  /// never a free-text string, never inferred from unrelated UI state (the
  /// mistake `VideoFailureReason`'s own doc comment describes fixing: a
  /// message chosen from whether a poster image happened to be on screen,
  /// not from anything actually checked).
  ///
  /// [bestGuess], if given, is a labeled, non-authoritative reading — the
  /// "possibly: X" case (`LiveRecognition.settled == false` is the existing
  /// precedent). It is structurally separate from the confident value on
  /// purpose: a consumer must go out of its way to read it, and can never
  /// receive it through the same accessor as a real answer.
  const factory Answer.uncertain(R reason, {T? bestGuess}) =
      UncertainAnswer<T, R>;
}

final class ConfidentAnswer<T extends Object, R extends Object>
    extends Answer<T, R> {
  const ConfidentAnswer(this.value);

  final T value;

  // `other is ConfidentAnswer<T, R>` alone is not symmetric: Dart's
  // covariant generics make `ConfidentAnswer<int, R> is ConfidentAnswer<num,
  // R>` true but not the reverse, so `Answer<int, R>.confident(1) ==
  // Answer<num, R>.confident(1)` and its swap could disagree (codex review,
  // 2026-08-20, before this port landed on master). `runtimeType` pins the
  // check to the exact instantiation on both sides.
  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ConfidentAnswer<T, R> &&
      other.value == value;

  @override
  int get hashCode => Object.hash(ConfidentAnswer, value);

  @override
  String toString() => 'Answer.confident($value)';
}

final class UncertainAnswer<T extends Object, R extends Object>
    extends Answer<T, R> {
  const UncertainAnswer(this.reason, {this.bestGuess});

  final R reason;
  final T? bestGuess;

  // Same `runtimeType` guard as `ConfidentAnswer.==`, for the same reason.
  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is UncertainAnswer<T, R> &&
      other.reason == reason &&
      other.bestGuess == bestGuess;

  @override
  int get hashCode => Object.hash(UncertainAnswer, reason, bestGuess);

  @override
  String toString() => 'Answer.uncertain($reason, bestGuess: $bestGuess)';
}

extension AnswerX<T extends Object, R extends Object> on Answer<T, R> {
  bool get isConfident => this is ConfidentAnswer<T, R>;

  /// The confident value, or null. Deliberately the ONLY way to read a
  /// value out without handling both cases explicitly via `switch` —
  /// there is no accessor that could return [UncertainAnswer.bestGuess] by
  /// mistake in place of a real answer.
  T? get valueOrNull => switch (this) {
        ConfidentAnswer<T, R>(:final value) => value,
        UncertainAnswer<T, R>() => null,
      };

  /// The reason there is no confident value, or null when there is one.
  R? get reasonOrNull => switch (this) {
        ConfidentAnswer<T, R>() => null,
        UncertainAnswer<T, R>(:final reason) => reason,
      };
}
