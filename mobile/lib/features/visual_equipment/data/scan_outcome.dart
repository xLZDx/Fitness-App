import 'visual_equipment_match.dart';

/// How a recognition attempt actually ended.
///
/// R2.2 states 6-11. The controller used to expose only
/// `AsyncValue<List<VisualMatch>>`, which collapses four different endings
/// into two renderings: a non-empty list, or "empty" — and "empty" was doing
/// duty for *the classifier matched nothing*, *the classifier matched nothing
/// and the describer could not name it either*, and *nothing came back at
/// all*. A timeout had no representation whatsoever: `classifyFile` was
/// awaited unbounded, so a request that never returned left the spinner up
/// forever, which is precisely the "no infinite spinner" rule.
enum ScanOutcome {
  /// One match clearly ahead of the rest. Open it.
  confident,

  /// Several plausible candidates, none decisive. Show them and let the user
  /// choose — never silently pick the nearest.
  alternatives,

  /// The image held something, but it is not in the catalogue. The machine
  /// card (name + photo) is the honest answer.
  unknown,

  /// Nothing could be identified: not in the catalogue, and the describer had
  /// no name for it either.
  ///
  /// Read this as "no equipment was identified", NOT as "there is no
  /// equipment in the photo" — the app cannot know the second one, and a
  /// describer outage lands here too. That is why the rendered copy is
  /// "couldn't tell what that is" rather than "there is no machine here": the
  /// honest uncertainty has to survive an enum name that is more absolute
  /// than the state it labels.
  ///
  /// Distinct from [unknown], where the app CAN say what the machine is and
  /// only the catalogue is missing it. Telling a user their machine is
  /// missing from the catalogue when we never identified it would be a claim
  /// about our data that we have not earned.
  noEquipment,

  /// Recognition exceeded its bounded wait. Retryable, and the local fallback
  /// (if any) is still worth offering.
  timeout,

  /// Recognition itself failed — model missing, unreadable file, native
  /// error. Retryable.
  failed,
}

/// The result of one recognition attempt: what was found, and how it ended.
class ScanResult {
  const ScanResult({
    required this.outcome,
    this.matches = const [],
    this.answeredOffline = false,
  });

  const ScanResult.confident(List<VisualMatch> matches,
      {bool answeredOffline = false})
      : this(
          outcome: ScanOutcome.confident,
          matches: matches,
          answeredOffline: answeredOffline,
        );

  const ScanResult.alternatives(List<VisualMatch> matches,
      {bool answeredOffline = false})
      : this(
          outcome: ScanOutcome.alternatives,
          matches: matches,
          answeredOffline: answeredOffline,
        );

  const ScanResult.unknown() : this(outcome: ScanOutcome.unknown);
  const ScanResult.noEquipment() : this(outcome: ScanOutcome.noEquipment);
  const ScanResult.timeout() : this(outcome: ScanOutcome.timeout);
  const ScanResult.failed() : this(outcome: ScanOutcome.failed);

  final ScanOutcome outcome;

  /// Ranked, best first. Empty for every outcome except [ScanOutcome.confident]
  /// and [ScanOutcome.alternatives].
  final List<VisualMatch> matches;

  /// True when the on-device fallback answered because the cloud recogniser
  /// could not be reached.
  ///
  /// R2.2 state 12. Surfaced so a weaker answer reads as "we were offline"
  /// rather than as the app being bad at recognition — and so the user knows
  /// a retry on a connection is worth something.
  final bool answeredOffline;

  /// True when trying the same shot again could plausibly change the answer.
  ///
  /// [ScanOutcome.unknown] is deliberately absent: re-running the same image
  /// through the same model returns the same "not in the catalogue", so a
  /// retry button there would be a loop with a friendly label.
  bool get isRetryable =>
      outcome == ScanOutcome.timeout || outcome == ScanOutcome.failed;

  /// Whether this result should be written into the user's recognition
  /// history ("My machines").
  ///
  /// Only a confident answer. [ScanOutcome.alternatives] is the app saying
  /// "I am not sure, you pick" — filing its top candidate would record, as a
  /// machine the user identified, one they were never even asked about.
  ///
  /// A rule on the result rather than an `if` inside the page, because the
  /// page's own capture path cannot be driven from a host widget test (it
  /// needs a real camera file), so an `if` there is a decision no test can
  /// reach. Two widget tests written against it passed by writing nothing at
  /// all — the wrong reason.
  bool get isWorthRemembering => outcome == ScanOutcome.confident;

  /// The gap that separates "one answer" from "pick one of these".
  ///
  /// 0.15 is not tuned against a labelled set — it is a starting threshold,
  /// chosen so a leader has to be clearly ahead rather than merely first.
  /// Named and in one place so it can be tuned from evidence later instead of
  /// being re-invented at each call site.
  static const double confidentMargin = 0.15;

  /// Classifies a ranked match list into confident-vs-alternatives.
  ///
  /// Never returns [ScanOutcome.unknown] or [ScanOutcome.noEquipment]: an
  /// empty list means the CALLER must decide which of those two it is, and it
  /// needs the describer's answer to tell them apart.
  factory ScanResult.fromMatches(
    List<VisualMatch> ranked, {
    bool answeredOffline = false,
  }) {
    if (ranked.isEmpty) return const ScanResult.noEquipment();
    if (ranked.length == 1) {
      return ScanResult.confident(ranked, answeredOffline: answeredOffline);
    }
    final lead = ranked[0].confidence - ranked[1].confidence;
    return lead >= confidentMargin
        ? ScanResult.confident(ranked, answeredOffline: answeredOffline)
        : ScanResult.alternatives(ranked, answeredOffline: answeredOffline);
  }
}
