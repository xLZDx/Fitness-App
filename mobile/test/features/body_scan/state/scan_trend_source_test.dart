// C14 (D-54, D-71): readings from the two sources and the trend the weekly
// review consumes. A provisional estimator or an estimator change must never
// look like a real body-fat decrease.
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/data/body_scan_entry.dart';
import 'package:fitness_app/features/body_scan/data/scan_trend.dart';
import 'package:fitness_app/features/body_scan/state/scan_trend_source.dart';
import 'package:fitness_app/features/nutrition_plan/data/body_fat_trend_source.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';

import '../support/scan_test_support.dart';

final _t0 = DateTime.utc(2026, 8, 3, 8);
DateTime _day(int d) => _t0.add(Duration(days: d));

ScanRecord _rec(String id, int day, {double? value, bool provisional = false, String? remote, double hw = 1.0}) =>
    ScanRecord(
      id: id,
      createdAt: _day(day),
      shots: const {},
      analysis: ScanAnalysis.queued().copyWith(
        remoteId: remote,
        estimate: value == null
            ? null
            : estimate(value: value, halfWidth: hw, provisional: provisional),
      ),
    );

BodyScanEntry _entry(String id, int day,
        {double? value,
        ScanDocStatus status = ScanDocStatus.done,
        bool provisional = false}) =>
    BodyScanEntry(
      scanId: id,
      takenAt: _day(day),
      status: status,
      photosState: PhotosState.none,
      estimate: value == null ? null : estimate(value: value, provisional: provisional),
    );

ScanTrend _trend(List<ScanReading> r) => computeScanTrend(r);

