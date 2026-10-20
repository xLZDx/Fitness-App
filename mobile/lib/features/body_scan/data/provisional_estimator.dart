/// The estimator provider interface and the PROVISIONAL on-device estimator
/// (design s8, D-3, D-52). Pure Dart, no Flutter imports.
///
/// There is NO validated photo-based body-fat model in this repository. The
/// shipped estimator is the Deurenberg et al. (1991, Br J Nutr 65:105-114)
/// anthropometric equation, which uses ONLY height, weight, age and sex; the
/// photos are ignored, so no photo leaves the device while it is active. The
/// half-width of 5.0 points is a deliberately wide PLACEHOLDER, not a measured
/// accuracy; no accuracy number is claimed anywhere.
library;

import '../../nutrition_plan/data/energy_math.dart';
import 'body_fat_estimate.dart';
import 'check_items.dart';

/// Who is being measured. The weight range is 30..300 everywhere (D-52).
class EstimatorSubject {
  const EstimatorSubject({
    required this.heightCm,
    required this.weightKg,
    required this.ageYears,
    required this.sex,
  });

  final double heightCm;
  final double weightKg;
  final int ageYears;
  final SexBasis sex;

  double? get bmi => bmiOf(weightKg, heightCm);
}

class EstimatorInput {
  const EstimatorInput({
    required this.scanId,
    required this.subject,
    this.manualOverride = false,
  });

  final String scanId;
  final EstimatorSubject subject;

  /// A pose was captured with the manual shutter while not ready.
  final bool manualOverride;
}

/// A body-composition estimator behind the provider interface. A real
/// photo-based provider is a later swap; this interface is what it implements.
abstract class BodyCompositionEstimator {
  String get id;
  String get version;

  /// True => the UI shows the provisional banner.
  bool get provisional;
  bool get requiresPhotos;

  Future<BodyFatEstimate> estimate(EstimatorInput input);
}

/// Deurenberg: `BF% = 1.20 BMI + 0.23 age - 10.8 s - 5.4`, with `s = 1` male,
/// `0` female, `0.5` unspecified. Not clamped.
double deurenbergBodyFatPct({
  required double bmi,
  required int ageYears,
  required SexBasis sex,
}) {
  final s = switch (sex) {
    SexBasis.male => 1.0,
    SexBasis.female => 0.0,
    SexBasis.unspecified => 0.5,
  };
  return 1.20 * bmi + 0.23 * ageYears - 10.8 * s - 5.4;
}

class ProvisionalEstimator implements BodyCompositionEstimator {
  const ProvisionalEstimator();

  static const String estimatorId = 'provisional-anthropometric';
  static const String estimatorVersion = 'deurenberg-1991-v0';

  /// Output clamp of the value [OWN].
  static const double minValue = 5;
  static const double maxValue = 55;

  /// Placeholder half-width in percentage points [OWN]; NOT an accuracy.
  static const double halfWidthPts = 5.0;

  /// The range edges stay inside the plausibility window [3, 60] so a valid
  /// reading is never rejected by `validateEstimate`/`evaluatePlausibility`.
  static const double rangeFloor = 3;
  static const double rangeCeiling = 60;

  @override
  String get id => estimatorId;

  @override
  String get version => estimatorVersion;

  @override
  bool get provisional => true;

  @override
  bool get requiresPhotos => false;

  /// Synchronous form; photos play no part.
  BodyFatEstimate estimateNow(EstimatorSubject subject,
      {bool manualOverride = false}) {
    final bmi = subject.bmi ?? 0;
    final raw = deurenbergBodyFatPct(
      bmi: bmi,
      ageYears: subject.ageYears,
      sex: subject.sex,
    );
    final value = raw.clamp(minValue, maxValue).toDouble();
    final low = (value - halfWidthPts).clamp(rangeFloor, rangeCeiling).toDouble();
    final high =
        (value + halfWidthPts).clamp(rangeFloor, rangeCeiling).toDouble();
    return BodyFatEstimate(
      value: value,
      low: low,
      high: high,
      confidence: EstimateConfidence.low,
      modelId: estimatorId,
      modelVersion: estimatorVersion,
      provisional: true,
      checkCodes: [
        CheckCode.provisionalEstimator,
        if (manualOverride) CheckCode.manualCapture,
      ],
    );
  }

  @override
  Future<BodyFatEstimate> estimate(EstimatorInput input) async =>
      estimateNow(input.subject, manualOverride: input.manualOverride);
}
