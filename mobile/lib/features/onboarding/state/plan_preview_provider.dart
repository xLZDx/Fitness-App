import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_planner/data/plan_builder.dart';
import '../../ai_planner/data/workout_plan.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import '../../personalisation/state/personalisation_providers.dart';
import '../../recovery/state/recovery_providers.dart';
import 'questionnaire_notifier.dart';

/// O10 — the preview at the end of onboarding, built by the REAL generator.
///
/// The spec forbids a fixture here, and this is the reason it can be obeyed:
/// `buildPlan` already exists, is pure, and takes everything it needs as
/// arguments (`plan_builder.dart:20-27`). Nothing had to be invented.
///
/// Distinct from `generatedPlanProvider` in one respect that matters: that one
/// reads `currentProfileProvider`, the SAVED profile. At this point in the flow
/// nothing has been saved — the answers are still a draft — so reading it would
/// preview a plan built from the profile the user had *before* answering, or
/// from nothing at all on a first run.
///
/// [TrainingSchedule.sessionMinutes] drives the length, which is the first
/// thing O5's screen is actually used for: a 30-minute answer must not preview
/// an hour.
final onboardingPlanPreviewProvider =
    FutureProvider.autoDispose<GeneratedPlan>((ref) async {
  final draft = ref.watch(questionnaireDraftProvider);
  final fitness = await ref.watch(fitnessProfileProvider.future);
  final deload = ref.watch(deloadVerdictProvider);

  final repo = ref.watch(equipmentRepositoryProvider);
  final allEquipment = await repo.listEquipment();
  final pool = <ExerciseItem>[
    ...await repo.bodyweightExercises(),
    for (final eq in allEquipment) ...await repo.exercisesFor(eq.id),
  ];

  return buildPlan(
    candidatePool: pool,
    // The injuries the user has just entered — including the ones O6 wrote by
    // tapping the body map, which is what makes the preview reflect the
    // limitations screen rather than ignore it.
    reportedInjuries: draft.health.injuries,
    profile: fitness,
    deload: deload,
    targetMinutes: draft.schedule.sessionMinutes ?? 45,
  );
});
