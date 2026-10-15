/// History rows for the body-scan history list (design s17, s12.3-12.5a, D-54,
/// D-73). Pure Dart over the two places a scan can live: the encrypted local
/// record and the server document, merged to ONE row per scan.
///
/// Nothing here is stored: the baseline marker, the change label and the "new
/// estimator" marker are derived from the segmented trend, so they survive the
/// deletion of the first scan and never compare across estimators.
library;

import '../../progress_photos/scan/scan_models.dart';
import '../data/body_fat_estimate.dart';
import '../data/body_scan_entry.dart';
import '../data/scan_trend.dart';

/// One scan in the history.
class ScanHistoryRow {
  const ScanHistoryRow({
    required this.id,
    required this.takenAt,
    this.weightKg,
    this.estimate,
    this.record,
    this.entry,
    this.isBaseline = false,
    this.startsNewEstimator = false,
    this.change,
  });

  /// The id the result route takes: the local record id when there is one,
  /// else the server scan id.
  final String id;
  final DateTime takenAt;
  final double? weightKg;

  /// Null for a legacy (v1) photo-only scan.
  final BodyFatEstimate? estimate;
  final ScanRecord? record;
  final BodyScanEntry? entry;

  /// First reading of its estimator's series (D-54).
  final bool isBaseline;

  /// A different estimator took over at this scan: nothing before it is
  /// comparable (D-54, D-73).
  final bool startsNewEstimator;

  /// Against the previous reading of the SAME estimator; null for the first.
  final ChangeLabel? change;

  bool get provisional => estimate?.provisional ?? false;

  /// A photo-only scan without any estimate.
  bool get photosOnly => estimate == null;

  /// The server delete of this scan is owed (it was queued offline).
  bool get deletePending => record?.pendingRemoteDelete ?? false;

  /// Photos that can still be opened on this phone.
  bool get hasLocalPhotos => record != null && record!.shots.isNotEmpty;

  /// A copy of the photos may exist on the server (cloud path only).
  bool get mayHaveServerPhotos {
    final e = entry;
    if (e != null) {
      return e.photosState == PhotosState.stored ||
          e.photosState == PhotosState.awaitingUpload;
    }
    final a = record?.analysis;
    return a != null && a.remoteStatus != null;
  }

  /// The id the server knows this scan by; null for a local-only scan.
  String? get serverScanId =>
      entry?.scanId ?? (mayHaveServerPhotos ? record?.remoteId : null);
}

/// Merges [records] and [entries] into rows, newest first.
List<ScanHistoryRow> buildHistoryRows({
  required Iterable<ScanRecord> records,
  required Iterable<BodyScanEntry> entries,
  required ScanTrend trend,
}) {
  // Entry ids already shown through a local record.
  final byRemote = {for (final e in entries) e.scanId: e};
  final consumed = <String>{};

  // Series position of every reading, keyed by scan id.
  final baselines = <String>{};
  final changes = <String, ChangeLabel>{};
  for (final s in trend.series) {
    for (var i = 0; i < s.points.length; i++) {
      final id = s.points[i].reading.scanId;
      if (id == null) continue;
      if (i == 0) {
        baselines.add(id);
      } else {
        changes[id] = changeLabelBetween(
          s.points[i - 1].reading,
          s.points[i].reading,
        );
      }
    }
  }
  final switches = {for (final t in trend.modelChangeAt) t.millisecondsSinceEpoch};

  ScanHistoryRow make({
    required String id,
    required DateTime at,
    required double? weight,
    required BodyFatEstimate? estimate,
    ScanRecord? record,
    BodyScanEntry? entry,
    required List<String> readingIds,
  }) {
    String? readingId;
    for (final r in readingIds) {
      if (baselines.contains(r) || changes.containsKey(r)) readingId = r;
    }
    return ScanHistoryRow(
      id: id,
      takenAt: at,
      weightKg: weight,
      estimate: estimate,
      record: record,
      entry: entry,
      isBaseline: readingId != null && baselines.contains(readingId),
      startsNewEstimator:
          estimate != null && switches.contains(at.millisecondsSinceEpoch),
      change: readingId == null ? null : changes[readingId],
    );
  }

  final rows = <ScanHistoryRow>[];
  for (final r in records) {
    final entry = byRemote[r.remoteId];
    if (entry != null) consumed.add(entry.scanId);
    final serverEstimate = entry != null && entry.hasResult ? entry.estimate : null;
    final estimate = serverEstimate ?? r.analysis?.estimate;
    // A queued or failed scan with no result is the resume card's business; a
    // legacy v1 scan has no analysis and stays as a photo-only row.
    if (estimate == null && r.analysis != null) continue;
    rows.add(make(
      id: r.id,
      at: entry?.takenAt ?? r.createdAt,
      weight: entry?.weightKg ?? r.weightKg,
      estimate: estimate,
      record: r,
      entry: entry,
      readingIds: [r.id, r.remoteId],
    ));
  }
  for (final e in entries) {
    if (consumed.contains(e.scanId) || !e.hasResult) continue;
    rows.add(make(
      id: e.scanId,
      at: e.takenAt,
      weight: e.weightKg,
      estimate: e.estimate,
      entry: e,
      readingIds: [e.scanId],
    ));
  }
  rows.sort((a, b) => b.takenAt.compareTo(a.takenAt));
  return List.unmodifiable(rows);
}
