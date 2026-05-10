import 'dart:math' as math;

/// MK.6 — Continuous body comp via phone camera.
///
/// On-device photo + height + weight → estimate body-fat %. Uses
/// silhouette ratios from a single front-facing photo. Not a clinical
/// measurement; surfaced as "trend" not "ground truth". The estimate
/// stays on-device; only the trend point lands server-side, encrypted.
class BodyCompEstimate {
  const BodyCompEstimate({
    required this.takenAt,
    required this.heightCm,
    required this.weightKg,
    required this.bodyFatPercent,
    required this.method,
    this.confidence,
  });

  final DateTime takenAt;
  final double heightCm;
  final double weightKg;
  final double bodyFatPercent;
  final BodyCompMethod method;

  /// 0..1, model-reported confidence. Drop estimates below 0.5 in the
  /// trend chart so noise doesn't move the line.
  final double? confidence;
}

enum BodyCompMethod { photoSilhouette, navy, manual }

/// US Navy body-fat formula. Pure helper for the [BodyCompMethod.navy]
/// fallback when photos aren't available.
///
/// Uses cm. Returns 0 when inputs are out of expected range.
/// Source formula: U.S. Navy Bureau of Medicine, BUMED Instruction
/// 6110.1 — circumference method.
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
