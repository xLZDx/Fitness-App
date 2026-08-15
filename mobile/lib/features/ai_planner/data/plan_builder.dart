import '../../cycle_aware/data/cycle_phase.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart';
import '../../personalisation/data/volume_ledger.dart';
import '../../profile/data/profile_models.dart';
import '../../recovery/data/deload_detector.dart';
import '../../safety/data/par_q.dart';
import 'workout_plan.dart';

/// Pure plan-builder. Combines:
///   - the pre-exercise screening verdict (can a plan be produced at all)
///   - 34Q intake (reported injuries → contraindication tags)
///   - candidate exercise pool (free + premium catalog)
///   - weekly per-muscle set deficit (what has been trained least)
///   - deload verdict (auto-pulls intensity if signals fire)
///   - optional cycle-phase hint (intensity multiplier)
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
  required Iterable<Injury> reportedInjuries,
  required Map<String, double> deficit,
  required DeloadVerdict deload,
  required SafetyVerdict safety,
  CyclePhase? cyclePhase,
  int targetMinutes = 45,
}) {
  // 0. The floor. Before any pool is read, any deficit consulted, any
  //    exercise scored — because a refusal that depends on the catalogue
  //    having loaded is a refusal that can be raced.
  if (!safety.allowsTraining) {
    return PlanRefused(List.unmodifiable(safety.reasons));
  }

  final injuryList = reportedInjuries.toList();

  // 1. Filter for safety. Reuse the existing pure exercise filter so
  //    the plan never contains an exercise that conflicts with a logged
  //    injury — the entire moat.
  final safe = filterContraindicated(candidatePool, injuryList);

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

  // 3. Greedy fill to the target duration cap (with a small safety
  //    buffer so we don't overshoot).
  final picked = <ExerciseItem>[];
  var minutes = 0;
  for (final entry in scored) {
    if (minutes + entry.ex.durationMinutes > targetMinutes + 5) {
      continue;
    }
    picked.add(entry.ex);
    minutes += entry.ex.durationMinutes;
    if (picked.length >= 6) break;
  }

  // 4. Apply intensity factor — recovery + cycle phase compose
  //    multiplicatively. Floor at 0.5, ceiling at 1.10, lowered to
  //    `safety.intensityCeiling` when the screen could not clear the user.
  var factor = deload.suggestedVolumeFactor;
  if (cyclePhase != null) {
    factor *= hintFor(cyclePhase).intensityFactor;
  }
  // `?? 1.10` is the planner's own ceiling, unchanged. The screen only ever
  // LOWERS it — a verdict that raised the ceiling would be a safety type
  // prescribing more work, which is not a thing this file will let it do.
  final screened = safety.intensityCeiling;
  final ceiling = screened != null && screened < 1.10 ? screened : 1.10;
  factor = factor.clamp(0.5, ceiling).toDouble();

  // 5. Compose rationale string for transparency.
  final reasons = <String>[];
  if (safety.decision == SafetyDecision.restricted) {
    // First, and unconditionally. A user the screen could not clear must not
    // have to read past a deload note to find out that the app has not
    // cleared them — and this line must not be the one that gets dropped
    // because some other reason fired.
    reasons.add('Your health screening answers mean this app has not cleared '
        'you for unrestricted exercise, so intensity is capped at '
        '${((safety.intensityCeiling ?? 1.0) * 100).round()}%. Talk to a doctor or a '
        'qualified exercise professional before training harder.');
  }
  if (deload.shouldDeload) {
    reasons.add('Recovery signals are firing — intensity pulled to '
        '${(factor * 100).round()}%.');
  }
  if (cyclePhase != null) {
    reasons.add(hintFor(cyclePhase).headline);
  }
  if (injuryList.isNotEmpty) {
    final filteredOut = candidatePool.length - safe.length;
    if (filteredOut > 0) {
      // "injuries", not "conditions". `filterContraindicated` is passed
      // `injuryList` and nothing else; `HealthHistory.conditions` is a
      // separate field that reaches no filter at all. Claiming otherwise
      // told a user with diabetes and hypertension that both had been
      // screened for, which is the one direction a safety claim must never
      // be wrong in.
      reasons.add(
          'Filtered out $filteredOut exercise(s) that conflict with '
          'an injury you reported.');
    }
  }
  if (reasons.isEmpty) {
    // This used to read "Built from your latest difficulty ratings — weakest
    // muscle groups first", and both halves were wrong. The builder never read
    // a difficulty rating for ordering, and "weakest" was a claim about
    // strength that nothing here measures. It now says what the code does.
    reasons.add(deficit.isEmpty
        ? 'A starting session from your available equipment — '
            'log a few workouts and this will follow what you train least.'
        : 'Ordered by the muscle groups you have trained least this week.');
  }

  return PlanReady(GeneratedPlan(
    title: safety.decision == SafetyDecision.restricted
        ? 'Reduced session'
        : deload.shouldDeload
            ? 'Deload day'
            : cyclePhase == CyclePhase.menstrual
                ? 'Easy session'
                : 'Adaptive session',
    estimatedMinutes: minutes,
    exercises: List.unmodifiable(picked),
    intensityFactor: factor,
    rationale: reasons.join(' '),
  ));
}
