import '../../equipment/data/equipment_models.dart';
import 'volume_ledger.dart';

/// Re-rank the For-You feed by what the user has trained least this week.
///
/// The file's own doc said exactly that before the code did. It ranked by
/// `1 - profile.averageFor(muscles)` — an inverted difficulty rating — which
/// answers a different question: not "what has been neglected" but "what did
/// this person find hard". Those come apart the moment they disagree, and the
/// direction they disagreed in surfaced more of whatever the user could not
/// tolerate. Gate K replaced the measure; this consumes it.
///
/// Strategy:
///   - Each candidate gets a 0..1 priority from the weekly set deficit of the
///     muscles it is FOR (`exercisePriority`).
///   - An exercise with no muscle attribution gets no priority at all and
///     falls to the end, rather than scoring mid-range and tying with every
///     muscle the user has never trained.
///   - Tie-break by novelty (less-recently-logged ranks higher) when
///     [recentExerciseIds] is provided, then by input order.
///   - Cold start returns input order: an empty deficit map is "nothing
///     known", and the filtered order is the honest answer to that.
List<ExerciseItem> rankForYou(
  List<ExerciseItem> candidates, {
  required Map<String, double> deficit,
  Set<String> recentExerciseIds = const {},
}) {
  if (candidates.isEmpty) return candidates;
  if (deficit.isEmpty) return List.unmodifiable(candidates);

  double? priority(ExerciseItem ex) {
    final p = exercisePriority(
      (primary: ex.primaryMuscles, secondary: ex.muscles),
      deficit,
    );
    if (p == null) return null;
    // Lightly upweight novel exercises (not in the last-7 list).
    return (recentExerciseIds.contains(ex.id) ? p : p + 0.05).clamp(0.0, 1.5);
  }

  // Indexed so the sort is a total order rather than relying on `List.sort`
  // being stable, which Dart does not guarantee. Without this, every exercise
  // in the (large) tie class at cold start comes back in an arbitrary order
  // that changes between runs and cannot be reproduced from a bug report.
  final scored = [
    for (var i = 0; i < candidates.length; i++)
      (ex: candidates[i], p: priority(candidates[i]), i: i),
  ]..sort((a, b) {
      // Unattributed last, in input order — "no signal" is not "no deficit".
      if (a.p == null || b.p == null) {
        if (a.p == null && b.p == null) return a.i.compareTo(b.i);
        return a.p == null ? 1 : -1;
      }
      final byPriority = b.p!.compareTo(a.p!);
      return byPriority != 0 ? byPriority : a.i.compareTo(b.i);
    });

  return List.unmodifiable(scored.map((e) => e.ex));
}
