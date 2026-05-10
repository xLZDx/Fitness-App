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

/// Re-ranked For-You feed. Falls back to the input list if the profile
/// is still loading.
final rankedForYouProvider =
    Provider.family<List<ExerciseItem>, List<ExerciseItem>>((ref, candidates) {
  final profile = ref.watch(fitnessProfileProvider).valueOrNull;
  if (profile == null) return List.unmodifiable(candidates);
  final logs = ref.watch(workoutLogsProvider).valueOrNull ?? const [];
  final recent = logs
      .where((l) =>
          DateTime.now().difference(l.completedAt).inDays < 7)
      .map((l) => l.exerciseId)
      .toSet();
  return rankForYou(candidates, profile: profile, recentExerciseIds: recent);
});
