// C16 functional tests: scan history rows (design s17, D-54, D-73). The rows
// merge local records and server entries into ONE row per scan; baseline,
// change label and "new estimator" marker are derived from the segmented trend
// and never compare across estimators.
import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_entry.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/body_scan/data/scan_trend.dart';
import 'package:fitness_app/features/body_scan/state/scan_history_rows.dart';
import 'package:fitness_app/features/body_scan/state/scan_trend_source.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:flutter_test/flutter_test.dart';

const _photo = 'photo-model';
const _prov = 'provisional-anthropometric';

BodyFatEstimate _est(
  double value, {
  String modelId = _photo,
  String version = '1',
  bool provisional = false,
  double hw = 2.0,
}) =>
    BodyFatEstimate(
      value: value,
      low: value - hw,
      high: value + hw,
      confidence: EstimateConfidence.medium,
      modelId: modelId,
      modelVersion: version,
      provisional: provisional,
    );

BodyScanEntry _entry(
  String id,
  DateTime at,
  BodyFatEstimate? estimate, {
  ScanDocStatus status = ScanDocStatus.done,
  PhotosState photos = PhotosState.stored,
  double? weight,
}) =>
    BodyScanEntry(
      scanId: id,
      takenAt: at,
      status: status,
      photosState: photos,
      weightKg: weight,
      estimate: estimate,
    );

ScanShot _shot() => const ScanShot(photoId: 'p', landmarks: []);

ScanRecord _record(
  String id,
  DateTime at, {
  BodyFatEstimate? estimate,
  bool legacy = false,
  JobStatus status = JobStatus.done,
  String? remoteId,
  String? remoteStatus,
  double? weight,
  bool pendingDelete = false,
  bool withShots = true,
}) =>
    ScanRecord(
      id: id,
      createdAt: at,
      shots: withShots ? {ScanPose.front: _shot()} : const {},
      analysis: legacy
          ? null
          : ScanAnalysis(
              status: status,
              estimate: estimate,
              remoteId: remoteId,
              remoteStatus: remoteStatus,
            ),
      weightKg: weight,
      pendingRemoteDelete: pendingDelete,
    );

List<ScanHistoryRow> _rows(
  List<ScanRecord> records,
  List<BodyScanEntry> entries,
) {
  final trend =
      computeScanTrend(readingsFrom(records: records, entries: entries));
  return buildHistoryRows(records: records, entries: entries, trend: trend);
}

ScanHistoryRow _byId(List<ScanHistoryRow> rows, String id) =>
    rows.firstWhere((r) => r.id == id);

final _d0 = DateTime(2026, 9, 1, 9);
DateTime _day(int n) => _d0.add(Duration(days: 7 * n));

