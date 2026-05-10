import '../../equipment/data/equipment_models.dart';
import 'fitness_model.dart';

/// Re-rank the For-You feed using the user's [FitnessProfile].
///
/// Strategy:
///   - Each candidate exercise gets a 0..1 priority.
///   - Priority = (1 - profile.averageFor(muscles)) — i.e. muscles the
///     user is "weakest in" surface higher. This is the Freeletics-style
///     adaptive loop the assessment calls for.
///   - Tie-break by exercise novelty (less-recently-logged ranks higher)
///     when [recentExerciseIds] is provided.
///   - Stable for empty / cold-start profiles (returns input order).
List<ExerciseItem> rankForYou(
  List<ExerciseItem> candidates, {
  required FitnessProfile profile,
  Set<String> recentExerciseIds = const {},
}) {
  if (candidates.isEmpty) return candidates;
  if (profile.byMuscle.isEmpty) return List.unmodifiable(candidates);

  double priority(ExerciseItem ex) {
    final muscleScore = profile.averageFor(ex.muscles);
    // Invert: weaker muscle group = higher priority.
    var p = 1.0 - muscleScore;
    // Lightly upweight novel exercises (not in the last-7 list).
    if (!recentExerciseIds.contains(ex.id)) {
      p += 0.05;
    }
    return p.clamp(0, 1.5);
  }

  final scored = [
    for (final ex in candidates) (ex: ex, p: priority(ex)),
  ]..sort((a, b) => b.p.compareTo(a.p));

  return List.unmodifiable(scored.map((e) => e.ex));
}
