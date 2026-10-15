/// What the result screen shows for one scan, decided in pure Dart so the
/// provisional presentation rules (D-73) and the measurement-only mode (D-74)
/// are testable without a widget tree.
library;

import '../data/body_fat_estimate.dart';
import '../data/check_items.dart';
import '../data/scan_plan_context.dart';
import '../data/scan_result_math.dart';
import '../data/scan_trend.dart';
import 'scan_result_source.dart';

enum WeightTrendDirection { down, up, flat, unknown }

class ScanResultViewModel {
  const ScanResultViewModel({
    required this.data,
    required this.surfaceMode,
    required this.series,
    required this.modelChangeAt,
    required this.changeLabel,
    required this.noisePts,
    required this.trendLabel,
    required this.pointsToGoal,
    required this.showGoalFigures,
    required this.showChange,
    required this.showPlanDecision,
    required this.showSeePlanAction,
    required this.trendSplit,
    required this.readingSplit,
    required this.weightTrend,
    required this.checks,
  });

  final ScanResultData data;
  final ScanSurfaceMode surfaceMode;

  /// The active (latest estimator) series; null when there is no reading.
  final TrendSeries? series;
  final List<DateTime> modelChangeAt;

  /// Latest reading vs the previous one of the SAME estimator; null with a
  /// single reading.
  final ChangeLabel? changeLabel;
  final double? noisePts;

  /// Four-week trend label of the active series; null with too few readings.
  final ChangeLabel? trendLabel;
  final double? pointsToGoal;

  /// Ring, points to go and ETA (hidden while provisional or measurement only).
  final bool showGoalFigures;

  /// Fat/lean CHANGE labels and the "change since last scan" line.
  final bool showChange;
  final bool showPlanDecision;

  /// Provisional replacement of the plan decision card.
  final bool showSeePlanAction;

  /// Fat/lean tiles computed from the smoothed trend ("from your trend").
  final MassSplit? trendSplit;

  /// Fat/lean tiles for this single reading ("this reading").
  final MassSplit? readingSplit;
  final WeightTrendDirection weightTrend;
  final List<CheckCode> checks;

  BodyFatEstimate get estimate => data.estimate;
  bool get provisional => data.estimate.provisional;
  bool get measurementOnly => surfaceMode == ScanSurfaceMode.measurementOnly;

  /// Weight first headline while the series is provisional (D-73).
  bool get weightFirst => provisional;

  /// Smoothed value of the active series, null when none.
  double? get smoothedNow => series?.smoothedNow;
}

/// Slope under this magnitude (kg per week) reads as steady.
const double kSteadyWeightSlopeKgPerWeek = 0.1;

ScanResultViewModel buildScanResultViewModel(
  ScanResultData data,
  ScanPlanContext plan,
) {
  final est = data.estimate;
  final trend = computeScanTrend(data.readings);
  final series = trend.active;
  final measurementOnly = plan.surfaceMode == ScanSurfaceMode.measurementOnly;
  final provisional = est.provisional;

  ChangeLabel? change;
  double? noise;
  if (series != null && series.points.length >= 2) {
    final prev = series.points[series.points.length - 2].reading;
    final cur = series.latest.reading;
    change = changeLabelBetween(prev, cur);
    noise = noiseThresholdPts(cur.halfWidth, prev.halfWidth);
  }

  final showGoal = !measurementOnly &&
      !provisional &&
      plan.targetBodyFatPct != null &&
      series != null;
  final smoothed = series?.smoothedNow;

  MassSplit? trendSplit;
  if (!measurementOnly && !provisional && smoothed != null) {
    trendSplit = massSplit(
      weightKg: data.weightKg,
      valuePct: smoothed,
      lowPct: smoothed - est.halfWidth,
      highPct: smoothed + est.halfWidth,
    );
  }
  final readingSplit = measurementOnly
      ? null
      : massSplit(
          weightKg: data.weightKg,
          valuePct: est.value,
          lowPct: est.low,
          highPct: est.high,
        );

  final slope = data.weightSlopeKgPerWeek;
  final direction = slope == null
      ? WeightTrendDirection.unknown
      : slope.abs() < kSteadyWeightSlopeKgPerWeek
          ? WeightTrendDirection.flat
          : slope < 0
              ? WeightTrendDirection.down
              : WeightTrendDirection.up;

  final checks = <CheckCode>[
    if (provisional && !est.checkCodes.contains(CheckCode.provisionalEstimator))
      CheckCode.provisionalEstimator,
    ...est.checkCodes,
  ];

  final full = plan.surfaceMode == ScanSurfaceMode.full;
  return ScanResultViewModel(
    data: data,
    surfaceMode: plan.surfaceMode,
    series: series,
    modelChangeAt: trend.modelChangeAt,
    changeLabel: change,
    noisePts: noise,
    trendLabel: series == null ? null : fourWeekLabel(series),
    pointsToGoal: showGoal
        ? pointsToGoal(
            smoothedPct: smoothed, targetBodyFatPct: plan.targetBodyFatPct)
        : null,
    showGoalFigures: showGoal,
    showChange: !measurementOnly && !provisional && change != null,
    showPlanDecision: full && !provisional && plan.decision != null,
    showSeePlanAction: full && provisional,
    trendSplit: trendSplit,
    readingSplit: readingSplit,
    weightTrend: direction,
    checks: checks,
  );
}
