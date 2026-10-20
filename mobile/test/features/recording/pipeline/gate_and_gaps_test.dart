// S04-05 Sampling, fields, gate, gaps (R-006 .. R-009): rows DT-05-4 .. DT-05-9
// and DT-05-11. (DT-05-1 .. DT-05-3 live in state/recorder_service_test.dart;
// DT-05-10, the journal-to-session mapper, belongs to the journal epic.)
import 'dart:math' as math;

import 'package:fitness_app/features/recording/location/fix.dart';
import 'package:fitness_app/features/recording/pipeline/accuracy_gate.dart';
import 'package:fitness_app/features/recording/pipeline/geo.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/pipeline/recorder_pipeline.dart';
import 'package:fitness_app/features/recording/pipeline/recorded_track.dart';
import 'package:fitness_app/features/recording/pipeline/recording_constants.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording/recorder_world.dart';
import '../../../support/recording/replay_fixtures.dart';

PipelineSample _s(int offsetMs, double lat, double lon,
        {double? acc = 6, double? alt, double? speed}) =>
    PipelineSample(
        offsetMs: offsetMs,
        lat: lat,
        lon: lon,
        accuracyM: acc,
        altitudeM: alt,
        speedMps: speed);

PipelineSample _east(int tS, double xM, {double? acc = 6}) {
  final p = fixturePoint(xM, 0);
  return _s(tS * 1000, p.lat, p.lon, acc: acc);
}

