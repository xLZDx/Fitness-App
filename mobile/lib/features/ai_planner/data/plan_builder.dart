import 'dart:math' as math;

import '../../cycle_aware/data/cycle_phase.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart' show isContraindicated;
import '../../personalisation/data/recommendation_hints.dart';
import '../../personalisation/data/volume_ledger.dart';
import '../../recovery/data/deload_detector.dart';
import '../../safety/data/age_policy.dart';
import '../../safety/data/eligibility.dart';
import '../../training_context/data/training_context.dart'
    show TrainingContext, contextAffinity;
import 'workout_plan.dart';

/// Pure plan-builder. Combines:
///   - the pre-exercise screening verdict (can a plan be produced at all)
///   - 34Q intake (reported injuries → contraindication tags)
///   - candidate exercise pool (free + premium catalog)
///   - weekly per-muscle set deficit (what has been trained least)
///   - deload verdict (auto-pulls intensity if signals fire)
///   - the cycle state (a NOTE) and the user's own self-report (the only
///     cycle input that changes a dose — see `cycle_phase.dart`)
///
/// Returns [PlanReady] with a single-day plan of 4–6 exercises ordered by
/// priority, or [PlanRefused]. No I/O; all inputs are passed in by the caller.
/// The page or background scheduler resolves the providers and feeds them here.
///
/// [safety] is required and has no default. A default would be a decision
/// about what happens to a caller that forgot to screen, and the only two
/// candidates are "block everyone who has not been wired up yet" (breaks every
/// existing call site silently) and "let them through" (which is the bug this
/// gate exists to remove). Making it required moves that decision to each call
/// site, where the compiler asks about it once.
PlanOutcome buildPlan({
  required List<ExerciseItem> candidatePool,
  required Map<String, double> deficit,
  required DeloadVerdict deload,
  required SafetyContext safety,
  CycleState cycle = const CycleUnknown(CycleUnavailable.notTracked),
  CycleSelfReport? cycleSelfReport,
  int targetMinutes = 45,

  /// What the questionnaire says about the mix and starting volume (goal,
  /// activity level, sleep/stress, basics). [RecommendationHints.none] keeps
  /// the pre-hints behaviour for callers without a profile.
  RecommendationHints hints = RecommendationHints.none,

  /// The stated training context, or null (never asked / skipped). The caller
  /// has already narrowed [candidatePool] and [safety] to it with
  /// `narrowToTrainingContext` / `safetyContextForTrainingContext`; this only
  /// makes the plan say so.
  TrainingContext? trainingContext,
}) {
  // 0. The floor. Before any pool is read, any deficit consulted, any
  //    exercise scored — because a refusal that depends on the catalogue
  //    having loaded is a refusal that can be raced.
  //
  //    Gate N widened what can stop a plan: the screening still can, and so now
  //    can a clinician's stated advice against exercise and unexpired
  //    post-operative restrictions. All three are the user's own words, none is
  //    inferred, and they arrive through one type.
  if (!safety.allowsAnyTraining) {
    return PlanRefused(safetyReasonsFrom(safety));
  }

  final injuryList = safety.injuries;

  // 1. Filter for safety. Gate N replaced the injury-only filter with the
  //    eligibility layer, so the same pool that the feed, the programme
  //    builder and the catalogue use is the pool here — injuries, normalised
  //    movement restrictions and equipment, decided once.
  final safe = recommendableAtLevel(
      eligibleExercises(candidatePool, safety), safety);

  // 2. Score each remaining exercise by adaptive priority; novelty is broken
  //    by insertion order.
  //
  //    Priority is the weekly SET DEFICIT of the muscles the exercise is for,
  //    not an inverted difficulty rating. The old expression asked "what did
  //    this person find hard" and used the answer to decide what to show them
  //    more of; this asks "what have they trained least", which is the
  //    question the plan is actually trying to answer and the one a difficulty
  //    rating was never evidence about.
  final scored = [
    for (var i = 0; i < safe.length; i++)
      (
        ex: safe[i],
        priority: exercisePriority(
          (primary: safe[i].primaryMuscles, secondary: safe[i].muscles),
          deficit,
        ),
        i: i,
        // How well the item suits the stated training context (0 without
        // one). Only a tie-break below: the deficit stays the primary key, so
        // the rationale about the user's history remains true.
        affinity: contextAffinity(safe[i], trainingContext, null),
      ),
  ]..sort((a, b) {
      // Unattributed exercises last. 182 rows carry no muscle tag; when they
      // scored mid-range they tied with every untrained muscle and a greedy
      // top-N could fill a whole session from them while the rationale
      // claimed the plan came from the user's own history.
      if (a.priority == null || b.priority == null) {
        if (a.priority == null && b.priority == null) {
          final byAffinity = b.affinity.compareTo(a.affinity);
          return byAffinity != 0 ? byAffinity : a.i.compareTo(b.i);
        }
        return a.priority == null ? 1 : -1;
      }
      final byPriority = b.priority!.compareTo(a.priority!);
      if (byPriority != 0) return byPriority;
      // Equal deficit: the training context decides (best fit first), then the
      // explicit index tie-break: `List.sort` is not stable in Dart, and the
      // comment here used to claim novelty was "broken by insertion order".
      final byAffinity = b.affinity.compareTo(a.affinity);
      return byAffinity != 0 ? byAffinity : a.i.compareTo(b.i);
    });

  // 3. Decide the factor — recovery + cycle self-report + the screening
  //    ceiling. Floor at 0.5, ceiling at 1.10, lowered to
  //    `safety.intensityCeiling` when the screen could not clear the user.
  //
  //    This used to run AFTER the session was filled, which is why it did
  //    nothing: the greedy fill spent the full `targetMinutes` budget, and the
  //    factor was carried to the screen and rendered as "intensity 80%" over a
  //    session identical to the one a well-recovered user got. The number was
  //    true about what the app had decided and false about what it handed over.
  // `isFinite` first, and NOT because clamp would propagate a NaN — measured,
  // it does not: `double.nan.clamp(0.5, 1.10)` returns 1.10. That is the
  // problem. A factor that is not a real number would come out of the clamp as
  // the planner's MAXIMUM, so "we could not work out a recovery factor" would
  // silently read as "train ten per cent harder than baseline" — a fail-open
  // in the one place in this file whose job is to fail closed.
  //
  // `DeloadVerdict` now asserts the invariant, which makes a bad const literal
  // a compile error and a bad runtime value throw in debug. Asserts are
  // stripped in release, so the release-safe half lives here.
  //
  // 1.0 is not an invented value: it is exactly what `detectDeload` returns
  // for "no signal fired", i.e. no change, and it stays subject to
  // `safety.intensityCeiling` below like any other factor.
  var factor =
      deload.suggestedVolumeFactor.isFinite ? deload.suggestedVolumeFactor : 1.0;
  // Gate O: the calendar phase no longer multiplies anything. What the user
  // says they feel does, and only downwards.
  final cycleAdjustment = adjustmentFor(cycleSelfReport);
  // `?? 1.10` is the planner's own ceiling, unchanged. The screen only ever
  // LOWERS it — a verdict that raised the ceiling would be a safety type
  // prescribing more work, which is not a thing this file will let it do.
  var ceiling = 1.10;
  for (final opinion in [safety.intensityCeiling, cycleAdjustment.intensityCeiling]) {
    if (opinion != null && opinion < ceiling) ceiling = opinion;
  }
  // The age band and the answer-driven starting-volume cap are separate from
  // the screening ceiling on purpose: the screening ceiling's wording says the
  // app has not cleared the user's HEALTH answers, which is false for a healthy
  // 15-year-old. Both only ever lower the factor.
  final baseFactor = factor.clamp(0.5, ceiling).toDouble();
  final ageCap = safety.ageBand.intensityCap;
  if (ageCap != null && ageCap < ceiling) ceiling = ageCap;
  final hintCap = hints.volumeCap;
  if (hintCap != null && hintCap < ceiling) ceiling = hintCap;
  factor = factor.clamp(0.5, ceiling).toDouble();

  // 4. Greedy fill against a budget the factor has already shrunk.
  //
  //    The session never exceeds the minutes the user stated: the budget is
  //    capped by `targetMinutes` itself. (It used to allow `budget + 5`, so a
  //    45-minute answer could be handed a 50-minute plan.) The 10-minute floor
  //    on the budget still stops a low factor over a short target from
  //    producing an empty plan.
  //
  //    Goal-driven items are RESERVED first, in score order, so the mix the
  //    user's answers ask for (mobility, conditioning, a senior's balance
  //    work) is present whenever the eligible pool has such an item that fits.
  final budget = math.max(10, (targetMinutes * factor).round());
  final limit = math.min(budget, targetMinutes);
  final chosen = <int>{}; // indexes into `scored`
  var minutes = 0;
  bool fits(ExerciseItem e) => minutes + e.durationMinutes <= limit;
  int? reserve(bool Function(ExerciseItem) wanted) {
    for (var i = 0; i < scored.length; i++) {
      final ex = scored[i].ex;
      if (chosen.contains(i) || !wanted(ex) || !fits(ex)) continue;
      chosen.add(i);
      minutes += ex.durationMinutes;
      return i;
    }
    return null;
  }

  final mixes = <GoalMix>[];
  final senior = safety.ageBand.needsBalanceAndMobility;
  if (hints.wantsMobility) {
    if (reserve((e) => e.isStretch) != null) {
      mixes.add(GoalMix.mobility);
      if (senior) mixes.add(GoalMix.seniorBalance);
    }
  } else if (senior) {
    if (reserve(isMobilityOrBalanceExercise) != null) {
      mixes.add(GoalMix.seniorBalance);
    }
  }
  if (hints.wantsConditioning) {
    if (reserve(isConditioningExercise) != null) mixes.add(GoalMix.conditioning);
  }
  // Diversity: a first pass takes the best-ranked exercise per distinct first
  // primary muscle (an untagged exercise is its own group), counting muscles
  // already covered by the reserved items; only then are the remaining slots
  // filled from the rest in the same sorted order. The sort above (deficit
  // first) still decides which muscle and which exercise comes first.
  String muscleGroup(ExerciseItem e) =>
      e.primaryMuscles.isEmpty ? 'id:${e.id}' : e.primaryMuscles.first;
  final usedGroups = <String>{
    for (final i in chosen) muscleGroup(scored[i].ex),
  };
  for (var i = 0; i < scored.length && chosen.length < 6; i++) {
    if (chosen.contains(i) || !fits(scored[i].ex)) continue;
    if (!usedGroups.add(muscleGroup(scored[i].ex))) continue;
    chosen.add(i);
    minutes += scored[i].ex.durationMinutes;
  }
  for (var i = 0; i < scored.length && chosen.length < 6; i++) {
    if (chosen.contains(i) || !fits(scored[i].ex)) continue;
    chosen.add(i);
    minutes += scored[i].ex.durationMinutes;
  }
  final picked = [for (final i in (chosen.toList()..sort())) scored[i].ex];

  // 5. State the reasons, as codes.
  //
  //    F027: this block used to compose English prose, in a pure data layer
  //    with no `BuildContext` and therefore no locale — so a Russian user read
  //    the safety ceiling, the most important line here, in English. The
  //    sibling type in this very file (`PlanRefused`) had carried typed
  //    reasons since Gate M for exactly that argument; only the success path
  //    disagreed with it.
  //
  //    Order is the contract. The ceiling is first and unconditional.
  final reasons = <PlanReason>[];
  if (safety.intensityCeiling != null) {
    reasons.add(
        ScreeningCeilingReason((safety.intensityCeiling! * 100).round()));
  }
  if (deload.shouldDeload) {
    reasons.add(DeloadReason((factor * 100).round()));
  }
  if (cycleAdjustment.intensityCeiling != null && cycleSelfReport != null) {
    // Keyed off the self-report rather than off a rendered string. The old
    // `cycleAdjustment.rationale.isNotEmpty` test was asking a text field
    // whether an adjustment had happened, which made the English load-bearing
    // for control flow as well as for display.
    reasons.add(CycleSelfReportReason(cycleSelfReport));
  }
  if (cycle.phase case final phase?) {
    // A note, not a prescription — the rendered text has to keep saying that
    // nothing was changed because of it.
    reasons.add(CyclePhaseReason(phase));
  }
  for (final advisory in safety.advisories) {
    reasons.add(advisory.reason == BlockReason.unscreenableRestriction
        ? UntaggedRestrictionReason(advisory.restriction)
        : SafetyAdvisoryReason(advisory));
  }
  // Only what the injuries themselves removed. `candidatePool - safe` also
  // counted equipment, age-policy and movement-restriction removals, so the
  // sentence "conflicts with an injury you reported" was false for most users.
  if (injuryList.isNotEmpty) {
    final byInjury =
        candidatePool.where((e) => isContraindicated(e, injuryList)).length;
    if (byInjury > 0) {
      reasons.add(InjuryFilterReason(byInjury));
    }
  }
  for (final mix in mixes) {
    reasons.add(GoalMixReason(mix));
  }
  // Said only when the answer-driven cap really lowered the factor, and not
  // when the age cap is the tighter one (the age advisory already says so).
  if (hintCap != null &&
      hints.volumeCapCause != null &&
      factor < baseFactor - 1e-9 &&
      hintCap <= (ageCap ?? 2.0)) {
    reasons.add(VolumeCapReason((factor * 100).round(), hints.volumeCapCause!));
  }
  if (reasons.isEmpty) {
    // The fallback used to read "Built from your latest difficulty ratings —
    // weakest muscle groups first", and both halves were wrong: the builder
    // never read a difficulty rating for ordering, and "weakest" was a claim
    // about strength nothing here measures. The two codes say what the code
    // does, and which one fires is still decided here rather than in the UI —
    // "do we have history yet" is the builder's question.
    reasons.add(deficit.isEmpty
        ? const NoHistoryReason()
        : const DeficitOrderReason());
  }

  if (trainingContext != null) reasons.add(TrainingContextReason(trainingContext));

  return PlanReady(GeneratedPlan(
    title: safety.intensityCeiling != null
        ? PlanTitle.reduced
        : deload.shouldDeload
            ? PlanTitle.deload
            : cycleSelfReport == CycleSelfReport.significantSymptoms
                ? PlanTitle.easy
                : PlanTitle.adaptive,
    estimatedMinutes: minutes,
    exercises: List.unmodifiable(picked),
    intensityFactor: factor,
    reasons: List.unmodifiable(reasons),
  ));
}
