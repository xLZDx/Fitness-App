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
/// **This score does not decide what to train.** It once did, through
/// `adaptivePriorityFor`, and the direction was argued over at length — this
/// comment asserted one answer while the code computed the other. The argument
/// was the wrong one: a difficulty rating is evidence about how a dose landed,
/// and no sign convention turns it into evidence about which muscle has been
/// neglected. Those are different questions with different observables.
///
/// Selection reads `volume_ledger.dart` — sets actually performed.
///
/// **Nothing consumes this today.** The paragraph above used to end "this score
/// keeps the job it can do, which is telling `progression.dart` whether to move
/// the load", and `progression.dart` does not import this file: it reads
/// `DifficultyRating` off the last logs directly. `fitnessProfileProvider` has
/// no watcher either. Kept, tested and stated as unconsumed rather than
/// described as load-bearing — the claim was the defect, not the code.
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

  // `credibilityBounds()` was here, and with it a hand-rolled `_sqrt`.
  //
  // Both are deleted rather than fixed. The method's own documentation said it
  // was "used to fade in the model only after enough evidence accumulates" and
  // nothing called it — there was no fade-in, in this file or anywhere else.
  //
  // The `_sqrt` under it was wrong as well, which is the part worth recording:
  // six Newton-Raphson iterations seeded at `x / 2` do not converge for small
  // inputs, and small inputs are the only ones this had. For a variance of
  // 0.0025 it returned 0.0543 against a true 0.05 — an 8.6% error, growing as
  // the input shrinks, in an interval whose whole purpose was to say how
  // confident to be. "6 iterations is plenty for our precision" was an
  // assertion nobody had measured, and `dart:math` has had `sqrt` all along.
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

  /// **Withdrawn 2026-08-15.** This class no longer answers "what should be
  /// trained next".
  ///
  /// `adaptivePriorityFor` returned `1 - averageFor(muscles)`, turning a
  /// post-set difficulty rating into a targeting decision: a muscle the user
  /// kept reporting as too hard was surfaced more. The direction was argued
  /// over for a long time and the argument was the wrong one — a difficulty
  /// rating is evidence about TOLERANCE, and no sign convention makes it
  /// evidence about what has been neglected.
  ///
  /// Targeting now comes from `volume_ledger.dart`, which counts sets actually
  /// performed. Difficulty keeps the job it can do: `progression.dart` reads it
  /// to adjust the load. The method is deleted rather than deprecated because
  /// a deprecated ranking signal is one import away from being a live one.
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
