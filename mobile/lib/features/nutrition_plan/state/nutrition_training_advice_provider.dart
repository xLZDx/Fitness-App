/// The nutrition-aware programme hook (design s30, C09) over LIVE inputs: the
/// pure `adviseTrainingFromNutrition` function fed from the stored plan, the
/// weight slope and the profile. Nutrition may only LOWER training load, and
/// anything missing (or a user who may not get numbers) gives the neutral
/// advice.
///
/// Inputs that do not exist yet (logged protein adherence, sleep, the recovery
/// detector) are left unset, so the rules that need them stay inactive until a
/// later commit supplies them; nothing is guessed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/profile_models.dart';
import '../../profile/state/profile_providers.dart';
import '../data/energy_math.dart';
import '../data/nutrition_training_state.dart';
import '../data/weight_entry.dart';
import 'nutrition_providers.dart';
import 'weight_providers.dart';

final nutritionTrainingAdviceProvider =
    Provider<TrainingNutritionAdvice>((ref) {
  final verdict = ref.watch(nutritionEligibilityProvider);
  final plan = ref.watch(nutritionPlanProvider).valueOrNull;
  if (verdict == null || !verdict.allowsNumbers || plan == null) {
    return TrainingNutritionAdvice.neutralAdvice;
  }
  final now = ref.watch(nutritionClockProvider)();
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  final entries = ref.watch(weightEntriesProvider).valueOrNull ?? const [];
  final tdee = plan.digest.tdee;
  final mid = plan.kcalRange.mid;
  final gap = tdee > 0 ? (tdee - mid) / tdee : null;
  final phase = switch (plan.goal) {
    GoalDirection.lose => EnergyPhase.deficit,
    GoalDirection.gain => EnergyPhase.surplus,
    GoalDirection.maintain => EnergyPhase.maintenance,
  };
  final slope = weightSlopeKgPerWeek(entries, asOf: now);
  final weight = plan.digest.weightKg;
  final bmiRow = plan.maxKgPerWeek;
  return adviseTrainingFromNutrition(
    NutritionTrainingInput(
      eligibility: verdict,
      phase: phase,
      deficitPct: gap != null && gap > 0 ? gap : null,
      surplusPct: gap != null && gap < 0 ? -gap : null,
      weightRatePctPerWeek: slope == null || weight <= 0
          ? null
          : slope / weight * 100,
      planMaxRatePctPerWeek: weight <= 0 ? null : bmiRow / weight * 100,
      sessionsPerWeek: profile?.level.frequencyPerWeek ?? 0,
      kcalMid: mid,
      floorKcal: calorieFloor(plan.digest.bmr, plan.digest.sexBasis).toDouble(),
    ),
  );
});
