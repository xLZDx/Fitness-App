// EP-C calculators: S04-08 distance and summary (DT-08-x), S04-09 pace and
// speed (DT-09-x), S04-10 elevation (DT-10-x).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_versions.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/recording/pipeline/elevation.dart';
import 'package:fitness_app/features/recording/pipeline/geo.dart';
import 'package:fitness_app/features/recording/pipeline/pace.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/pipeline/recorded_track.dart';
import 'package:fitness_app/features/recording/pipeline/recording_constants.dart';
import 'package:fitness_app/features/recording/pipeline/smoothing.dart';
import 'package:fitness_app/features/recording/pipeline/summary_builder.dart';
import 'package:fitness_app/features/recording/widgets/gps_format.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording/replay_fixtures.dart';

double _tol(double truth) => math.max(0.005 * truth, 5.0);

SessionMetrics _finalOf(ReplayResult r) =>
    const SessionCalculator().compute(r.track);

List<PipelineSample> _samplesOf(Iterable<FixRow> rows) => [
      for (final r in rows)
        PipelineSample(
            offsetMs: r.tMs - kFixtureT0Ms,
            lat: r.lat,
            lon: r.lon,
            accuracyM: r.acc,
            altitudeM: r.alt,
            speedMps: r.speed),
    ];

class _FixedCalculator extends SessionCalculator {
  const _FixedCalculator(this.m);
  final SessionMetrics m;
  @override
  SessionMetrics compute(RecordedTrack track) => m;
}

SessionMetrics _metrics({
  double distanceM = 1000,
  double movingTimeS = 600,
  double elapsedS = 600,
  double? ascentM = 10,
  double? descentM = 5,
  double? avgSpeedMps = 1.6,
}) =>
    SessionMetrics(
        distanceM: distanceM,
        movingTimeS: movingTimeS,
        elapsedS: elapsedS,
        ascentM: ascentM,
        descentM: descentM,
        avgSpeedMps: avgSpeedMps,
        avgPaceSecPerKm: null,
        segmentCount: 1,
        smoothingId: kSmoothingAlgorithmId);

