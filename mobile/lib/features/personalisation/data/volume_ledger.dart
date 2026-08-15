import '../../workouts/data/workout_session.dart';

/// Weekly sets per muscle group — the quantity resistance programming is
/// actually made of, and the one this app has never had.
///
/// Nothing in the repository could answer "how many sets did this person do
/// for their back last week". The set data exists — `WorkoutSessionExercise.sets`
/// is a real list — but every analytic reads through `WorkoutSession.asLogEntries`,
/// which keeps `sets.last` and drops `sets.length`. So the profile, the deload
/// detector, the suggestion builder and the home dashboard all consume a view
/// in which a five-set session and a one-set session are the same row.
///
/// This reads `WorkoutSession` directly, which is why it needs no schema
/// migration: the counts were never missing, only unreachable.
///
/// **What this is for.** Training priority — *which* muscle to work next —
/// comes from here. It used to come from `FitnessProfile.adaptivePriorityFor`,
/// which inverts a subjective difficulty rating, so a muscle the user kept
/// reporting as too hard was surfaced more. Four independent specialist
/// reviews reached the same conclusion on 2026-08-15: a difficulty rating is a
/// *tolerance* signal and belongs to dose control, while "what should I train"
/// is a *volume deficit* question that is observable without any rating at all
/// and is not subject to the feedback loop that ranking-by-rating creates.
///
/// Deficit is also immune to the loop that broke the old signal. The ranker
/// decided what was shown, which decided what was rated, which updated the
/// score — a muscle could stay top-ranked forever on evidence the ranking
/// itself generated. Sets performed do not have that property: training a
/// muscle *reduces* its priority, so the system self-corrects by construction.

/// Which muscles an exercise trains, split by how much.
///
/// `primary` is what the movement is FOR; `secondary` carries the supporting
/// groups. `ExerciseItem` already draws this distinction and 1,436 catalogue
/// rows populate it — it was simply never read by anything that aggregates.
typedef ExerciseMuscles = ({List<String> primary, List<String> secondary});

/// How much a supporting muscle counts toward its weekly total.
///
/// `PRODUCT_HEURISTIC`, not evidence. There is no published number for "what
/// fraction of a set does a triceps get from a bench press", and inventing a
/// precise one would be worse than admitting the choice: counting a secondary
/// as a *full* set is the error this replaces, and counting it as zero would
/// hide real work. Half is the midpoint, stated so it can be argued with.
///
/// Owner: unassigned. `fitness-prescription-reference` §10 requires a named
/// policy owner on any executable numeric rule; this has none yet and the
/// absence is recorded rather than papered over.
const double kSecondaryMuscleWeight = 0.5;

/// Sets per muscle per week the product treats as "enough".
///
/// Reference point, not a gate. ACSM's 2026 position stand on resistance
/// training reports roughly 10 sets per muscle per week for hypertrophy in
/// healthy adults; that is a population figure and this app applies it to
/// individuals, which the evidence does not license. It is used here only to
/// *order* muscles by how far short they fall — a monotone transform, so the
/// ordering is unchanged for any positive target. Nothing gates on the value.
const double kWeeklySetTarget = 10.0;

/// What one muscle group received over the window.
class MuscleVolume {
  const MuscleVolume({
    required this.muscle,
    required this.sets,
    required this.sessions,
  });

  final String muscle;

  /// Weighted sets: a primary attribution counts 1.0, a secondary
  /// [kSecondaryMuscleWeight]. Fractional on purpose — rounding here would
  /// discard exactly the distinction the field exists to make.
  final double sets;

  /// Distinct sessions that touched this muscle.
  ///
  /// Frequency, which is a separate programming variable from volume: 10 sets
  /// in one session and 10 across three are not the same stimulus. Nothing
  /// reads it yet; it is computed here because the pass that computes volume
  /// is the only place the information is available, and re-deriving it later
  /// would mean walking the sessions twice.
  final int sessions;

