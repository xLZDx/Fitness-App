import '../../equipment/data/equipment_models.dart';
import '../../safety/data/eligibility.dart';

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

/// Generated workout plan — one day's worth of training.
class GeneratedPlan {
  const GeneratedPlan({
    required this.title,
    required this.estimatedMinutes,
    required this.exercises,
    required this.intensityFactor,
    required this.rationale,
  });

  final String title;
  final int estimatedMinutes;
  final List<ExerciseItem> exercises;

  /// Effective intensity vs baseline (0.5..1.1). Lower when recovery
  /// signals (deload, cycle phase, low compliance) suggest it.
  final double intensityFactor;

  /// Why this plan was selected (read out by the page so users trust it).
  final String rationale;
}
