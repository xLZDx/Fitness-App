import 'dart:math' as math;

/// The US Navy circumference formula, and nothing else.
///
/// ## What used to be here
///
/// A `BodyCompEstimate` record and a `BodyCompMethod.photoSilhouette` value,
/// under a header that read *"MK.6 — Continuous body comp via phone camera.
/// On-device photo + height + weight -> estimate body-fat %"*. None of it
/// existed: no capture, no model, no storage, no screen, and no caller for the
/// data class. The subscription page nonetheless listed "Body comp + advanced
/// analytics" as a paid feature.
///
/// The claim has been removed from the paywall. What is kept is the one thing
/// that was real — a pure, tested formula — and it is kept without a type
/// around it implying a pipeline that was never built.
///
/// US Navy body-fat formula.
///
/// Uses cm. Returns 0 when inputs are out of expected range.
/// Source formula: U.S. Navy Bureau of Medicine, BUMED Instruction
/// 6110.1 — circumference method.
///
/// Currently has no production caller. That is stated rather than hidden: it
/// is a helper waiting for a feature, not a feature.
double navyBodyFatPercent({
  required double heightCm,
  required double waistCm,
  required double neckCm,
  double? hipCm,
  required bool isMale,
}) {
  if (heightCm <= 0 || waistCm <= 0 || neckCm <= 0) return 0;
  if (!isMale && (hipCm ?? 0) <= 0) return 0;
  double log10(double x) => math.log(x) / math.ln10;
  if (isMale) {
    final raw = 86.010 * log10(waistCm - neckCm) -
        70.041 * log10(heightCm) +
        36.76;
    return raw.clamp(2, 60);
  }
  final raw = 163.205 * log10(waistCm + hipCm! - neckCm) -
      97.684 * log10(heightCm) -
      78.387;
  return raw.clamp(8, 60);
}
