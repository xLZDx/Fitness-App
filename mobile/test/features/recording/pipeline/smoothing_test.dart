// S04-06 Smoothing, raw kept (R-010, R-011): rows DT-06-1 .. DT-06-8.
import 'dart:convert';
import 'dart:math' as math;

import 'package:fitness_app/features/activity/data/activity_versions.dart';
import 'package:fitness_app/features/activity/data/summary_fields.dart';
import 'package:fitness_app/features/recording/pipeline/distance_accumulator.dart';
import 'package:fitness_app/features/recording/pipeline/geo.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/pipeline/recorded_track.dart';
import 'package:fitness_app/features/recording/pipeline/recording_constants.dart';
import 'package:fitness_app/features/recording/pipeline/smoothing.dart';
import 'package:fitness_app/features/recording/pipeline/summary_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording/replay_fixtures.dart';

/// A second algorithm: no smoothing at all (raw polyline).
class _IdentitySmoothing extends SmoothingStrategy {
  const _IdentitySmoothing();
  @override
  String get id => 'identity-1';
  @override
  List<PipelineSample> smooth(List<PipelineSample> segment) =>
      List.of(segment);
  @override
  IncrementalSmoother createIncremental() => _IdentityInc();
}

class _IdentityInc implements IncrementalSmoother {
  @override
  List<PipelineSample> add(PipelineSample raw) => [raw];
  @override
  List<PipelineSample> flush() => const [];
}

List<PipelineSample> _samples(TrackFixture fx) => [
      for (final r in fx.rows)
        PipelineSample(
            offsetMs: r.tMs - kFixtureT0Ms,
            lat: r.lat,
            lon: r.lon,
            accuracyM: r.acc,
            altitudeM: r.alt,
            speedMps: r.speed),
    ];

String _rawBytes(List<PipelineSample> s) => jsonEncode([
      for (final x in s)
        [x.offsetMs, x.lat, x.lon, x.accuracyM, x.altitudeM, x.speedMps]
    ]);

double _pathLength(List<PipelineSample> s) {
  var d = 0.0;
  for (var i = 1; i < s.length; i++) {
    d += haversineM(s[i - 1].lat, s[i - 1].lon, s[i].lat, s[i].lon);
  }
  return d;
}

double _maxDisplacement(List<PipelineSample> raw, List<PipelineSample> out) {
  var m = 0.0;
  for (var i = 0; i < raw.length; i++) {
    final d = haversineM(raw[i].lat, raw[i].lon, out[i].lat, out[i].lon);
    if (d > m) m = d;
  }
  return m;
}

RecordedTrack _trackOf(List<PipelineSample> s,
        {List<TrackInterval> gaps = const [],
        List<TrackInterval> pauses = const []}) =>
    RecordedTrack(
        samples: s,
        elapsedMs: s.last.offsetMs,
        gaps: gaps,
        manualPauses: pauses);

