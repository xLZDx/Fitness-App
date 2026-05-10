import '../../cycle_aware/data/cycle_phase.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart';
import '../../personalisation/data/fitness_model.dart';
import '../../profile/data/profile_models.dart';
import '../../recovery/data/deload_detector.dart';
import 'workout_plan.dart';

/// Pure plan-builder. Combines:
///   - 34Q intake (reported injuries → contraindication tags)
///   - candidate exercise pool (free + premium catalog)
///   - personalisation profile (per-muscle Bayesian fitness scores)
///   - deload verdict (auto-pulls intensity if signals fire)
///   - optional cycle-phase hint (intensity multiplier)
///
/// Returns a single-day [GeneratedPlan] with 4–6 exercises ordered by
/// priority. No I/O; all inputs are passed in by the caller. The page
/// or background scheduler resolves the providers and feeds them here.
GeneratedPlan buildPlan({
  required List<ExerciseItem> candidatePool,
  required Iterable<Injury> reportedInjuries,
  required FitnessProfile profile,
  required DeloadVerdict deload,
  CyclePhase? cyclePhase,
  int targetMinutes = 45,
}) {
  final injuryList = reportedInjuries.toList();

  // 1. Filter for safety. Reuse the existing pure exercise filter so
  //    the plan never contains an exercise that conflicts with a logged
  //    injury — the entire moat.
  final safe = filterContraindicated(candidatePool, injuryList);

  // 2. Score each remaining exercise by adaptive priority. The fitness
  //    profile gives weakest-muscle-first ranking; novelty is broken by
  //    insertion order.
  final scored = [
    for (final ex in safe)
      (
        ex: ex,
        priority: 1.0 - profile.averageFor(ex.muscles),
      ),
  ]..sort((a, b) => b.priority.compareTo(a.priority));

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
  //    multiplicatively. Floor at 0.5, ceiling at 1.10.
  var factor = deload.suggestedVolumeFactor;
  if (cyclePhase != null) {
    factor *= hintFor(cyclePhase).intensityFactor;
  }
  factor = factor.clamp(0.5, 1.10).toDouble();

  // 5. Compose rationale string for transparency.
  final reasons = <String>[];
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
      reasons.add(
          'Filtered out $filteredOut exercise(s) that conflict with '
          'your reported conditions.');
    }
  }
  if (reasons.isEmpty) {
    reasons.add('Built from your latest difficulty ratings — '
        'weakest muscle groups first.');
  }

  return GeneratedPlan(
    title: deload.shouldDeload
        ? 'Deload day'
        : cyclePhase == CyclePhase.menstrual
            ? 'Easy session'
            : 'Adaptive session',
    estimatedMinutes: minutes,
    exercises: List.unmodifiable(picked),
    intensityFactor: factor,
    rationale: reasons.join(' '),
  );
}
