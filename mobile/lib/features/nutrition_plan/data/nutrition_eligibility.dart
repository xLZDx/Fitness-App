/// Who may be given nutrition numbers (design s14). Pure Dart, no Flutter
/// imports.
///
/// The verdict is computed on the DEVICE at read time from device-only answers
/// and is NEVER persisted (D-55): nothing derived from it is written to the
/// server, and no plan or review document is written for an ineligible user.
/// The reason behind a `referProfessional` verdict is never shown to the user
/// either; the UI renders one neutral notice.
library;

import '../../profile/data/profile_models.dart';
import '../../safety/data/health_flags.dart';
import 'energy_math.dart';
import 'missing_inputs.dart';
import 'safety_clamps.dart';

/// Why a user is referred to a professional. Internal, never displayed.
enum ReferReason {
  /// Under 18, or could still be 17 (birth-year bracket).
  underAge,

  /// Pregnancy / breastfeeding / postpartum reported, or a clinician or
  /// dietitian supervising food, or a difficult relationship with food.
  guidance,

  /// A clinician advised against exercise, or surgery under restrictions
  /// (D-9: conservative).
  clinician,
}

/// A safety question that has never been answered.
enum NutritionQuestion { nutritionGuidance, professionalGuidance }

/// Exactly one of [Eligible], [ReferProfessional], [NeedsAnswer],
/// [NeedsProfile].
sealed class NutritionEligibility {
  const NutritionEligibility();

  /// True only for [Eligible]: the single case in which numbers may be shown.
  bool get allowsNumbers => this is Eligible;
}

class Eligible extends NutritionEligibility {
  const Eligible();
}

class ReferProfessional extends NutritionEligibility {
  const ReferProfessional(this.reason);

  /// The FIRST matching reason (first match wins).
  final ReferReason reason;

  List<ReferReason> get reasons => [reason];
}

class NeedsAnswer extends NutritionEligibility {
  const NeedsAnswer(this.question);

  final NutritionQuestion question;
}

class NeedsProfile extends NutritionEligibility {
  const NeedsProfile(this.missing);

  final List<NutritionInput> missing;
}

/// Evaluates the nine rows of design 14 in order; the first match wins.
///
/// 1 unknown age -> needsProfile(birthYear); 2 under 18 -> referProfessional;
/// 3 pregnancy/breastfeeding reported; 4 nutrition guidance reported; 5
/// clinician advice against exercise or surgery under restrictions; 6
/// nutrition question unanswered -> needsAnswer (the coach is LOCKED, never
/// assumed clear); 7 pregnancy question unanswered; 8 other inputs missing
/// (height, weight, sex basis, activity); 9 eligible.
///
/// [currentWeightKg] is the resolved current weight (a recent weigh-in); the
/// profile weight counts when null.
NutritionEligibility evaluateNutritionEligibility(
  UserProfile profile,
  DateTime now, {
  double? currentWeightKg,
}) {
  final personal = profile.personal;
  final flags = profile.health.flags;

  // 1 and 2: age. `lowestAgeAt` brackets a birth year to two values and the
  // gate uses the lower, so the boundary year counts as the safer side.
  final lowestAge = personal.lowestAgeAt(now.year);
  if (lowestAge == null) {
    return const NeedsProfile([NutritionInput.birthYear]);
  }
  if (lowestAge < SafetyClamps.minAdultAge) {
    return const ReferProfessional(ReferReason.underAge);
  }
  // 3, 4, 5.
  if (flags.professionalGuidance == ProfessionalGuidanceNeed.reported ||
      flags.nutritionGuidance == NutritionGuidanceNeed.reported) {
    return const ReferProfessional(ReferReason.guidance);
  }
  if (flags.clinicianAdvice == ClinicianExerciseAdvice.advisedAgainstExercise ||
      flags.surgery == SurgeryStatus.underRestrictions) {
    return const ReferProfessional(ReferReason.clinician);
  }
  // 6 and 7: unanswered locks the coach.
  if (flags.nutritionGuidance == null) {
    return const NeedsAnswer(NutritionQuestion.nutritionGuidance);
  }
  if (flags.professionalGuidance == null) {
    return const NeedsAnswer(NutritionQuestion.professionalGuidance);
  }
  // 8: other inputs.
  final weight = currentWeightKg ?? personal.weightCurrentKg;
  final missing = [
    if (personal.heightCm == null) NutritionInput.height,
    if (weight == null) NutritionInput.weight,
    if (resolveSexBasis(profile) == null) NutritionInput.sexBasis,
    if (personal.activityLevel == null) NutritionInput.activity,
  ];
  if (missing.isNotEmpty) return NeedsProfile(missing);
  return const Eligible();
}