void main() {
  group('merge of local records and server entries', () {
    test('a record and the entry it points to via remoteId become ONE row', () {
      final rec = _record('local-1', _day(0),
          estimate: _est(20), remoteId: 'srv-1', weight: 80);
      final entry = _entry('srv-1', DateTime(2026, 9, 1, 9, 5), _est(22),
          weight: 81);
      final rows = _rows([rec], [entry]);

      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.id, 'local-1', reason: 'the result route takes the local id');
      expect(r.record, same(rec));
      expect(r.entry, same(entry));
      expect(r.takenAt, entry.takenAt, reason: 'server time wins when merged');
      expect(r.weightKg, 81, reason: 'server weight wins when merged');
      expect(r.estimate!.value, 22, reason: 'server estimate wins');
    });

    test('a merged row falls back to the local estimate and weight when the '
        'entry has no result yet', () {
      final rec = _record('local-1', _day(0),
          estimate: _est(20), remoteId: 'srv-1', weight: 80);
      final entry = _entry('srv-1', _day(0), null,
          status: ScanDocStatus.pending, weight: null);
      final rows = _rows([rec], [entry]);

      expect(rows, hasLength(1));
      expect(rows.single.estimate!.value, 20);
      expect(rows.single.weightKg, 80);
    });

    test('a rotated remote id (<id>_r1) still merges with its entry', () {
      final rec = _record('a', _day(0), estimate: _est(20), remoteId: 'a_r1');
      final entry = _entry('a_r1', _day(0), _est(20));
      expect(_rows([rec], [entry]), hasLength(1));
    });

    test('server-only and local-only scans are both shown, newest first', () {
      final local = _record('L', _day(0), estimate: _est(20));
      final server = _entry('S', _day(2), _est(21));
      final localNew = _record('L2', _day(3), estimate: _est(22));
      final rows = _rows([local, localNew], [server]);

      expect(rows.map((r) => r.id).toList(), ['L2', 'S', 'L']);
      expect(_byId(rows, 'S').record, isNull);
      expect(_byId(rows, 'L').entry, isNull);
    });

    test('a scan never appears twice when both sources carry it', () {
      final rows = _rows(
        [_record('x', _day(0), estimate: _est(20))],
        [_entry('x', _day(0), _est(20))],
      );
      expect(rows.map((r) => r.id), ['x']);
    });

    test('entries that are not done results (pending, failed, cancelled, '
        'done without estimate) are not rows', () {
      final entries = [
        _entry('p', _day(0), null, status: ScanDocStatus.pending),
        _entry('f', _day(1), _est(20), status: ScanDocStatus.failed),
        _entry('c', _day(2), _est(20), status: ScanDocStatus.cancelled),
        _entry('d', _day(3), null),
        _entry('ok', _day(4), _est(20)),
      ];
      expect(_rows(const [], entries).map((r) => r.id), ['ok']);
    });

    test('a queued or failed local scan with an analysis but no estimate is '
        'left to the resume card', () {
      final rows = _rows([
        _record('q', _day(0), status: JobStatus.queued),
        _record('f', _day(1), status: JobStatus.failed),
      ], const []);
      expect(rows, isEmpty);
    });

    test('a legacy v1 record stays as a photo-only row without trend markers',
        () {
      final legacy = _record('old', _day(0), legacy: true, weight: 79);
      final rows = _rows([legacy, _record('new', _day(1), estimate: _est(20))],
          const []);
      final r = _byId(rows, 'old');
      expect(r.photosOnly, isTrue);
      expect(r.estimate, isNull);
      expect(r.isBaseline, isFalse);
      expect(r.change, isNull);
      expect(r.startsNewEstimator, isFalse);
      expect(r.weightKg, 79);
      expect(r.hasLocalPhotos, isTrue);
    });

    test('empty inputs give an empty, unmodifiable list', () {
      final rows = _rows(const [], const []);
      expect(rows, isEmpty);
      expect(() => rows.add(_byId(_rows([_record('a', _day(0), estimate: _est(1))], const []), 'a')),
          throwsUnsupportedError);
    });
  });

  group('baseline is the earliest done scan by takenAt, derived', () {
    test('exactly one row is the baseline regardless of input order', () {
      final records = [
        _record('c', _day(2), estimate: _est(22)),
        _record('a', _day(0), estimate: _est(20)),
        _record('b', _day(1), estimate: _est(21)),
      ];
      final rows = _rows(records, const []);
      expect(rows.where((r) => r.isBaseline).map((r) => r.id), ['a']);
      expect(_byId(rows, 'a').change, isNull,
          reason: 'the baseline has nothing to compare with');
      expect(_byId(rows, 'b').change, isNotNull);
      expect(_byId(rows, 'c').change, isNotNull);
    });

    test('baseline is by takenAt, not by list order or id order', () {
      final entries = [
        _entry('zzz', _day(0), _est(20)),
        _entry('aaa', _day(5), _est(20)),
      ];
      final rows = _rows(const [], entries);
      expect(rows.where((r) => r.isBaseline).map((r) => r.id), ['zzz']);
    });

    test('deleting the first scan moves the baseline to the next one '
        '(nothing stored)', () {
      final first = _record('a', _day(0), estimate: _est(20));
      final second = _record('b', _day(1), estimate: _est(21));
      final third = _record('c', _day(2), estimate: _est(22));

      final before = _rows([first, second, third], const []);
      expect(_byId(before, 'a').isBaseline, isTrue);
      expect(_byId(before, 'b').isBaseline, isFalse);

      final after = _rows([second, third], const []);
      expect(after.where((r) => r.isBaseline).map((r) => r.id), ['b']);
      expect(_byId(after, 'b').change, isNull);
    });

    test('a failed first scan is not the baseline', () {
      final entries = [
        _entry('bad', _day(0), _est(20), status: ScanDocStatus.failed),
        _entry('good', _day(1), _est(20)),
        _entry('good2', _day(2), _est(20)),
      ];
      final rows = _rows(const [], entries);
      expect(rows.where((r) => r.isBaseline).map((r) => r.id), ['good']);
    });

    test('a single scan is the baseline and has no change label', () {
      final rows = _rows([_record('a', _day(0), estimate: _est(20))], const []);
      expect(rows.single.isBaseline, isTrue);
      expect(rows.single.change, isNull);
    });

    test('the baseline of a merged record+entry row is detected through '
        'either id', () {
      final rec = _record('local', _day(0), estimate: _est(20), remoteId: 'srv');
      final entry = _entry('srv', _day(0), _est(20));
      final next = _record('n', _day(1), estimate: _est(20));
      final rows = _rows([rec, next], [entry]);
      expect(_byId(rows, 'local').isBaseline, isTrue);
      expect(_byId(rows, 'n').isBaseline, isFalse);
    });
  });

  group('change label per estimator', () {
    test('changes within the noise threshold read noMeaningfulChange', () {
      // hw 2 and 2: noise = sqrt(8) = 2.83.
      final rows = _rows([
        _record('a', _day(0), estimate: _est(20)),
        _record('b', _day(1), estimate: _est(22.5)),
        _record('c', _day(2), estimate: _est(20.0)),
      ], const []);
      expect(_byId(rows, 'b').change, ChangeLabel.noMeaningfulChange);
      expect(_byId(rows, 'c').change, ChangeLabel.noMeaningfulChange);
    });

    test('a drop beyond the noise reads down, a rise reads up, each against '
        'the PREVIOUS reading', () {
      final rows = _rows([
        _record('a', _day(0), estimate: _est(30)),
        _record('b', _day(1), estimate: _est(25)),
        _record('c', _day(2), estimate: _est(31)),
      ], const []);
      expect(_byId(rows, 'b').change, ChangeLabel.down);
      expect(_byId(rows, 'c').change, ChangeLabel.up);
    });

    test('the noise boundary is inclusive (diff == noise -> no change)', () {
      // hw 1 and 1: noise = max(1.0, sqrt(2)) = 1.4142...; use floor case
      // hw 0.5 and 0.5 -> sqrt(0.5)=0.707 -> floor 1.0, diff exactly 1.0.
      final rows = _rows([
        _record('a', _day(0), estimate: _est(20, hw: 0.5)),
        _record('b', _day(1), estimate: _est(21, hw: 0.5)),
        _record('c', _day(2), estimate: _est(22.01, hw: 0.5)),
      ], const []);
      expect(_byId(rows, 'b').change, ChangeLabel.noMeaningfulChange);
      expect(_byId(rows, 'c').change, ChangeLabel.up,
          reason: '1.01 exceeds the 1.0 floor');
    });

    test('provisional readings (hw 5, noise 7.07) show no change for a '
        'weekly move inside it', () {
      final rows = _rows([
        _record('a', _day(0),
            estimate: _est(15, modelId: _prov, provisional: true, hw: 5)),
        _record('b', _day(1),
            estimate: _est(21, modelId: _prov, provisional: true, hw: 5)),
      ], const []);
      expect(_byId(rows, 'b').change, ChangeLabel.noMeaningfulChange);
      expect(_byId(rows, 'b').provisional, isTrue);
    });

    test('the label uses server entries as well as local records', () {
      final rows = _rows(const [], [
        _entry('s1', _day(0), _est(30)),
        _entry('s2', _day(1), _est(20)),
      ]);
      expect(_byId(rows, 's2').change, ChangeLabel.down);
    });
  });

  group('new-estimator marker and no cross-model comparison', () {
    test('the first scan of a new estimator is flagged, is its own baseline '
        'and carries NO change label despite a huge difference', () {
      final rows = _rows([
        _record('a', _day(0),
            estimate: _est(15, modelId: _prov, provisional: true, hw: 5)),
        _record('b', _day(1),
            estimate: _est(15, modelId: _prov, provisional: true, hw: 5)),
        _record('c', _day(2), estimate: _est(35)),
      ], const []);

      final c = _byId(rows, 'c');
      expect(c.startsNewEstimator, isTrue);
      expect(c.isBaseline, isTrue,
          reason: 'first reading of its own estimator series');
      expect(c.change, isNull,
          reason: '20 points apart but from another model: never compared');

      expect(_byId(rows, 'a').startsNewEstimator, isFalse);
      expect(_byId(rows, 'a').isBaseline, isTrue);
      expect(_byId(rows, 'b').startsNewEstimator, isFalse);
      expect(_byId(rows, 'b').isBaseline, isFalse);
    });

    test('later scans of the new estimator compare with the new series only',
        () {
      final rows = _rows([
        _record('a', _day(0), estimate: _est(10)),
        _record('b', _day(1), estimate: _est(40, version: '2')),
        _record('c', _day(2), estimate: _est(30, version: '2')),
      ], const []);
      expect(_byId(rows, 'b').startsNewEstimator, isTrue);
      expect(_byId(rows, 'b').change, isNull);
      expect(_byId(rows, 'c').startsNewEstimator, isFalse);
      expect(_byId(rows, 'c').change, ChangeLabel.down,
          reason: '40 -> 30 inside version 2');
    });

    test('a model version bump alone counts as a new estimator', () {
      final rows = _rows([
        _record('a', _day(0), estimate: _est(20, version: '1')),
        _record('b', _day(1), estimate: _est(20, version: '2')),
      ], const []);
      expect(_byId(rows, 'b').startsNewEstimator, isTrue);
      expect(_byId(rows, 'a').startsNewEstimator, isFalse);
    });

    test('exactly one marker per switch; none without a switch', () {
      final same = _rows([
        _record('a', _day(0), estimate: _est(20)),
        _record('b', _day(1), estimate: _est(21)),
      ], const []);
      expect(same.where((r) => r.startsNewEstimator), isEmpty);

      final switched = _rows([
        _record('a', _day(0), estimate: _est(20)),
        _record('b', _day(1), estimate: _est(21, version: '2')),
        _record('c', _day(2), estimate: _est(21, version: '2')),
      ], const []);
      expect(switched.where((r) => r.startsNewEstimator).map((r) => r.id), ['b']);
    });

    test('switching back to an earlier estimator is flagged again and still '
        'compares only inside its own series', () {
      final rows = _rows([
        _record('a', _day(0), estimate: _est(20)),
        _record('b', _day(1), estimate: _est(30, version: '2')),
        _record('c', _day(2), estimate: _est(30)),
      ], const []);
      expect(_byId(rows, 'c').startsNewEstimator, isTrue);
      // c belongs to series v1 (a, c): it compares with a, not with b.
      expect(_byId(rows, 'c').change, ChangeLabel.up);
      expect(_byId(rows, 'c').isBaseline, isFalse);
    });
  });

  group('derived flags of a row', () {
    test('serverScanId: entry id, else remote id only when a copy may exist',
        () {
      final localOnly = _record('l', _day(0), estimate: _est(20));
      expect(_byId(_rows([localOnly], const []), 'l').serverScanId, isNull);

      final uploaded = _record('u', _day(1),
          estimate: _est(20), remoteId: 'u_r1', remoteStatus: 'done');
      expect(_byId(_rows([uploaded], const []), 'u').serverScanId, 'u_r1');

      final serverOnly = _entry('s', _day(2), _est(20));
      expect(_byId(_rows(const [], [serverOnly]), 's').serverScanId, 's');
    });

    test('mayHaveServerPhotos follows photosState of the entry', () {
      bool may(PhotosState s) => _rows(const [],
              [_entry('s', _day(0), _est(20), photos: s)])
          .single
          .mayHaveServerPhotos;
      expect(may(PhotosState.stored), isTrue);
      expect(may(PhotosState.awaitingUpload), isTrue);
      expect(may(PhotosState.deleted), isFalse);
      expect(may(PhotosState.none), isFalse);
    });

    test('deletePending, hasLocalPhotos and provisional reflect the record',
        () {
      final pending = _record('p', _day(0),
          estimate: _est(20, modelId: _prov, provisional: true),
          pendingDelete: true,
          withShots: false);
      final r = _rows([pending], const []).single;
      expect(r.deletePending, isTrue);
      expect(r.hasLocalPhotos, isFalse);
      expect(r.provisional, isTrue);

      final normal = _rows([_record('n', _day(0), estimate: _est(20))], const [])
          .single;
      expect(normal.deletePending, isFalse);
      expect(normal.hasLocalPhotos, isTrue);
      expect(normal.provisional, isFalse);
    });
  });
}
