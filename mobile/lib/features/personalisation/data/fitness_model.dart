import '../../workouts/data/workout_log.dart';

/// Adaptive-personalisation kernel.
///
/// We maintain a per-muscle-group "fitness score" updated from each
/// post-workout difficulty rating. Score is the Beta-distribution mean
/// of (good, total) pseudo-counts where:
///   - tooEasy   → +1 to "good"      (we should push harder here)
///   - justRight → +0.5 to "good"
///   - tooHard   → +0    (we should back off here)
///
/// Higher score → user is comfortable. Lower score → the user has been
/// reporting this group as too hard.
///
/// What the ranker DOES with that is deliberately not asserted here. This
/// comment used to finish "ranker upweights novel / progression-worthy
/// options … lower score → ranker downweights to give the muscle group
/// recovery time", which is the exact opposite of what
/// [FitnessProfile.adaptivePriorityFor] has always computed. A reader had no
/// way to tell which of the two was the intent and which was the bug. See that
/// method: the disagreement is real, it is a product decision, and it is
/// recorded there in one place instead of being asserted differently in three.
///
/// Initialising with `(good=2, total=4)` (Beta(2,2) prior) gives a
/// neutral 0.5 starting score so brand-new users aren't biased.
///
/// All pure. No DB, no I/O.
class MuscleFitness {
  const MuscleFitness({
    required this.muscle,
    required this.good,
    required this.total,
  });

  final String muscle;
  final double good;
  final double total;

  double get score => total <= 0 ? 0.5 : good / total;

  /// 95% credibility bounds — lo / hi. Used to fade in the model only
  /// after enough evidence accumulates.
  ({double lo, double hi}) credibilityBounds() {
    if (total < 4) {
      // No data — return wide bound centred on neutral.
      return (lo: 0.10, hi: 0.90);
    }
    // Approximate Beta(good, total-good) 95% interval via Normal.
    final mean = score;
    final variance = (mean * (1 - mean)) / (total + 1);
    final stddev = _sqrt(variance);
    return (
      lo: (mean - 1.96 * stddev).clamp(0, 1),
      hi: (mean + 1.96 * stddev).clamp(0, 1),
    );
  }
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  // Newton-Raphson 6 iterations is plenty for our precision.
  var g = x / 2;
  for (var i = 0; i < 6; i++) {
    g = 0.5 * (g + x / g);
  }
  return g;
}

/// Aggregate state: one entry per muscle group the user has ever logged.
class FitnessProfile {
  const FitnessProfile({required this.byMuscle});

  final Map<String, MuscleFitness> byMuscle;

  static FitnessProfile get empty => const FitnessProfile(byMuscle: {});

  MuscleFitness scoreFor(String muscle) =>
      byMuscle[muscle] ?? MuscleFitness(muscle: muscle, good: 2, total: 4);

  /// Average score across the named muscles. Used by the ranker for
  /// composite-movement (squat works quads+glutes, etc.).
  double averageFor(Iterable<String> muscles) {
    final list = muscles.toList();
    if (list.isEmpty) return 0.5;
    var sum = 0.0;
    for (final m in list) {
      sum += scoreFor(m).score;
    }
    return sum / list.length;
  }

  /// How strongly an exercise working [muscles] should be surfaced, 0..1.
  ///
  /// **One definition.** This arithmetic was written out twice — in
  /// `for_you_ranker.dart` and again in `ai_planner/data/plan_builder.dart` —
  /// and the second copy is not referenced by any document that discusses the
  /// first. A change made to one would have silently left the other ranking the
  /// opposite way, on a surface nobody was looking at.
  ///
  /// **The direction is contested and has NOT been changed here.** What ships,
  /// and what this returns, is `1 - score`: a muscle group the user keeps
  /// rating "too hard" is surfaced MORE, on the reading that you are weakest at
  /// what you struggle with and weakness is what training should attack.
  ///
  /// The file that DEFINES the score says the opposite, in four places: tooEasy
  /// means "we should push harder here", tooHard means "we should back off
  /// here", and — directly about this function — "Lower score → ranker
  /// downweights to give the muscle group recovery time".
  ///
  /// Both are coherent training philosophies, which is why this is a decision
  /// and not a defect to be quietly fixed. It is recorded rather than resolved
  /// so that whoever settles it does so on purpose and in one place.
  double adaptivePriorityFor(Iterable<String> muscles) =>
      1.0 - averageFor(muscles);
}

/// Pure builder: replays the user's logs into a [FitnessProfile].
///
/// Decay is applied so older sessions (>30d) gradually contribute less —
/// otherwise a beginner who logs 100 sessions can never recover from an
/// early "tooHard" verdict on bench press.
FitnessProfile buildProfile(
  Iterable<WorkoutLogEntry> logs, {
  required Map<String, List<String>> musclesByExerciseId,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final acc = <String, MuscleFitness>{};
  for (final log in logs) {
    if (log.difficulty == null) continue;
    final muscles = musclesByExerciseId[log.exerciseId] ?? const [];
    if (muscles.isEmpty) continue;

    final ageDays = t.difference(log.completedAt).inDays;
    // Linear decay over 90 days, floor at 0.2.
    final w = (1.0 - (ageDays / 90)).clamp(0.2, 1.0).toDouble();

    final delta = switch (log.difficulty!) {
      DifficultyRating.tooEasy => 1.0,
      DifficultyRating.justRight => 0.5,
      DifficultyRating.tooHard => 0.0,
    };
    for (final m in muscles) {
      final cur = acc[m] ?? MuscleFitness(muscle: m, good: 2, total: 4);
      acc[m] = MuscleFitness(
        muscle: m,
        good: cur.good + (delta * w),
        total: cur.total + (1.0 * w),
      );
    }
  }
  return FitnessProfile(byMuscle: acc);
}
