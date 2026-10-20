/// Age bands and the cautious selection policy attached to them.
///
/// ## Why this exists
///
/// Age was collected by the questionnaire (`PersonalInfo.birthYear`) and read
/// by nothing that chose exercises: a 15-year-old and a 78-year-old with the
/// same answers as a 30-year-old received byte-identical output. This file is
/// the one place that turns an age into a policy, and `SafetyContext` carries
/// the result to every recommending surface (plan, home suggestions, programme
/// builder) so a rule added here reaches all of them.
///
/// ## What it is NOT
///
/// Not a clinical statement. There are no medical thresholds here, no claim
/// that any age is unsafe for any exercise, and no diagnosis. The two bands are
/// a PRODUCT_HEURISTIC for "be more conservative by default":
///
///  * **minor** (< 18): no maximal-effort / 1RM-style work, an exercise
///    difficulty ceiling, a lower intensity and volume ceiling, fewer training
///    days, and an advisory to train with a qualified adult and to make sure a
///    parent or guardian knows about the plan.
///  * **senior** (>= 65): no maximal-effort work, no high-impact work, a
///    difficulty ceiling, a lower intensity ceiling, fewer training days (more
///    recovery spacing), balance/mobility work included, and an advisory to
///    check with a clinician when unsure.
///
/// An unknown age is [AgeBand.adult]: the app does not guess a band for a
/// person who did not answer.
///
/// ## Birth-year precision
///
/// The questionnaire stores a birth YEAR, never a month, so an age is one of
/// two values. Wherever an age restricts something, the boundary year resolves
/// on the cautious side: see [ageBandForPersonal] (minor band while the person
/// might still be 17, senior band from a year difference of 65) and
/// `PersonalInfo.lowestAgeAt` (the adults-only body scan).
library;

import '../../equipment/data/equipment_models.dart';
import '../../profile/data/profile_models.dart' show PersonalInfo;

/// The policy band an age falls in.
enum AgeBand { adult, minor, senior }

/// First age that is not a minor.
const int kAdultFromAge = 18;

/// First age of the senior band.
const int kSeniorFromAge = 65;

/// The band for [age], or [AgeBand.adult] when the age is unknown.
AgeBand ageBandFor(int? age) {
  if (age == null) return AgeBand.adult;
  if (age < kAdultFromAge) return AgeBand.minor;
  if (age >= kSeniorFromAge) return AgeBand.senior;
  return AgeBand.adult;
}

/// The band for a person whose age is known only as a birth YEAR.
///
/// The questionnaire never asked for the month, so the age is one of two
/// values. The boundary year is resolved on the cautious side at both edges:
/// the minor band applies while the person MIGHT still be under 18 (calendar
/// year difference of 18 or less, so someone born in December 2008 stays on the
/// minor path through the whole of 2026), and the senior band applies from a
/// year difference of 65, since either of the two possible ages is at or next
/// to the line. An unknown age is [AgeBand.adult], as before. [year] is
/// injectable for tests.
AgeBand ageBandForPersonal(PersonalInfo? personal, int year) {
  final lowest = personal?.lowestAgeAt(year);
  final highest = personal?.ageAt(year);
  if (lowest == null || highest == null) return AgeBand.adult;
  if (lowest < kAdultFromAge) return AgeBand.minor;
  if (highest >= kSeniorFromAge) return AgeBand.senior;
  return AgeBand.adult;
}

extension AgeBandPolicy on AgeBand {
  /// Whether any cautious rule applies.
  bool get isCautious => this != AgeBand.adult;

  /// Upper bound on the plan's intensity factor, or null for none.
  ///
  /// PRODUCT_HEURISTIC. Independent of the screening ceiling, which is about
  /// health answers: a healthy 15-year-old must never be told the app "has not
  /// cleared" them, so the two are applied separately.
  double? get intensityCap => switch (this) {
        AgeBand.adult => null,
        AgeBand.minor => 0.8,
        AgeBand.senior => 0.85,
      };

  /// Upper bound on training days per week, or null for none.
  ///
  /// For seniors this is the "longer recovery spacing" lever: three days a week
  /// always leaves a rest day between sessions. PRODUCT_HEURISTIC.
  int? get maxDaysPerWeek => switch (this) {
        AgeBand.adult => null,
        AgeBand.minor => 4,
        AgeBand.senior => 3,
      };

  /// Whether programme volume (sets per slot) is lowered.
  bool get conservativeVolume => isCautious;

  /// Whether a plan for this band must include balance/mobility work.
  bool get needsBalanceAndMobility => this == AgeBand.senior;

  /// Whether high-impact exercises are withheld.
  bool get avoidsHighImpact => this == AgeBand.senior;
}

/// Maximal-effort work: the powerlifting group and anything the catalogue marks
/// advanced (advanced barbell lifts, inversions, handstands).
bool isMaxEffortExercise(ExerciseItem e) =>
    e.vendorGroup == 'Powerlifting' || e.difficulty == ExerciseDifficulty.advanced;

final RegExp _highImpact = RegExp(
    r'jump|hop\b|hops\b|hopping|plyo|burpee|sprint|bound|skipping|clap push|tuck jump',
    caseSensitive: false);

/// High-impact work, by title: jumps, hops, burpees, sprints, bounds.
///
/// By title because the catalogue carries no impact field. Conservative on
/// purpose: a false positive only hides one exercise from a senior.
bool isHighImpactExercise(ExerciseItem e) => _highImpact.hasMatch(e.title);

final RegExp _balance = RegExp(
    r'balance|stork|tree pose|single[- ]leg stand|tai chi|heel[- ]to[- ]toe',
    caseSensitive: false);

/// Mobility, stretching, yoga/pilates and balance work.
bool isMobilityOrBalanceExercise(ExerciseItem e) =>
    e.isStretch ||
    e.vendorGroup == 'Yoga' ||
    e.vendorGroup == 'Stretching - Mobility' ||
    _balance.hasMatch(e.title);

/// Why an exercise is withheld from a cautious selection, or null if it is not.
enum SelectionBlock { maxEffort, highImpact }

/// The cautious-selection verdict for one exercise.
///
/// [gentle] is the goal/ability-driven variant (comeback and flexibility goals,
/// "cannot do the basics"): max-effort work only. The age band adds high-impact
/// work for seniors.
SelectionBlock? selectionBlockFor(
  ExerciseItem e, {
  required AgeBand ageBand,
  required bool gentle,
}) {
  if ((ageBand.isCautious || gentle) && isMaxEffortExercise(e)) {
    return SelectionBlock.maxEffort;
  }
  if (ageBand.avoidsHighImpact && isHighImpactExercise(e)) {
    return SelectionBlock.highImpact;
  }
  return null;
}