void main() {
  const wma = WeightedMovingAverageSmoothing();

  group('DT-06-1 raw is kept, smoothing is derived', () {
    test('re-smoothing with a second algorithm changes the derived distance '
        'and the formula version, and leaves the raw bytes identical', () {
      final fx = fNoiseLine();
      final raw = _samples(fx);
      final hashBefore = _rawBytes(raw);
      final track = _trackOf(raw);

      final a = buildSessionSummary(
          track: track, startUtc: DateTime.utc(2026, 1, 1));
      final b = buildSessionSummary(
          track: track,
          startUtc: DateTime.utc(2026, 1, 1),
          calculator: const SessionCalculator(smoothing: _IdentitySmoothing()));

      expect(a.metrics.distanceM, isNot(closeTo(b.metrics.distanceM, 1.0)),
          reason: 'a different algorithm must change the derived value');
      expect(a.formulaVersion, 'rec1.smooth-wma5-1');
      expect(b.formulaVersion, 'rec1.identity-1');
      expect(a.formulaVersion, isNot(b.formulaVersion));
      expect(_rawBytes(raw), hashBefore,
          reason: 'raw samples are untouched by either computation');
      // The identity algorithm gives the raw points to the minimum-step chord
      // distance (kDistanceMinStepM), which is what the calculator sums.
      final chord = DistanceAccumulator();
      for (final s in raw) {
        chord.add(s.lat, s.lon);
      }
      expect(b.metrics.distanceM, closeTo(chord.totalM, 1e-6));
    });

    test('the live pipeline never edits the raw samples it kept', () {
      final fx = fNoiseLine();
      final r = replay(fx);
      final keptRaw = [for (final e in r.kept) e.sample];
      final expected = _samples(fx);
      expect(_rawBytes(keptRaw), _rawBytes(expected));
    });
  });

  group('DT-06-2 formula version strings', () {
    test('the id and the stored version fit the S02 limit and pattern', () {
      expect(kSmoothingAlgorithmId.length, lessThanOrEqualTo(32));
      final s = buildSessionSummary(
          track: _trackOf(_samples(fNoAlt())),
          startUtc: DateTime.utc(2026, 1, 1));
      expect(s.formulaVersion.length, lessThanOrEqualTo(kMaxVersionStringLength));
      expect(kVersionStringPattern.hasMatch(s.formulaVersion), isTrue);
      expect(s.formulaVersion, '$kCalculatorVersionPrefix.$kSmoothingAlgorithmId');
      expect(s.flaggedFields, isEmpty);
      expect(s.metricDefinitionVersion, kMetricDefinitionVersion);
    });

    test('a too long algorithm id is flagged at build time, not at hand-off',
        () {
      final s = buildSessionSummary(
          track: _trackOf(_samples(fNoAlt())),
          startUtc: DateTime.utc(2026, 1, 1),
          calculator: const SessionCalculator(
              smoothing: _LongIdSmoothing()));
      expect(s.formulaVersion.length, greaterThan(kMaxVersionStringLength));
      expect(s.flaggedFields, contains('formulaVersion'));
      expect(s.summary, isNull, reason: 'a flagged result is never written');
    });
  });

  group('DT-06-3 / DT-06-4 smoothing quality', () {
    test('/F-noise-line (2 m noise): smoothed length within 3 percent of '
        'truth', () {
      final fx = fNoiseLine(noiseM: 2.0);
      final r = replay(fx);
      final s = const SessionCalculator().compute(r.track);
      final err = (s.distanceM - fx.truthLengthM!).abs() / fx.truthLengthM!;
      expect(err, lessThanOrEqualTo(0.03),
          reason: 'measured ${s.distanceM} for ${fx.truthLengthM}');
      // Smoothing must help: the raw polyline is much longer than the truth.
      expect(_pathLength(_samples(fx)), greaterThan(fx.truthLengthM! * 1.1));
    });

    test('/F-noise-line (8 m noise, plan fixture): length within 3 percent '
        'of truth', () {
      final fx = fNoiseLine(); // noise up to 8 m on each axis
      final s = const SessionCalculator().compute(replay(fx).track);
      final err = (s.distanceM - fx.truthLengthM!).abs() / fx.truthLengthM!;
      expect(err, lessThanOrEqualTo(0.03),
          reason: 'KNOWN_DEFECT S04-R-011: measured ${s.distanceM} m for a '
              '${fx.truthLengthM} m truth (+${(err * 100).toStringAsFixed(1)} '
              'percent) with the 5-fix weighted average');
    });

    test('/F-turns: smoothed length within 3 percent of truth (2 m noise)',
        () {
      final t = fTurns();
      final s = const SessionCalculator().compute(replay(t.fixture).track);
      final truth = t.fixture.truthLengthM!;
      expect((s.distanceM - truth).abs() / truth, lessThanOrEqualTo(0.03));
    });

    test('no kept point moves more than 15 m from its raw position, at 2 m '
        'and at 8 m noise', () {
      for (final fx in [fNoiseLine(noiseM: 2.0), fNoiseLine(), fTurns().fixture]) {
        final raw = _samples(fx);
        final out = wma.smooth(raw);
        expect(out.length, raw.length);
        expect(_maxDisplacement(raw, out), lessThanOrEqualTo(15.0 + 1e-3),
            reason: fx.name);
        // Offsets, accuracy, altitude and speed are copied, not smoothed.
        for (var i = 0; i < raw.length; i++) {
          expect(out[i].offsetMs, raw[i].offsetMs);
          expect(out[i].accuracyM, raw[i].accuracyM);
          expect(out[i].speedMps, raw[i].speedMps);
        }
      }
    });

    test('the 15 m clamp is active: one far outlier is pulled by exactly 15 m '
        'at most', () {
      final base = _samples(fNoiseLine(noiseM: 0));
      final raw = base.sublist(0, 9);
      final p = fixturePoint(raw[4].lon * 0 + 1.4 * 4, 400); // 400 m north
      raw[4] = PipelineSample(
          offsetMs: raw[4].offsetMs,
          lat: p.lat,
          lon: p.lon,
          accuracyM: 1.0, // so heavy that the average wants to follow it
          speedMps: 1.4);
      final out = wma.smooth(raw);
      // Neighbours (accuracy 5..12) are dragged towards the outlier but never
      // by more than the limit.
      expect(_maxDisplacement(raw, out), lessThanOrEqualTo(15.0 + 1e-3));
      expect(_maxDisplacement(raw, out), greaterThan(10.0),
          reason: 'the outlier should have pulled a neighbour');
    });

    test('/F-turns apex: the smoothed corner is within 15 m of the raw '
        'apex', () {
      final t = fTurns();
      final raw = _samples(t.fixture);
      final out = wma.smooth(raw);
      // Closest raw fix to the true corner, and its smoothed counterpart.
      var best = 0;
      var bestD = double.infinity;
      for (var i = 0; i < raw.length; i++) {
        final d = haversineM(raw[i].lat, raw[i].lon, t.apexLat, t.apexLon);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      final moved = haversineM(
          out[best].lat, out[best].lon, t.apexLat, t.apexLon);
      expect(moved, lessThanOrEqualTo(15.0), reason: 'corner cut by $moved m');
      // And not trivially zero movement everywhere: the corner IS rounded.
      expect(_maxDisplacement(raw, out), greaterThan(0.01));
    });
  });

  group('DT-06-5 segments split at gaps and pauses', () {
    PipelineSample at(int tS, double x, double y) {
      final p = fixturePoint(x, y);
      return PipelineSample(
          offsetMs: tS * 1000,
          lat: p.lat,
          lon: p.lon,
          accuracyM: 6,
          speedMps: 1.4);
    }

    final a = [for (var i = 0; i <= 9; i++) at(i, 1.4 * i, 0)];
    final b = [for (var i = 0; i <= 9; i++) at(70 + i, 5000 + 1.4 * i, 0)];

    test('across a tunnel the two sides are not blended', () {
      final whole = const SessionCalculator().compute(_trackOf([...a, ...b],
          gaps: [TrackInterval(9000, 70000)]));
      final onlyA = const SessionCalculator().compute(_trackOf(a));
      final onlyB = const SessionCalculator().compute(_trackOf(b));
      expect(whole.distanceM, closeTo(onlyA.distanceM + onlyB.distanceM, 1e-9));
      expect(whole.segmentCount, 2);
      expect(whole.distanceM, lessThan(100),
          reason: 'the 5 km between the sides must not be counted');
    });

    test('across a manual pause the two sides are not blended', () {
      final whole = const SessionCalculator().compute(_trackOf([...a, ...b],
          pauses: [TrackInterval(9500, 69500)]));
      final onlyA = const SessionCalculator().compute(_trackOf(a));
      final onlyB = const SessionCalculator().compute(_trackOf(b));
      expect(whole.distanceM, closeTo(onlyA.distanceM + onlyB.distanceM, 1e-9));
      expect(whole.segmentCount, 2);
    });

    test('without a gap the same samples are one segment (the control)', () {
      final one = const SessionCalculator().compute(_trackOf([...a, ...b]));
      expect(one.segmentCount, 1);
      expect(one.distanceM, greaterThan(4000));
    });
  });

  group('DT-06-6 short inputs', () {
    PipelineSample at(int tS) {
      final p = fixturePoint(1.4 * tS, 0);
      return PipelineSample(
          offsetMs: tS * 1000, lat: p.lat, lon: p.lon, accuracyM: 6);
    }

    for (final n in [0, 1, 2, 4]) {
      test('length $n: no exception, same length, finite coordinates', () {
        final input = [for (var i = 0; i < n; i++) at(i)];
        final out = wma.smooth(input);
        expect(out.length, n);
        for (final s in out) {
          expect(s.lat.isFinite && s.lon.isFinite, isTrue);
        }
        if (n == 0) expect(out, isEmpty);
        // A straight line stays (almost) where it is with short windows.
        if (n > 0) expect(_maxDisplacement(input, out), lessThan(2.0));
      });
    }

    test('an empty and a one-fix track survive the whole finalizer', () {
      final empty = const SessionCalculator()
          .compute(RecordedTrack(samples: const [], elapsedMs: 0));
      expect(empty.distanceM, 0);
      expect(empty.avgSpeedMps, isNull);
      final one = const SessionCalculator()
          .compute(RecordedTrack(samples: [at(0)], elapsedMs: 5000));
      expect(one.distanceM, 0);
      expect(one.segmentCount, 0);
    });
  });

  group('DT-06-7 weights stay finite', () {
    test('accuracy at the lowest value that passes the gate (0, 1e-9, tiny '
        'positive, null)', () {
      for (final acc in <double?>[0.0, 1e-12, 1e-9, 0.5, 1.0, null]) {
        final raw = [
          for (var i = 0; i < 9; i++)
            PipelineSample(
                offsetMs: i * 1000,
                lat: 10 + i * 1e-5,
                lon: 20 + (i.isEven ? 1e-5 : 0),
                accuracyM: acc),
        ];
        final out = wma.smooth(raw);
        for (final s in out) {
          expect(s.lat.isFinite, isTrue, reason: 'acc=$acc');
          expect(s.lon.isFinite, isTrue, reason: 'acc=$acc');
        }
        expect(_maxDisplacement(raw, out), lessThanOrEqualTo(15.0 + 1e-3));
      }
    });

    test('a mix of 0 m and 30 m accuracy does not blow up', () {
      final raw = [
        for (var i = 0; i < 7; i++)
          PipelineSample(
              offsetMs: i * 1000,
              lat: 10 + i * 1e-5,
              lon: 20,
              accuracyM: i.isEven ? 0.0 : 30.0),
      ];
      final out = wma.smooth(raw);
      expect(out.every((s) => s.lat.isFinite && s.lon.isFinite), isTrue);
    });
  });

  group('DT-06-8 live and final use one algorithm', () {
    test('same algorithm id; after finish the live distance equals the '
        'final value; before finish it lags by at most the 2-fix window', () {
      final fx = fWalk();
      final partial = replay(fx, endAtMs: 600000, finish: false);
      final liveBefore = partial.metrics.distanceM;
      final r = replay(fx, endAtMs: 600000);
      final fin = const SessionCalculator().compute(r.track);
      expect(r.pipeline.smoothing.id, kSmoothingAlgorithmId);
      expect(fin.smoothingId, kSmoothingAlgorithmId);
      expect(r.metrics.distanceM, closeTo(fin.distanceM, 1e-6));
      // The live number before the tail is flushed is slightly smaller.
      expect(liveBefore, lessThanOrEqualTo(r.metrics.distanceM));
      expect(r.metrics.distanceM - liveBefore, lessThan(2 * 1.4 + 0.01));
    });

    test('incremental and batch smoothing produce identical points', () {
      final raw = _samples(fNoiseLine());
      final batch = wma.smooth(raw);
      final inc = wma.createIncremental();
      final live = <PipelineSample>[];
      for (final s in raw) {
        live.addAll(inc.add(s));
      }
      live.addAll(inc.flush());
      expect(live.length, batch.length);
      for (var i = 0; i < batch.length; i++) {
        expect(live[i], batch[i], reason: 'point $i');
      }
    });

    test('the lag is two fixes: the first output appears with the third '
        'input', () {
      final raw = _samples(fWalk()).take(6).toList();
      final inc = wma.createIncremental();
      expect(inc.add(raw[0]), isEmpty);
      expect(inc.add(raw[1]), isEmpty);
      expect(inc.add(raw[2]).length, 1);
      expect(math.max(1, inc.add(raw[3]).length), 1);
    });
  });
}

class _LongIdSmoothing extends SmoothingStrategy {
  const _LongIdSmoothing();
  @override
  String get id => 'a-very-long-smoothing-algorithm-id-1';
  @override
  List<PipelineSample> smooth(List<PipelineSample> segment) =>
      List.of(segment);
  @override
  IncrementalSmoother createIncremental() => _IdentityInc();
}
