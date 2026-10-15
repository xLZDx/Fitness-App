/// The REAL `ScanPlanContextSource` (D-71, D-74, SD-9): turns the device-local
/// eligibility verdict, the plan and the weekly decision into what the scan
/// surfaces may show. body_scan only sees the port in
/// `body_scan/data/scan_plan_context.dart`; this implementation is bound at the
/// app root (`scanPlanContextProvider.overrideWith(...)`), which replaces the
/// measurement-only placeholder.
///
/// Rules: the surface mode follows the verdict (`full` only for `eligible` and
/// `needsProfile`; `referProfessional` and `needsAnswer` are measurement only,
/// no figures at all); the decision and the target body fat are given ONLY to
/// an eligible user; an unknown verdict is measurement only. Hiding the
/// decision while the estimator is provisional is the result screen's job (it
/// knows the series).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../body_scan/data/scan_plan_context.dart';
import '../data/nutrition_eligibility.dart';
import 'nutrition_providers.dart';

class NutritionScanPlanContextSource extends ScanPlanContextSource {
  const NutritionScanPlanContextSource(this._context);

  final ScanPlanContext _context;

  /// Builds the context for [verdict] (pure; unit-testable).
  factory NutritionScanPlanContextSource.from({
    required NutritionEligibility? verdict,
    required ScanPlanContext eligibleContext,
  }) {
    if (verdict == null) {
      return const NutritionScanPlanContextSource(
          ScanPlanContext.measurementOnly);
    }
    final mode = surfaceModeFor(verdict);
    if (verdict is! Eligible) {
      return NutritionScanPlanContextSource(ScanPlanContext(surfaceMode: mode));
    }
    return NutritionScanPlanContextSource(eligibleContext);
  }

  @override
  ScanPlanContext current() => _context;
}

/// The live source. Watch it from the app-root override of the body_scan port.
final nutritionScanPlanContextSourceProvider =
    Provider<ScanPlanContextSource>((ref) {
  final verdict = ref.watch(nutritionEligibilityProvider);
  final inputs = ref.watch(nutritionInputsProvider)?.inputs;
  return NutritionScanPlanContextSource.from(
    verdict: verdict,
    eligibleContext: ScanPlanContext(
      surfaceMode: ScanSurfaceMode.full,
      decision: ref.watch(weeklyReviewProvider),
      targetBodyFatPct: inputs?.targetBodyFatPct,
    ),
  );
});
