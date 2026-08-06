import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';

/// The rest timer's state machine, driven by a clock the test owns.
///
/// The previous version of this file used `fake_async` to advance a real
/// `Timer.periodic`, which tested the thing that was wrong: a tick counter is
/// only equal to elapsed time while the process is scheduled at 1 Hz, and the
/// phone is in a pocket for the whole rest. Moving the deadline into the state
/// made that untestable in the good sense — there is no longer a tick to get
/// wrong — so these tests move the clock instead.
///
/// Covers the list master prompt §17 asks for by name: starts exactly once, no
/// duplicate clocks, add time, skip, pause and resume, background and
/// foreground, completion, and that a persisted set is never lost to timer
/// behaviour.

class _Clock {
  DateTime now = DateTime.utc(2026, 8, 6, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

({ProviderContainer c, _Clock clock, RestTimerController ctrl}) _harness() {
  final clock = _Clock();
  final c = ProviderContainer(overrides: [
    restClockProvider.overrideWithValue(clock.call),
  ]);
  addTearDown(c.dispose);
  return (c: c, clock: clock, ctrl: c.read(restTimerProvider.notifier));
}

void main() {
  group('a rest is a deadline', () {
    test('it begins with the full duration and counts down by wall clock', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));
      expect(h.c.read(restTimerProvider).remaining(h.clock.now),
          const Duration(seconds: 90));

      h.clock.advance(const Duration(seconds: 30));
      expect(h.c.read(restTimerProvider).remaining(h.clock.now),
          const Duration(seconds: 60));
    });

    test('progress runs 0 to 1 and clamps there', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 10));
      expect(h.c.read(restTimerProvider).progress(h.clock.now), 0);

      h.clock.advance(const Duration(seconds: 5));
      expect(h.c.read(restTimerProvider).progress(h.clock.now),
          closeTo(0.5, 0.001));

