/// Narrow read port for one scan result (C15). The repository, weight and
/// training providers of the data layer (C14) are bound behind it at the app
/// root; until then the default source answers "not found" so the result route
/// shows a calm message instead of throwing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/body_fat_estimate.dart';
import '../data/scan_trend.dart';

/// Everything the result screen needs about one scan, already resolved.
class ScanResultData {
  const ScanResultData({
    required this.scanId,
    required this.takenAt,
    required this.estimate,
    required this.readings,
    this.weightKg,
    this.weightSlopeKgPerWeek,
    this.strengthSessionsLast4Weeks,
    this.terminalFailure = false,
  });

  final String scanId;
  final DateTime takenAt;
  final BodyFatEstimate estimate;

  /// Recorded weight for this scan.
  final double? weightKg;

  /// Every reading to chart, this scan included, any estimator. The view model
  /// segments them by estimator (D-54).
  final List<ScanReading> readings;

  /// Theil-Sen weight slope in kg per week; null = not enough data (12.5).
  final double? weightSlopeKgPerWeek;

  /// Strength sessions logged in the last 4 weeks; null = unknown.
  final int? strengthSessionsLast4Weeks;

  /// True when the scan ended in a terminal failure after the retries (D-78).
  final bool terminalFailure;
}

abstract class ScanResultSource {
  const ScanResultSource();

  /// Null when the scan does not exist (or is not readable).
  Future<ScanResultData?> load(String scanId);
}

/// Default until the data layer is bound: nothing is found.
class NoScanResultSource extends ScanResultSource {
  const NoScanResultSource();

  @override
  Future<ScanResultData?> load(String scanId) async => null;
}

final scanResultSourceProvider =
    Provider<ScanResultSource>((_) => const NoScanResultSource());

final scanResultProvider =
    FutureProvider.family<ScanResultData?, String>((ref, scanId) {
  return ref.watch(scanResultSourceProvider).load(scanId);
});
