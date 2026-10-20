/// Body-fat trend: irregular-interval smoothing, the noise threshold, the
/// 4-week label and the per-estimator series segmentation (design s12.3-12.5a,
/// D-37, D-54, D-73). Pure Dart, no Flutter imports.
///
/// The shared EWMA primitives come from `core/math/series_math.dart`, so
/// neither feature depends on the other for maths (D-71).
library;

import 'dart:math' as math;

import '../../../core/math/series_math.dart';

/// Parameters of the body-fat trend [OWN] (design s29).
class TrendConfig {
  const TrendConfig({
    this.tauDays = 21,
    this.winsorPts = 4.0,
    this.warmupMean = true,
    this.trendIntervalFloor = 0.85,
    this.noiseFloorPts = 1.0,
    this.fourWeekDays = 28,
    this.fourWeekFactor = 0.8,
    this.fourWeekMinReadings = 3,
    this.trendIntervalMinReadings = 3,
  });

  final double tauDays;
  final double winsorPts;

  /// D-37: first readings are weighted like a running mean (alpha >= 1/n).
  final bool warmupMean;
  final double trendIntervalFloor;
  final double noiseFloorPts;
  final int fourWeekDays;
  final double fourWeekFactor;
  final int fourWeekMinReadings;
  final int trendIntervalMinReadings;

  static const standard = TrendConfig();
}

/// One reading of the series.
class ScanReading {
  const ScanReading({
    required this.at,
    required this.value,
    required this.halfWidth,
    required this.modelId,
    required this.modelVersion,
    this.scanId,
  });

  final DateTime at;
  final double value;
  final double halfWidth;
  final String modelId;
  final String modelVersion;
  final String? scanId;

  String get modelKey => '$modelId|$modelVersion';
}

enum ChangeLabel { noMeaningfulChange, down, up }

/// `noisePts = max(1.0, sqrt(hwNew^2 + hwPrev^2))` (design 12.3). With the
/// provisional half-width of 5 this is about 7.07, so every weekly change reads
/// "no meaningful change" by construction.
double noiseThresholdPts(
  double hwNew,
  double hwPrevious, {
  double floorPts = 1.0,
}) =>
    math.max(floorPts, math.sqrt(hwNew * hwNew + hwPrevious * hwPrevious));

/// Label for a new reading against the previous one OF THE SAME ESTIMATOR:
/// within the noise threshold (inclusive) is no meaningful change.
ChangeLabel changeLabelBetween(
  ScanReading previous,
  ScanReading current, {
  TrendConfig config = TrendConfig.standard,
}) {
  final d = current.value - previous.value;
  final noise = noiseThresholdPts(
    current.halfWidth,
    previous.halfWidth,
    floorPts: config.noiseFloorPts,
  );
  if (d.abs() <= noise) return ChangeLabel.noMeaningfulChange;
  return d < 0 ? ChangeLabel.down : ChangeLabel.up;
}

/// A reading with its smoothed value.
class SmoothedPoint {
  const SmoothedPoint({
    required this.reading,
    required this.smoothed,
    required this.isOutlier,
    required this.weight,
  });

  final ScanReading reading;

  /// `S_t` after this reading.
  final double smoothed;

  /// The raw value was beyond the winsorising bound of the previous smoothed
  /// value (it is still plotted, marked, and enters the smoothing clamped).
  final bool isOutlier;

  /// The weight of this reading in the LATEST smoothed value (weights sum to
  /// 1 across the series).
  final double weight;
}

/// The series of one estimator (`modelId` + `modelVersion`).
class TrendSeries {
  const TrendSeries({required this.modelKey, required this.points});

  final String modelKey;
  final List<SmoothedPoint> points;

  bool get isEmpty => points.isEmpty;
  SmoothedPoint get latest => points.last;
  SmoothedPoint get baseline => points.first;

  /// The baseline's RAW value (start value for points to goal), derived on the
  /// client, never stored (D-54).
  double get startValue => points.first.reading.value;

  /// `S_t`, the latest smoothed value.
  double get smoothedNow => points.last.smoothed;

  /// Effective sample size of the EWMA weights: `(sum w)^2 / sum w^2`.
  double get effectiveN {
    var sum = 0.0;
    var sq = 0.0;
    for (final p in points) {
      sum += p.weight;
      sq += p.weight * p.weight;
    }
    return sq == 0 ? 0 : sum * sum / sq;
  }

  /// Weighted mean half-width over the EWMA window.
  double get meanHalfWidth {
    var acc = 0.0;
    for (final p in points) {
      acc += p.weight * p.reading.halfWidth;
    }
    return acc;
  }
}

class ScanTrend {
  const ScanTrend({
    required this.series,
    required this.active,
    required this.modelChangeAt,
  });

  /// One series per estimator, ordered by the time of its first reading.
  final List<TrendSeries> series;

  /// The series of the NEWEST reading's estimator; null for no readings.
  final TrendSeries? active;

  /// Times at which a different estimator took over (the chart's "new
  /// estimator" markers). No comparison is ever made across them.
  final List<DateTime> modelChangeAt;
}

