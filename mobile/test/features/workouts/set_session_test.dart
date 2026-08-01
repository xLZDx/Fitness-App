import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/set_session.dart';

/// A timed set, driven a second at a time.
///
/// The reason [SetSession] owns no clock: every one of these would otherwise
/// take real minutes to run, and the failures that matter — a gong played
/// twice, a paused timer still counting, the last set ending without its
/// sound — are exactly the ones nobody sits through three minutes to notice.
void main() {
  /// Runs the session to completion, returning every cue in order.
  List<SetCue> runOut(SetSession s, {int maxTicks = 10000}) {
    final cues = <SetCue>[...s.start()];
    var n = 0;
    while (!s.isFinished && n++ < maxTicks) {
      cues.addAll(s.tick().cues);
    }
    return cues;
  }

  const tiny = SetPlan(
      sets: 2, workSeconds: 3, restSeconds: 2, readySeconds: 2, cueLead: 1);

  group('the shape of a session', () {
    test('ready, then work, rest, work, done', () {
      final s = SetSession(tiny);
      s.start();
      expect(s.phase, SetPhase.gettingReady);

      final seen = <SetPhase>[s.phase];
      while (!s.isFinished) {
        s.tick();
        if (seen.last != s.phase) seen.add(s.phase);
      }
      expect(seen, [
        SetPhase.gettingReady,
        SetPhase.work,
        SetPhase.rest,
        SetPhase.work,
        SetPhase.done,
      ]);
    });

    test('every set gets a start gong and an end gong', () {
      final cues = runOut(SetSession(tiny));
      expect(cues.where((c) => c == SetCue.startGong).length, tiny.sets);
      expect(cues.where((c) => c == SetCue.endGong).length, tiny.sets);
    });

    test('the last set ends with BOTH its own gong and the finish', () {
      // The bug this pins: collapsing the two into one "finished" cue leaves
      // the final set as the only one that ends in silence.
      final cues = runOut(SetSession(tiny));
      expect(cues.length, greaterThan(2));
      expect(cues[cues.length - 2], SetCue.endGong);
      expect(cues.last, SetCue.finished);
      expect(cues.where((c) => c == SetCue.finished).length, 1);
    });

    test('ticking counts down through each phase exactly once', () {
      final s = SetSession(tiny);
      s.start();
      final work = <int>[];
      while (!s.isFinished) {
        final t = s.tick();
        if (t.phase == SetPhase.work && t.setNumber == 1) {
          work.add(t.secondsLeft);
        }
      }
      // 3, 2, 1 — and never 0. The tick that would show zero is the same tick
      // that moves into the rest, so the display goes straight from "1 second
      // of work left" to "resting", which is what a person watching a clock
      // expects. A zero would sit there for a full second saying nothing.
      expect(work, [3, 2, 1]);
    });
  });

  group('ticking cues', () {
    test('the last cueLead seconds of a work phase tick', () {
      const plan = SetPlan(
          sets: 1, workSeconds: 6, restSeconds: 2, readySeconds: 0, cueLead: 3);
      final s = SetSession(plan);
      s.start();
      final ticksAt = <int>[];
      while (!s.isFinished) {
        final t = s.tick();
        if (t.cues.contains(SetCue.tick)) ticksAt.add(t.secondsLeft);
      }
      expect(ticksAt, [3, 2, 1]);
    });

    test('the countdown before the first set ticks too', () {
      // "за 5 сек до начала подхода" — the operator asked for both edges.
      const plan = SetPlan(
          sets: 1, workSeconds: 2, restSeconds: 1, readySeconds: 4, cueLead: 2);
      final s = SetSession(plan);
      s.start();
      final duringReady = <int>[];
      while (s.phase == SetPhase.gettingReady) {
        final t = s.tick();
        if (t.cues.contains(SetCue.tick)) duringReady.add(t.secondsLeft);
      }
      expect(duringReady, [2, 1]);
    });

    test('a tick and a gong never land on the same second', () {
      // They would talk over each other. The gong replaces the last tick.
      final s = SetSession(tiny);
      s.start();
      while (!s.isFinished) {
        final c = s.tick().cues;
        final hasTick = c.contains(SetCue.tick);
        final hasGong =
            c.contains(SetCue.startGong) || c.contains(SetCue.endGong);
        expect(hasTick && hasGong, isFalse, reason: '$c');
      }
    });
  });

  group('control', () {
    test('a paused session does not advance', () {
      final s = SetSession(tiny);
      s.start();
      s.tick();
      s.pause();
      final phase = s.phase;
      final left = s.secondsLeft;
      for (var i = 0; i < 50; i++) {
        expect(s.tick().cues, isEmpty);
      }
      expect(s.phase, phase);
      expect(s.secondsLeft, left);
    });

    test('a finished session cannot be driven further', () {
      // A Timer that outlives the page would otherwise keep calling tick().
      final s = SetSession(tiny);
      runOut(s);
      expect(s.isFinished, isTrue);
      for (var i = 0; i < 20; i++) {
        expect(s.tick().cues, isEmpty);
      }
      expect(s.setNumber, tiny.sets);
    });

    test('starting twice does not restart', () {
      // A double tap must not send the user back to set one.
      final s = SetSession(tiny);
      s.start();
      for (var i = 0; i < 4; i++) {
        s.tick();
      }
      final set = s.setNumber;
      final phase = s.phase;
      expect(s.start(), isEmpty);
      expect(s.setNumber, set);
      expect(s.phase, phase);
    });

    test('pause then start resumes rather than restarting', () {
      final s = SetSession(tiny);
      s.start();
      for (var i = 0; i < 3; i++) {
        s.tick();
      }
      final phase = s.phase;
      final left = s.secondsLeft;
      s.pause();
      s.start();
      expect(s.phase, phase);
      expect(s.secondsLeft, left);
      expect(s.isRunning, isTrue);
    });

    test('skip ends the current set as if it had run out', () {
      final s = SetSession(tiny);
      s.start();
      s.tick();
      while (s.phase != SetPhase.work) {
        s.tick();
      }
      expect(s.skip(), contains(SetCue.endGong));
      expect(s.phase, SetPhase.rest);
    });

    test('skip on a stopped session does nothing', () {
      final s = SetSession(tiny);
      expect(s.skip(), isEmpty);
      expect(s.phase, SetPhase.idle);
    });

    test('reset returns it to the start', () {
      final s = SetSession(tiny);
      runOut(s);
      s.reset();
      expect(s.phase, SetPhase.idle);
      expect(s.setNumber, 0);
      expect(s.isRunning, isFalse);
      // ...and it can run again from scratch.
      expect(runOut(s).where((c) => c == SetCue.startGong).length, tiny.sets);
    });
  });

  group('progress', () {
    test('runs 0 to 1 and never goes backwards', () {
      final s = SetSession(tiny);
      expect(s.progress, 0);
      s.start();
      var last = s.progress;
      while (!s.isFinished) {
        s.tick();
        expect(s.progress, greaterThanOrEqualTo(last));
        expect(s.progress, inInclusiveRange(0, 1));
        last = s.progress;
      }
      expect(s.progress, 1);
    });

    test('phase progress resets each phase', () {
      final s = SetSession(tiny);
      s.start();
      while (s.phase != SetPhase.work) {
        s.tick();
      }
      final atStartOfWork = s.phaseProgress;
      s.tick();
      expect(s.phaseProgress, greaterThan(atStartOfWork));
      while (s.phase == SetPhase.work) {
        s.tick();
      }
      // Now resting: the phase counter starts over.
      expect(s.phase, SetPhase.rest);
      expect(s.phaseProgress, lessThan(0.6));
    });
  });

  group('the plans', () {
    test("the middle plan is the operator's own example", () {
      // "один подход это 30 секунд подход и 10 сек отдых и так 3 раза"
      expect(SetPlan.intermediate.workSeconds, 30);
      expect(SetPlan.intermediate.restSeconds, 10);
      expect(SetPlan.intermediate.sets, 3);
    });

    test('experience moves work up and rest down', () {
      expect(SetPlan.beginner.workSeconds,
          lessThan(SetPlan.intermediate.workSeconds));
      expect(SetPlan.advanced.workSeconds,
          greaterThan(SetPlan.intermediate.workSeconds));
      expect(SetPlan.beginner.restSeconds,
          greaterThan(SetPlan.advanced.restSeconds));
    });

    test('total time counts the gaps between sets, not after the last', () {
      const p = SetPlan(
          sets: 3, workSeconds: 30, restSeconds: 10, readySeconds: 10);
      expect(p.totalSeconds, 10 + 3 * 30 + 2 * 10);
    });

    test('a zero-length ready phase starts the first set immediately', () {
      const p = SetPlan(
          sets: 1, workSeconds: 5, restSeconds: 5, readySeconds: 0);
      final s = SetSession(p);
      expect(s.start(), contains(SetCue.startGong));
      expect(s.phase, SetPhase.work);
    });
  });
}
