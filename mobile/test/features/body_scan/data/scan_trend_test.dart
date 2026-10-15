// T20 scan_trend_test (SCAN-16, SCAN-17, SCAN-18, SCAN-45). Smoothing,
// winsorising, warm-up, noise threshold, 4-week label and per-estimator
// segmentation. Vectors come from a scratch calculation of design s12.3-12.5a.
//
// MAP NOTE (deviation 2): V-EWMA S = 25.5669 holds WITHOUT the D-37 warm-up
// (plain ewmaStep/ewmaAlpha, or TrendConfig(warmupMean: false)). With the
// warm-up on, the second reading gets alpha = max(0.28347, 1/2) = 0.5.
import 'package:fitness_app/core/math/series_math.dart';
import 'package:fitness_app/features/body_scan/data/scan_trend.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 1, 5);
DateTime _d(num days) => _t0.add(Duration(minutes: (days * 1440).round()));

ScanReading _r(num day, double v,
        {double hw = 0.5, String model = 'm', String ver = 'v1'}) =>
    ScanReading(
      at: _d(day),
      value: v,
      halfWidth: hw,
      modelId: model,
      modelVersion: ver,
    );

const _noWarm = TrendConfig(warmupMean: false);

void main() {
  group('V-EWMA alpha (SCAN-18)', () {
    test('tau 21 d, 7 d gap: alpha 0.283469', () {
      expect(ewmaAlpha(dDays: 7, tauDays: 21), closeTo(0.283469, 1e-6));
    });
    test('gap below 0.5 d is clamped to 0.5 d: alpha 0.023528', () {
      expect(ewmaAlpha(dDays: 0.2, tauDays: 21), closeTo(0.023528, 1e-6));
      expect(ewmaAlpha(dDays: 0.0, tauDays: 21),
          ewmaAlpha(dDays: 0.5, tauDays: 21));
      expect(ewmaAlpha(dDays: -3, tauDays: 21),
          ewmaAlpha(dDays: 0.5, tauDays: 21));
    });
    test('gap above 28 d is clamped to 28 d: alpha 0.736403', () {
      expect(ewmaAlpha(dDays: 40, tauDays: 21), closeTo(0.736403, 1e-6));
      expect(ewmaAlpha(dDays: 28, tauDays: 21),
          ewmaAlpha(dDays: 400, tauDays: 21));
    });
    test('V-EWMA-W: tau 7 d daily readings alpha 0.133122', () {
      expect(ewmaAlpha(dDays: 1, tauDays: 7), closeTo(0.133122, 1e-6));
    });
    test('warm-up: alpha = max(exponential, 1/n)', () {
      double a(int n) =>
          ewmaAlpha(dDays: 7, tauDays: 21, readingCount: n);
      expect(a(2), 0.5);
      expect(a(3), closeTo(1 / 3, 1e-12));
      expect(a(4), closeTo(0.283469, 1e-6)); // 0.25 < 0.2835: exponential wins
      expect(a(10), closeTo(0.283469, 1e-6));
    });
    test('warm-up is off when readingCount is null', () {
      expect(ewmaAlpha(dDays: 7, tauDays: 21, readingCount: null),
          closeTo(0.283469, 1e-6));
    });
  });

  group('V-EWMA step and winsorising (SCAN-18)', () {
    test('S0 25.0, next reading 27.0 after 7 d, tau 21: S = 25.5669', () {
      final a = ewmaAlpha(dDays: 7, tauDays: 21);
      expect(ewmaStep(previous: 25, reading: 27, alpha: a),
          closeTo(25.5669, 1e-4));
    });
    test('winsorised 35.0 reading acts as 29.0: S = 26.1339', () {
      final a = ewmaAlpha(dDays: 7, tauDays: 21);
      expect(ewmaStep(previous: 25, reading: 35, alpha: a, winsorPts: 4),
          closeTo(26.1339, 1e-4));
      // unwinsorised would be 25 + 0.283469 * 10 = 27.8347
      expect(ewmaStep(previous: 25, reading: 35, alpha: a),
          closeTo(27.8347, 1e-4));
    });
    test('winsorising is symmetric (15.0 acts as 21.0)', () {
      final a = ewmaAlpha(dDays: 7, tauDays: 21);
      expect(ewmaStep(previous: 25, reading: 15, alpha: a, winsorPts: 4),
          closeTo(25 - 4 * 0.283469, 1e-4));
    });
    test('a reading inside the winsor band is untouched', () {
      expect(ewmaStep(previous: 25, reading: 28.9, alpha: 0.5, winsorPts: 4),
          closeTo(26.95, 1e-12));
    });
  });

  group('computeScanTrend smoothing (SCAN-18)', () {
    test('first reading S0 = x0', () {
      final t = computeScanTrend([_r(0, 25)]);
      expect(t.active!.smoothedNow, 25);
      expect(t.active!.startValue, 25);
    });
    test('without warm-up the second reading gives 25.5669', () {
      final t = computeScanTrend([_r(0, 25), _r(7, 27)], config: _noWarm);
      expect(t.active!.smoothedNow, closeTo(25.5669, 1e-4));
    });
    test('with warm-up (default) the second reading has weight 0.5: S = 26.0', () {
      final t = computeScanTrend([_r(0, 25), _r(7, 27)]);
      expect(t.active!.smoothedNow, closeTo(26.0, 1e-12));
    });
    test('warm-up third reading weighs 1/3: 25, 27, 29.5 -> 26.0, 27.16667', () {
      final t = computeScanTrend([_r(0, 25), _r(7, 27), _r(14, 29.5)]);
      final s = t.active!.points.map((p) => p.smoothed).toList();
      expect(s[0], 25);
      expect(s[1], closeTo(26.0, 1e-9));
      expect(s[2], closeTo(27.166667, 1e-6));
    });
    test('weekly series 25,24,23,22,21: 25, 24.5, 24.0, 23.433063, 22.743366', () {
      final t = computeScanTrend(
          [for (var i = 0; i < 5; i++) _r(i * 7, 25.0 - i)]);
      final s = t.active!.points.map((p) => p.smoothed).toList();
      expect(s[0], 25);
      expect(s[1], closeTo(24.5, 1e-9));
      expect(s[2], closeTo(24.0, 1e-9));
      expect(s[3], closeTo(23.433063, 1e-6));
      expect(s[4], closeTo(22.743366, 1e-6));
    });
    test('winsorised outlier: raw dot kept and flagged, smoothing uses 29', () {
      final t = computeScanTrend([_r(0, 25), _r(7, 35)], config: _noWarm);
      final p = t.active!.points.last;
      expect(p.reading.value, 35.0); // raw dot is still plotted
      expect(p.isOutlier, isTrue);
      expect(p.smoothed, closeTo(26.1339, 1e-4));
    });
    test('outlier flag boundary: exactly +4.0 is not an outlier, +4.01 is', () {
      final edge = computeScanTrend([_r(0, 25), _r(7, 29.0)], config: _noWarm);
      expect(edge.active!.points.last.isOutlier, isFalse);
      final over = computeScanTrend([_r(0, 25), _r(7, 29.01)], config: _noWarm);
      expect(over.active!.points.last.isOutlier, isTrue);
      final under = computeScanTrend([_r(0, 25), _r(7, 20.99)], config: _noWarm);
      expect(under.active!.points.last.isOutlier, isTrue);
    });
    test('the first reading is never an outlier', () {
      expect(computeScanTrend([_r(0, 55)]).active!.points.first.isOutlier,
          isFalse);
    });
    test('irregular spacing differs from a fixed-alpha result', () {
      // readings 25 (d0), 26 (d1), 30 (d8), no warm-up. Gap alphas: 1 d ->
      // 0.046503; 7 d -> 0.283469. S = 25.046503, then winsor(30) = 29.046503
      // -> 25.046503 + 0.283469 * 4 = 26.180378.
      final t = computeScanTrend(
          [_r(0, 25), _r(1, 26), _r(8, 30)], config: _noWarm);
      expect(t.active!.smoothedNow, closeTo(26.180378, 1e-5));
      // A fixed alpha 0.283469 would have produced 26.620458.
      expect((t.active!.smoothedNow - 26.620458).abs(), greaterThan(0.4));
    });
    test('input order does not matter (sorted inside)', () {
      final a = computeScanTrend([_r(0, 25), _r(7, 27), _r(14, 29.5)]);
      final b = computeScanTrend([_r(14, 29.5), _r(0, 25), _r(7, 27)]);
      expect(b.active!.smoothedNow, a.active!.smoothedNow);
    });
    test('series weights sum to 1; warm-up gives three equal weights', () {
      final t = computeScanTrend([_r(0, 25), _r(7, 27), _r(14, 29.5)]);
      final w = t.active!.points.map((p) => p.weight).toList();
      expect(w.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-12));
      for (final x in w) {
        expect(x, closeTo(1 / 3, 1e-9));
      }
      expect(t.active!.effectiveN, closeTo(3.0, 1e-9));
    });
    test('empty input gives no series and no active', () {
      final t = computeScanTrend(const []);
      expect(t.series, isEmpty);
      expect(t.active, isNull);
      expect(t.modelChangeAt, isEmpty);
    });
  });

  group('shared series_math primitives', () {
    test('ewmaSeries mirrors the step formula and sorts by time', () {
      final out = ewmaSeries(
        [SeriesPoint(_d(7), 27), SeriesPoint(_d(0), 25)],
        tauDays: 21,
      );
      expect(out.first, 25);
      expect(out.last, closeTo(25.566937, 1e-6));
    });
    test('ewmaSeries warm-up flag changes the second value to 26.0', () {
      final out = ewmaSeries(
        [SeriesPoint(_d(0), 25), SeriesPoint(_d(7), 27)],
        tauDays: 21,
        warmupMean: true,
      );
      expect(out.last, closeTo(26.0, 1e-12));
    });
    test('ewmaSeries on empty input is empty', () {
      expect(ewmaSeries(const [], tauDays: 7), isEmpty);
    });
    test('median: odd, even, empty', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 3, 2]), 2.5);
      expect(median(const []), isNull);
    });
  });

  group('SCAN-16 noise threshold and change label', () {
    test('V-NOISE: provisional half-widths 5 and 5 -> 7.0711', () {
      expect(noiseThresholdPts(5, 5), closeTo(7.0711, 1e-4));
    });
    test('half-widths 0.5 and 0.5 -> 0.7071 so the floor 1.0 applies', () {
      expect(noiseThresholdPts(0.5, 0.5), 1.0);
      expect(noiseThresholdPts(0.5, 0.5, floorPts: 0.5),
          closeTo(0.7071, 1e-4));
    });
    test('a threshold above the floor is the root of the sum of squares', () {
      expect(noiseThresholdPts(3, 4), 5.0);
    });
    test('provisional: a 7.0-point change is noMeaningfulChange, 7.2 is up/down', () {
      final p = _r(0, 20, hw: 5);
      expect(changeLabelBetween(p, _r(7, 27.0, hw: 5)),
          ChangeLabel.noMeaningfulChange);
      expect(changeLabelBetween(p, _r(7, 27.2, hw: 5)), ChangeLabel.up);
      expect(changeLabelBetween(p, _r(7, 12.8, hw: 5)), ChangeLabel.down);
      expect(changeLabelBetween(p, _r(7, 13.0, hw: 5)),
          ChangeLabel.noMeaningfulChange);
    });
    test('floor: |change| exactly 1.0 -> none, 1.01 -> up/down; sign gives direction', () {
      final p = _r(0, 25);
      expect(changeLabelBetween(p, _r(7, 26.0)), ChangeLabel.noMeaningfulChange);
      expect(changeLabelBetween(p, _r(7, 24.0)), ChangeLabel.noMeaningfulChange);
      expect(changeLabelBetween(p, _r(7, 26.01)), ChangeLabel.up);
      expect(changeLabelBetween(p, _r(7, 23.99)), ChangeLabel.down);
    });
    test('latestChangeLabel compares the newest with the previous of the SAME series', () {
      final t = computeScanTrend([_r(0, 25), _r(7, 27)]);
      expect(latestChangeLabel(t.active!), ChangeLabel.up);
      final one = computeScanTrend([_r(0, 25)]);
      expect(latestChangeLabel(one.active!), isNull);
    });
  });

  group('SCAN-17 four-week label', () {
    test('needs >= 3 readings in the window, else null', () {
      expect(fourWeekLabel(computeScanTrend([_r(0, 25), _r(7, 20)]).active!),
          isNull);
      // 3 readings but only 2 inside the last 28 days (d0 is 50 days back).
      expect(
          fourWeekLabel(
              computeScanTrend([_r(0, 25), _r(40, 24), _r(50, 23)]).active!),
          isNull);
    });
    test('weekly loss 25 -> 21 over 28 d: S 25 -> 22.743 is meaningful (down)', () {
      final t = computeScanTrend(
          [for (var i = 0; i < 5; i++) _r(i * 7, 25.0 - i)]);
      expect(fourWeekLabel(t.active!), ChangeLabel.down);
    });
    test('the same series with provisional half-width 5 is within noise', () {
      // threshold max(1, 0.8 * 5) = 4.0 > 2.2566
      final t = computeScanTrend(
          [for (var i = 0; i < 5; i++) _r(i * 7, 25.0 - i, hw: 5)]);
      expect(fourWeekLabel(t.active!), ChangeLabel.noMeaningfulChange);
    });
    test('a flat-ish series younger than 28 d compares with its first value', () {
      final t = computeScanTrend(
          [_r(0, 25), _r(7, 25.5), _r(14, 24.5), _r(21, 25.2)]);
      expect(t.active!.smoothedNow, closeTo(25.056694, 1e-6));
      expect(fourWeekLabel(t.active!), ChangeLabel.noMeaningfulChange);
    });
    // tau 0.0001 d makes alpha exactly 1 so S_t = clamp(x_t); winsor 10.
    const sharp = TrendConfig(tauDays: 0.0001, warmupMean: false, winsorPts: 10);
    ScanTrend sharpTo(double last) => computeScanTrend([
          _r(0, 25, hw: 5),
          _r(7, 25, hw: 5),
          _r(14, 25, hw: 5),
          _r(21, 25, hw: 5),
          _r(28, last, hw: 5),
        ], config: sharp);
    test('boundary |S_t - S_t-28d| == max(1, 0.8 * mean hw) = 4.0 is NOT meaningful', () {
      expect(sharpTo(29.0).active!.smoothedNow, 29.0);
      expect(fourWeekLabel(sharpTo(29.0).active!, config: sharp),
          ChangeLabel.noMeaningfulChange);
      expect(fourWeekLabel(sharpTo(21.0).active!, config: sharp),
          ChangeLabel.noMeaningfulChange);
    });
    test('just beyond the boundary is meaningful in the right direction', () {
      expect(fourWeekLabel(sharpTo(29.01).active!, config: sharp),
          ChangeLabel.up);
      expect(fourWeekLabel(sharpTo(20.99).active!, config: sharp),
          ChangeLabel.down);
    });
  });

  group('trend interval (12.5a)', () {
    test('shown only from the third reading', () {
      expect(
          trendHalfWidth(computeScanTrend([_r(0, 25, hw: 5), _r(7, 26, hw: 5)])
              .active!),
          isNull);
      expect(
          trendHalfWidth(computeScanTrend([_r(0, 25, hw: 5)]).active!), isNull);
    });
    test('three equal-weight readings: n_eff 3 -> 5 * max(0.85, 0.577) = 4.25', () {
      final t = computeScanTrend(
          [_r(0, 25, hw: 5), _r(7, 27, hw: 5), _r(14, 29.5, hw: 5)]);
      expect(trendHalfWidth(t.active!)!, closeTo(4.25, 1e-9));
    });
    test('never narrower than 85 % of the readings mean half-width', () {
      final t = computeScanTrend([
        for (var i = 0; i < 12; i++) _r(i * 7, 25.0 + (i.isEven ? 0.2 : -0.2), hw: 2)
      ]);
      expect(trendHalfWidth(t.active!)!, closeTo(2 * 0.85, 1e-9));
    });
    test('the mean half-width is the weighted mean: 4, 4, 6 -> 4.6667 * 0.85', () {
      final t = computeScanTrend(
          [_r(0, 25, hw: 4), _r(7, 26, hw: 4), _r(14, 25.5, hw: 6)]);
      expect(trendHalfWidth(t.active!)!, closeTo(14 / 3 * 0.85, 1e-9));
    });
    test('when one reading dominates (n_eff ~ 1) the range is not narrowed at all', () {
      // tau 1 d, 40-day gaps: alpha ~ 1 so the last reading carries ~all weight.
      final c = const TrendConfig(tauDays: 1);
      final t = computeScanTrend(
          [_r(0, 25, hw: 5), _r(40, 26, hw: 5), _r(80, 27, hw: 5)],
          config: c);
      expect(trendHalfWidth(t.active!, config: c)!, closeTo(5.0, 1e-6));
    });
    test('the floor is configurable', () {
      final c = const TrendConfig(trendIntervalFloor: 0.5);
      final t = computeScanTrend(
          [_r(0, 25, hw: 5), _r(7, 27, hw: 5), _r(14, 29.5, hw: 5)],
          config: c);
      expect(trendHalfWidth(t.active!, config: c)!,
          closeTo(5 * 0.57735, 1e-4));
    });
  });

  group('SCAN-45 segmentation per estimator (D-54)', () {
    final readings = [
      _r(0, 25, model: 'A'),
      _r(7, 25.5, model: 'A'),
      _r(14, 26, model: 'A'),
      _r(21, 20, model: 'B'),
      _r(28, 20.5, model: 'B'),
    ];
    test('two model ids give two independent series; active is the newest one', () {
      final t = computeScanTrend(readings);
      expect(t.series.map((s) => s.modelKey), ['A|v1', 'B|v1']);
      expect(t.active!.modelKey, 'B|v1');
      expect(t.series[0].points.length, 3);
      expect(t.active!.points.length, 2);
    });
    test('a new estimator marker is recorded at the first reading of the new model', () {
      expect(computeScanTrend(readings).modelChangeAt, [_d(21)]);
    });
    test('the new series starts fresh: baseline and start value are its own', () {
      final b = computeScanTrend(readings).active!;
      expect(b.startValue, 20);
      expect(b.baseline.reading.at, _d(21));
      expect(b.points.first.smoothed, 20);
      // second reading uses ITS OWN warm-up (n = 2): 20 + 0.5 * 0.5
      expect(b.smoothedNow, closeTo(20.25, 1e-9));
    });
    test('NO change label is computed across estimators', () {
      final b = computeScanTrend(readings).active!;
      // would be a -5.5 point "down" change if compared with the A series.
      expect(latestChangeLabel(b), ChangeLabel.noMeaningfulChange);
      expect(fourWeekLabel(b), isNull); // only 2 readings of the new series
    });
    test('a version change of the same model id is also a new series', () {
      final t = computeScanTrend([
        _r(0, 25, model: 'A', ver: 'v1'),
        _r(7, 25, model: 'A', ver: 'v2'),
      ]);
      expect(t.series.length, 2);
      expect(t.modelChangeAt, [_d(7)]);
    });
    test('the baseline is the earliest reading of the active series and survives deleting the first scan', () {
      final base = computeScanTrend([
        _r(0, 25, model: 'P'), _r(7, 24, model: 'P'), _r(14, 23, model: 'P'),
      ]).active!;
      expect(base.baseline.reading.at, _d(0));
      final withoutFirst = computeScanTrend([
        _r(7, 24, model: 'P'), _r(14, 23, model: 'P'),
      ]).active!;
      expect(withoutFirst.baseline.reading.at, _d(7));
      expect(withoutFirst.startValue, 24);
    });
    test('the start value is the RAW baseline value, not smoothed', () {
      final s = computeScanTrend([_r(0, 25), _r(7, 20)]).active!;
      expect(s.startValue, 25);
      expect(s.points.first.smoothed, 25);
    });
    test('alternating models still produce one series per estimator and every switch is marked', () {
      final t = computeScanTrend([
        _r(0, 25, model: 'A'),
        _r(7, 20, model: 'B'),
        _r(14, 24, model: 'A'),
      ]);
      expect(t.series.length, 2);
      expect(t.modelChangeAt, [_d(7), _d(14)]);
      expect(t.active!.modelKey, 'A|v1');
    });
  });

  group('TrendConfig defaults (design 29)', () {
    test('standard values', () {
      const c = TrendConfig.standard;
      expect(c.tauDays, 21);
      expect(c.winsorPts, 4.0);
      expect(c.warmupMean, isTrue);
      expect(c.trendIntervalFloor, 0.85);
      expect(c.noiseFloorPts, 1.0);
      expect(c.fourWeekDays, 28);
      expect(c.fourWeekFactor, 0.8);
      expect(c.fourWeekMinReadings, 3);
      expect(c.trendIntervalMinReadings, 3);
      expect(kEwmaMinGapDays, 0.5);
      expect(kEwmaMaxGapDays, 28.0);
    });
  });
}