/// Builds the segmented, smoothed trend. Readings are sorted by time inside.
ScanTrend computeScanTrend(
  List<ScanReading> readings, {
  TrendConfig config = TrendConfig.standard,
}) {
  final sorted = [...readings]..sort((a, b) => a.at.compareTo(b.at));
  final order = <String>[];
  final groups = <String, List<ScanReading>>{};
  final changes = <DateTime>[];
  String? lastKey;
  for (final r in sorted) {
    if (!groups.containsKey(r.modelKey)) {
      order.add(r.modelKey);
      groups[r.modelKey] = [];
    }
    groups[r.modelKey]!.add(r);
    if (lastKey != null && lastKey != r.modelKey) changes.add(r.at);
    lastKey = r.modelKey;
  }
  final series = [
    for (final k in order) _buildSeries(k, groups[k]!, config),
  ];
  return ScanTrend(
    series: series,
    active: sorted.isEmpty
        ? null
        : series.firstWhere((s) => s.modelKey == sorted.last.modelKey),
    modelChangeAt: changes,
  );
}

TrendSeries _buildSeries(
  String key,
  List<ScanReading> rs,
  TrendConfig c,
) {
  final smoothed = <double>[rs.first.value];
  final alphas = <double>[1.0];
  final outlier = <bool>[false];
  for (var i = 1; i < rs.length; i++) {
    final dDays = rs[i].at.difference(rs[i - 1].at).inMinutes / 1440.0;
    final alpha = ewmaAlpha(
      dDays: dDays,
      tauDays: c.tauDays,
      readingCount: c.warmupMean ? i + 1 : null,
    );
    final prev = smoothed.last;
    outlier.add((rs[i].value - prev).abs() > c.winsorPts);
    smoothed.add(ewmaStep(
      previous: prev,
      reading: rs[i].value,
      alpha: alpha,
      winsorPts: c.winsorPts,
    ));
    alphas.add(alpha);
  }
  // Weight of reading i in the latest value: alpha_i times the product of
  // (1 - alpha_j) for j > i; the first reading carries the remainder.
  final weights = List<double>.filled(rs.length, 0);
  var carry = 1.0;
  for (var i = rs.length - 1; i >= 1; i--) {
    weights[i] = alphas[i] * carry;
    carry *= 1 - alphas[i];
  }
  weights[0] = carry;
  return TrendSeries(
    modelKey: key,
    points: [
      for (var i = 0; i < rs.length; i++)
        SmoothedPoint(
          reading: rs[i],
          smoothed: smoothed[i],
          isOutlier: outlier[i],
          weight: weights[i],
        ),
    ],
  );
}

/// Trend interval half-width `hwMean * max(floor, n_eff^-0.5)`, shown only
/// from the third reading; null before that (the single reading's own range
/// is shown instead). We never narrow a provider's per-reading range.
double? trendHalfWidth(
  TrendSeries s, {
  TrendConfig config = TrendConfig.standard,
}) {
  if (s.points.length < config.trendIntervalMinReadings) return null;
  final n = s.effectiveN;
  if (n <= 0) return null;
  return s.meanHalfWidth * math.max(config.trendIntervalFloor, 1 / math.sqrt(n));
}

/// The 4-week trend label: the smoothed value now against the smoothed value
/// 28 days earlier, within ONE estimator's series. Needs at least three
/// readings in the last 28 days, else null. Meaningful iff
/// `|S_t - S_(t-28d)| > max(1.0, 0.8 * mean(hw))` (equal is not meaningful).
///
/// The reference `S_(t-28d)` is the smoothed value of the newest reading at or
/// before `latest - 28 d`, or the series' first smoothed value when the series
/// is younger than that.
ChangeLabel? fourWeekLabel(
  TrendSeries s, {
  TrendConfig config = TrendConfig.standard,
}) {
  if (s.isEmpty) return null;
  final end = s.latest.reading.at;
  final windowMinutes = config.fourWeekDays * 1440;
  final inWindow = [
    for (final p in s.points)
      if (end.difference(p.reading.at).inMinutes <= windowMinutes) p,
  ];
  if (inWindow.length < config.fourWeekMinReadings) return null;
  SmoothedPoint? reference;
  for (final p in s.points) {
    if (end.difference(p.reading.at).inMinutes >= windowMinutes) reference = p;
  }
  final refValue = reference?.smoothed ?? s.points.first.smoothed;
  final meanHw =
      inWindow.fold<double>(0, (a, p) => a + p.reading.halfWidth) /
          inWindow.length;
  final threshold = math.max(
    config.noiseFloorPts,
    config.fourWeekFactor * meanHw,
  );
  final d = s.smoothedNow - refValue;
  if (d.abs() <= threshold) return ChangeLabel.noMeaningfulChange;
  return d < 0 ? ChangeLabel.down : ChangeLabel.up;
}

/// The change label of the newest reading against the previous one of the same
/// estimator; null when the active series has fewer than two readings.
ChangeLabel? latestChangeLabel(
  TrendSeries s, {
  TrendConfig config = TrendConfig.standard,
}) {
  if (s.points.length < 2) return null;
  return changeLabelBetween(
    s.points[s.points.length - 2].reading,
    s.latest.reading,
    config: config,
  );
}
