/// Readings and the trend source (design s12.3-12.5a, D-54, D-71). Pure Dart
/// helpers over the two places a scan result can live: the encrypted local
/// record (`analysis.estimate`, provisional or a finished cloud scan) and the
/// server document (`BodyScanEntry`, cloud path). One reading per scan id, the
/// server copy winning, so a finished cloud scan is never counted twice.
library;

import '../../nutrition_plan/data/body_fat_trend_source.dart';
import '../../progress_photos/scan/scan_models.dart';
import '../data/body_scan_entry.dart';
import '../data/provisional_estimator.dart';
import '../data/scan_trend.dart';

/// Readings from both sources, deduplicated by scan id (the remote id of a
/// local record), sorted by time inside [computeScanTrend].
List<ScanReading> readingsFrom({
  required Iterable<ScanRecord> records,
  required Iterable<BodyScanEntry> entries,
}) {
  final byId = <String, ScanReading>{};
  for (final r in records) {
    final e = r.analysis?.estimate;
    if (e == null) continue;
    byId[r.remoteId] = ScanReading(
      at: r.createdAt,
      value: e.value,
      halfWidth: e.halfWidth,
      modelId: e.modelId,
      modelVersion: e.modelVersion,
      scanId: r.id,
    );
  }
  for (final s in entries) {
    final e = s.estimate;
    if (!s.hasResult || e == null) continue;
    byId[s.scanId] = ScanReading(
      at: s.takenAt,
      value: e.value,
      halfWidth: e.halfWidth,
      modelId: e.modelId,
      modelVersion: e.modelVersion,
      scanId: s.scanId,
    );
  }
  return byId.values.toList(growable: false);
}

/// The trend as the weekly review needs it, or null when there is no series or
/// fewer than the three readings the 4-week label requires. A provisional
/// estimator or an estimator change inside the window is flagged so the review
/// ignores it (D-54, D-71).
BodyFatTrendInput? bodyFatTrendInputFor(
  ScanTrend trend, {
  TrendConfig config = TrendConfig.standard,
}) {
  final s = trend.active;
  if (s == null || s.isEmpty) return null;
  final label = fourWeekLabel(s, config: config);
  if (label == null) return null;

  final end = s.latest.reading.at;
  final windowMinutes = config.fourWeekDays * 1440;
  SmoothedPoint? reference;
  for (final p in s.points) {
    if (end.difference(p.reading.at).inMinutes >= windowMinutes) reference = p;
  }
  final refValue = reference?.smoothed ?? s.points.first.smoothed;
  final change = s.smoothedNow - refValue;

  final changedInWindow = trend.modelChangeAt.any(
    (t) => end.difference(t).inMinutes <= windowMinutes,
  );
  return BodyFatTrendInput(
    meaningful: label != ChangeLabel.noMeaningfulChange,
    changePts: change.isFinite ? change : 0,
    modelId: s.latest.reading.modelId,
    provisional: s.latest.reading.modelId == ProvisionalEstimator.estimatorId,
    seriesChanged: changedInWindow,
  );
}

/// `BodyFatTrendSource` backed by a trend value; bound at the app root
/// (`bodyFatTrendSourceProvider.overrideWith(...)`), replacing the
/// `NoBodyFatTrendSource` default.
class ScanBodyFatTrendSource extends BodyFatTrendSource {
  const ScanBodyFatTrendSource(this._trend);

  final ScanTrend _trend;

  @override
  BodyFatTrendInput? currentTrend() => bodyFatTrendInputFor(_trend);
}
