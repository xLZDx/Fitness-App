/// The resolved numeric inputs of the nutrition maths (design s13.1). Pure
/// Dart, no Flutter imports.
library;

import '../../profile/data/profile_models.dart';
import 'energy_math.dart';
import 'missing_inputs.dart';
import 'safety_clamps.dart';
import 'weight_entry.dart';

/// The current weight and whether it is the stale profile fallback.
class ResolvedWeight {
  const ResolvedWeight({required this.kg, required this.stale});

  final double kg;

  /// True when no weigh-in within 14 days exists and the profile weight was
  /// used.
  final bool stale;
}

/// The ONE definition of "current weight" (D-72): the newest weigh-in within
/// [SafetyClamps.currentWeightFreshDays] days, else [profileWeightKg] flagged
/// stale, else null.
ResolvedWeight? resolveCurrentWeight({
  required Iterable<WeightEntry> entries,
  required double? profileWeightKg,
  required DateTime now,
}) {
  final recent = latestWeightWithin(entries, now);
  if (recent != null) return ResolvedWeight(kg: recent.kg, stale: false);
  if (profileWeightKg != null) {
    return ResolvedWeight(kg: profileWeightKg, stale: true);
  }
  return null;
}

/// Everything the energy and plan maths read, resolved from the profile.
class NutritionInputs {
  const NutritionInputs({
    required this.weightKg,
    required this.heightCm,
    required this.ageYears,
    required this.sex,
    required this.activityLevel,
    required this.goal,
    this.typicalSteps,
    this.weightStale = false,
    this.weightTargetKg,
    this.targetBodyFatPct,
  });

  final double weightKg;
  final double heightCm;
  final int ageYears;
  final SexBasis sex;
  final ActivityLevel? activityLevel;
  final GoalDirection goal;

  /// Health-platform 14-day median steps when connected, else the self-reported
  /// bucket midpoint, else null.
  final int? typicalSteps;
  final bool weightStale;
  final double? weightTargetKg;
  final double? targetBodyFatPct;

  double get bmi => bmiOf(weightKg, heightCm) ?? 0;

  /// Resolves [profile] into inputs, or reports exactly which required inputs
  /// are missing. Required: age, height, weight, sex basis, activity (the goal
  /// defaults from the questionnaire, so it never blocks).
  static NutritionInputsResolution resolve(
    UserProfile profile, {
    required DateTime now,
    Iterable<WeightEntry> weightEntries = const [],
    int? healthMedianSteps,
  }) {
    final weight = resolveCurrentWeight(
      entries: weightEntries,
      profileWeightKg: profile.personal.weightCurrentKg,
      now: now,
    );
    final missing = [
      for (final m in missingNutritionInputs(
        profile,
        currentWeightKg: weight?.kg,
        now: now,
      ))
        if (m == NutritionInput.birthYear ||
            m == NutritionInput.height ||
            m == NutritionInput.weight ||
            m == NutritionInput.sexBasis ||
            m == NutritionInput.activity)
          m,
    ];
    if (missing.isNotEmpty) {
      return NutritionInputsResolution(inputs: null, missing: missing);
    }
    final p = profile.personal;
    return NutritionInputsResolution(
      inputs: NutritionInputs(
        weightKg: weight!.kg,
        heightCm: p.heightCm!.toDouble(),
        ageYears: nutritionAgeYears(profile, now.year)!,
        sex: resolveSexBasis(profile)!,
        activityLevel: p.activityLevel,
        goal: deriveGoalDirection(profile),
        typicalSteps: healthMedianSteps ?? profile.nutrition.typicalDailySteps,
        weightStale: weight.stale,
        weightTargetKg: p.weightTargetKg,
        targetBodyFatPct: profile.nutrition.targetBodyFatPct,
      ),
      missing: const [],
    );
  }
}

/// Either complete [inputs] or the non-empty [missing] list (`needsProfile`).
class NutritionInputsResolution {
  const NutritionInputsResolution({
    required this.inputs,
    required this.missing,
  });

  final NutritionInputs? inputs;
  final List<NutritionInput> missing;

  bool get isComplete => inputs != null;
}