  @override
  String toString() => 'MuscleVolume($muscle, ${sets}s, ${sessions}x)';
}

/// Weighted sets per muscle over the trailing [window], newest-anchored at [now].
///
/// Sessions with no `completedAt` fall back to `startedAt`, matching
/// `asLogEntries`. An exercise whose id is absent from [musclesByExerciseId]
/// contributes nothing — it is not attributed to a default group, because a
/// wrong attribution is worse than a missing one for a quantity whose whole
/// purpose is to say what has been neglected.
Map<String, MuscleVolume> weeklyVolume(
  Iterable<WorkoutSession> sessions, {
  required Map<String, ExerciseMuscles> musclesByExerciseId,
  required DateTime now,
  Duration window = const Duration(days: 7),
}) {
  final cutoff = now.subtract(window);
  final setsBy = <String, double>{};
  final sessionsBy = <String, Set<String>>{};

  for (final session in sessions) {
    final at = session.completedAt ?? session.startedAt;
    if (at.isBefore(cutoff) || at.isAfter(now)) continue;

    for (final exercise in session.exercises) {
      final muscles = musclesByExerciseId[exercise.exerciseId];
      if (muscles == null) continue;
      // The count of sets actually performed. This single expression is the
      // whole point of the file — it is what `asLogEntries` throws away.
      final performed = exercise.sets.length;
      if (performed == 0) continue;

      void credit(String muscle, double weight) {
        setsBy[muscle] = (setsBy[muscle] ?? 0) + performed * weight;
        (sessionsBy[muscle] ??= <String>{}).add(session.id);
      }

      for (final m in muscles.primary) {
        credit(m, 1.0);
      }
      for (final m in muscles.secondary) {
        // A muscle listed as both is credited once, at the primary weight.
        if (muscles.primary.contains(m)) continue;
        credit(m, kSecondaryMuscleWeight);
      }
    }
  }

  return {
    for (final entry in setsBy.entries)
      entry.key: MuscleVolume(
        muscle: entry.key,
        sets: entry.value,
        sessions: sessionsBy[entry.key]!.length,
      ),
  };
}

/// How far each of [allMuscles] falls short of [target], from 0 (met) to 1
/// (untrained).
///
/// Takes the full muscle vocabulary rather than reading it off the ledger,
/// because the muscles that matter most are precisely the ones with no entry —
/// a group the user has never trained is absent from `weeklyVolume` and must
/// come back as the maximum deficit, not as missing.
Map<String, double> volumeDeficit(
  Map<String, MuscleVolume> volume,
  Iterable<String> allMuscles, {
  double target = kWeeklySetTarget,
}) {
  assert(target > 0, 'a target of zero would make every muscle satisfied');
  return {
    for (final muscle in allMuscles)
      muscle: (1.0 - (volume[muscle]?.sets ?? 0) / target).clamp(0.0, 1.0),
  };
}

/// Training priority for an exercise, from the deficit of the muscles it works.
///
/// The replacement for `FitnessProfile.adaptivePriorityFor`. Reads `primary`
/// where an exercise has one, because a movement should be chosen for what it
/// is for — averaging a bench press over chest, triceps and front delts
/// dilutes the signal with groups it barely trains.
///
/// Returns null when the exercise has no muscle attribution at all. Null is
/// not zero and not neutral: 182 catalogue rows carry no muscle tag, and
/// scoring them at the mid-point put them in the same tie class as every
/// muscle the user had never rated, from which a greedy top-N fill could take
/// an entire session. "No signal" has to be distinguishable from "no deficit".
double? exercisePriority(
  ExerciseMuscles muscles,
  Map<String, double> deficit,
) {
  final considered =
      muscles.primary.isNotEmpty ? muscles.primary : muscles.secondary;
  if (considered.isEmpty) return null;

  var total = 0.0;
  var counted = 0;
  for (final m in considered) {
    final d = deficit[m];
    if (d == null) continue;
    total += d;
    counted++;
  }
  if (counted == 0) return null;
  return total / counted;
}
