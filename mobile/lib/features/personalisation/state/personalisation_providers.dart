import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import '../../workouts/state/workout_session_providers.dart';
import '../data/fitness_model.dart';
import '../data/for_you_ranker.dart';
import '../data/volume_ledger.dart';

/// Live FitnessProfile derived from the user's logs + the catalog's
/// muscle map. Recomputed when either dependency changes.
final fitnessProfileProvider = FutureProvider<FitnessProfile>((ref) async {
  // F3.3 read-convergence: sourced from workout_sessions, see progress_page.
  final logs = ref.watch(workoutSessionHistoryProvider);
  final repo = ref.watch(equipmentRepositoryProvider);
  final allEquipment = await repo.listEquipment();
  final exercises = <ExerciseItem>[
    ...await repo.bodyweightExercises(),
    for (final eq in allEquipment) ...await repo.exercisesFor(eq.id),
  ];
  final muscleMap = <String, List<String>>{
    for (final ex in exercises) ex.id: ex.muscles,
  };
  return buildProfile(logs, musclesByExerciseId: muscleMap);
});

/// The For-You feed, ordered by what the user has been training least.
///
/// This is the whole personalisation layer's one exit. Before it existed, a
/// tested ranker, a fitness model built from every logged set and a provider
/// to drive them sat in this folder and NOTHING watched any of it: the Train
/// tab read the filtered catalog directly, so the feed named "For you" was the
/// same order for everybody.
///
/// It used to be a `Provider.family` keyed on the candidate LIST, which is why
/// it could never be used from anywhere sensible. A family key is compared by
/// `==`, a `List` compares by identity, and the feed is a fresh list on every
/// rebuild — so every rebuild would have allocated a new provider that is
/// never disposed. Composing the two providers here removes the key entirely.
final rankedForYouProvider = FutureProvider<List<ExerciseItem>>((ref) async {
  final candidates = await ref.watch(forYouExercisesProvider.future);
  // Cold start: nothing trained, so nothing is neglected more than anything
  // else. The filtered order is the honest answer, not a made-up one.
  final deficit = await ref.watch(weeklyVolumeDeficitProvider.future);
  if (deficit.isEmpty) return candidates;
  final logs = ref.watch(workoutSessionHistoryProvider);
  final recent = logs
      .where((l) => DateTime.now().difference(l.completedAt).inDays < 7)
      .map((l) => l.exerciseId)
      .toSet();
  return rankForYou(candidates, deficit: deficit, recentExerciseIds: recent);
});

/// How far short of its weekly set target each muscle group is, 0..1.
///
/// The one input selection is allowed to have. Built from sessions rather than
/// from the log-entry view, because that view keeps `sets.last` and drops
/// `sets.length` — the count is the whole measure.
final weeklyVolumeDeficitProvider =
    FutureProvider<Map<String, double>>((ref) async {
  // `.future`, not `.valueOrNull`. Reading the value would return null while
  // the stream is still loading, which this provider cannot distinguish from
  // "this user has trained nothing" — and the two produce opposite feeds. The
  // first draft did exactly that, so every cold open showed the unpersonalised
  // catalogue order for one frame and then reshuffled under the user's thumb.
  final sessions = await ref.watch(workoutSessionsProvider.future);

  final repo = ref.watch(equipmentRepositoryProvider);
  final allEquipment = await repo.listEquipment();
  final exercises = <ExerciseItem>[
    ...await repo.bodyweightExercises(),
    for (final eq in allEquipment) ...await repo.exercisesFor(eq.id),
  ];

  final byId = <String, ExerciseMuscles>{
    for (final ex in exercises)
      ex.id: (primary: ex.primaryMuscles, secondary: ex.muscles),
  };
  // Every muscle the catalogue names, not only the ones already trained: a
  // group with no entry in the ledger is the maximum deficit, and reading the
  // vocabulary off the ledger would drop exactly those.
  final allMuscles = <String>{
    for (final ex in exercises) ...ex.primaryMuscles,
    for (final ex in exercises) ...ex.muscles,
  };

  final volume = weeklyVolume(
    sessions,
    musclesByExerciseId: byId,
    now: DateTime.now(),
  );
  return volumeDeficit(volume, allMuscles);
});