void main() {
  group('DT-05-4 gate boundary table', () {
    GateResult eval(PipelineSample s) => AccuracyGate().evaluate(s);

    void kept(String label, PipelineSample s) {
      final r = eval(s);
      expect(r, isA<GateKept>(), reason: '$label must be kept');
    }

    void rejected(String label, PipelineSample s, RejectReason why) {
      final r = eval(s);
      expect(r, isA<GateRejected>(), reason: '$label must be rejected');
      expect((r as GateRejected).reason, why, reason: label);
    }

    test('accuracy: 30.0 kept, 30.1 rejected', () {
      kept('30.0', _s(1000, 10, 20, acc: 30.0));
      rejected('30.1', _s(1000, 10, 20, acc: 30.1), RejectReason.accuracy);
      kept('29.9', _s(1000, 10, 20, acc: 29.9));
    });

    test('accuracy: negative, NaN, infinite and missing are rejected and '
        'counted', () {
      for (final bad in <double?>[-0.001, -1.0, -30.0, double.nan,
          double.infinity, double.negativeInfinity, null]) {
        final g = AccuracyGate();
        final r = g.evaluate(_s(1000, 10, 20, acc: bad));
        expect(r, isA<GateRejected>(), reason: 'accuracy $bad');
        expect(g.counters.total, 1, reason: 'counted once: $bad');
        expect(g.anchor, isNull, reason: 'a rejected fix is never the anchor');
      }
    });

    test('accuracy 0 is kept today (design text: present, finite, at most '
        '30 m); DEPENDS-ON-DESIGN, pinned so a change is visible', () {
      kept('0.0', _s(1000, 10, 20, acc: 0.0));
    });

    test('latitude: 90.0 kept, 90.0001 rejected as invalid; -90 and -90.0001',
        () {
      kept('lat 90', _s(1000, 90.0, 20));
      kept('lat -90', _s(1000, -90.0, 20));
      rejected('lat 90.0001', _s(1000, 90.0001, 20), RejectReason.invalid);
      rejected('lat -90.0001', _s(1000, -90.0001, 20), RejectReason.invalid);
    });

    test('longitude: 180.0 kept, 180.0001 rejected as invalid; -180 and '
        '-180.0001', () {
      kept('lon 180', _s(1000, 10, 180.0));
      kept('lon -180', _s(1000, 10, -180.0));
      rejected('lon 180.0001', _s(1000, 10, 180.0001), RejectReason.invalid);
      rejected('lon -180.0001', _s(1000, 10, -180.0001), RejectReason.invalid);
    });

    test('non-finite coordinates are invalid', () {
      rejected('lat NaN', _s(1000, double.nan, 20), RejectReason.invalid);
      rejected('lon inf', _s(1000, 10, double.infinity), RejectReason.invalid);
    });

    test('implied speed: exactly the limit is kept, just above is rejected',
        () {
      final a = _east(0, 0);
      final b = _east(1, 30.0);
      final implied = haversineM(a.lat, a.lon, b.lat, b.lon) / 1.0;
      // Limit equal to the implied speed: kept (inclusive).
      var g = AccuracyGate(config: PipelineConfig(maxImpliedSpeedMps: implied));
      expect(g.evaluate(a), isA<GateKept>());
      expect(g.evaluate(b), isA<GateKept>(), reason: 'at the limit');
      // Limit one ulp below the implied speed: rejected.
      g = AccuracyGate(
          config: PipelineConfig(
              maxImpliedSpeedMps: implied - implied * 1e-12));
      expect(g.evaluate(a), isA<GateKept>());
      final r = g.evaluate(b);
      expect(r, isA<GateRejected>());
      expect((r as GateRejected).reason, RejectReason.speed);
      // With the real constant: 29.9 m in 1 s kept, 30.1 m rejected.
      g = AccuracyGate();
      g.evaluate(a);
      expect(g.evaluate(_east(1, 29.9)), isA<GateKept>());
      g = AccuracyGate();
      g.evaluate(a);
      expect(g.evaluate(_east(1, 30.1)), isA<GateRejected>());
    });

    test('the first fix after start has no previous fix and passes the speed '
        'rule wherever it is', () {
      kept('far first fix', _s(1000, -45.0, 170.0, acc: 10));
    });

    test('non-monotonic: equal or earlier offsets are rejected, counted '
        'separately', () {
      final g = AccuracyGate();
      expect(g.evaluate(_east(10, 0)), isA<GateKept>());
      final eq = g.evaluate(_east(10, 5));
      expect((eq as GateRejected).reason, RejectReason.nonMonotonic);
      final back = g.evaluate(_east(7, 5));
      expect((back as GateRejected).reason, RejectReason.nonMonotonic);
      expect(g.counters.nonMonotonic, 2);
      expect(g.counters.total, 2);
      expect(g.evaluate(_east(11, 1.4)), isA<GateKept>());
    });

    test('rejected fixes are counted only and never journaled (controller '
        'level)', () async {
      final w = RecorderWorld.create();
      await w.start();
      await w.walk(3);
      final journaled = w.journal.samples.length;
      await w.advance(const Duration(seconds: 1));
      await w.emitNow(5, acc: 31); // accuracy
      await w.advance(const Duration(seconds: 1));
      await w.emit(Fix(
          timeUtcMs: w.startMs + 4500,
          latitude: 91,
          longitude: 20,
          accuracyMeters: 5)); // invalid
      await w.advance(const Duration(seconds: 1));
      await w.emit(w.fixAt(0.5, 0)); // earlier than the last kept offset
      expect(w.journal.samples.length, journaled);
      final c = w.state.metrics!.counters;
      expect(c.accuracy, 1);
      expect(c.invalid, 1);
      expect(c.nonMonotonic, 1);
      expect(c.speed, 0);
      await w.dispose();
    });
  });

  group('DT-05-5 injected bad fixes never enter the track', () {
    test('/F-jump: neither the 2 km jump nor the 50 m fix is kept, the 29.5 '
        'm/s fix is kept and the 30.5 m/s fix is rejected', () {
      final fx = fJump();
      final r = replay(fx);
      final keptOffsets = r.keptOffsets.toSet();
      for (final i in fx.injectedIndexes) {
        expect(keptOffsets, isNot(contains(fx.rows[i].tMs - kFixtureT0Ms)),
            reason: 'injected row $i');
      }
      for (final i in fx.keptBoundary) {
        expect(keptOffsets, contains(fx.rows[i].tMs - kFixtureT0Ms));
      }
      for (final i in fx.rejectedBoundary) {
        expect(keptOffsets, isNot(contains(fx.rows[i].tMs - kFixtureT0Ms)));
      }
      expect(r.metrics.counters.accuracy, 1);
      expect(r.metrics.counters.speed, 2);
      expect(r.metrics.keptCount, fx.rows.length - 3);
      // Counters are plain integers.
      expect(r.metrics.counters.total, 3);
    });

    test('/F-urban-canyon: none of the 40 accuracy spikes is kept; 30.0 m '
        'fixes are kept and 30.1 m fixes are not', () {
      final fx = fUrbanCanyon();
      expect(fx.injectedIndexes.length, 40);
      final r = replay(fx);
      final keptOffsets = r.keptOffsets.toSet();
      for (final i in fx.injectedIndexes) {
        expect(keptOffsets, isNot(contains(fx.rows[i].tMs - kFixtureT0Ms)));
      }
      for (final i in fx.keptBoundary) {
        expect(keptOffsets, contains(fx.rows[i].tMs - kFixtureT0Ms));
      }
      for (final i in fx.rejectedBoundary) {
        expect(keptOffsets, isNot(contains(fx.rows[i].tMs - kFixtureT0Ms)));
      }
      expect(r.metrics.counters.accuracy, 40 + 3);
      expect(r.metrics.keptCount, fx.rows.length - 43);
      // The spikes are non-consecutive so no speed run builds up.
      expect(r.metrics.counters.speed, 0);
      // The route stays on the 1.4 m/s line: no spike pulled it sideways.
      final track = r.track;
      final lastX = track.samples.last.lon;
      expect(lastX, greaterThan(kFixtureLon0));
    });
  });

  group('DT-05-6 F-tunnel: poor accuracy, one gap, no distance across it', () {
    test('poor accuracy at 10 s without a kept fix, left on the next kept '
        'fix; one gap with start and end; gap events produced', () {
      final t = fTunnel();
      final r = replay(t.fixture);
      final lastBeforeMs = t.lastBeforeS * 1000;
      final firstAfterMs = t.firstAfterS * 1000;
      expect(r.gapStarts.length, 1);
      expect(r.gapEnds.length, 1);
      expect(r.gapStarts.single.offsetMs, lastBeforeMs);
      expect(r.gapStarts.single.cause, GapCause.noFix);
      expect(r.gapEnds.single.offsetMs, firstAfterMs);
      // Poor accuracy entered exactly 10 s after the last kept fix.
      final poor = r.timeline.where((e) => e.$2 == 'poorAccuracy').toList();
      expect(poor.length, 1);
      expect(poor.single.$1, lastBeforeMs + kPoorAccuracyAfterMs);
      // ... and left on the next kept fix.
      final after = r.timeline.skipWhile((e) => e.$2 != 'poorAccuracy').toList();
      expect(after[1], (firstAfterMs, 'recording'));
      // The track record carries exactly one gap interval.
      expect(r.track.gaps, [TrackInterval(lastBeforeMs, firstAfterMs)]);
    });

    test('no distance is added across the gap: whole = first half + second '
        'half', () {
      final t = fTunnel();
      final whole = const SessionCalculator().compute(replay(t.fixture).track);
      final rows = t.fixture.rows;
      final cut = rows.indexWhere((r) => r.tMs - kFixtureT0Ms >= t.firstAfterS * 1000);
      TrackFixture half(List<FixRow> rr) => TrackFixture('half', rr, sport: 'ride');
      final a = const SessionCalculator()
          .compute(replay(half(rows.sublist(0, cut))).track);
      final b = const SessionCalculator()
          .compute(replay(half(rows.sublist(cut))).track);
      expect(whole.distanceM, closeTo(a.distanceM + b.distanceM, 0.01));
      // The 700 m jump (and the 500 m the rider covered unseen) is not in it.
      expect(whole.distanceM, lessThan(2 * 60 * 8.33 + 1));
      // Live metrics agree to within the 2-fix smoothing lag.
      final live = replay(t.fixture).metrics.distanceM;
      expect(live, closeTo(whole.distanceM, 0.01));
    });

    test('journal events: gapStart and gapEnd are written by the controller',
        () async {
      final w = RecorderWorld.create();
      await w.start();
      final x = await w.walk(20);
      await w.advance(const Duration(seconds: 30)); // no fixes for 30 s
      await w.walk(5, fromEastM: x + 500);
      final kinds = w.journal.eventKinds;
      expect(kinds.where((k) => k == JournalEventKind.gapStart).length, 1);
      expect(kinds.where((k) => k == JournalEventKind.gapEnd).length, 1);
      final gs =
          w.journal.events.firstWhere((e) => e.kind == JournalEventKind.gapStart);
      final ge =
          w.journal.events.firstWhere((e) => e.kind == JournalEventKind.gapEnd);
      expect(gs.offsetMs, 20000, reason: 'last kept fix');
      expect(ge.offsetMs, greaterThan(gs.offsetMs + 30000 - 1));
      await w.dispose();
    });
  });

  group('DT-05-7 the 10 s threshold is exact', () {
    test('9.9 s without a kept fix: no state; 10.0 s: poor accuracy', () {
      final p = RecorderPipeline();
      p.addSample(_east(0, 0));
      p.advanceTo(1000); // establishes time
      p.addSample(_east(5, 7));
      expect(p.metrics.poorAccuracy, isFalse);
      p.advanceTo(5000 + 9900);
      expect(p.metrics.poorAccuracy, isFalse);
      final ev = p.advanceTo(5000 + 10000);
      expect(p.metrics.poorAccuracy, isTrue);
      expect(ev.whereType<GapStarted>().single.offsetMs, 5000);
    });

    test('at the very start (no kept fix yet) 10 s gives poor accuracy but no '
        'gap marker', () {
      final p = RecorderPipeline();
      p.advanceTo(9900);
      expect(p.metrics.poorAccuracy, isFalse);
      expect(p.metrics.acquiring, isTrue);
      final ev = p.advanceTo(10000);
      expect(p.metrics.poorAccuracy, isTrue);
      expect(ev.whereType<GapStarted>(), isEmpty,
          reason: 'no kept fix, so no gap start offset exists');
    });

    test('fixes rejected by the gate do not reset the 10 s clock', () {
      final p = RecorderPipeline();
      p.addSample(_east(0, 0));
      for (var t = 1; t <= 12; t++) {
        p.addSample(_east(t, 1.4 * t, acc: 80)); // all rejected
        p.advanceTo(t * 1000);
      }
      expect(p.metrics.poorAccuracy, isTrue);
      expect(p.metrics.counters.accuracy, 12);
    });
  });

  group('DT-05-8 F-clock-jump', () {
    test('/backwards: the earlier-stamped fix is dropped and counted', () {
      final c = fClockJump();
      final r = replay(c.fixture);
      final row = c.fixture.rows[c.backwardsIndex];
      expect(row.inject, 'back');
      final off = row.tMs - kFixtureT0Ms;
      expect(
          r.rejected
              .where((e) => e.offsetMs == off)
              .map((e) => e.reason)
              .toList(),
          [RejectReason.nonMonotonic]);
      // The earlier timestamp already belongs to a kept fix: exactly once.
      expect(r.keptOffsets.where((o) => o == off).length, 1);
      expect(r.metrics.counters.nonMonotonic, 2);
    });

    test('/duplicate-timestamp: the equal-time fix with another position is '
        'dropped and counted', () {
      final c = fClockJump();
      final r = replay(c.fixture);
      final row = c.fixture.rows[c.equalIndex];
      final sameTime = c.fixture.rows[c.equalIndex - 1];
      expect(row.tMs, sameTime.tMs);
      expect(row.lat, isNot(sameTime.lat));
      final rejectedAt = r.rejected
          .where((e) => e.reason == RejectReason.nonMonotonic)
          .map((e) => e.offsetMs)
          .toList();
      expect(rejectedAt, contains(row.tMs - kFixtureT0Ms));
      // The first of the two equal-time fixes is the one that is kept.
      expect(r.keptOffsets, contains(sameTime.tMs - kFixtureT0Ms));
    });

    test('/forward-1h: becomes one gap, offsets strictly increasing, nothing '
        'interpolated', () {
      final c = fClockJump();
      final r = replay(c.fixture);
      expect(r.gapStarts.length, 1);
      final before = c.fixture.rows[c.forwardIndex - 1];
      final after = c.fixture.rows[c.forwardIndex];
      expect(after.tMs - before.tMs, greaterThan(3600 * 1000));
      expect(r.gapStarts.single.offsetMs, before.tMs - kFixtureT0Ms);
      expect(r.gapEnds.single.offsetMs, after.tMs - kFixtureT0Ms);
      final offs = r.keptOffsets;
      for (var i = 1; i < offs.length; i++) {
        expect(offs[i], greaterThan(offs[i - 1]));
      }
      // The recorder never produced a negative offset.
      expect(offs.every((o) => o >= 0), isTrue);
      expect(r.track.gaps.length, 1);
    });
  });

  group('DT-05-9 F-dup-fix', () {
    test('one fix kept, four counted as non-monotonic', () {
      final fx = fDupFix();
      final r = replay(fx);
      expect(r.metrics.counters.nonMonotonic, 4);
      expect(r.metrics.keptCount, fx.rows.length - 4);
      final offs = r.keptOffsets;
      expect(offs.toSet().length, offs.length, reason: 'no duplicate offset');
      // Distance is not inflated: 29 steps of 1.4 m at most.
      expect(r.metrics.distanceM, lessThan(29 * 1.4 + 0.5));
    });
  });

  group('DT-05-11 bad anchor recovery', () {
    test('/four-speed-rejections-no-reanchor', () {
      final g = AccuracyGate();
      g.evaluate(_east(0, 5000, acc: 10)); // wrong first fix
      for (var t = 1; t <= 4; t++) {
        final r = g.evaluate(_east(t, 1.4 * t, acc: 8));
        expect(r, isA<GateRejected>(), reason: 'rejection $t');
      }
      expect(g.reanchors, 0);
      expect(g.counters.speed, 4);
      expect(g.anchor!.offsetMs, 0, reason: 'the anchor is unchanged');
    });

    test('/five-speed-rejections-reanchor: on the best-accuracy rejected fix',
        () {
      final g = AccuracyGate();
      g.evaluate(_east(0, 5000, acc: 10));
      final accs = [20.0, 9.0, 15.0, 12.0, 8.5]; // best is the 2nd (9.0)
      GateResult? last;
      for (var t = 1; t <= 5; t++) {
        last = g.evaluate(_east(t, 1.4 * t, acc: accs[t - 1]));
      }
      expect(last, isA<GateKept>());
      final k = last as GateKept;
      expect(k.reanchored, isTrue);
      expect(g.reanchors, 1);
      // best accuracy among the five rejected is 8.5 (the fifth).
      expect(k.sample.accuracyM, 8.5);
      expect(g.anchor!.offsetMs, 5000);
      expect(g.counters.speed, 5, reason: 'the event is counted in speed');
      // Later fixes are judged against the new anchor.
      expect(g.evaluate(_east(6, 1.4 * 6)), isA<GateKept>());
    });

    test('/thirty-seconds-without-kept-fix-reanchor', () {
      final g = AccuracyGate();
      g.evaluate(_east(0, 5000, acc: 10));
      // Four speed rejections spread over 30 s (not five): the span rule fires.
      expect(g.evaluate(_east(1, 1.4)), isA<GateRejected>());
      expect(g.evaluate(_east(11, 15)), isA<GateRejected>());
      expect(g.evaluate(_east(21, 29)), isA<GateRejected>());
      final r = g.evaluate(_east(31, 43)); // 30 s after the first rejection
      expect(r, isA<GateKept>());
      expect((r as GateKept).reanchored, isTrue);
      expect(g.reanchors, 1);
    });

    test('/fixes-rejected-for-accuracy-are-never-the-anchor', () {
      final g = AccuracyGate();
      g.evaluate(_east(0, 5000, acc: 10));
      // Five fixes: four rejected for speed with accuracy 25..28, one with the
      // best accuracy 3 m but rejected for ACCURACY? accuracy 3 passes the
      // accuracy rule, so use an accuracy-rejected fix (40 m) in the middle:
      // it must not be counted in the run nor become the anchor.
      for (var t = 1; t <= 2; t++) {
        expect(g.evaluate(_east(t, 1.4 * t, acc: 25)), isA<GateRejected>());
      }
      final bad = g.evaluate(_east(3, 4.2, acc: 40));
      expect((bad as GateRejected).reason, RejectReason.accuracy);
      for (var t = 4; t <= 6; t++) {
        g.evaluate(_east(t, 1.4 * t, acc: 27));
      }
      expect(g.reanchors, 1, reason: 'fifth SPEED rejection re-anchored');
      expect(g.anchor!.accuracyM, lessThanOrEqualTo(30.0));
      expect(g.anchor!.accuracyM, isNot(40.0));
      expect(g.anchor!.accuracyM, 25.0, reason: 'best among speed-only rejects');
    });

    test('/gap-already-open-gets-no-second-pair', () {
      final p = RecorderPipeline();
      p.addSample(_east(0, 5000, acc: 10)); // wrong anchor, kept
      final events = <PipelineEvent>[];
      for (var t = 1; t <= 20; t++) {
        events.addAll(p.addSample(_east(t, 1.4 * t, acc: 8)));
        events.addAll(p.advanceTo(t * 1000));
      }
      // 10 s rule opened a gap at t=10 s; the re-anchor at the 5th rejection
      // (t=5 s) came first: exactly one pair, not two.
      expect(events.whereType<GapStarted>().length, 1);
      expect(events.whereType<GapEnded>().length, 1);
      expect(events.whereType<GapStarted>().single.cause, GapCause.reanchor);
    });

    test('F-bad-anchor end to end: the recorder recovers and keeps recording',
        () {
      final fx = fBadAnchor();
      final r = replay(fx);
      expect(r.metrics.counters.speed, 5);
      expect(r.metrics.keptCount, fx.rows.length - 4);
      expect(r.gapStarts.length, 1);
      expect(r.gapEnds.length, 1);
      // The true track continues: distance reflects ~115 s of walking, not 0
      // and not the 5 km phantom.
      expect(r.metrics.distanceM, greaterThan(100));
      expect(r.metrics.distanceM, lessThan(200));
      // No distance across the break.
      final jumpM = haversineM(
          r.kept.first.sample.lat,
          r.kept.first.sample.lon,
          r.kept[1].sample.lat,
          r.kept[1].sample.lon);
      expect(jumpM, greaterThan(4000));
      expect(math.max(0, r.metrics.distanceM), lessThan(jumpM));
    });

    test('a manual pause drops the anchor: the first fix after Resume is kept '
        'wherever it is', () {
      final p = RecorderPipeline();
      p.addSample(_east(0, 0));
      p.addSample(_east(1, 1.4));
      p.pauseManual(2000);
      p.resumeManual(60000);
      final ev = p.addSample(_east(61, 900)); // far away after a long pause
      expect(ev.whereType<FixKept>().length, 1);
      expect(p.metrics.counters.speed, 0);
    });
  });
}
