import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';

import 'rep_counter_test.dart' show frameAt, repFrames, drive;

/// A repetition that never ends is not a repetition.
///
/// The counter has always had a floor — a lap completed in under 600ms is a
/// landmark glitch, not a body — and had no ceiling at all. Measured on an S23
/// on 2026-09-02, at the end of a real set: the thirteenth "repetition" ran to
/// 980 observed frames, roughly 33 seconds, against a set whose tempo readout
/// averaged 1.9s. It completed. It was scored against a target it had never
/// been anywhere near (peak match 0.072), the set summary gained a repetition
/// nobody performed, and the lifter — who had stopped half a minute earlier —
/// was told they had not reached the shape.
///
/// Recorded in `reports/device-check-2026-09-02/logcat_reps.txt` (repo root),
/// line 13 of the extracted `reps_all.txt`.

/// A body that starts down and then simply stops, holding position.
List<PoseFrame> _stalledDescent({
  int startMs = 0,
  int stepMs = 50,
  required int holdMs,
}) {
  final frames = <PoseFrame>[
    // Standing, to arm the counter.
    frameAt(-0.20, startMs),
    // Past `topExit`, which opens the rep.
    frameAt(-0.09, startMs + stepMs),
  ];
  var ms = startMs + 2 * stepMs;
  final until = startMs + stepMs + holdMs;
  while (ms <= until) {
    // Part-way down and going nowhere: never deep enough to reach the bottom,
    // never shallow enough to be a partial rep coming back up.
    frames.add(frameAt(-0.09, ms));
    ms += stepMs;
  }
  return frames;
}

void main() {
  group('a lap that stops being performed is thrown away', () {
    test('after the ceiling, and not before it', () {
      final counter = RepCounter();
      const max = 20000; // the shipped default

      // Just under: still in flight, nothing rejected. This is the half that
      // matters — a ceiling that fires early would discard slow repetitions.
      final early = drive(counter, _stalledDescent(holdMs: max - 1000));
      expect(early.where((e) => e.kind == RepEventKind.repRejected), isEmpty);
      expect(counter.phase, isNot(RepPhase.top),
          reason: 'positive control: the rep really is still open here');

      // Past it.
      final late = drive(
        RepCounter(),
        _stalledDescent(holdMs: max + 1000),
      );
      final rejected =
          late.where((e) => e.kind == RepEventKind.repRejected).toList();
      expect(rejected, hasLength(1));
      expect(rejected.single.rejectReason, RepRejectReason.abandoned);
      expect(rejected.single.repCount, 0, reason: 'and it counts for nothing');
    });

    test('and the counter will not start another until the lifter stands up',
        () {
      // Without this the discard would return the machine to the top phase
      // while the signal is still deep, a new rep would open on the very next
      // frame, and the same lifter would be told the same thing every twenty
      // seconds for as long as they stayed put.
      final counter = RepCounter();
      drive(counter, _stalledDescent(holdMs: 21000));
      expect(counter.isArmed, isFalse);

      // Still deep: no new rep, no second rejection.
      final stillDown = drive(counter, [
        for (var i = 0; i < 40; i++) frameAt(-0.09, 30000 + i * 50),
      ]);
      expect(stillDown, isEmpty);

      // Standing up re-arms it, and the next real rep counts normally.
      drive(counter, [
        for (var i = 0; i < 5; i++) frameAt(-0.20, 40000 + i * 50),
      ]);
      expect(counter.isArmed, isTrue);
      final after = drive(counter, repFrames(startMs: 41000));
      expect(
        after.where((e) => e.kind == RepEventKind.repCompleted),
        hasLength(1),
        reason: 'the ceiling must not end the set, only the stalled lap',
      );
    });

    test('a genuinely slow tempo repetition is still counted', () {
      // The failure mode of this whole change: a lifter working to a slow
      // tempo protocol being told their repetitions do not count. 5s down, 3s
      // at the bottom, 5s up is a real prescription and comes to roughly 16s.
      //
      // Caught by GPT-PM against the first version of this test: it asserted
      // only `greaterThan(6000)` against a fixture that in fact measured
      // about 8.1s — nowhere near the 16s tempo case the comment described,
      // and nowhere near the 20s ceiling a boundary regression would show up
      // at. `repFrames`'s own doc comment says why the two numbers differ:
      // the counter measures from the frame that crosses `topExit` to the
      // frame that returns under `topEnter`, not the fixture's full span —
      // 26 steps' worth with `halfFrames: 20` and the default top/bottom,
      // empirically (the doc comment's own "25 frames" is for `stepMs: 50`
      // specifically and does not by itself say the step COUNT is constant
      // across `stepMs`; measuring rather than assuming is why `stepMs: 640`
      // is 16640ms here and not the 16000 a clean 25-step scaling would give).
      // `stepMs: 325` gave neither.
      final counter = RepCounter();
      final slow = repFrames(startMs: 0, stepMs: 640, halfFrames: 20);
      final events = drive(counter, slow);
      final done =
          events.where((e) => e.kind == RepEventKind.repCompleted).toList();
      expect(done, hasLength(1));
      final rep = done.single.rep!;
      expect(rep.endMs - rep.startMs, inInclusiveRange(15000, 17000),
          reason: 'positive control: this fixture is meant to land near the '
              'stated 16s tempo case, not merely somewhere slow');
    });

    test('a repetition finishing just under the ceiling still counts', () {
      // The boundary itself, as a POSITIVE control — distinct from the test
      // above, which is about a real tempo protocol comfortably inside the
      // ceiling, and from "after the ceiling, and not before it", whose
      // under-the-ceiling half never completes a rep at all, only proves one
      // is still open. A regression that starts rejecting slightly early
      // would pass both of those and fail only here.
      final counter = RepCounter();
      final nearCeiling = repFrames(startMs: 0, stepMs: 760, halfFrames: 20);
      final events = drive(counter, nearCeiling);
      final done =
          events.where((e) => e.kind == RepEventKind.repCompleted).toList();
      expect(done, hasLength(1),
          reason: 'a repetition finishing before the 20s ceiling must not be '
              'discarded as abandoned');
      final rep = done.single.rep!;
      expect(rep.endMs - rep.startMs, inInclusiveRange(18000, 19999),
          reason: 'positive control: this fixture is meant to sit right up '
              'against the ceiling, not merely somewhere slow');
    });
  });

  group('the ceiling is part of the config contract', () {
    test('a ceiling under the floor is not an ordered config', () {
      // Both bounds are checked against the same lap, so a ceiling at or below
      // the floor rejects every repetition by one bound or the other and the
      // counter can never count anything. `isOrdered` is what the app asserts
      // before trusting a config, so it has to see that.
      expect(
        const RepCounterConfig(minRepDurationMs: 600, maxRepDurationMs: 600)
            .isOrdered,
        isFalse,
      );
      expect(
        const RepCounterConfig(minRepDurationMs: 5000, maxRepDurationMs: 600)
            .isOrdered,
        isFalse,
      );
      expect(const RepCounterConfig().isOrdered, isTrue,
          reason: 'positive control: the shipped defaults are ordered');
    });

    test('the ceiling is honoured wherever it is set', () {
      // Rather than asserting the 20000 default twice: the mechanism is the
      // config value, so a hard-coded constant in the counter would pass the
      // tests above and fail here.
      final counter = RepCounter(
        config: const RepCounterConfig(maxRepDurationMs: 3000),
      );
      final events = drive(counter, _stalledDescent(holdMs: 4000));
      expect(
        events.where((e) => e.rejectReason == RepRejectReason.abandoned),
        hasLength(1),
      );
    });
  });
}
