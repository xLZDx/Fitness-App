// S04-07 Auto-pause (R-012): rows DT-07-1 .. DT-07-8.
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/recording/pipeline/auto_pause.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/pipeline/recorded_track.dart';
import 'package:fitness_app/features/recording/pipeline/recorder_pipeline.dart';
import 'package:fitness_app/features/recording/pipeline/recording_constants.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording/recorder_world.dart';
import '../../../support/recording/replay_fixtures.dart';

/// A kept fix with a provider speed, 1 Hz positions on the east line.
PipelineSample _fix(int offsetMs, double xM, double? speed) {
  final p = fixturePoint(xM, 0);
  return PipelineSample(
      offsetMs: offsetMs,
      lat: p.lat,
      lon: p.lon,
      accuracyM: 6,
      speedMps: speed);
}

/// Feeds [speed] at 1 Hz from [fromMs] while the last fix is at or before
/// [toMs] (inclusive), returns all events.
List<PipelineEvent> _feed(AutoPause a, int fromMs, int toMs, double speed,
    {int stepMs = 1000}) {
  final out = <PipelineEvent>[];
  for (var t = fromMs; t <= toMs; t += stepMs) {
    out.addAll(a.onKept(_fix(t, 0.0 + t / 1000.0 * speed, speed)));
  }
  return out;
}

