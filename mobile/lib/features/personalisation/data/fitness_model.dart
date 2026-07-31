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
/// Higher score → user is comfortable; ranker upweights novel /
/// progression-worthy options. Lower score → ranker downweights to
/// give the muscle group recovery time.
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
