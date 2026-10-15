/// Which nutrition inputs a profile still lacks (design s13.1, s16.3). Pure,
/// no Flutter imports. Drives the "complete your nutrition profile" flow and
/// the `needsProfile` verdict.
library;

import '../../profile/data/profile_models.dart';
import 'energy_math.dart';

/// One input the nutrition coach needs. The names are what `needsProfile`
/// lists, so they are stable identifiers.
enum NutritionInput {
  birthYear,
  height,
  weight,
  sexBasis,
  activity,

  /// Goal direction: missing only when the user never chose one AND no goal
  /// answer lets us derive a default.
  goal,

  /// The two safety questions. Unanswered locks the coach (never read as
  /// clear); the flow asks them first.
  nutritionGuidance,
  professionalGuidance,
}

/// Goal direction: the explicit answer, else derived from the questionnaire
/// goals (`weightLoss` -> lose, `muscleGain` -> gain, anything else ->
/// maintain). Never null; use [hasGoalSignal] to know whether it was derivable.
GoalDirection deriveGoalDirection(UserProfile profile) {
  final explicit = profile.nutrition.goalDirection;
  if (explicit != null) return explicit;
  if (profile.goals.weightLoss) return GoalDirection.lose;
  if (profile.goals.muscleGain) return GoalDirection.gain;
  return GoalDirection.maintain;
}

/// True when the goal direction was answered or can be derived.
bool hasGoalSignal(UserProfile profile) =>
    profile.nutrition.goalDirection != null ||
    profile.goals.weightLoss ||
    profile.goals.muscleGain;

/// The age as of [year] used for the energy maths (the higher bracket of the
/// birth-year pair, which gives the lower, more conservative BMR). The
/// eligibility gate uses `lowestAgeAt` instead.
int? nutritionAgeYears(UserProfile profile, int year) =>
    profile.personal.ageAt(year);

/// Everything [profile] still lacks, in the order the flow asks it: the two
/// safety questions first, then body inputs, then goal. Empty for a complete
/// profile.
///
/// [currentWeightKg] is the resolved current weight (a recent weigh-in); when
/// null the profile weight counts. [now] fixes the clock year for the age.
List<NutritionInput> missingNutritionInputs(
  UserProfile profile, {
  double? currentWeightKg,
  DateTime? now,
}) {
  final year = (now ?? DateTime.now()).year;
  final flags = profile.health.flags;
  final p = profile.personal;
  final weight = currentWeightKg ?? p.weightCurrentKg;
  return [
    if (flags.nutritionGuidance == null) NutritionInput.nutritionGuidance,
    if (flags.professionalGuidance == null) NutritionInput.professionalGuidance,
    if (p.ageAt(year) == null) NutritionInput.birthYear,
    if (p.heightCm == null) NutritionInput.height,
    if (weight == null) NutritionInput.weight,
    if (resolveSexBasis(profile) == null) NutritionInput.sexBasis,
    if (p.activityLevel == null) NutritionInput.activity,
    if (!hasGoalSignal(profile)) NutritionInput.goal,
  ];
}
