/// Plausibility and trend verification of one estimate (design s12.4). Pure
/// Dart, no Flutter imports.
library;

import 'dart:math' as math;

import 'body_fat_estimate.dart';
import 'check_items.dart';

/// Thresholds, all [OWN] (design s29).
abstract final class PlausibilityLimits {
  /// A value outside this window is rejected and the scan stays unresolved.
  static const double valueMin = 3;
  static const double valueMax = 60;

  /// `|v - deurenberg(profile)|` above this raises `estimateFarFromProfile`.
  static const double farFromProfilePts = 12;

  /// A recorded weight differing from the previous scan's by MORE than this
  /// many kg within [weightJumpDays] raises `weightJump`.
  static const double weightJumpKg = 3;
  static const int weightJumpDays = 7;

  /// A half-width ABOVE this raises `wideRange` and caps confidence at low.
  static const double wideHalfWidthPts = 4;

  /// `|v_t - S_{t-1}|` above `max(largeJumpFloorPts, largeJumpHwFactor * hw)`
  /// raises `largeJumpVsTrend`.
  static const double largeJumpFloorPts = 4;
  static const double largeJumpHwFactor = 2.5;
}

/// Everything the check needs; every context value is optional so a missing
/// one simply skips its check.
class PlausibilityInput {
  const PlausibilityInput({
    required this.estimate,
    this.profileExpectedPct,
    this.recordedWeightKg,
    this.weightAgeDays,
    this.previousScanWeightKg,
    this.daysSincePreviousScan,
    this.previousSmoothedPct,
    this.manualOverride = false,
  });

  final BodyFatEstimate estimate;

  /// The Deurenberg value for the profile, for the far-from-profile check.
  final double? profileExpectedPct;

  /// Null means no weight was recorded for the scan (`weightMissing`).
  final double? recordedWeightKg;

  /// How old the recorded weight is, in days (`weightStale` above 7).
  final double? weightAgeDays;
  final double? previousScanWeightKg;
  final double? daysSincePreviousScan;

  /// The smoothed trend value before this reading (`S_{t-1}`).
  final double? previousSmoothedPct;

  /// A pose was captured with the manual shutter while not ready.
  final bool manualOverride;
}

class PlausibilityResult {
  const PlausibilityResult({
    required this.rejected,
    required this.codes,
    required this.confidence,
  });

  /// `estimateOutOfRange`: the value must not be displayed; the scan stays
  /// unresolved with a retry.
  final bool rejected;

  /// Chips to show, in the stable declaration order of [CheckCode].
  final List<CheckCode> codes;
  final EstimateConfidence confidence;
}

PlausibilityResult evaluatePlausibility(PlausibilityInput i) {
  final e = i.estimate;
  if (!e.value.isFinite ||
      e.value < PlausibilityLimits.valueMin ||
      e.value > PlausibilityLimits.valueMax) {
    return PlausibilityResult(
      rejected: true,
      codes: List.unmodifiable(e.checkCodes),
      confidence: e.confidence,
    );
  }
  final codes = <CheckCode>{...e.checkCodes};
  var confidence = e.confidence;

  if (e.provisional) codes.add(CheckCode.provisionalEstimator);

  // Skipped for the provisional estimator: the comparison would be the formula
  // with itself (vacuous).
  final expected = i.profileExpectedPct;
  if (!e.provisional &&
      expected != null &&
      (e.value - expected).abs() > PlausibilityLimits.farFromProfilePts) {
    codes.add(CheckCode.estimateFarFromProfile);
    confidence = confidence.lowered;
  }

  if (e.halfWidth > PlausibilityLimits.wideHalfWidthPts) {
    codes.add(CheckCode.wideRange);
    confidence = EstimateConfidence.low;
  }

  final w = i.recordedWeightKg;
  if (w == null) {
    codes.add(CheckCode.weightMissing);
  } else {
    final age = i.weightAgeDays;
    if (age != null && age > CheckCode.weightStaleAfterDays) {
      codes.add(CheckCode.weightStale);
    }
    final prev = i.previousScanWeightKg;
    final gap = i.daysSincePreviousScan;
    if (prev != null &&
        gap != null &&
        gap <= PlausibilityLimits.weightJumpDays &&
        (w - prev).abs() > PlausibilityLimits.weightJumpKg) {
      codes.add(CheckCode.weightJump);
    }
  }

  final s = i.previousSmoothedPct;
  if (s != null &&
      (e.value - s).abs() >
          math.max(
            PlausibilityLimits.largeJumpFloorPts,
            PlausibilityLimits.largeJumpHwFactor * e.halfWidth,
          )) {
    codes.add(CheckCode.largeJumpVsTrend);
  }

  if (i.manualOverride) {
    codes.add(CheckCode.manualCapture);
    confidence = confidence.lowered;
  }

  return PlausibilityResult(
    rejected: false,
    codes: [
      for (final c in CheckCode.values)
        if (codes.contains(c)) c,
    ],
    confidence: confidence,
  );
}