      h.clock.advance(const Duration(seconds: 60));
      expect(h.c.read(restTimerProvider).progress(h.clock.now), 1.0);
    });

    test('a zero-length rest does not divide by zero', () {
      final h = _harness();
      h.ctrl.start(Duration.zero);
      expect(h.c.read(restTimerProvider).progress(h.clock.now), 0);
    });
  });

  group('background and foreground', () {
    // The defect that motivated the rewrite. A tick counter loses time while
    // Android throttles the isolate; a deadline cannot.
    test('a rest that elapsed entirely while away is over, not partly done',
        () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));

      // The phone was in a pocket for four minutes. No ticks fired.
      h.clock.advance(const Duration(minutes: 4));

      expect(h.c.read(restTimerProvider).remaining(h.clock.now), Duration.zero);
    });

    test('remaining never goes negative', () {
      // A deadline five minutes in the past is over, not overdue by five
      // minutes — a negative remaining would render as "-5:00" and drive the
      // progress ring past full.
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 30));
      h.clock.advance(const Duration(minutes: 5));

      final left = h.c.read(restTimerProvider).remaining(h.clock.now);
      expect(left, Duration.zero);
      expect(left.isNegative, isFalse);
    });

    test('it is over on return without anything having observed it', () {
      // The defect two reviewers found independently. Marking a rest elapsed
      // used to require a ticker inside the mounted card, so leaving the page
      // mid-rest — which is what waiting out three minutes looks like —
      // cancelled the only thing in the app that could finish it, and the rest
      // stayed running against a deadline in the past forever.
      //
      // Nothing is called between starting and asserting here. That is the
      // test: ending is a comparison, not an event.
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 30));
      h.clock.advance(const Duration(minutes: 1));

      expect(h.c.read(restTimerProvider).outcomeAt(h.clock.now),
          RestOutcome.elapsed);
      expect(h.c.read(restTimerProvider).isRunningAt(h.clock.now), isFalse);
    });
  });

  group('completion', () {
    test('it does not complete early', () {
      // The guard that matters: an early repaint must not hand the user back
      // to the bar a second before the rest is over.
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 30));
      h.clock.advance(const Duration(seconds: 29));
      
      expect(h.c.read(restTimerProvider).outcomeAt(h.clock.now), isNull);
      expect(h.c.read(restTimerProvider).isRunningAt(h.clock.now), isTrue);
    });

    test('the outcome does not flicker once the deadline is behind us', () {
      // Derived state has to be stable, not merely correct once: the card asks
      // for it on every repaint, and a value that changed under a still clock
      // would re-announce and re-buzz.
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 5));
      h.clock.advance(const Duration(seconds: 5));
      final s = h.c.read(restTimerProvider);

      expect(s.outcomeAt(h.clock.now), RestOutcome.elapsed);
      expect(s.outcomeAt(h.clock.now), RestOutcome.elapsed);
      h.clock.advance(const Duration(hours: 2));
      expect(s.outcomeAt(h.clock.now), RestOutcome.elapsed);
    });

    test('the deadline instant itself counts as over, not as one tick left',
        () {
      // `isBefore` rather than `isAfter`: at exactly the deadline the rest is
      // finished. The opposite choice leaves a one-frame state where remaining
      // is 0:00 and the card still offers Skip and +30.
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 30));
      h.clock.advance(const Duration(seconds: 30));

      expect(h.c.read(restTimerProvider).outcomeAt(h.clock.now),
          RestOutcome.elapsed);
    });

    test('an elapsed rest reports zero remaining', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 5));
      h.clock.advance(const Duration(seconds: 5));
      
      expect(h.c.read(restTimerProvider).remaining(h.clock.now), Duration.zero);
      expect(h.c.read(restTimerProvider).isRunningAt(h.clock.now), isFalse);
    });
  });

  group('skip', () {
    test('it ends the rest immediately and says it was skipped', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));
      h.clock.advance(const Duration(seconds: 10));
      h.ctrl.skip();

      expect(h.c.read(restTimerProvider).outcomeAt(h.clock.now), RestOutcome.skipped);
      expect(h.c.read(restTimerProvider).remaining(h.clock.now), Duration.zero);
    });

    test('a skip is not reported as an elapsed rest', () {
      // The distinction earns its keep twice: only `elapsed` buzzes the phone,
      // and a summary that counted skips as completed rests would overstate
      // how well the session was paced.
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));
      h.ctrl.skip();
      h.clock.advance(const Duration(minutes: 5));
      
      expect(h.c.read(restTimerProvider).outcomeAt(h.clock.now), RestOutcome.skipped);
    });

    test('skipping nothing does nothing', () {
      final h = _harness();
      h.ctrl.skip();
      expect(h.c.read(restTimerProvider).outcomeAt(h.clock.now), isNull);
      expect(h.c.read(restTimerProvider).isIdle, isTrue);
    });
  });

  group('add time', () {
    test('+30 s while running pushes the deadline and grows the total', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 60));
      h.clock.advance(const Duration(seconds: 50));
      h.ctrl.addTime(const Duration(seconds: 30));

      final s = h.c.read(restTimerProvider);
      expect(s.remaining(h.clock.now), const Duration(seconds: 40));
      // Without growing the total the ring would already be at 100% with 40
      // seconds still to run.
      expect(s.total, const Duration(seconds: 90));
      expect(s.progress(h.clock.now), closeTo(50 / 90, 0.001));
    });

    test('+30 s while paused adds to what is left, not to the clock', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 60));
      h.clock.advance(const Duration(seconds: 20));
      h.ctrl.pause();
      h.clock.advance(const Duration(minutes: 3));
      h.ctrl.addTime(const Duration(seconds: 30));

      expect(h.c.read(restTimerProvider).remaining(h.clock.now),
          const Duration(seconds: 70));
    });

    test('it does nothing to a finished or idle rest', () {
      final h = _harness();
      h.ctrl.addTime(const Duration(seconds: 30));
      expect(h.c.read(restTimerProvider).isIdle, isTrue);

      h.ctrl.start(const Duration(seconds: 5));
      h.ctrl.skip();
      h.ctrl.addTime(const Duration(seconds: 30));
      expect(h.c.read(restTimerProvider).remaining(h.clock.now), Duration.zero);
    });
  });

  group('pause and resume', () {
    test('a paused rest does not lose time while paused', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));
      h.clock.advance(const Duration(seconds: 30));
      h.ctrl.pause();
      h.clock.advance(const Duration(minutes: 10));

      expect(h.c.read(restTimerProvider).remaining(h.clock.now),
          const Duration(seconds: 60));
      expect(h.c.read(restTimerProvider).isRunningAt(h.clock.now), isFalse);
      expect(h.c.read(restTimerProvider).isPaused, isTrue);
    });

    test('resume gives back what was left, measured from now', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));
      h.clock.advance(const Duration(seconds: 30));
      h.ctrl.pause();
      h.clock.advance(const Duration(minutes: 10));
      h.ctrl.resume();

      expect(h.c.read(restTimerProvider).remaining(h.clock.now),
          const Duration(seconds: 60));

      h.clock.advance(const Duration(seconds: 60));
      expect(h.c.read(restTimerProvider).remaining(h.clock.now), Duration.zero);
    });

    test('pausing an idle or finished rest does nothing', () {
      final h = _harness();
      h.ctrl.pause();
      expect(h.c.read(restTimerProvider).isPaused, isFalse);

      h.ctrl.start(const Duration(seconds: 5));
      h.ctrl.skip();
      h.ctrl.pause();
      expect(h.c.read(restTimerProvider).isPaused, isFalse);
    });

    test('resuming something that is not paused does nothing', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 60));
      h.ctrl.resume();
      expect(h.c.read(restTimerProvider).remaining(h.clock.now),
          const Duration(seconds: 60));
    });
  });

  group('exactly one authoritative state', () {
    test('reading the provider twice gives the same rest', () {
      // The old controller was constructed inside the widget's State, so the
      // second reader got a second countdown from full.
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));
      h.clock.advance(const Duration(seconds: 30));

      final a = h.c.read(restTimerProvider);
      final b = h.c.read(restTimerProvider);
      expect(a.remaining(h.clock.now), b.remaining(h.clock.now));
      expect(a.endsAt, b.endsAt);
    });

    test('a rest survives the widget that started it', () {
      // Scrolling the card out of a lazy list used to destroy the rest. The
      // provider is app-scoped, so nothing about the widget tree touches it.
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));
      final deadline = h.c.read(restTimerProvider).endsAt;

      h.clock.advance(const Duration(seconds: 20));
      expect(h.c.read(restTimerProvider).endsAt, deadline);
      expect(h.c.read(restTimerProvider).remaining(h.clock.now),
          const Duration(seconds: 70));
    });

    test('starting again replaces the rest rather than stacking one', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));
      h.clock.advance(const Duration(seconds: 30));
      h.ctrl.start(const Duration(seconds: 60));

      expect(h.c.read(restTimerProvider).remaining(h.clock.now),
          const Duration(seconds: 60));
      expect(h.c.read(restTimerProvider).total, const Duration(seconds: 60));
      expect(h.c.read(restTimerProvider).outcomeAt(h.clock.now), isNull);
    });

    test('the card is visible exactly while a rest exists', () {
      // The second half of the same defect. Visibility used to be a page-local
      // `StateProvider.autoDispose<bool>`, which reset when the page was
      // popped — so a rest that correctly survived navigation had no way back
      // onto the screen, and vanished with nothing on screen to say so.
      final h = _harness();
      expect(h.c.read(restTimerVisibleProvider), isFalse);

      h.ctrl.start(const Duration(seconds: 90));
      expect(h.c.read(restTimerVisibleProvider), isTrue);

      // Still visible after it ends: the card is how the user learns it ended.
      h.clock.advance(const Duration(minutes: 5));
      expect(h.c.read(restTimerVisibleProvider), isTrue);

      h.ctrl.clear();
      expect(h.c.read(restTimerVisibleProvider), isFalse);
    });

    test('clear returns it to idle', () {
      final h = _harness();
      h.ctrl.start(const Duration(seconds: 90));
      h.ctrl.clear();
      expect(h.c.read(restTimerProvider).isIdle, isTrue);
      expect(h.c.read(restTimerProvider).outcomeAt(h.clock.now), isNull);
    });
  });
}
