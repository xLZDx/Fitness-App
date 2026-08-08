/// Body-mass arithmetic for the onboarding's `BMICard` and `DeltaCard`
/// (`App.tsx`, step 7).
///
/// Pure, and in its own file, for the same reason `home_dashboard.dart` is:
/// the numbers a screen states about a person's body should be testable
/// without a widget tree, and should be readable next to the caveat that
/// belongs with them.
library;

/// BMI, or null when either input is missing or nonsensical.
///
/// Null rather than 0: a card that renders "0.0" for someone who has not
/// entered a height is stating a measurement about them that is false.
double? bmiFor({int? heightCm, double? weightKg}) {
  if (heightCm == null || weightKg == null) return null;
  if (heightCm <= 0 || weightKg <= 0) return null;
  final m = heightCm / 100;
  return weightKg / (m * m);
}

/// The conventional WHO adult bands.
enum BmiBand { underweight, healthy, overweight, obese }

/// Which band [bmi] falls in.
///
/// **This is a lookup, not an assessment.** BMI does not distinguish muscle
/// from fat, and this app's users are people who lift — a fact that makes the
/// index least reliable exactly where it will be read most. The band is shown
/// with that caveat next to it (`onbBmiCaveat`) and nothing in the app acts on
/// it: no plan, no recommendation and no filter reads this value.
BmiBand bandFor(double bmi) {
  if (bmi < 18.5) return BmiBand.underweight;
  if (bmi < 25) return BmiBand.healthy;
  if (bmi < 30) return BmiBand.overweight;
  return BmiBand.obese;
}

/// Target minus current, or null when either is missing.
///
/// Signed, and deliberately not described as good or bad: a gain is the goal
/// for someone bulking and the opposite for someone cutting, and the
/// questionnaire has not asked yet at the point this card appears.
double? weightDelta({double? currentKg, double? targetKg}) {
  if (currentKg == null || targetKg == null) return null;
  return targetKg - currentKg;
}