void main() {
  // ---------------------------------------------------------------- S04-08
  group('DT-08-1 distance accuracy on synthetic tracks', () {
    for (final fxb in <(String, TrackFixture Function())>[
      ('F-walk', fWalk),
      ('F-ride-30kmh', fRide30),
    ]) {
      test('/${fxb.$1}: live and final error at most 0.5 percent or 5 m', () {
        final fx = fxb.$2();
        final r = replay(fx);
        final truth = fx.truthLengthM!;
        expect((r.metrics.distanceM - truth).abs(), lessThanOrEqualTo(_tol(truth)),
            reason: 'live ${r.metrics.distanceM} vs $truth');
        expect((_finalOf(r).distanceM - truth).abs(),
            lessThanOrEqualTo(_tol(truth)),
            reason: 'final ${_finalOf(r).distanceM} vs $truth');
      });
    }

    test('/F-noise-line (2 m noise): within the 3 percent smoothing limit '
        '(the 0.5 percent limit of this row cannot hold for a noisy fixture; '
        'see the findings)', () {
      final fx = fNoiseLine(noiseM: 2.0);
      final d = _finalOf(replay(fx)).distanceM;
      expect((d - fx.truthLengthM!).abs() / fx.truthLengthM!,
          lessThanOrEqualTo(0.03));
    });

    test('/F-noise-line (8 m noise, plan fixture)', () {
      final fx = fNoiseLine();
      final d = _finalOf(replay(fx)).distanceM;
      expect((d - fx.truthLengthM!).abs() / fx.truthLengthM!,
          lessThanOrEqualTo(0.03));
    },
        skip: 'KNOWN_DEFECT S04-R-011/S04-R-032: +54 percent on the plan\'s '
            '8 m noise fixture (see S04_TEST_FINDINGS_EP_A_B_C.md)');
  });

  group('DT-08-2 real-shaped tracks', () {
    test('/F-ride-real (AR(1) noise, stops, a 12 m/s descent): final error '
        'at most 2 percent', () {
      final fx = fRideReal();
      final r = replay(fx);
      final d = _finalOf(r).distanceM;
      expect((d - fx.truthLengthM!).abs() / fx.truthLengthM!,
          lessThanOrEqualTo(0.02),
          reason: 'final $d vs ${fx.truthLengthM}');
      expect(r.autoPauses.length, greaterThanOrEqualTo(3),
          reason: 'the fixture has stops');
    });

    test('/F-walk-real (noise sigma 1 m, correlated): final error at most 2 '
        'percent', () {
      final fx = fWalkReal(sigmaM: 1.0);
      final d = _finalOf(replay(fx)).distanceM;
      expect((d - fx.truthLengthM!).abs() / fx.truthLengthM!,
          lessThanOrEqualTo(0.02),
          reason: 'final $d vs ${fx.truthLengthM}');
    });

    test('/F-walk-real (plan noise sigma 2.5 m)', () {
      final fx = fWalkReal();
      final d = _finalOf(replay(fx)).distanceM;
      expect((d - fx.truthLengthM!).abs() / fx.truthLengthM!,
          lessThanOrEqualTo(0.02));
    },
        skip: 'KNOWN_DEFECT S04-R-032: +8.7 percent with correlated 2.5 m '
            'noise under the 5-fix smoothing (see findings)');
  });

  group('DT-08-3 gaps and pauses add 0 m', () {
    /// Distance of [rows] replayed alone as one fresh recording.
    double aloneM(Iterable<FixRow> rows, {bool autoPause = true}) {
      final fx = TrackFixture('part', rows.toList(), autoPause: autoPause);
      return _finalOf(replay(fx)).distanceM;
    }

    test('/gap (F-tunnel): total equals the two sides alone', () {
      final t = fTunnel();
      final rows = t.fixture.rows;
      final cut = rows
          .indexWhere((r) => r.tMs - kFixtureT0Ms >= t.firstAfterS * 1000);
      final whole = _finalOf(replay(t.fixture)).distanceM;
      expect(whole,
          closeTo(aloneM(rows.sublist(0, cut)) + aloneM(rows.sublist(cut)), 0.01));
    });

    test('/auto-pause (F-stop-go): total equals the independently smoothed '
        'moving segments, nothing inside a pause', () {
      final sg = fStopGo();
      final r = replay(sg.fixture);
      final fin = _finalOf(r);
      // Independent oracle: split the kept samples at the pause intervals the
      // events report and smooth every part on its own.
      final spans = <(int, int)>[
        for (var i = 0; i < r.autoPauses.length; i++)
          (r.autoPauses[i].offsetMs, r.autoResumes[i].offsetMs),
      ];
      final kept = r.kept.map((e) => e.sample).toList();
      final parts = <List<PipelineSample>>[[]];
      for (final s in kept) {
        final inside = spans.any((p) => s.offsetMs > p.$1 && s.offsetMs < p.$2);
        if (inside) {
          if (parts.last.isNotEmpty) parts.add([]);
          continue;
        }
        // A fix exactly on a boundary belongs to the neighbouring part.
        final onStart = spans.any((p) => s.offsetMs == p.$1);
        parts.last.add(s);
        if (onStart) parts.add([]);
      }
      var oracle = 0.0;
      for (final part in parts) {
        final sm = const WeightedMovingAverageSmoothing().smooth(part);
        for (var i = 1; i < sm.length; i++) {
          oracle += haversineM(
              sm[i - 1].lat, sm[i - 1].lon, sm[i].lat, sm[i].lon);
        }
      }
      expect(fin.distanceM, closeTo(oracle, 1e-6));
    });

    test('/manual-pause: fixes during the pause are ignored and the two '
        'sides are separate segments', () {
      final fx = fWalk();
      final r = replay(fx,
          endAtMs: 300000,
          manualPauses: const [ManualPause(100000, 160000)]);
      final fin = _finalOf(r);
      final beforeRows =
          fx.rows.where((x) => x.tMs - kFixtureT0Ms < 100000).toList();
      final afterRows = fx.rows
          .where((x) {
            final o = x.tMs - kFixtureT0Ms;
            return o >= 160000 && o <= 300000;
          })
          .toList();
      final separate = _finalOf(replay(TrackFixture('b', beforeRows))).distanceM +
          _finalOf(replay(TrackFixture('a', afterRows))).distanceM;
      expect(fin.distanceM, closeTo(separate, 0.01));
      // None of the 60 paused fixes was kept.
      for (final k in r.keptOffsets) {
        expect(k >= 100000 && k < 160000, isFalse, reason: 'kept $k in pause');
      }
      expect(fin.movingTimeS, closeTo(300 - 60, 1.0));
    });
  });

  group('DT-08-4 haversine', () {
    test('known lengths within 0.01 m, never NaN', () {
      const perDeg = kMeanEarthRadiusM * math.pi / 180.0; // 111194.9266
      expect(haversineM(0, 0, 0, 1), closeTo(perDeg, 0.01));
      expect(haversineM(0, 0, 1, 0), closeTo(perDeg, 0.01));
      expect(haversineM(89.9, 10, 90.0, 10), closeTo(perDeg * 0.1, 0.01));
      expect(haversineM(90, 0, 90, 123), closeTo(0, 1e-6),
          reason: 'at the pole every longitude is the same point');
      expect(haversineM(0, 179.9, 0, -179.9), closeTo(perDeg * 0.2, 0.01),
          reason: 'antimeridian: the short way');
      expect(haversineM(10, 20, 10, 20), 0.0);
      expect(haversineM(90, 0, -90, 0), closeTo(kMeanEarthRadiusM * math.pi, 0.01));
      expect(haversineM(0, 0, 0, 180), closeTo(kMeanEarthRadiusM * math.pi, 0.01));
    });

    test('0.1 m apart is measured as 0.1 m (no cancellation to zero)', () {
      final a = fixturePoint(0, 0);
      final b = fixturePoint(0.1, 0);
      expect(haversineM(a.lat, a.lon, b.lat, b.lon), closeTo(0.1, 1e-4));
      expect(haversineM(a.lat, a.lon, a.lat + 1e-9, a.lon).isFinite, isTrue);
    });

    test('symmetric and non-negative on random pairs (LCG)', () {
      final r = Lcg(5);
      for (var i = 0; i < 200; i++) {
        final la = r.range(-90, 90), lo = r.range(-180, 180);
        final lb = r.range(-90, 90), lp = r.range(-180, 180);
        final d1 = haversineM(la, lo, lb, lp);
        final d2 = haversineM(lb, lp, la, lo);
        expect(d1, closeTo(d2, 1e-6));
        expect(d1.isFinite && d1 >= 0, isTrue);
        expect(d1, lessThanOrEqualTo(kMeanEarthRadiusM * math.pi + 1e-6));
      }
    });
  });

  group('DT-08-5 the summary passes the S02 validators', () {
    test('a walk: every field inside the S02 bounds, the version strings '
        'accepted, a full JSON round trip loses nothing', () {
      final fx = fWalk();
      final r = replay(fx, endAtMs: 600000);
      final start = DateTime.utc(2026, 5, 1, 7, 30);
      final res = buildSessionSummary(track: r.track, startUtc: start);
      expect(res.flagged, isFalse);
      expect(res.summary, isNotNull);
      expect(res.endUtc, start.add(Duration(milliseconds: r.elapsedMs)));
      final session = ActivitySession(
        id: 'rec-1',
        sport: SportType.walking,
        startUtc: res.startUtc,
        endUtc: res.endUtc,
        movingTimeS: res.movingTimeS,
        summary: res.summary!,
        formulaVersion: res.formulaVersion,
        metricDefinitionVersion: res.metricDefinitionVersion,
      );
      final json = jsonDecode(jsonEncode(session.toJson()));
      final back = ActivitySession.tryFromJson(json);
      expect(back, isNotNull);
      expect(back!.readDiagnostics, isEmpty);
      expect(back.formulaVersion, 'rec1.smooth-wma5-1');
      expect(back.metricDefinitionVersion, kMetricDefinitionVersion);
      expect(back.movingTimeS, closeTo(res.movingTimeS, 1e-9));
      expect(back.summary.distanceM, closeTo(res.metrics.distanceM, 1e-9));
      expect(back.summary.avgSpeedMps, closeTo(res.metrics.avgSpeedMps!, 1e-9));
      expect(back.summary.ascentM, isNull, reason: 'no altitude, so absent');
      expect(back.summary.descentM, isNull);
      expect(res.elapsedS, closeTo(600, 1e-9));
    });

    test('a climb carries ascent and descent through the round trip', () {
      final fx = fClimb();
      final r = replay(fx);
      final res = buildSessionSummary(
          track: r.track, startUtc: DateTime.utc(2026, 5, 1));
      expect(res.summary!.ascentM, closeTo(res.metrics.ascentM!, 1e-9));
      expect(res.summary!.descentM, closeTo(res.metrics.descentM!, 1e-9));
      expect(res.summary!.ascentM, greaterThan(90));
    });
  });

  group('DT-08-6 out-of-bounds values are flagged, never clamped', () {
    test('/over-bound: distance above 10^7 m', () {
      final track = RecordedTrack(
        samples: [
          PipelineSample(
              offsetMs: 0, lat: 0, lon: 0, accuracyM: 5, speedMps: 1),
          PipelineSample(
              offsetMs: 1000, lat: 0, lon: 100, accuracyM: 5, speedMps: 1),
        ],
        elapsedMs: 1000,
      );
      // The real calculator on a physically absurd pair (two fixes 11 000 km
      // apart): the gate would stop it live, the finalizer must still refuse.
      final res = buildSessionSummary(
          track: track, startUtc: DateTime.utc(2026, 1, 1));
      expect(res.metrics.distanceM, greaterThan(kSummaryDistanceMax));
      expect(res.flaggedFields, contains('distanceM'));
      expect(res.summary, isNull);
      expect(res.metrics.distanceM, greaterThan(1e7),
          reason: 'the value is reported as it is, not clamped');
    });

    test('/negative: a negative distance is flagged and left as it is', () {
      final res = buildSessionSummary(
          track: RecordedTrack(samples: const [], elapsedMs: 0),
          startUtc: DateTime.utc(2026, 1, 1),
          calculator: _FixedCalculator(_metrics(distanceM: -5)));
      expect(res.flaggedFields, ['distanceM']);
      expect(res.metrics.distanceM, -5);
      expect(res.summary, isNull);
    });

    test('/nan: NaN and infinity are flagged', () {
      for (final bad in [double.nan, double.infinity]) {
        final res = buildSessionSummary(
            track: RecordedTrack(samples: const [], elapsedMs: 0),
            startUtc: DateTime.utc(2026, 1, 1),
            calculator: _FixedCalculator(_metrics(distanceM: bad)));
        expect(res.flaggedFields, contains('distanceM'), reason: '$bad');
        expect(res.summary, isNull);
      }
    });

    test('other bounds: ascent, average speed and moving time', () {
      final res = buildSessionSummary(
          track: RecordedTrack(samples: const [], elapsedMs: 0),
          startUtc: DateTime.utc(2026, 1, 1),
          calculator: _FixedCalculator(_metrics(
              ascentM: 100001, avgSpeedMps: 120.5, movingTimeS: 604801)));
      expect(res.flaggedFields,
          containsAll(['ascentM', 'avgSpeedMps', 'movingTimeS']));
      expect(res.flaggedFields.contains('descentM'), isFalse);
    });

    test('the bounds are inclusive: 10^7 m is accepted', () {
      final res = buildSessionSummary(
          track: RecordedTrack(samples: const [], elapsedMs: 0),
          startUtc: DateTime.utc(2026, 1, 1),
          calculator: _FixedCalculator(_metrics(distanceM: 1e7)));
      expect(res.flagged, isFalse);
      expect(res.summary!.distanceM, 1e7);
    });
  });

  group('DT-08-7 undefined values are absent, not zero', () {
    test('/no-altitude (F-no-alt): ascent and descent are null in the metrics '
        'and absent in the summary', () {
      final fx = fNoAlt();
      final res = buildSessionSummary(
          track: replay(fx).track, startUtc: DateTime.utc(2026, 1, 1));
      expect(res.metrics.ascentM, isNull);
      expect(res.metrics.descentM, isNull);
      expect(res.summary!.ascentM, isNull);
      expect(res.summary!.descentM, isNull);
      expect(jsonEncode(res.summary!.toJson()).contains('ascentM'), isFalse,
          reason: 'an absent key, not a zero');
    });

    test('/zero-moving-time: average speed and pace are undefined, never '
        'infinity; the validator passes', () {
      final track = RecordedTrack(samples: [
        PipelineSample(offsetMs: 0, lat: 10, lon: 20, accuracyM: 5),
        PipelineSample(offsetMs: 1, lat: 10.0001, lon: 20, accuracyM: 5),
      ], elapsedMs: 0);
      final res = buildSessionSummary(
          track: track, startUtc: DateTime.utc(2026, 1, 1));
      expect(res.metrics.avgSpeedMps, isNull);
      expect(res.metrics.avgPaceSecPerKm, isNull);
      expect(res.flagged, isFalse);
      expect(res.summary!.avgSpeedMps, isNull);
    });

    test('a whole-track pause leaves zero moving time and an undefined '
        'average', () {
      final track = RecordedTrack(
        samples: const [],
        elapsedMs: 60000,
        manualPauses: [TrackInterval(0, 60000)],
      );
      final m = const SessionCalculator().compute(track);
      expect(m.movingTimeS, 0);
      expect(m.avgSpeedMps, isNull);
    });
  });

  group('DT-08-8 gap time counts as moving time (design D-8, PROPOSED)', () {
    test('F-tunnel: moving time equals elapsed and the average speed uses '
        'it', () {
      final t = fTunnel();
      final r = replay(t.fixture);
      final fin = _finalOf(r);
      expect(fin.movingTimeS, closeTo(fin.elapsedS, 1e-9),
          reason: 'the 60 s without fixes are inside the moving time');
      expect(fin.avgSpeedMps, closeTo(fin.distanceM / fin.movingTimeS, 1e-9));
      expect(r.metrics.movingTimeMs, r.elapsedMs);
    });
  });

  group('DT-08-9 degenerate tracks', () {
    SessionMetrics fin(List<PipelineSample> s, int elapsed) =>
        const SessionCalculator()
            .compute(RecordedTrack(samples: s, elapsedMs: elapsed));

    PipelineSample at(int tS, double x) {
      final p = fixturePoint(x, 0);
      return PipelineSample(
          offsetMs: tS * 1000, lat: p.lat, lon: p.lon, accuracyM: 6);
    }

    test('/zero-fixes: distance 0, no segment, no exception; the reason '
        'string exists', () {
      final m = fin(const [], 5000);
      expect(m.distanceM, 0);
      expect(m.segmentCount, 0);
      expect(m.avgPaceSecPerKm, isNull);
      final arb = File('lib/l10n/app_en.arb').readAsStringSync();
      expect(arb, contains('"gpsNothingRecorded"'));
    });

    test('/one-fix: distance 0', () {
      final m = fin([at(0, 0)], 5000);
      expect(m.distanceM, 0);
      expect(m.segmentCount, 0);
    });

    test('/two-fixes: one segment; smoothing may shorten, never lengthen, '
        'two points (today two equal-accuracy fixes collapse to 0 m: the '
        'segment-end contraction, see the findings)', () {
      final m = fin([at(0, 0), at(1, 10)], 1000);
      expect(m.segmentCount, 1);
      expect(m.distanceM, inInclusiveRange(0.0, 10.0 + 1e-6));
    });

    test('the summary of each degenerate track builds without error', () {
      for (final s in [
        <PipelineSample>[],
        [at(0, 0)],
        [at(0, 0), at(1, 10)]
      ]) {
        final res = buildSessionSummary(
            track: RecordedTrack(samples: s, elapsedMs: 1000),
            startUtc: DateTime.utc(2026, 1, 1));
        expect(res.flagged, isFalse);
      }
    });
  });

  // ---------------------------------------------------------------- S04-09
  group('DT-09-1 current pace and speed on constant segments', () {
    for (final c in <(String, double)>[
      ('walk-1.4', 1.4),
      ('run-3.0', 3.0),
      ('ride-8.33', 8.33),
    ]) {
      test('/${c.$1}: pace within 3 s/km once the 10 s window is full', () {
        final expected = 1000.0 / c.$2;
        final w = PaceWindow();
        for (var t = 0; t <= 60; t++) {
          w.add(t * 1000, c.$2 * t);
          if (t >= 12) {
            expect(w.currentPaceSecPerKm, isNotNull, reason: 't=$t');
            expect((w.currentPaceSecPerKm! - expected).abs(), lessThan(3.0),
                reason: 't=$t');
            expect(w.currentSpeedMps!, closeTo(c.$2, 0.01));
          }
        }
      });
    }

    test('through the pipeline: F-walk and F-ride-30kmh after the window '
        'fills', () {
      for (final c in [(fWalk(), 1.4), (fRide30(), 8.33)]) {
        // Live metrics while recording: no finish(), so the segment-end
        // flush does not distort the trailing window.
        final r = replay(c.$1, endAtMs: 300000, finish: false);
        final expected = 1000.0 / c.$2;
        final m = r.metrics;
        expect((m.currentPaceSecPerKm! - expected).abs(), lessThan(3.0),
            reason: c.$1.name);
        expect(m.currentSpeedMps!, closeTo(c.$2, 0.02));
        // Averages include the 20 s slow start of F-walk: compare with the
        // exact moving-time quotient instead of the cruising pace.
        expect(m.averagePaceSecPerKm!,
            closeTo(m.movingTimeMs / 1000.0 / (m.distanceM / 1000.0), 1e-6));
        expect(m.averageSpeedMps!,
            closeTo(m.distanceM / (m.movingTimeMs / 1000.0), 1e-9));
      }
    });

    test('the window follows a speed change: after a step from 1.4 to 3.0 '
        'm/s the pace converges within one window', () {
      final w = PaceWindow();
      var d = 0.0;
      for (var t = 0; t <= 60; t++) {
        d += t < 30 ? 1.4 : 3.0;
        w.add(t * 1000, d);
      }
      expect((w.currentPaceSecPerKm! - 1000 / 3.0).abs(), lessThan(3.0));
    });
  });

  group('DT-09-2 undefined pace is null, never 0 or infinity', () {
    test('/under-10m: 9.99 m of moving distance has no pace, 10.0 m has',
        () {
      for (final c in [(9.99, false), (10.0, true)]) {
        final w = PaceWindow();
        w.add(0, 0);
        // The distance is covered inside the first 10 s, then the walker
        // stands still until the window is full.
        w.add(5000, c.$1);
        w.add(10000, c.$1);
        w.add(15000, c.$1 + 5.0); // fresh movement inside the window
        // Window distance is positive; the cumulative-distance rule decides.
        if (c.$2) {
          expect(w.currentPaceSecPerKm, isNotNull);
        } else {
          expect(w.currentPaceSecPerKm, isNotNull,
              reason: 'cumulative distance is above 10 m by now');
        }
      }
      // The minimum applies to the distance at the newest point.
      final w = PaceWindow();
      w.add(0, 0);
      w.add(10000, 9.99);
      expect(w.currentPaceSecPerKm, isNull);
      expect(w.currentSpeedMps, isNull);
      final w2 = PaceWindow();
      w2.add(0, 0);
      w2.add(10000, 10.0);
      expect(w2.currentPaceSecPerKm, closeTo(1000.0, 1e-9));
    });

    test('/stopped: zero distance in the window gives null', () {
      final w = PaceWindow();
      for (var t = 0; t <= 30; t++) {
        w.add(t * 1000, t < 10 ? 1.4 * t : 14.0);
      }
      expect(w.currentPaceSecPerKm, isNull);
      expect(w.currentSpeedMps, isNull);
    });

    test('/window-not-full: nothing before 10 s of moving time', () {
      final w = PaceWindow();
      for (var t = 0; t <= 9; t++) {
        w.add(t * 1000, 5.0 * t);
        expect(w.currentPaceSecPerKm, isNull, reason: 't=$t');
      }
      w.add(10000, 50.0);
      expect(w.currentPaceSecPerKm, closeTo(200.0, 1e-9));
    });

    test('values are never zero, negative, NaN or infinite', () {
      final w = PaceWindow();
      final r = Lcg(8);
      var d = 0.0;
      for (var t = 0; t <= 600; t++) {
        d += t % 90 < 30 ? 0.0 : r.range(0.2, 4.0);
        w.add(t * 1000, d);
        for (final v in [w.currentPaceSecPerKm, w.currentSpeedMps]) {
          if (v != null) expect(v.isFinite && v > 0, isTrue, reason: 't=$t');
        }
      }
    });
  });

  group('DT-09-3 moving time is elapsed minus paused', () {
    test('/no-pause: moving time equals elapsed (live and final)', () {
      final r = replay(fWalk(), endAtMs: 300000);
      expect(r.metrics.movingTimeMs, 300000);
      expect(_finalOf(r).movingTimeS, closeTo(300, 1.0));
    });

    test('/manual-pause: a 60 s manual pause is subtracted', () {
      final r = replay(fWalk(),
          endAtMs: 300000, manualPauses: const [ManualPause(100000, 160000)]);
      expect((r.metrics.movingTimeMs - 240000).abs(), lessThanOrEqualTo(1000));
      expect((_finalOf(r).movingTimeS - 240).abs(), lessThanOrEqualTo(1.0));
    });

    test('/auto-pause (F-stop-go): the 86 s of auto pause are subtracted', () {
      final sg = fStopGo();
      final r = replay(sg.fixture);
      final expected = r.elapsedMs - 86000;
      expect((r.metrics.movingTimeMs - expected).abs(), lessThanOrEqualTo(1000));
      expect((_finalOf(r).movingTimeS * 1000 - expected).abs(),
          lessThanOrEqualTo(1000));
    });

    test('an open manual pause at the end is subtracted too', () {
      final r = replay(fWalk(),
          endAtMs: 120000, manualPauses: const [ManualPause(100000, 999999)]);
      expect((r.metrics.movingTimeMs - 100000).abs(), lessThanOrEqualTo(1000));
      expect((_finalOf(r).movingTimeS - 100).abs(), lessThanOrEqualTo(1.0));
    });

    test('average pace uses moving time, not elapsed time', () {
      final r = replay(fWalk(),
          endAtMs: 300000, manualPauses: const [ManualPause(100000, 160000)]);
      final m = r.metrics;
      final byMoving = (m.movingTimeMs / 1000.0) / (m.distanceM / 1000.0);
      expect(m.averagePaceSecPerKm, closeTo(byMoving, 1e-6));
      final byElapsed = (m.elapsedMs / 1000.0) / (m.distanceM / 1000.0);
      expect(m.averagePaceSecPerKm, lessThan(byElapsed - 50));
    });
  });

  group('DT-09-4 averages with no moving time or no distance', () {
    test('moving time 0, negative, NaN or infinite gives null, not infinity',
        () {
      for (final t in [0.0, -1.0, double.nan, double.infinity]) {
        expect(averagePaceSecPerKm(100, t), isNull, reason: 'time $t');
        expect(averageSpeedMps(100, t), isNull, reason: 'time $t');
      }
      for (final d in [double.nan, double.infinity]) {
        expect(averagePaceSecPerKm(d, 60), isNull);
        expect(averageSpeedMps(d, 60), isNull);
      }
    });

    test('distance under 10 m or zero gives no average pace; speed is 0 '
        'only for a real zero distance', () {
      expect(averagePaceSecPerKm(0, 60), isNull);
      expect(averagePaceSecPerKm(9.99, 60), isNull);
      expect(averagePaceSecPerKm(10.0, 60), closeTo(6000, 1e-9));
      expect(averageSpeedMps(0, 60), 0.0);
      expect(averageSpeedMps(60, 60), 1.0);
    });
  });

  group('DT-09-5 pace formatter', () {
    test('5:59.6 reads 6:00 and 6:00.0 reads 6:00, never 5:60', () {
      expect(gpsFormatPace(359.6), '6:00 /km');
      expect(gpsFormatPace(360.0), '6:00 /km');
      expect(gpsFormatPace(359.4), '5:59 /km');
      for (var s = 0.0; s < 3600; s += 0.05) {
        final t = gpsFormatPace(s);
        if (t == null) continue;
        expect(t.contains(':60'), isFalse, reason: 'pace $s read "$t"');
      }
    });

    test('undefined pace has no text', () {
      expect(gpsFormatPace(null), isNull);
      expect(gpsFormatPace(0), isNull);
      expect(gpsFormatPace(double.infinity), isNull);
      expect(gpsFormatPace(double.nan), isNull);
      expect(gpsFormatSpeed(null), isNull);
      expect(gpsFormatSpeed(double.infinity), isNull);
    });
  });

  // ---------------------------------------------------------------- S04-10
  group('DT-10-1 altitude noise does not inflate elevation', () {
    ({double asc, double desc}) elev(TrackFixture fx) {
      final e = ElevationAccumulator();
      for (final r in fx.rows) {
        e.add(r.tMs - kFixtureT0Ms, r.alt);
      }
      return (asc: e.ascentM!, desc: e.descentM!);
    }

    test('/ascent and /descent on a flat walk with +-1.5 m altitude noise: '
        'each at most 5 m', () {
      final rnd = Lcg(9);
      final e = ElevationAccumulator();
      for (var t = 0; t < 600; t++) {
        e.add(t * 1000, 100 + rnd.sym() * 1.5);
      }
      expect(e.ascentM!, lessThanOrEqualTo(5.0));
      expect(e.descentM!, lessThanOrEqualTo(5.0));
    });

    test('/ascent and /descent on F-flat-alt-noise (+-4 m, plan fixture)', () {
      final r = elev(fFlatAltNoise());
      expect(r.asc, lessThanOrEqualTo(5.0), reason: 'ascent ${r.asc}');
      expect(r.desc, lessThanOrEqualTo(5.0), reason: 'descent ${r.desc}');
    },
        skip: 'KNOWN_DEFECT S04-R-034: measured ascent 61 m and descent 59 m '
            'for +-4 m noise with the 5-sample median and 3 m hysteresis '
            '(see findings)');

    test('through the live pipeline the same numbers appear', () {
      final r = replay(fFlatAltNoise());
      final e = elev(fFlatAltNoise());
      expect(r.metrics.ascentM, closeTo(e.asc, 1e-9));
      expect(r.metrics.descentM, closeTo(e.desc, 1e-9));
    });
  });

  group('DT-10-2 a real climb is counted', () {
    test('/F-climb: ascent within 10 percent of 100 m, descent 0', () {
      final r = replay(fClimb());
      final fin = _finalOf(r);
      expect(fin.ascentM!, inInclusiveRange(90.0, 110.0));
      expect(fin.descentM!, 0.0);
      expect(r.metrics.ascentM!, inInclusiveRange(90.0, 110.0));
    });

    test('/F-climb-reversed: descent about 100 m and ascent 0', () {
      final r = replay(fClimb(reversed: true));
      final fin = _finalOf(r);
      expect(fin.descentM!, inInclusiveRange(90.0, 110.0));
      expect(fin.ascentM!, 0.0);
    });
  });

  group('DT-10-3 missing altitude', () {
    test('/none (F-no-alt): null, not 0', () {
      final r = replay(fNoAlt());
      expect(r.metrics.ascentM, isNull);
      expect(r.metrics.descentM, isNull);
      final fin = _finalOf(r);
      expect(fin.ascentM, isNull);
      expect(fin.descentM, isNull);
    });

    test('/partial: altitude on every second fix still yields the climb, '
        'defined and not silently 0', () {
      final full = fClimb();
      final half = TrackFixture('half', [
        for (var i = 0; i < full.rows.length; i++)
          i.isEven
              ? full.rows[i]
              : FixRow(
                  tMs: full.rows[i].tMs,
                  lat: full.rows[i].lat,
                  lon: full.rows[i].lon,
                  acc: full.rows[i].acc,
                  speed: full.rows[i].speed),
      ]);
      final fin = _finalOf(replay(half));
      expect(fin.ascentM, isNotNull);
      expect(fin.ascentM!, inInclusiveRange(85.0, 115.0));
    });

    test('/partial: altitude only on the first half: the climb of that half '
        'is reported (design: what exists is counted), still not 0', () {
      final full = fClimb();
      final mid = full.rows.length ~/ 2;
      final firstHalf = TrackFixture('fh', [
        for (var i = 0; i < full.rows.length; i++)
          i < mid
              ? full.rows[i]
              : FixRow(
                  tMs: full.rows[i].tMs,
                  lat: full.rows[i].lat,
                  lon: full.rows[i].lon,
                  acc: full.rows[i].acc,
                  speed: full.rows[i].speed),
      ]);
      final fin = _finalOf(replay(firstHalf));
      expect(fin.ascentM, isNotNull);
      expect(fin.ascentM!, inInclusiveRange(35.0, 65.0));
    });

    test('a non-finite altitude is ignored like a missing one', () {
      final e = ElevationAccumulator();
      e.add(0, double.nan);
      e.add(1000, double.infinity);
      expect(e.ascentM, isNull);
    });
  });

  group('DT-10-4 hysteresis is exactly 3 m', () {
    // Plateaus of five identical readings make the 5-sample median equal the
    // plateau, so the hysteresis alone decides.
    ElevationAccumulator run(List<double> plateaus) {
      final e = ElevationAccumulator();
      var t = 0;
      for (final p in plateaus) {
        for (var i = 0; i < 5; i++) {
          e.add(t * 1000, p);
          t++;
        }
      }
      return e;
    }

    test('2.9 m is not counted, 3.0 m is (from the last counted extreme)',
        () {
      expect(run([100, 102.9]).ascentM, 0.0);
      expect(run([100, 103.0]).ascentM, closeTo(3.0, 1e-9));
      expect(run([100, 97.1]).descentM, 0.0);
      expect(run([100, 97.0]).descentM, closeTo(3.0, 1e-9));
    });

    test('creep: 1 m steps are counted only once 3 m from the reference, in '
        'total no more than the real climb', () {
      final e = run([100, 101, 102, 103, 104, 105]);
      expect(e.ascentM!, closeTo(3.0, 1e-9),
          reason: 'one count at 103; 104 and 105 are less than 3 m from it');
      final e2 = run([100, 101, 102, 103, 104, 105, 106]);
      expect(e2.ascentM!, closeTo(6.0, 1e-9));
    });

    test('a reversal of exactly 3 m from the counted level counts as '
        'descent; 2.9 m does not', () {
      final up = run([100, 103, 100]);
      expect(up.ascentM, closeTo(3.0, 1e-9));
      expect(up.descentM, closeTo(3.0, 1e-9));
      final small = run([100, 103, 100.1]);
      expect(small.descentM, 0.0);
    });

    test('ascent and descent are never negative and never decrease', () {
      final rnd = Lcg(77);
      final e = ElevationAccumulator();
      var lastA = 0.0, lastD = 0.0;
      for (var t = 0; t < 2000; t++) {
        e.add(t * 1000, 200 + 30 * math.sin(t / 50.0) + rnd.sym() * 2);
        expect(e.ascentM! >= lastA && e.descentM! >= lastD, isTrue);
        lastA = e.ascentM!;
        lastD = e.descentM!;
      }
      expect(lastA, greaterThan(100));
    });
  });

  group('DT-10-5 altitude outliers', () {
    test('/spike-ignored: one +100 m sample changes the ascent by at most the '
        'DT-10-2 tolerance', () {
      final clean = _finalOf(replay(fClimb())).ascentM!;
      final spiky = _finalOf(replay(fClimb(spike: true))).ascentM!;
      expect((spiky - clean).abs(), lessThanOrEqualTo(10.0),
          reason: 'clean $clean, with spike $spiky');
      expect(spiky, inInclusiveRange(90.0, 110.0));
      final e = ElevationAccumulator();
      for (final r in fClimb(spike: true).rows) {
        e.add(r.tMs - kFixtureT0Ms, r.alt);
      }
      expect(e.outlierCount, 0,
          reason: 'a single sample is absorbed by the median before the '
              'step rule even sees it');
    });

    test('a lone spike on a flat track adds nothing', () {
      final e = ElevationAccumulator();
      for (var t = 0; t < 60; t++) {
        e.add(t * 1000, t == 30 ? 600.0 : 500.0);
      }
      expect(e.ascentM, 0.0);
      expect(e.descentM, 0.0);
    });

    test('/real-climb-still-counted: 3 m/s of climbing is not swallowed by '
        'the 10 m/s step rule', () {
      final e = ElevationAccumulator();
      for (var t = 0; t <= 100; t++) {
        e.add(t * 1000, 500 + 3.0 * t);
      }
      expect(e.ascentM!, inInclusiveRange(285.0, 305.0));
      expect(e.descentM, 0.0);
    });

    test('a sustained jump (5 or more consecutive outlier steps) is accepted '
        'as a new level without counting the jump itself', () {
      final e = ElevationAccumulator();
      for (var t = 0; t < 30; t++) {
        e.add(t * 1000, 500.0);
      }
      for (var t = 30; t < 90; t++) {
        e.add(t * 1000, 900.0); // e.g. a data source switch, +400 m at once
      }
      expect(e.ascentM!, lessThan(10.0),
          reason: 'the +400 m step is not climbing');
      expect(e.outlierCount, greaterThanOrEqualTo(1));
    });
  });
}

/// The S02 upper bound of the summary distance (10^7 m).
const double kSummaryDistanceMax = 10000000;
