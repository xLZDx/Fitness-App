/// PORT through which the scan result reads the nutrition plan decision
/// without `body_scan` and `nutrition_plan` importing each other's state
/// (D-71, D-74, SD-9). Pure Dart, no Flutter imports.
///
/// The SAFE default is "no decision, measurement only": an unwired app hides
/// goal figures instead of showing wrong ones. The real implementation lives in
/// `nutrition_plan/state` and is bound only at the app root.
library;

import '../../nutrition_plan/data/nutrition_eligibility.dart';
import '../../nutrition_plan/data/weekly_review.dart';

/// How much of the goal-related surface a scan screen may show.
enum ScanSurfaceMode {
  /// Goal ring, points to go, ETA, target UI, fat/lean CHANGE tiles and the
  /// plan decision may be shown (subject to the provisional rules, D-73).
  full,

  /// Photo capture, compare and history only: no goal figures, no plan
  /// decision, no default reminder, estimate behind a neutral ask (D-74).
  measurementOnly,
}

class ScanPlanContext {
  const ScanPlanContext({
    this.surfaceMode = ScanSurfaceMode.measurementOnly,
    this.decision,
    this.targetBodyFatPct,
  });

  final ScanSurfaceMode surfaceMode;

  /// The same decision the weekly review produces (one decision path).
  final WeeklyReviewDecision? decision;
  final double? targetBodyFatPct;

  /// The safe default.
  static const measurementOnly = ScanPlanContext();
}

/// Supplies the context; implemented in `nutrition_plan/state`.
abstract class ScanPlanContextSource {
  const ScanPlanContextSource();

  ScanPlanContext current();
}

/// The safe default source: no decision, measurement only.
class MeasurementOnlyScanPlanContextSource extends ScanPlanContextSource {
  const MeasurementOnlyScanPlanContextSource();

  @override
  ScanPlanContext current() => ScanPlanContext.measurementOnly;
}

/// Surface mode for an eligibility verdict: `full` only when eligible or when
/// only profile inputs are missing (then target-dependent items stay hidden
/// because there is no target/decision); `referProfessional` and `needsAnswer`
/// are measurement only.
ScanSurfaceMode surfaceModeFor(NutritionEligibility verdict) => switch (verdict) {
      Eligible() || NeedsProfile() => ScanSurfaceMode.full,
      ReferProfessional() || NeedsAnswer() => ScanSurfaceMode.measurementOnly,
    };