void main() {
  group('readingsFrom', () {
    test('empty inputs give no readings', () {
      expect(readingsFrom(records: const [], entries: const []), isEmpty);
    });

    test('a record without an estimate (queued, legacy) is not a reading', () {
      final r = readingsFrom(records: [
        _rec('a', 0),
        ScanRecord(id: 'legacy', createdAt: _day(1), shots: const {}),
      ], entries: const []);
      expect(r, isEmpty);
    });

    test('a record reading carries value, halfWidth, model and the LOCAL id', () {
      final r = readingsFrom(
          records: [_rec('a', 2, value: 22.5, hw: 3.0)], entries: const []).single;
      expect(r.value, 22.5);
      expect(r.halfWidth, 3.0);
      expect(r.at, _day(2));
      expect(r.modelId, kPhotoModelId);
      expect(r.modelVersion, '1');
      expect(r.scanId, 'a');
    });

    test('only a done entry with an estimate counts', () {
      final r = readingsFrom(records: const [], entries: [
        _entry('p', 0, value: 20, status: ScanDocStatus.pending),
        _entry('f', 1, value: 20, status: ScanDocStatus.failed),
        _entry('c', 2, value: 20, status: ScanDocStatus.cancelled),
        _entry('n', 3),
        _entry('ok', 4, value: 21),
      ]);
      expect(r.map((e) => e.scanId), ['ok']);
      expect(r.single.at, _day(4));
    });

    test('the server copy wins over the local copy of the same scan', () {
      final r = readingsFrom(
        records: [_rec('local1', 0, value: 30, remote: 'srv1')],
        entries: [_entry('srv1', 0, value: 25)],
      );
      expect(r, hasLength(1), reason: 'counted once');
      expect(r.single.value, 25);
      expect(r.single.scanId, 'srv1');
    });

    test('dedupe keys on remoteId: a rotated remote id is a different scan', () {
      final r = readingsFrom(
        records: [_rec('l1', 0, value: 30, remote: 'srv1_r1')],
        entries: [_entry('srv1', 0, value: 25)],
      );
      expect(r, hasLength(2));
    });

    test('a record whose remoteId defaults to its id dedupes against an entry of that id',
        () {
      final r = readingsFrom(
        records: [_rec('same', 0, value: 30)],
        entries: [_entry('same', 0, value: 24)],
      );
      expect(r.single.value, 24);
    });
  });

  group('bodyFatTrendInputFor', () {
    List<ScanReading> series(List<double> values, {int stepDays = 7, bool provisional = false}) =>
        readingsFrom(records: [
          for (var i = 0; i < values.length; i++)
            _rec('s$i', i * stepDays, value: values[i], provisional: provisional),
        ], entries: const []);

    test('no readings: null', () {
      expect(bodyFatTrendInputFor(_trend(const [])), isNull);
    });

    test('fewer than 3 readings: null (no 4-week label yet)', () {
      expect(bodyFatTrendInputFor(_trend(series([30, 26]))), isNull);
      expect(bodyFatTrendInputFor(_trend(series([30]))), isNull);
    });

    test('a clear drop on a real estimator is a meaningful decrease', () {
      final i = bodyFatTrendInputFor(_trend(series([30, 26, 22])))!;
      expect(i.meaningful, isTrue);
      expect(i.changePts, closeTo(-3.333, 0.01));
      expect(i.modelId, kPhotoModelId);
      expect(i.provisional, isFalse);
      expect(i.seriesChanged, isFalse);
      expect(i.isMeaningfulDecrease, isTrue);
    });

    test('a rise is meaningful but not a decrease', () {
      final i = bodyFatTrendInputFor(_trend(series([22, 26, 30])))!;
      expect(i.meaningful, isTrue);
      expect(i.changePts, greaterThan(0));
      expect(i.isMeaningfulDecrease, isFalse);
    });

    test('a flat series is not meaningful and its change is within noise', () {
      final i = bodyFatTrendInputFor(_trend(series([25, 25.2, 24.9])))!;
      expect(i.meaningful, isFalse);
      expect(i.changePts.abs(), lessThan(1));
      expect(i.isMeaningfulDecrease, isFalse);
    });

    test('the provisional estimator is flagged and can never count as a decrease',
        () {
      final i = bodyFatTrendInputFor(
          _trend(series([30, 26, 22], provisional: true)))!;
      expect(i.meaningful, isTrue);
      expect(i.changePts, lessThan(0));
      expect(i.provisional, isTrue);
      expect(i.modelId, kProvisionalModelId);
      expect(i.isMeaningfulDecrease, isFalse);
    });

    test('an estimator change inside the window sets seriesChanged', () {
      // provisional x1, then three photo-model readings inside 28 days.
      final readings = readingsFrom(records: [
        _rec('p0', 0, value: 30, provisional: true),
        _rec('a', 7, value: 28),
        _rec('b', 14, value: 25),
        _rec('c', 21, value: 22),
      ], entries: const []);
      final i = bodyFatTrendInputFor(_trend(readings))!;
      expect(i.seriesChanged, isTrue);
      expect(i.modelId, kPhotoModelId);
      expect(i.isMeaningfulDecrease, isFalse,
          reason: 'no comparison across an estimator change');
    });

    test('an estimator change older than the window does not set seriesChanged',
        () {
      final readings = readingsFrom(records: [
        _rec('p0', 0, value: 30, provisional: true),
        _rec('a', 60, value: 30),
        _rec('b', 70, value: 27),
        _rec('c', 80, value: 24),
        _rec('d', 90, value: 21),
      ], entries: const []);
      final i = bodyFatTrendInputFor(_trend(readings))!;
      expect(i.seriesChanged, isFalse);
      expect(i.isMeaningfulDecrease, isTrue);
    });

    test('the reference is the last point at least 28 days before the latest', () {
      // Readings every 7 days, 0..42: the reference for latest=42 is day 14.
      final readings = series([30, 28, 26, 24, 22, 20, 18], stepDays: 7);
      final trend = _trend(readings);
      final s = trend.active!;
      final i = bodyFatTrendInputFor(trend)!;
      final ref = s.points.firstWhere((p) => p.reading.at == _day(14));
      expect(i.changePts, closeTo(s.smoothedNow - ref.smoothed, 1e-9));
    });
  });

  group('ScanBodyFatTrendSource', () {
    test('is a BodyFatTrendSource that reports the trend input', () {
      final trend = _trend(readingsFrom(records: [
        for (var i = 0; i < 3; i++)
          _rec('s$i', i * 7, value: [30.0, 26.0, 22.0][i]),
      ], entries: const []));
      final BodyFatTrendSource src = ScanBodyFatTrendSource(trend);
      expect(src.currentTrend()!.isMeaningfulDecrease, isTrue);
    });

    test('with no usable series it reports null', () {
      expect(ScanBodyFatTrendSource(_trend(const [])).currentTrend(), isNull);
    });
  });
}
