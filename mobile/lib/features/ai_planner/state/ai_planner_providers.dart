import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import '../../personalisation/state/personalisation_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../../recovery/state/recovery_providers.dart';
import '../../safety/state/safety_providers.dart';
import '../data/plan_builder.dart';
import '../data/workout_plan.dart';

/// Live plan outcome for the signed-in user. Reads:
///   - the pre-exercise screening verdict (whether a plan may be produced)
///   - candidate exercise pool from the equipment repository
///   - reported injuries from the user's profile
///   - weekly per-muscle set deficit (what has been trained least)
///   - deload verdict (recovery signals)
///
/// Returns null while any dependency is still loading. Null means LOADING and
/// nothing else — a refusal comes back as [PlanRefused], which is why Gate M
/// made the outcome a sealed type instead of leaning on this null.
final generatedPlanProvider = FutureProvider<PlanOutcome?>((ref) async {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return null;
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return null;
  final deload = ref.watch(deloadVerdictProvider);
  final safety = await ref.watch(safetyVerdictProvider.future);
  final deficit = await ref.watch(weeklyVolumeDeficitProvider.future);

  // Build the candidate pool from the catalog. Limit to body-weight +
  // every available equipment so the planner doesn't propose machines
  // the user can't reach.
  final repo = ref.watch(equipmentRepositoryProvider);
  final allEquipment = await repo.listEquipment();
  final pool = <ExerciseItem>[
    ...await repo.bodyweightExercises(),
    for (final eq in allEquipment) ...await repo.exercisesFor(eq.id),
  ];

  return buildPlan(
    candidatePool: pool,
    reportedInjuries: profile.health.injuries,
    deficit: deficit,
    deload: deload,
    safety: safety,
  );
});
