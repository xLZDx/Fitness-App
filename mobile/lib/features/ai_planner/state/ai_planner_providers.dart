import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import '../../personalisation/state/personalisation_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../../recovery/state/recovery_providers.dart';
import '../data/plan_builder.dart';
import '../data/workout_plan.dart';

/// Live generated plan for the signed-in user. Reads:
///   - candidate exercise pool from the equipment repository
///   - reported injuries from the user's profile
///   - personalisation profile (Bayesian)
///   - deload verdict (recovery signals)
///
/// Returns null while any dependency is still loading -- and also for a
/// resolved "signed in, no profile document yet". A caller reading
/// `.valueOrNull` cannot tell those two apart; do not do that (`when()` on
/// the current sole consumer, `ai_planner_page.dart`, does). No wrapper type
/// was introduced to enforce this here -- `Answer<T,R>`
/// (`shared/uncertainty/answer.dart`) is documented as the wrong shape for
/// "confidently nothing, for one of two different reasons", not a fit.
///
/// MVP-1: the auth check awaits `authUserProvider.future` rather than
/// sampling `.valueOrNull`, which collapsed "auth still restoring" and
/// "genuinely signed out" into the same branch -- reachable on every cold
/// start, not just under adversarial timing. Same fix already applied to
/// `currentSubscriptionProvider` and `screeningProfileProvider`; see
/// `core/plans/SPTR_MVP_CLOSURE_PLAN_2026-08-19.md`.
final generatedPlanProvider = FutureProvider<GeneratedPlan?>((ref) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) return null;
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return null;
  final fitness =
      await ref.watch(fitnessProfileProvider.future);
  final deload = ref.watch(deloadVerdictProvider);

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
    profile: fitness,
    deload: deload,
  );
});
