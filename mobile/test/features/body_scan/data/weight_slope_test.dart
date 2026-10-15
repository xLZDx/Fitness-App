// T21 weight_slope_test (SCAN-19, PLAN-24 maths): Theil-Sen weekly slope with
// its data-sufficiency rules, the weight smoothing, and the weigh-in model.
// Slopes were computed by scratch arithmetic (pairwise medians).
import 'package:fitness_app/core/math/series_math.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 9, 1, 8);
DateTime _d(num days) => _t0.add(Duration(minutes: (days * 1440).round()));
SeriesPoint _p(num day, double kg) => SeriesPoint(_d(day), kg);
WeightEntry _e(num day, double kg, {WeightSource s = WeightSource.manual}) =>
    WeightEntry(at: _d(day), kg: kg, source: s);

void main() {
  group('V-THEIL (SCAN-19)', () {
    test('80.0 d0, 79.8 d3, 79.6 d7 -> median of -0.0667, -0.0571, -0.05 x 7 = -0.4', () {
      final s = theilSenSlopePerWeek([_p(0, 80.0), _p(3, 79.8), _p(7, 79.6)]);
      expect(s, closeTo(-0.4, 1e-9));
    });
    test('the per-day slope is the same median before the x7', () {
      final s = theilSenSlopePerDay([_p(0, 80.0), _p(3, 79.8), _p(7, 79.6)]);
      expect(s, closeTo(-0.4 / 7, 1e-12));
    });
    test('a gain gives a positive slope', () {
      final s = theilSenSlopePerWeek([_p(0, 70.0), _p(4, 70.3), _p(7, 70.35)]);
      // pairs: 0.3/4 = 0.075 ; 0.35/7 = 0.05 ; 0.05/3 = 0.016667 -> median 0.05 -> 0.35/wk
      expect(s, closeTo(0.35, 1e-9));
    });
  });

  group('data sufficiency [OWN]: >= 3 entries spanning >= 7 days', () {
    test('fewer than 3 entries -> null', () {
      expect(theilSenSlopePerWeek([_p(0, 80), _p(10, 79)]), isNull);
      expect(theilSenSlopePerWeek([_p(0, 80)]), isNull);
      expect(theilSenSlopePerWeek(const []), isNull);
    });
    test('3 entries spanning 6 days -> null; 7 days -> a value', () {
      expect(theilSenSlopePerWeek([_p(0, 80), _p(3, 79.8), _p(6, 79.6)]),
          isNull);
      expect(theilSenSlopePerWeek([_p(0, 80), _p(3, 79.8), _p(7, 79.6)]),
          isNotNull);
    });
    test('the span is measured in minutes: 6 d 23 h 59 min is still too short', () {
      final pts = [
        _p(0, 80),
        _p(3, 79.8),
        SeriesPoint(_d(7).subtract(const Duration(minutes: 1)), 79.6),
      ];
      expect(theilSenSlopePerWeek(pts), isNull);
    });
    test('pairs with dDays < 2 are skipped', () {
      // 80.0 d0, 80.5 d1, 79.6 d7: pair (0,1) skipped. Remaining
      // (79.6-80)/7 = -0.057143 and (79.6-80.5)/6 = -0.15; median of two =
      // mean = -0.103571; x7 = -0.725.
      final s = theilSenSlopePerWeek([_p(0, 80.0), _p(1, 80.5), _p(7, 79.6)]);
      expect(s, closeTo(-0.725, 1e-9));
    });
    test('a pair exactly 2 days apart is used (>= 2)', () {
      final s = theilSenSlopePerDay([_p(0, 80), _p(2, 79)]);
      expect(s, closeTo(-0.5, 1e-12));
      expect(theilSenSlopePerDay([_p(0, 80), _p(1.9, 79)]), isNull);
    });
    test('all entries within 2 days of each other and nothing qualifies -> null', () {
      expect(
          theilSenSlopePerDay([_p(0, 80), _p(1, 79.9), _p(1.5, 79.8)]), isNull);
    });
  });

  group('21-day window', () {
    test('entries older than 21 days before the newest are ignored', () {
      final s = theilSenSlopePerWeek([
        _p(0, 100.0), // 30 days before the newest: ignored
        _p(9, 80.0), // exactly 21 days before: counted
        _p(16, 79.6),
        _p(30, 78.8),
      ]);
      expect(s, closeTo(-0.4, 1e-9)); // perfectly linear in the window
    });
    test('21 days + 1 minute is out; the span rule then applies to the rest', () {
      final s = theilSenSlopePerWeek([
        SeriesPoint(_d(30).subtract(const Duration(days: 21, minutes: 1)), 90),
        _p(20, 80),
        _p(30, 79),
      ]);
      expect(s, isNull); // only 2 points left
    });
    test('asOf moves the window: an earlier asOf ignores later entries', () {
      final pts = [_p(0, 80), _p(4, 79.8), _p(8, 79.6), _p(30, 60)];
      final s = theilSenSlopePerWeek(pts, asOf: _d(8));
      expect(s, closeTo(-0.35, 1e-9)); // -0.2/4 per day * 7
    });
    test('entries after asOf are not used', () {
      final pts = [_p(0, 80), _p(4, 79.8), _p(8, 79.6), _p(10, 200)];
      final s = theilSenSlopePerWeek(pts, asOf: _d(8));
      expect(s, closeTo(-0.35, 1e-9));
    });
    test('input order does not matter', () {
      final a = theilSenSlopePerWeek([_p(0, 80.0), _p(3, 79.8), _p(7, 79.6)]);
      final b = theilSenSlopePerWeek([_p(7, 79.6), _p(0, 80.0), _p(3, 79.8)]);
      expect(b, a);
    });
  });

  group('robustness to an outlier (vs a least-squares fit)', () {
    // 8 weigh-ins every 2 days on a clean -0.05 kg/day (-0.35 kg/wk) line; the
    // last one is +2 kg too heavy. Theil-Sen stays at -0.35; an OLS fit moves
    // to +0.2333 (a shift of 0.583 kg/wk), verified by scratch computation.
    final clean = [for (var d = 0; d <= 14; d += 2) _p(d, 80 - 0.05 * d)];
    final dirty = [
      ...clean.sublist(0, clean.length - 1),
      _p(14, 80 - 0.05 * 14 + 2.0),
    ];
    test('clean line gives -0.35', () {
      expect(theilSenSlopePerWeek(clean), closeTo(-0.35, 1e-9));
    });
    test('a single +2 kg outlier moves the slope by less than 0.15', () {
      final moved = theilSenSlopePerWeek(dirty)!;
      expect((moved - -0.35).abs(), lessThan(0.15));
    });
    test('the same fixture would move an ordinary least-squares fit by more than 0.3', () {
      double ols(List<SeriesPoint> p) {
        final n = p.length;
        final x = [for (final q in p) q.at.difference(_t0).inMinutes / 1440.0];
        final mx = x.reduce((a, b) => a + b) / n;
        final my = p.map((q) => q.value).reduce((a, b) => a + b) / n;
        var num = 0.0, den = 0.0;
        for (var i = 0; i < n; i++) {
          num += (x[i] - mx) * (p[i].value - my);
          den += (x[i] - mx) * (x[i] - mx);
        }
        return num / den * 7;
      }

      expect((ols(dirty) - ols(clean)).abs(), greaterThan(0.3));
    });
  });

  group('WeightEntry model', () {
    test('valid weight range 30..300 inclusive, finite', () {
      expect(WeightEntry.isValidKg(30), isTrue);
      expect(WeightEntry.isValidKg(300), isTrue);
      expect(WeightEntry.isValidKg(29.9), isFalse);
      expect(WeightEntry.isValidKg(300.1), isFalse);
      expect(WeightEntry.isValidKg(double.nan), isFalse);
      expect(WeightEntry.isValidKg(double.infinity), isFalse);
    });
    test('toJson shape', () {
      final j = WeightEntry(
              at: DateTime.utc(2026, 10, 15, 6, 30),
              kg: 79.5,
              source: WeightSource.scan)
          .toJson();
      expect(j, {
        'schema': 1,
        'kg': 79.5,
        'at': '2026-10-15T06:30:00.000Z',
        'source': 'scan',
      });
    });
    test('round trip through tryFromJson', () {
      final e = _e(3, 81.2, s: WeightSource.scan);
      expect(WeightEntry.tryFromJson(e.toJson()), e);
    });
    test('tolerant read: DateTime, ISO string and epoch millis', () {
      final at = DateTime.utc(2026, 10, 15, 6);
      expect(WeightEntry.tryFromJson({'kg': 80, 'at': at})!.at, at);
      expect(WeightEntry.tryFromJson({'kg': 80, 'at': at.toIso8601String()})!.at,
          at);
      expect(
          WeightEntry.tryFromJson(
                  {'kg': 80, 'at': at.millisecondsSinceEpoch})!
              .at
              .millisecondsSinceEpoch,
          at.millisecondsSinceEpoch);
    });
    test('unknown or missing source reads as manual', () {
      final at = DateTime.utc(2026, 10, 15);
      expect(WeightEntry.tryFromJson({'kg': 80, 'at': at, 'source': 'fitbit'})!
              .source,
          WeightSource.manual);
      expect(WeightEntry.tryFromJson({'kg': 80, 'at': at})!.source,
          WeightSource.manual);
    });
    test('documents that cannot be a weigh-in read as null', () {
      final at = DateTime.utc(2026, 10, 15);
      expect(WeightEntry.tryFromJson(null), isNull);
      expect(WeightEntry.tryFromJson('x'), isNull);
      expect(WeightEntry.tryFromJson({'at': at}), isNull); // no kg
      expect(WeightEntry.tryFromJson({'kg': '80', 'at': at}), isNull);
      expect(WeightEntry.tryFromJson({'kg': 29.9, 'at': at}), isNull);
      expect(WeightEntry.tryFromJson({'kg': 300.1, 'at': at}), isNull);
      expect(WeightEntry.tryFromJson({'kg': 80}), isNull); // no at
      expect(WeightEntry.tryFromJson({'kg': 80, 'at': 'not a date'}), isNull);
      expect(WeightEntry.tryFromJson({'kg': 80, 'at': 1.5}), isNull);
      expect(WeightEntry.tryFromJson({'kg': 30, 'at': at}), isNotNull);
      expect(WeightEntry.tryFromJson({'kg': 300, 'at': at}), isNotNull);
    });
    test('day key is the zero-padded local calendar date', () {
      expect(weightDayKey(DateTime(2026, 3, 5, 23, 59)), '2026-03-05');
      expect(WeightEntry(at: DateTime(2026, 12, 31), kg: 70).dayKey,
          '2026-12-31');
    });
    test('value equality and hashCode', () {
      expect(_e(1, 80), _e(1, 80));
      expect(_e(1, 80).hashCode, _e(1, 80).hashCode);
      expect(_e(1, 80), isNot(_e(1, 80.1)));
      expect(_e(1, 80), isNot(_e(2, 80)));
      expect(_e(1, 80), isNot(_e(1, 80, s: WeightSource.scan)));
    });
  });

  group('latestWeightWithin / weightSlopeKgPerWeek / smoothing', () {
    final now = _d(30);
    test('the newest entry within 14 days wins', () {
      final r = latestWeightWithin([_e(20, 81), _e(28, 80), _e(25, 82)], now);
      expect(r!.kg, 80);
    });
    test('exactly 14 days old still counts; 14 days + 1 minute does not', () {
      expect(latestWeightWithin([_e(16, 81)], now), isNotNull);
      expect(
          latestWeightWithin([
            WeightEntry(
                at: now.subtract(const Duration(days: 14, minutes: 1)), kg: 81)
          ], now),
          isNull);
    });
    test('empty and all-stale lists are null', () {
      expect(latestWeightWithin(const [], now), isNull);
      expect(latestWeightWithin([_e(1, 80)], now), isNull);
    });
    test('maxAgeDays is configurable', () {
      expect(latestWeightWithin([_e(20, 81)], now, maxAgeDays: 9), isNull);
      expect(latestWeightWithin([_e(20, 81)], now, maxAgeDays: 10), isNotNull);
    });
    test('weightSlopeKgPerWeek maps entries through the Theil-Sen rules', () {
      expect(
          weightSlopeKgPerWeek([_e(0, 80.0), _e(3, 79.8), _e(7, 79.6)]),
          closeTo(-0.4, 1e-9));
      expect(weightSlopeKgPerWeek([_e(0, 80.0), _e(3, 79.8)]), isNull);
    });
    test('it uses the entry time, not the day key (two entries on one date are fine)', () {
      final a = WeightEntry(at: DateTime.utc(2026, 9, 1, 1), kg: 80.0);
      final b = WeightEntry(at: DateTime.utc(2026, 9, 4, 22), kg: 79.8);
      final c = WeightEntry(at: DateTime.utc(2026, 9, 8, 1), kg: 79.6);
      // spans 7 d 0 h; pairs: (a,b) 3.875 d, (a,c) 7 d, (b,c) 3.125 d
      final s = weightSlopeKgPerWeek([a, b, c])!;
      final pairs = [-0.2 / 3.875, -0.4 / 7, -0.2 / 3.125]..sort();
      expect(s, closeTo(pairs[1] * 7, 1e-9));
    });
    test('smoothed weight: tau 7 d plain exponential (no warm-up)', () {
      // 80.0, 79.8, 79.9 daily: alpha 0.133122 -> 79.973376, then 79.963608.
      final v = smoothedWeightKg([_e(0, 80.0), _e(1, 79.8), _e(2, 79.9)]);
      expect(v, closeTo(79.963608, 1e-5));
      expect(kWeightTauDays, 7);
    });
    test('smoothed weight of an empty series is null; one entry is itself', () {
      expect(smoothedWeightKg(const []), isNull);
      expect(smoothedWeightKg([_e(0, 80.0)]), 80.0);
    });
  });
}
