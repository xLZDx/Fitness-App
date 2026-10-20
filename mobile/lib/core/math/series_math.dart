/// Shared pure numeric primitives for irregularly spaced series: exponential
/// smoothing and a robust (Theil-Sen) slope.
///
/// Lives in `core/math` rather than in a feature on purpose (D-71): both
/// `nutrition_plan` (weight series) and `body_scan` (body-fat series) need it,
/// and neither feature may depend on the other for maths. No Flutter imports.
///
/// Provenance tags (design s29): the smoothing form and the window numbers are
/// OWN choices; Theil-Sen is a published estimator (Theil 1950, Sen 1968).
library;

import 'dart:math' as math;

/// One timed observation.
class SeriesPoint {
  const SeriesPoint(this.at, this.value);

  final DateTime at;
  final double value;
}

/// Lower clamp for the gap between two readings, in days [OWN].
const double kEwmaMinGapDays = 0.5;

/// Upper clamp for the gap between two readings, in days [OWN].
const double kEwmaMaxGapDays = 28.0;

/// Smoothing weight of a new reading after [dDays] days.
///
/// `alpha = 1 - exp(-d / tau)` with `d = clamp(dDays, 0.5, 28)`. When
/// [readingCount] (the number of readings INCLUDING the new one) is given, the
/// warm-up rule of D-37 applies: `alpha = max(alpha, 1 / readingCount)`, so the
/// first readings are weighted like a running mean (the second reading gets
/// 0.5, the third 0.33) before the exponential rule takes over. Pass null to
/// get the plain exponential weight.
double ewmaAlpha({
  required double dDays,
  required double tauDays,
  int? readingCount,
}) {
  final d = dDays.clamp(kEwmaMinGapDays, kEwmaMaxGapDays).toDouble();
  final a = 1 - math.exp(-d / tauDays);
  if (readingCount == null || readingCount < 1) return a;
  return math.max(a, 1 / readingCount);
}

/// One smoothing step: `prev + alpha * (x - prev)`.
///
/// When [winsorPts] is set the reading is first clamped to
/// `prev +- winsorPts` (body fat only, D-18).
double ewmaStep({
  required double previous,
  required double reading,
  required double alpha,
  double? winsorPts,
}) {
  var x = reading;
  if (winsorPts != null) {
    x = x.clamp(previous - winsorPts, previous + winsorPts).toDouble();
  }
  return previous + alpha * (x - previous);
}

/// Smooths [points] (sorted ascending by time inside this function) and
/// returns one smoothed value per point. `S_0 = x_0`.
///
/// [warmupMean] turns the `1 / n` warm-up of D-37 on (body fat) or off
/// (weight, which uses the plain exponential weight).
List<double> ewmaSeries(
  List<SeriesPoint> points, {
  required double tauDays,
  double? winsorPts,
  bool warmupMean = false,
}) {
  if (points.isEmpty) return const [];
  final sorted = [...points]..sort((a, b) => a.at.compareTo(b.at));
  final out = <double>[sorted.first.value];
  for (var i = 1; i < sorted.length; i++) {
    final dDays = sorted[i].at.difference(sorted[i - 1].at).inMinutes / 1440.0;
    final alpha = ewmaAlpha(
      dDays: dDays,
      tauDays: tauDays,
      readingCount: warmupMean ? i + 1 : null,
    );
    out.add(ewmaStep(
      previous: out.last,
      reading: sorted[i].value,
      alpha: alpha,
      winsorPts: winsorPts,
    ));
  }
  return out;
}

/// Median of [values]; null for an empty list. The mean of the two middle
/// values for an even count.
double? median(List<double> values) {
  if (values.isEmpty) return null;
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// Theil-Sen slope per DAY: the median of `(v_j - v_i) / (d_j - d_i)` over all
/// pairs `i < j` whose time gap is at least [minPairGapDays]. Null when no pair
/// qualifies.
double? theilSenSlopePerDay(
  List<SeriesPoint> points, {
  double minPairGapDays = 2,
}) {
  final sorted = [...points]..sort((a, b) => a.at.compareTo(b.at));
  final slopes = <double>[];
  for (var i = 0; i < sorted.length; i++) {
    for (var j = i + 1; j < sorted.length; j++) {
      final dDays = sorted[j].at.difference(sorted[i].at).inMinutes / 1440.0;
      if (dDays < minPairGapDays) continue;
      slopes.add((sorted[j].value - sorted[i].value) / dDays);
    }
  }
  return median(slopes);
}

/// Windowed weekly Theil-Sen slope with the data-sufficiency rules of design
/// 12.5 [OWN]: only points within [windowDays] before [asOf] (default: the
/// newest point) count, at least [minPoints] of them, spanning at least
/// [minSpanDays]; otherwise null ("not enough data").
double? theilSenSlopePerWeek(
  List<SeriesPoint> points, {
  DateTime? asOf,
  double windowDays = 21,
  int minPoints = 3,
  double minSpanDays = 7,
  double minPairGapDays = 2,
}) {
  if (points.isEmpty) return null;
  final sorted = [...points]..sort((a, b) => a.at.compareTo(b.at));
  final end = asOf ?? sorted.last.at;
  final windowStartMinutes = (windowDays * 1440).round();
  final inWindow = [
    for (final p in sorted)
      if (!p.at.isAfter(end) &&
          end.difference(p.at).inMinutes <= windowStartMinutes)
        p,
  ];
  if (inWindow.length < minPoints) return null;
  final spanDays =
      inWindow.last.at.difference(inWindow.first.at).inMinutes / 1440.0;
  if (spanDays < minSpanDays) return null;
  final perDay = theilSenSlopePerDay(inWindow, minPairGapDays: minPairGapDays);
  return perDay == null ? null : perDay * 7;
}
