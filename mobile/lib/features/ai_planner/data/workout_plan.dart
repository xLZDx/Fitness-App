import '../../cycle_aware/data/cycle_phase.dart';
import '../../equipment/data/equipment_models.dart';
import '../../safety/data/eligibility.dart';
import '../../safety/data/health_flags.dart';

/// What a plan request produced.
///
/// Gate M, 2026-08-15. Before this, plan generation returned `GeneratedPlan`,
/// so "we are not going to give you a workout" had no shape to be returned in
/// and the app had no state in which it declined. Making refusal a variant
/// rather than a null or an empty exercise list means every caller has to
/// decide what to render for it — the compiler asks, once, at each site.
///
/// A nullable `GeneratedPlan?` would not have done this: the existing
/// `generatedPlanProvider` already returned null for "still loading", and
/// overloading that with "refused on safety grounds" is how a refusal ends up
/// rendering as a spinner.
sealed class PlanOutcome {
  const PlanOutcome();
}

/// A plan was produced.
final class PlanReady extends PlanOutcome {
  const PlanReady(this.plan);
  final GeneratedPlan plan;
}

/// No plan was produced, and why.
///
/// Carries the screening reasons rather than a rendered string: the message
/// belongs to the UI layer, which has the locale. A pure builder that returned
/// English prose would be untranslatable and untestable in the same stroke.
final class PlanRefused extends PlanOutcome {
  const PlanRefused(this.reasons);
  final List<EligibilityReason> reasons;
}

/// What kind of session this is, as a code rather than a heading.
///
/// The four values are not interchangeable labels: `reduced` is the screening
/// ceiling speaking and outranks the rest, which is why it is first in the
/// builder's own conditional and why nothing may reorder them casually.
enum PlanTitle { reduced, deload, easy, adaptive }

/// Why the plan looks the way it does — one code per statement, with its
/// numbers, and no prose.
///
/// F027. `PlanRefused` above already carries [EligibilityReason] for exactly
/// the reason stated in its doc: *"the message belongs to the UI layer, which
/// has the locale. A pure builder that returned English prose would be
/// untranslatable and untestable in the same stroke."* Every word of that
/// applied equally to the plan that DOES get built, and for months the two
/// halves of one file disagreed — refusal was typed, success was a
/// `reasons.join(' ')` of hand-composed English in a layer with no
/// `BuildContext`.
///
/// The consequence was not theoretical. A Russian user was shown the safety
/// ceiling — the single most important line the planner emits, the one that
/// says the app has NOT cleared them — in English.
///
/// A sealed hierarchy rather than a flat enum with side-car fields: the
/// arguments genuinely differ per case (a percentage, a count, a phase, a
/// restriction), and modelling that as one enum plus four nullable companions
/// is how a renderer ends up reading the wrong field for the wrong code.
sealed class PlanReason {
  const PlanReason();
}

/// The screen could not clear this user, so intensity is capped.
///
/// Emitted first and unconditionally. A user the screen could not clear must
/// not have to read past a deload note to find that out.
final class ScreeningCeilingReason extends PlanReason {
  const ScreeningCeilingReason(this.percent);

  /// The ceiling as a whole percentage, already rounded.
  final int percent;
}

/// Recovery signals fired and pulled the session's intensity down.
final class DeloadReason extends PlanReason {
  const DeloadReason(this.percent);
  final int percent;
}

/// The user's own self-report lowered the ceiling. Gate O: only downwards, and
/// only from what they said they feel.
final class CycleSelfReportReason extends PlanReason {
  const CycleSelfReportReason(this.report);
  final CycleSelfReport report;
}

/// Where the calendar puts them. A NOTE — nothing was changed because of it,
/// and the rendered text has to keep saying so.
final class CyclePhaseReason extends PlanReason {
  const CyclePhaseReason(this.phase);
  final CyclePhase phase;
}

/// The user declared a restriction the catalogue carries no tag for, so
/// nothing was filtered on that basis.
///
/// Stated rather than skipped: a plan silent about it reads as though it had
/// been screened for.
final class UntaggedRestrictionReason extends PlanReason {
  const UntaggedRestrictionReason(this.restriction);
  final MovementRestriction? restriction;
}

/// Exercises were removed because they conflict with a reported **injury**.
///
/// "Injury", not "condition", and the rendered string must not widen it:
/// `HealthHistory.conditions` reaches no filter at all, and claiming otherwise
/// told a user with diabetes that it had been screened for.
final class InjuryFilterReason extends PlanReason {
  const InjuryFilterReason(this.count);
  final int count;
}

/// Nothing else applied and there is no training history yet.
final class NoHistoryReason extends PlanReason {
  const NoHistoryReason();
}

/// Nothing else applied; the order came from the weekly set deficit.
final class DeficitOrderReason extends PlanReason {
  const DeficitOrderReason();
}

/// Generated workout plan — one day's worth of training.
class GeneratedPlan {
  const GeneratedPlan({
    required this.title,
    required this.estimatedMinutes,
    required this.exercises,
    required this.intensityFactor,
    required this.reasons,
  });

  final PlanTitle title;
  final int estimatedMinutes;
  final List<ExerciseItem> exercises;

  /// Effective volume vs baseline (0.5..1.1), and the budget this session was
  /// actually built against.
  ///
  /// Load-bearing, not decorative: `buildPlan` multiplies the target duration
  /// by it BEFORE filling the session. It used to be computed afterwards and
  /// only rendered, so a user under a deload was shown "intensity 60%" over
  /// exactly the session a well-recovered user got.
  ///
  /// Lowered by a deload verdict, by the screening ceiling, and by what the
  /// user says they feel today. The calendar cannot move it — see Gate O.
  final double intensityFactor;

  /// Why this plan was selected, in the order it should be read.
  ///
  /// Order is part of the contract, not an accident of composition: the
  /// screening ceiling comes first when present, because it is the line a user
  /// must not have to scroll past.
  final List<PlanReason> reasons;
}
