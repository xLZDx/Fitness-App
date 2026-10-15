/// Energy maths: BMR, activity factors, TDEE, unit helpers and the Atwater
/// consistency check (design s13.2, s17.7). Pure Dart, no Flutter imports.
library;

import 'dart:math' as math;

import '../../profile/data/profile_models.dart';
import 'safety_clamps.dart';

/// The sex term of the BMR formula. `unspecified` is used for non-binary,
/// prefer-not-to-say and unknown answers (the midpoint constant, D-12).
enum SexBasis { male, female, unspecified }

/// Sex basis for the BMR constant: `NutritionPrefs.sexAtBirth` first, then
/// `gender` male/female, else `unspecified` for the other answers; null when
/// nothing at all was answered (the input is then "missing").
SexBasis? resolveSexBasis(UserProfile profile) {
  switch (profile.nutrition.sexAtBirth) {
    case SexAtBirth.male:
      return SexBasis.male;
    case SexAtBirth.female:
      return SexBasis.female;
    case SexAtBirth.unspecified:
      return SexBasis.unspecified;
    case null:
      break;
  }
  switch (profile.personal.gender) {
    case Gender.male:
      return SexBasis.male;
    case Gender.female:
      return SexBasis.female;
    case Gender.nonBinary:
    case Gender.preferNotToSay:
      return SexBasis.unspecified;
    case null:
      return null;
  }
}

/// Body-mass index; null for non-positive input.
double? bmiOf(double weightKg, double heightCm) {
  if (weightKg <= 0 || heightCm <= 0) return null;
  final m = heightCm / 100;
  return weightKg / (m * m);
}

/// Mifflin-St Jeor resting energy [PUB, AJCN 51:241]:
/// `10 W + 6.25 H - 5 A + c`.
double bmr({
  required double weightKg,
  required double heightCm,
  required int ageYears,
  required SexBasis sex,
}) {
  final c = switch (sex) {
    SexBasis.male => SafetyClamps.bmrConstantMale,
    SexBasis.female => SafetyClamps.bmrConstantFemale,
    SexBasis.unspecified => SafetyClamps.bmrConstantUnspecified,
  };
  return 10 * weightKg + 6.25 * heightCm - 5 * ageYears + c;
}

/// Questionnaire activity factor (1.9 is never produced).
double activityFactorFor(ActivityLevel level) => switch (level) {
      ActivityLevel.sedentary => SafetyClamps.factorSedentary,
      ActivityLevel.moderatelyActive => SafetyClamps.factorModerate,
      ActivityLevel.active => SafetyClamps.factorActive,
      ActivityLevel.veryActive => SafetyClamps.factorVeryActive,
    };

/// Steps cross-check factor: <5,000 -> 1.2, 5,000-7,499 -> 1.375,
/// 7,500-9,999 -> 1.55, >= 10,000 -> 1.725 [OWN].
double stepsFactorFor(int dailySteps) {
  if (dailySteps >= SafetyClamps.stepsBandVeryActive) {
    return SafetyClamps.factorVeryActive;
  }
  if (dailySteps >= SafetyClamps.stepsBandActive) {
    return SafetyClamps.factorActive;
  }
  if (dailySteps >= SafetyClamps.stepsBandModerate) {
    return SafetyClamps.factorModerate;
  }
  return SafetyClamps.factorSedentary;
}

/// The factor actually used: the LOWER of the questionnaire factor and the
/// steps factor when both exist (never over-estimate TDEE); whichever exists
/// otherwise; null when neither does.
double? combinedActivityFactor({ActivityLevel? level, int? typicalSteps}) {
  final q = level == null ? null : activityFactorFor(level);
  final s = typicalSteps == null ? null : stepsFactorFor(typicalSteps);
  if (q == null) return s;
  if (s == null) return q;
  return math.min(q, s);
}

/// Total daily energy expenditure. Exercise calories are NOT added back (D-29).
double tdee(double bmrKcal, double activityFactor) => bmrKcal * activityFactor;

/// The calorie floor: `max(absolute by sex, round(BMR))`.
int calorieFloor(double bmrKcal, SexBasis sex) {
  final absolute = sex == SexBasis.female
      ? SafetyClamps.absoluteFloorKcalFemale
      : SafetyClamps.absoluteFloorKcalMale;
  return math.max(absolute, bmrKcal.round());
}

/// Rounds to the nearest [step] (half away from zero).
int roundToStep(double value, int step) => (value / step).round() * step;

/// Rounds DOWN to a multiple of [step].
int floorToStep(double value, int step) => (value / step).floor() * step;

/// Rounds UP to a multiple of [step].
int ceilToStep(double value, int step) => (value / step).ceil() * step;

// --- Unit helpers --------------------------------------------------------

const double kKjPerKcal = 4.184;

/// kcal from kJ.
double kcalFromKj(double kj) => kj / kKjPerKcal;

/// kJ from kcal.
double kjFromKcal(double kcal) => kcal * kKjPerKcal;

/// The kcal figure to use when a source gives both: the kcal field wins; kJ is
/// converted only when kcal is absent (V-OFF: 539, not 2252 / 4.184).
double? resolveKcal({double? kcal, double? kj}) {
  if (kcal != null) return kcal;
  if (kj != null) return kcalFromKj(kj);
  return null;
}

/// Grams of salt for [sodiumG] grams of sodium (`salt = sodium x 2.5`).
double saltGFromSodiumG(double sodiumG) => sodiumG * 2.5;

/// Grams of sodium for [saltG] grams of salt.
double sodiumGFromSaltG(double saltG) => saltG / 2.5;

// --- Atwater check ---------------------------------------------------------

/// Energy implied by the macros at 4 / 4 / 9 kcal per gram [PUB, Atwater].
double atwaterKcal({
  required double proteinG,
  required double carbsG,
  required double fatG,
}) =>
    SafetyClamps.kcalPerGramProtein * proteinG +
    SafetyClamps.kcalPerGramCarb * carbsG +
    SafetyClamps.kcalPerGramFat * fatG;

/// True when the macros agree with the stated energy within
/// `max(25 %, 10 kcal)` (D-39). A larger gap is flagged `dataInconsistent`
/// by the caller; small gaps are normal (fibre, alcohol, rounding).
bool isAtwaterConsistent({
  required double kcal,
  required double proteinG,
  required double carbsG,
  required double fatG,
}) {
  final implied = atwaterKcal(proteinG: proteinG, carbsG: carbsG, fatG: fatG);
  final tolerance = math.max(
    SafetyClamps.atwaterTolerance * kcal,
    SafetyClamps.atwaterToleranceFloorKcal,
  );
  return (implied - kcal).abs() <= tolerance;
}
