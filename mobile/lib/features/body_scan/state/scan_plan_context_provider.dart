/// The body_scan side of the `ScanPlanContextSource` port (D-71, D-74, SD-9).
///
/// The provider's DEFAULT is the safe one: measurement only, no decision. The
/// real source lives in `nutrition_plan/state/scan_plan_context_source.dart`
/// (`nutritionScanPlanContextSourceProvider`) and is bound only at the app
/// root. Until C18 binds it, the app root installs the explicit, named
/// [kScanPlanContextPlaceholder] so the gap is visible in the wiring instead of
/// being an accident of a default.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/scan_plan_context.dart';

/// The named placeholder installed at the app root until C18 replaces it with
/// `nutritionScanPlanContextSourceProvider`. It hides every goal figure.
const ScanPlanContextSource kScanPlanContextPlaceholder =
    MeasurementOnlyScanPlanContextSource();

final scanPlanContextProvider = Provider<ScanPlanContextSource>(
  (_) => const MeasurementOnlyScanPlanContextSource(),
);

/// The context the scan surfaces render from.
final scanPlanContextValueProvider = Provider<ScanPlanContext>(
  (ref) => ref.watch(scanPlanContextProvider).current(),
);
