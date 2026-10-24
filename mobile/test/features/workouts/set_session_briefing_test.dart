import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/set_prescription.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';

/// The briefing gate and the repetition based work phase of [SetSession].
///
/// The gate is the thing a countdown-on-start gets wrong: the clock ran while
/// the instruction was still being spoken. Everything here is driven a second
/// at a time with no real clock.
void main() {
  const timed = SetPlan(
      sets: 2, workSeconds: 3, restSeconds: 2, readySeconds: 3, cueLead: 1);
  const reps = SetPlan(
    sets: 2,
    workSeconds: 30,
    restSeconds: 2,
    readySeconds: 2,
    cueLead: 1,
    prescription:
        SetPrescription(mode: SetMode.reps, targetReps: 10, loadKg: 50),
  );

  group('the default plan', () {
    test('readySeconds defaults to 3', () {
      const p = SetPlan(sets: 1, workSeconds: 1, restSeconds: 1);
      expect(p.readySeconds, 3);
      expect(p.prescription.mode, SetMode.timed);
    });

    test('the three tier plans use the short countdown', () {
      expect(SetPlan.beginner.readySeconds, 3);
      expect(SetPlan.intermediate.readySeconds, 3);
      expect(SetPlan.advanced.readySeconds, 3);
    });
  });

  group('start enters the briefing gate', () {
    test('start() goes to briefing and returns no cues', () {
      final s = SetSession(timed);
      expect(s.start(), isEmpty);
      expect(s.phase, SetPhase.briefing);
      expect(s.isRunning, isTrue);
      expect(s.setNumber, 0);
      expect(s.secondsLeft, 0);
    });

    test('tick() in the briefing is a no-op, however long it lasts', () {
      final s = SetSession(timed);
      s.start();
      for (var i = 0; i < 500; i++) {
        final t = s.tick();
        expect(t.cues, isEmpty, reason: 'second $i');
        expect(t.phase, SetPhase.briefing);
        expect(t.secondsLeft, 0);
      }
      expect(s.phase, SetPhase.briefing);
      expect(s.setNumber, 0);
      expect(s.progress, 0);
      expect(s.phaseProgress, 0);
    });

    test('a zero readySeconds plan still waits in the gate first', () {
      const p = SetPlan(
          sets: 1, workSeconds: 5, restSeconds: 5, readySeconds: 0);
      final s = SetSession(p);
      expect(s.start(), isEmpty);
      expect(s.phase, SetPhase.briefing,
          reason: 'zero countdown must not skip the gate');
    });

    test('start twice in the gate stays in the gate', () {
      final s = SetSession(timed);
      s.start();
      expect(s.start(), isEmpty);
      expect(s.phase, SetPhase.briefing);
    });
  });

  group('confirmReady', () {
    test('moves to the countdown with readySeconds on the clock, no cue', () {
      final s = SetSession(timed);
      s.start();
      expect(s.confirmReady(), isEmpty);
      expect(s.phase, SetPhase.gettingReady);
      expect(s.secondsLeft, 3);
      expect(s.isRunning, isTrue);
    });

    test('ticks at 2 and 1 (cueLead 2), then the start gong, then work', () {
      const p = SetPlan(
          sets: 1, workSeconds: 4, restSeconds: 1, readySeconds: 3, cueLead: 2);
      final s = SetSession(p);
      s.start();
      s.confirmReady();
      final seen = <(int, List<SetCue>, SetPhase)>[];
      for (var i = 0; i < 3; i++) {
        final t = s.tick();
        seen.add((t.secondsLeft, t.cues, t.phase));
      }
      expect(seen[0].$1, 2);
      expect(seen[0].$2, [SetCue.tick]);
      expect(seen[0].$3, SetPhase.gettingReady);
      expect(seen[1].$1, 1);
      expect(seen[1].$2, [SetCue.tick]);
      expect(seen[2].$2, [SetCue.startGong]);
      expect(seen[2].$3, SetPhase.work);
      expect(s.setNumber, 1);
      expect(s.secondsLeft, 4);
    });

    test('with the default cueLead the 3 s countdown ticks at 2 and 1', () {
      const p = SetPlan(sets: 1, workSeconds: 5, restSeconds: 1);
      final s = SetSession(p);
      s.start();
      s.confirmReady();
      final ticksAt = <int>[];
      while (s.phase == SetPhase.gettingReady) {
        final t = s.tick();
        if (t.cues.contains(SetCue.tick)) ticksAt.add(t.secondsLeft);
      }
      expect(ticksAt, [2, 1]);
    });

    test('with readySeconds 0 it goes straight to work with the gong', () {
      const p = SetPlan(
          sets: 1, workSeconds: 5, restSeconds: 5, readySeconds: 0);
      final s = SetSession(p);
      s.start();
      expect(s.confirmReady(), [SetCue.startGong]);
      expect(s.phase, SetPhase.work);
      expect(s.setNumber, 1);
    });

    test('is a no-op outside the briefing (a double tap skips nothing)', () {
      final s = SetSession(timed);
      expect(s.confirmReady(), isEmpty, reason: 'idle');
      expect(s.phase, SetPhase.idle);
      expect(s.isRunning, isFalse);

      s.start();
      s.confirmReady();
      final left = s.secondsLeft;
      expect(s.confirmReady(), isEmpty, reason: 'countdown');
      expect(s.phase, SetPhase.gettingReady);
      expect(s.secondsLeft, left);

      while (s.phase != SetPhase.work) {
        s.tick();
      }
      expect(s.confirmReady(), isEmpty, reason: 'work');
      expect(s.phase, SetPhase.work);
    });

    test('works while paused and resumes the clock', () {
      final s = SetSession(timed);
      s.start();
      s.pause();
      expect(s.isRunning, isFalse);
      expect(s.phase, SetPhase.briefing);
      s.confirmReady();
      expect(s.phase, SetPhase.gettingReady);
      expect(s.isRunning, isTrue);
      expect(s.tick().secondsLeft, 2);
    });

    test('the full timed run: briefing, ready, work, rest, work, done', () {
      final s = SetSession(timed);
      s.start();
      final seen = <SetPhase>[s.phase];
      s.confirmReady();
      seen.add(s.phase);
      while (!s.isFinished) {
        s.tick();
        if (seen.last != s.phase) seen.add(s.phase);
      }
      expect(seen, [
        SetPhase.briefing,
        SetPhase.gettingReady,
        SetPhase.work,
        SetPhase.rest,
        SetPhase.work,
        SetPhase.done,
      ]);
    });
  });

  group('pause, skip and reset in the gate', () {
    test('pause in the gate keeps the gate; ticking does nothing', () {
      final s = SetSession(timed);
      s.start();
      s.pause();
      expect(s.phase, SetPhase.briefing);
      expect(s.isRunning, isFalse);
      for (var i = 0; i < 10; i++) {
        expect(s.tick().cues, isEmpty);
      }
      expect(s.phase, SetPhase.briefing);
    });

    test('start after pause resumes the gate rather than restarting', () {
      final s = SetSession(timed);
      s.start();
      s.pause();
      s.start();
      expect(s.phase, SetPhase.briefing);
      expect(s.isRunning, isTrue);
    });

    test('skip() on the session in the gate leaves the gate (ready)', () {
      final s = SetSession(timed);
      s.start();
      s.skip();
      expect(s.phase, SetPhase.gettingReady,
          reason: 'skip in the gate is the same as ready');
    });

    test('reset from the gate goes idle and the session can run again', () {
      final s = SetSession(timed);
      s.start();
      s.reset();
      expect(s.phase, SetPhase.idle);
      expect(s.isRunning, isFalse);
      s.start();
      expect(s.phase, SetPhase.briefing);
    });

    test('after done a new start enters the briefing again', () {
      final s = SetSession(timed);
      s.start();
      s.confirmReady();
      while (!s.isFinished) {
        s.tick();
      }
      expect(s.start(), isEmpty);
      expect(s.phase, SetPhase.briefing);
      expect(s.setNumber, 0);
    });
  });

  group('rep based work phase', () {
    SetSession inWork() {
      final s = SetSession(reps);
      s.start();
      s.confirmReady();
      while (s.phase != SetPhase.work) {
        s.tick();
      }
      return s;
    }

    test('entering work gives the start gong and no clock', () {
      final s = SetSession(reps);
      s.start();
      s.confirmReady();
      final cues = <SetCue>[];
      while (s.phase != SetPhase.work) {
        cues.addAll(s.tick().cues);
      }
      expect(cues.last, SetCue.startGong);
      expect(s.setNumber, 1);
      expect(s.secondsLeft, 0);
    });

    test('tick() in rep work never advances, ticks or sounds', () {
      final s = inWork();
      for (var i = 0; i < 1000; i++) {
        final t = s.tick();
        expect(t.cues, isEmpty);
        expect(t.phase, SetPhase.work);
      }
      expect(s.phase, SetPhase.work);
      expect(s.setNumber, 1);
      expect(s.phaseProgress, 0);
    });

    test('skip (Done) ends the set into the unchanged rest phase', () {
      final s = inWork();
      expect(s.skip(), [SetCue.endGong]);
      expect(s.phase, SetPhase.rest);
      expect(s.secondsLeft, reps.restSeconds);
    });

    test('rest still counts down and the next set begins in rep work', () {
      final s = inWork();
      s.skip();
      final cues = <SetCue>[];
      while (s.phase == SetPhase.rest) {
        cues.addAll(s.tick().cues);
      }
      expect(cues, contains(SetCue.tick));
      expect(cues.last, SetCue.startGong);
      expect(s.phase, SetPhase.work);
      expect(s.setNumber, 2);
      expect(s.tick().cues, isEmpty);
    });

    test('Done on the last set ends the session with endGong + finished', () {
      final s = inWork();
      s.skip();
      while (s.phase != SetPhase.work) {
        s.tick();
      }
      expect(s.setNumber, 2);
      expect(s.skip(), [SetCue.endGong, SetCue.finished]);
      expect(s.phase, SetPhase.done);
      expect(s.isFinished, isTrue);
      expect(s.isRunning, isFalse);
    });

    test('a timed plan is unaffected: work still counts down to rest', () {
      final s = SetSession(timed);
      s.start();
      s.confirmReady();
      while (s.phase != SetPhase.work) {
        s.tick();
      }
      expect(s.secondsLeft, timed.workSeconds);
      s.tick();
      expect(s.secondsLeft, timed.workSeconds - 1);
    });

    test('skip while paused in rep work does nothing', () {
      final s = inWork();
      s.pause();
      expect(s.skip(), isEmpty);
      expect(s.phase, SetPhase.work);
    });

    test('finishRepSet while paused resumes into rest', () {
      final s = inWork();
      s.pause();
      expect(s.finishRepSet(), [SetCue.endGong]);
      expect(s.phase, SetPhase.rest);
      expect(s.isRunning, isTrue);
      expect(s.tick().secondsLeft, reps.restSeconds - 1,
          reason: 'the rest clock runs');
    });

    test('finishRepSet while running behaves like skip', () {
      final s = inWork();
      expect(s.finishRepSet(), [SetCue.endGong]);
      expect(s.phase, SetPhase.rest);
    });

    test('finishRepSet on the last set finishes and stops', () {
      final s = inWork();
      s.skip();
      while (s.phase != SetPhase.work) {
        s.tick();
      }
      s.pause();
      expect(s.finishRepSet(), [SetCue.endGong, SetCue.finished]);
      expect(s.isFinished, isTrue);
      expect(s.isRunning, isFalse);
    });

    test('finishRepSet is a no-op in the gate, countdown, rest, idle, timed',
        () {
      final s = SetSession(reps);
      expect(s.finishRepSet(), isEmpty);
      s.start();
      expect(s.finishRepSet(), isEmpty);
      expect(s.phase, SetPhase.briefing);
      s.confirmReady();
      expect(s.finishRepSet(), isEmpty);
      expect(s.phase, SetPhase.gettingReady);
      while (s.phase != SetPhase.work) {
        s.tick();
      }
      s.skip();
      expect(s.finishRepSet(), isEmpty);
      expect(s.phase, SetPhase.rest);

      final timedSession = SetSession(timed);
      timedSession.start();
      timedSession.confirmReady();
      while (timedSession.phase != SetPhase.work) {
        timedSession.tick();
      }
      expect(timedSession.finishRepSet(), isEmpty);
      expect(timedSession.phase, SetPhase.work);
    });
  });
}
