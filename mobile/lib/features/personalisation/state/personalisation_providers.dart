import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import '../../workouts/state/workout_log_providers.dart';
import '../data/fitness_model.dart';
import '../data/for_you_ranker.dart';

/// Live FitnessProfile derived from the user's logs + the catalog's
/// muscle map. Recomputed when either dependency changes.
final fitnessProfileProvider = FutureProvider<FitnessProfile>((ref) async {
  final logs = ref.watch(workoutLogsProvider).valueOrNull ?? const [];
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
  final profile = ref.watch(fitnessProfileProvider).valueOrNull;
  // Cold start: no logs, no model, nothing to personalise from. The filtered
  // order is the honest answer, not a made-up one.
  if (profile == null) return candidates;
  final logs = ref.watch(workoutLogsProvider).valueOrNull ?? const [];
  final recent = logs
      .where((l) => DateTime.now().difference(l.completedAt).inDays < 7)
      .map((l) => l.exerciseId)
      .toSet();
  return rankForYou(candidates, profile: profile, recentExerciseIds: recent);
});
