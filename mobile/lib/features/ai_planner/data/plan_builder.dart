import 'dart:math' as math;

import '../../cycle_aware/data/cycle_phase.dart';
import '../../equipment/data/equipment_models.dart';
import '../../personalisation/data/volume_ledger.dart';
import '../../recovery/data/deload_detector.dart';
import '../../safety/data/eligibility.dart';
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
  final safe = eligibleExercises(candidatePool, safety);

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
      ),
  ]..sort((a, b) {
      // Unattributed exercises last, in catalogue order. 182 rows carry no
      // muscle tag; when they scored mid-range they tied with every untrained
      // muscle and a greedy top-N could fill a whole session from them while
      // the rationale claimed the plan came from the user's own history.
      if (a.priority == null || b.priority == null) {
        if (a.priority == null && b.priority == null) return a.i.compareTo(b.i);
        return a.priority == null ? 1 : -1;
      }
      final byPriority = b.priority!.compareTo(a.priority!);
      // Explicit index tie-break: `List.sort` is not stable in Dart, and the
      // comment here used to claim novelty was "broken by insertion order".
      return byPriority != 0 ? byPriority : a.i.compareTo(b.i);
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
  var factor = deload.suggestedVolumeFactor;
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
  factor = factor.clamp(0.5, ceiling).toDouble();

  // 4. Greedy fill, against a budget the factor has already shrunk (with the
  //    same small buffer so we don't overshoot). A 0.5 factor now produces
  //    roughly half a session rather than a full one with a smaller number
  //    printed above it.
  //
  //    The 10-minute floor is what stops a low factor over a short target
  //    from producing an empty plan — which would be a refusal with no
  //    reason attached, the failure mode Gate M exists to end.
  final budget = math.max(10, (targetMinutes * factor).round());
  final picked = <ExerciseItem>[];
  var minutes = 0;
  for (final entry in scored) {
    if (minutes + entry.ex.durationMinutes > budget + 5) {
      continue;
    }
    picked.add(entry.ex);
    minutes += entry.ex.durationMinutes;
    if (picked.length >= 6) break;
  }

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
    reasons.add(UntaggedRestrictionReason(advisory.restriction));
  }
  if (injuryList.isNotEmpty) {
    final filteredOut = candidatePool.length - safe.length;
    if (filteredOut > 0) {
      reasons.add(InjuryFilterReason(filteredOut));
    }
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