void main() {
  group('DT-07-1 F-stop-go events', () {
    final sg = fStopGo();
    final plan = sg.plan;
    final r = replay(sg.fixture);

    test('/event-count: exactly two pauses and two resumes (the 20 s and '
        'the 60 s stops)', () {
      expect(r.autoPauses.length, 2);
      expect(r.autoResumes.length, 2);
    });

    test('/exact offsets: pause at the start of the stop, detected after '
        '8 s; resume at the first fast fix, detected after 3 s', () {
      final p20 = r.autoPauses[0];
      final p60 = r.autoPauses[1];
      expect(p20.offsetMs, plan.stop20StartS * 1000);
      expect(p20.detectedAtMs, p20.offsetMs + kAutoPauseEnterAfterMs);
      expect(p60.offsetMs, plan.stop60StartS * 1000);
      expect(p60.detectedAtMs, p60.offsetMs + kAutoPauseEnterAfterMs);
      final r20 = r.autoResumes[0];
      final r60 = r.autoResumes[1];
      expect(r20.offsetMs, (plan.stop20StartS + 20) * 1000);
      expect(r20.detectedAtMs, r20.offsetMs + kAutoResumeAfterMs);
      // After the 60 s stop the walker first crawls at 0.9 m/s for 6 s
      // (below the 1.0 resume limit), so resume is later by exactly 6 s.
      expect(r60.offsetMs, (plan.stop60StartS + 60 + 6) * 1000);
      expect(r60.detectedAtMs, r60.offsetMs + kAutoResumeAfterMs);
    });

    test('/no-event-in-7s-stop: nothing fires inside the 7 s stop', () {
      final from = plan.stop7StartS * 1000;
      final to = from + 7000 + kAutoResumeAfterMs;
      final inside = [
        ...r.autoPauses.map((e) => e.offsetMs),
        ...r.autoPauses.map((e) => e.detectedAtMs),
        ...r.autoResumes.map((e) => e.offsetMs),
      ].where((o) => o >= from && o <= to);
      expect(inside, isEmpty);
    });

    test('/no-flap-on-jitter: nothing fires over the 90 s of 0.6 to 0.9 m/s',
        () {
      final from = plan.jitterStartS * 1000;
      final to = plan.jitterEndS * 1000;
      final inside = [
        ...r.autoPauses.map((e) => e.offsetMs),
        ...r.autoPauses.map((e) => e.detectedAtMs),
        ...r.autoResumes.map((e) => e.offsetMs),
        ...r.autoResumes.map((e) => e.detectedAtMs),
      ].where((o) => o >= from && o <= to + 1000);
      expect(inside, isEmpty);
    });

    test('pause and resume alternate and never nest', () {
      final all = [
        for (final e in r.events)
          if (e is AutoPaused) 'P' else if (e is AutoResumed) 'R',
      ].join();
      expect(all, 'PRPR');
    });
  });

  group('DT-07-2 exact boundaries (AutoPause)', () {
    test('/enter-speed: 0.49 m/s for 8 s pauses, 0.50 m/s does not', () {
      var a = AutoPause();
      var ev = _feed(a, 0, 8000, 0.49);
      expect(ev.whereType<AutoPaused>().length, 1);
      expect(a.paused, isTrue);
      a = AutoPause();
      ev = _feed(a, 0, 20000, 0.50);
      expect(ev, isEmpty, reason: '0.50 m/s is not below the limit');
      expect(a.paused, isFalse);
    });

    test('/enter-time: 7.9 s below the limit does not pause, 8.0 s does', () {
      var a = AutoPause();
      var ev = <PipelineEvent>[];
      for (final t in [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 7900]) {
        ev.addAll(a.onKept(_fix(t, 0, 0.1)));
      }
      expect(ev, isEmpty);
      ev = a.onKept(_fix(8000, 0, 0.1)); // 8.0 s after the first slow fix
      expect(ev.whereType<AutoPaused>().length, 1);
      expect((ev.single as AutoPaused).offsetMs, 0);
      expect((ev.single as AutoPaused).detectedAtMs, 8000);
    });

    AutoPause pausedAt0() {
      final a = AutoPause();
      _feed(a, 0, 8000, 0.1);
      expect(a.paused, isTrue);
      return a;
    }

    test('/leave-speed: 0.99 m/s for 3 s stays paused, 1.0 m/s leaves', () {
      var a = pausedAt0();
      var ev = _feed(a, 9000, 20000, 0.99);
      expect(ev, isEmpty);
      expect(a.paused, isTrue);
      a = pausedAt0();
      ev = _feed(a, 9000, 12000, 1.0);
      expect(ev.whereType<AutoResumed>().length, 1);
      expect(a.paused, isFalse);
    });

    test('/leave-time: 2.9 s at 1.0 m/s stays paused, 3.0 s leaves', () {
      final a = pausedAt0();
      var ev = <PipelineEvent>[];
      for (final t in [9000, 10000, 11000, 11900]) {
        ev.addAll(a.onKept(_fix(t, 0, 1.0)));
      }
      expect(ev, isEmpty);
      expect(a.paused, isTrue);
      ev = a.onKept(_fix(12000, 0, 1.0));
      expect(ev.whereType<AutoResumed>().length, 1);
      expect((ev.single as AutoResumed).offsetMs, 9000);
      expect((ev.single as AutoResumed).detectedAtMs, 12000);
    });

    test('a single fast fix resets the below-limit clock', () {
      final a = AutoPause();
      _feed(a, 0, 6000, 0.1);
      a.onKept(_fix(7000, 0, 0.5)); // exactly the limit: resets
      final ev = _feed(a, 8000, 14000, 0.1);
      expect(ev, isEmpty, reason: 'only 6 s since the reset');
      expect(_feed(a, 15000, 16000, 0.1).length, 1);
    });

    test('a single slow fix resets the above-limit clock', () {
      final a = AutoPause();
      _feed(a, 0, 8000, 0.1);
      a.onKept(_fix(9000, 0, 1.2));
      a.onKept(_fix(10000, 0, 1.2));
      a.onKept(_fix(11000, 0, 0.9)); // dips below 1.0: reset
      expect(a.onKept(_fix(12000, 0, 1.2)), isEmpty);
      expect(a.onKept(_fix(14000, 0, 1.2)), isEmpty);
      expect(a.onKept(_fix(15000, 0, 1.2)).length, 1);
    });
  });

  group('DT-07-3 moving time and distance during paused spans', () {
    final sg = fStopGo();
    final r = replay(sg.fixture);

    test('moving time equals elapsed minus the paused spans within 1 s', () {
      var paused = 0;
      for (var i = 0; i < r.autoPauses.length; i++) {
        paused += r.autoResumes[i].offsetMs - r.autoPauses[i].offsetMs;
      }
      // 20 s stop, then 60 s stop plus the 6 s crawl below the resume limit.
      expect(paused, 86000);
      final elapsed = r.elapsedMs;
      final expectedMovingMs = elapsed - 86000;
      expect((r.metrics.movingTimeMs - expectedMovingMs).abs(),
          lessThanOrEqualTo(1000));
      final fin = const SessionCalculator().compute(r.track);
      expect((fin.movingTimeS * 1000 - expectedMovingMs).abs(),
          lessThanOrEqualTo(1000));
      expect(fin.elapsedS * 1000, elapsed);
    });

    test('no distance is added while paused: the live distance is constant '
        'between detection and resume', () {
      final p = RecorderPipeline();
      double? atPause;
      var pausedNow = false;
      var addedWhilePaused = 0.0;
      var sawPause = 0;
      for (final row in sg.fixture.rows) {
        final off = row.tMs - kFixtureT0Ms;
        p.advanceTo(off);
        final before = p.metrics.distanceM;
        final ev = p.addSample(PipelineSample(
            offsetMs: off,
            lat: row.lat,
            lon: row.lon,
            accuracyM: row.acc,
            speedMps: row.speed));
        final after = p.metrics.distanceM;
        for (final e in ev) {
          if (e is AutoPaused) {
            pausedNow = true;
            sawPause++;
            atPause = after; // includes the flush of the pre-pause tail
          }
          if (e is AutoResumed) pausedNow = false;
        }
        if (pausedNow && atPause != null && ev.whereType<AutoPaused>().isEmpty) {
          addedWhilePaused += after - before;
        }
      }
      expect(sawPause, 2);
      expect(addedWhilePaused, 0.0);
    });

    test('final distance excludes every fix strictly inside a pause', () {
      final fin = const SessionCalculator().compute(r.track);
      final walkedM = 1.4 * 30 * 4 + 1.4 * 30 + 0.9 * 6 + 90 * 0.75;
      // Smoothing shortens each of the 5 segments by about two steps, so the
      // total stays within 15 percent below the pure walking distance and can
      // not include the 80 s of standing (which would be 0 m anyway) or the
      // pause spans.
      expect(fin.distanceM, lessThan(walkedM + 1));
      expect(fin.distanceM, greaterThan(walkedM * 0.85));
    });
  });

  group('DT-07-4 defaults per sport', () {
    test('default on for walking, running and cycling only', () {
      for (final s in SportType.values) {
        final on = s == SportType.walking ||
            s == SportType.running ||
            s == SportType.cycling;
        expect(autoPauseDefaultOn(s), on, reason: s.name);
      }
      // "hike" and every other sport value default OFF (TP-S04-5).
      expect(autoPauseDefaultOn(SportType.hiking), isFalse);
      expect(autoPauseDefaultOn(SportType.trailRunning), isFalse);
      expect(autoPauseDefaultOn(SportType.mountainBiking), isFalse);
      expect(autoPauseDefaultOn(SportType.other), isFalse);
      expect(SportType.values.where(autoPauseDefaultOn).length, 3);
    });

    for (final c in <(String, SportType, bool)>[
      ('walk', SportType.walking, true),
      ('run', SportType.running, true),
      ('hike', SportType.hiking, false),
      ('ride', SportType.cycling, true),
    ]) {
      test('/${c.$1}: the journal meta carries the default ${c.$3}', () async {
        final w = RecorderWorld.create();
        await w.start(sport: c.$2);
        expect(w.journal.begun.single.autoPauseEnabled, c.$3);
        await w.dispose();
      });
    }

    test('/switched-off: with auto-pause off, standing still for 60 s never '
        'enters pausedAuto and nothing is journaled', () async {
      final w = RecorderWorld.create();
      await w.start(sport: SportType.walking, autoPause: false);
      expect(w.journal.begun.single.autoPauseEnabled, isFalse);
      final x = await w.walk(5);
      await w.stand(60, x, speed: 0.0);
      expect(w.phase, RecorderPhase.recording);
      expect(w.journal.eventKinds, isNot(contains(JournalEventKind.autoPause)));
      await w.dispose();
    });

    test('/switched-on explicitly for hiking is honoured', () async {
      final w = RecorderWorld.create();
      await w.start(sport: SportType.hiking, autoPause: true);
      expect(w.journal.begun.single.autoPauseEnabled, isTrue);
      final x = await w.walk(5);
      await w.stand(12, x, speed: 0.0);
      expect(w.phase, RecorderPhase.pausedAuto);
      await w.dispose();
    });
  });

  group('DT-07-5 speed source', () {
    test('/provider-speed: used when present (slow provider speed pauses '
        'although positions are not checked)', () {
      final a = AutoPause();
      // Positions move 1.4 m per second but the provider says 0.1 m/s.
      final ev = <PipelineEvent>[];
      for (var t = 0; t <= 8000; t += 1000) {
        ev.addAll(a.onKept(_fix(t, 1.4 * t / 1000, 0.1)));
      }
      expect(ev.whereType<AutoPaused>().length, 1,
          reason: 'provider speed wins over the implied speed when present');
    });

    test('/implied-speed: from the last two fixes when the provider speed is '
        'absent', () {
      // Standing still: implied 0 -> pauses.
      var a = AutoPause();
      var ev = <PipelineEvent>[];
      for (var t = 0; t <= 9000; t += 1000) {
        ev.addAll(a.onKept(_fix(t, 5, null)));
      }
      expect(ev.whereType<AutoPaused>().length, 1);
      // Walking at 1.4 m/s: implied 1.4 -> never pauses.
      a = AutoPause();
      ev = [];
      for (var t = 0; t <= 20000; t += 1000) {
        ev.addAll(a.onKept(_fix(t, 1.4 * t / 1000, null)));
      }
      expect(ev, isEmpty);
    });

    test('the first fix has no implied speed and starts nothing', () {
      final a = AutoPause();
      expect(a.onKept(_fix(0, 0, null)), isEmpty);
      expect(a.paused, isFalse);
    });

    test('an invalid provider speed (negative, NaN) falls back to the implied '
        'speed', () {
      for (final bad in <double>[-1.0, double.nan, double.infinity]) {
        final a = AutoPause();
        final ev = <PipelineEvent>[];
        for (var t = 0; t <= 20000; t += 1000) {
          ev.addAll(a.onKept(_fix(t, 1.4 * t / 1000, bad)));
        }
        expect(ev, isEmpty, reason: 'speed $bad with a walking position');
      }
    });

    test('PINNED (plan expects otherwise, see findings): provider speed 0.0 '
        'with a moving position does pause today, because Design 3.6 says '
        'the provider speed wins whenever it is present', () {
      final a = AutoPause();
      final ev = <PipelineEvent>[];
      for (var t = 0; t <= 8000; t += 1000) {
        ev.addAll(a.onKept(_fix(t, 1.4 * t / 1000, 0.0)));
      }
      // Documented risk: Android reports 0.0 when a fix carries no speed.
      expect(ev.whereType<AutoPaused>().length, 1);
    });
  });

  group('DT-07-6 F-still', () {
    test('pausedAuto is entered; no distance after the entry; distance '
        'before it bounded by the drift', () {
      final st = fStill();
      final p = RecorderPipeline();
      double? distanceAtPause;
      var pauseDetected = 0;
      for (final row in st.fixture.rows) {
        final off = row.tMs - kFixtureT0Ms;
        p.advanceTo(off);
        final ev = p.addSample(PipelineSample(
            offsetMs: off,
            lat: row.lat,
            lon: row.lon,
            accuracyM: row.acc,
            speedMps: row.speed));
        if (ev.whereType<AutoPaused>().isNotEmpty) {
          pauseDetected = off;
          distanceAtPause = p.metrics.distanceM;
        }
      }
      expect(p.metrics.autoPaused, isTrue);
      expect(pauseDetected, greaterThan(st.stillStartS * 1000));
      expect(pauseDetected, lessThanOrEqualTo(st.stillStartS * 1000 + 12000),
          reason: 'detected within the 8 s rule plus a few slow-but-above-'
              'limit fixes');
      expect(p.metrics.distanceM, distanceAtPause,
          reason: '540 s of drift add nothing after the pause');
      // Before entry: 60 s of walking (84 m) plus at most the drift of ~10 s.
      expect(distanceAtPause!, lessThan(1.4 * st.stillStartS + 10 * 8.0));
      expect(distanceAtPause, greaterThan(1.4 * st.stillStartS * 0.9));
      // The final value agrees.
      final r = replay(st.fixture);
      final fin = const SessionCalculator().compute(r.track);
      expect(fin.distanceM, lessThan(1.4 * st.stillStartS + 10 * 8.0));
    });
  });

  group('DT-07-7 events are the truth for the finalizer', () {
    test('edited pause offsets change moving time and distance exactly as '
        'the events say, not as a recomputation would', () {
      // A walk with NO standstill at all.
      final fx = fWalk();
      final r = replay(fx, endAtMs: 120000);
      final plain = const SessionCalculator().compute(r.track);
      expect(r.autoPauses, isEmpty);

      // The journal now says: paused from 40 s to 70 s.
      final edited = RecordedTrack.fromEvents(
        events: [
          ...r.events,
          const AutoPaused(40000, 48000),
          const AutoResumed(70000, 73000),
        ],
        elapsedMs: r.elapsedMs,
      );
      final fin = const SessionCalculator().compute(edited);
      expect(fin.movingTimeS, closeTo(plain.movingTimeS - 30, 1e-9));
      expect(fin.distanceM, lessThan(plain.distanceM - 30));
      expect(fin.segmentCount, 2);
    });

    test('an AutoPaused with no AutoResumed is an open interval to the end',
        () {
      final r = replay(fWalk(), endAtMs: 60000);
      final t = RecordedTrack.fromEvents(
          events: [...r.events, const AutoPaused(30000, 38000)],
          elapsedMs: r.elapsedMs);
      expect(t.autoPauses, [TrackInterval(30000)]);
      final fin = const SessionCalculator().compute(t);
      expect(fin.movingTimeS, closeTo(30, 1e-9));
    });
  });

  group('DT-07-8 user Resume does not re-pause at once', () {
    test('after Pause + Resume from pausedAuto the rule needs another full '
        '8 s', () async {
      final w = RecorderWorld.create();
      await w.start();
      final x = await w.walk(5);
      await w.stand(10, x, speed: 0.0);
      expect(w.phase, RecorderPhase.pausedAuto);
      await w.pause();
      expect(w.phase, RecorderPhase.pausedManual);
      await w.resume();
      expect(w.phase, RecorderPhase.recording);
      // Still standing. The first slow fix after Resume starts a fresh 8 s
      // clock: 8 fixes (7 s of span) later still recording, the 9th (8 s of
      // span) pauses again.
      var paused7 = false;
      for (var i = 1; i <= 8; i++) {
        await w.advance(const Duration(seconds: 1));
        await w.emitNow(x, speed: 0.0);
        if (w.phase == RecorderPhase.pausedAuto) paused7 = true;
      }
      expect(paused7, isFalse, reason: 'no immediate re-pause');
      await w.advance(const Duration(seconds: 1));
      await w.emitNow(x, speed: 0.0);
      expect(w.phase, RecorderPhase.pausedAuto,
          reason: 'after the full 8 s below the limit');
      await w.dispose();
    });
  });

  group('auto and manual pause bookkeeping', () {
    test('a manual pause during pausedAuto closes the auto span once; moving '
        'time never counts a paused second twice', () {
      final p = RecorderPipeline();
      var x = 0.0;
      for (var t = 0; t <= 10; t++) {
        p.advanceTo(t * 1000);
        p.addSample(_fix(t * 1000, x, 1.4));
        x += 1.4;
      }
      // Stand from 11 s on; the auto pause starts at 11 s (first slow fix).
      for (var t = 11; t <= 30; t++) {
        p.advanceTo(t * 1000);
        p.addSample(_fix(t * 1000, x, 0.0));
      }
      expect(p.metrics.autoPaused, isTrue);
      p.pauseManual(30000);
      expect(p.metrics.autoPaused, isFalse);
      expect(p.metrics.manualPaused, isTrue);
      p.advanceTo(50000);
      p.resumeManual(50000);
      p.advanceTo(60000);
      // Paused: auto 11..30 (19 s) + manual 30..50 (20 s) = 39 s of 60.
      expect(p.metrics.movingTimeMs, closeTo(60000 - 39000, 1));
      expect(p.metrics.elapsedMs, 60000);
    });

    test('manual pause wins: the auto rule is suppressed while paused '
        'manually and the first fix after Resume has no stale chain', () {
      final p = RecorderPipeline();
      p.addSample(_fix(0, 0, 1.4));
      p.pauseManual(1000);
      final ev = <PipelineEvent>[];
      for (var t = 2; t <= 30; t++) {
        ev.addAll(p.addSample(_fix(t * 1000, 0, 0.0)));
      }
      expect(ev, isEmpty, reason: 'fixes during a manual pause are ignored');
      p.resumeManual(30000);
      final after = p.addSample(_fix(31000, 0, 0.0));
      expect(after.whereType<AutoPaused>(), isEmpty);
    });

    test('a disabled AutoPause never fires', () {
      final a = AutoPause(enabled: false);
      expect(_feed(a, 0, 60000, 0.0), isEmpty);
      expect(a.paused, isFalse);
    });
  });
}
