import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';

/// Knee height is held fixed and the hip is moved, so `signal` below is
/// exactly what [squatDepthSignal] will read back out: hipY - kneeY.
const double _kneeY = 0.65;

PoseFrame frameAt(
  double signal,
  int timestampMs, {
  double likelihood = 1.0,
  bool dropHips = false,
}) {
  final hipY = _kneeY + signal;
  PoseLandmark lm(LandmarkType t, double y) =>
      PoseLandmark(type: t, x: 0.5, y: y, likelihood: likelihood);
  return PoseFrame(
    timestampMs: timestampMs,
    landmarks: {
      if (!dropHips) ...{
        LandmarkType.leftHip: lm(LandmarkType.leftHip, hipY),
        LandmarkType.rightHip: lm(LandmarkType.rightHip, hipY),
      },
      LandmarkType.leftKnee: lm(LandmarkType.leftKnee, _kneeY),
      LandmarkType.rightKnee: lm(LandmarkType.rightKnee, _kneeY),
    },
  );
}

/// One full squat: linear descent from [top] to [bottom] and back.
///
/// Defaults model a realistic rep: 41 frames at 50ms (20 FPS) spanning 2s.
///
/// Note the counter's own `durationMs` is *shorter* than that span. It times
/// from the frame that crosses `topExit` to the frame that returns under
/// `topEnter` — the plateaus at either end are not part of the rep. With
/// these defaults that measured duration is 25 frames = 1250ms, which is
/// what the min-rep-duration tests are calibrated against.
List<PoseFrame> repFrames({
  required int startMs,
  int stepMs = 50,
  int halfFrames = 20,
  double top = -0.20,
  double bottom = 0.0,
  double likelihood = 1.0,
  double jitter = 0.0,
}) {
  final frames = <PoseFrame>[];
  var ms = startMs;
  var n = 0;
  void add(double s) {
    // Deterministic alternating noise — a fixed seed would still be a
    // random walk, and this test must fail for a real regression only.
    final noise = jitter == 0 ? 0.0 : (n.isEven ? jitter : -jitter);
    frames.add(frameAt(s + noise, ms, likelihood: likelihood));
    ms += stepMs;
    n++;
  }

  for (var i = 0; i <= halfFrames; i++) {
    add(top + (bottom - top) * (i / halfFrames));
  }
  for (var i = 1; i <= halfFrames; i++) {
    add(bottom - (bottom - top) * (i / halfFrames));
  }
  return frames;
}

/// Feed frames, return every non-null event.
List<RepEvent> drive(
  RepCounter counter,
  List<PoseFrame> frames, {
  Iterable<FormFeedback> feedback = const <FormFeedback>[],
}) {
  final events = <RepEvent>[];
  for (final f in frames) {
    final e = counter.update(f, feedback: feedback);
    if (e != null) events.add(e);
  }
  return events;
}

FormFeedback fb(int severity, {String rule = 'squat.depth'}) =>
    FormFeedback(rule: rule, severity: severity, cueKey: FormCueKey.values[severity]);

void main() {
  group('squatDepthSignal', () {
    test('reads hip-minus-knee in the same sign convention as the rule', () {
      expect(squatDepthSignal(frameAt(-0.2, 0), 0.5), closeTo(-0.2, 1e-9));
      expect(squatDepthSignal(frameAt(0.05, 0), 0.5), closeTo(0.05, 1e-9));
    });

    test('null when a joint is missing', () {
      expect(squatDepthSignal(frameAt(-0.2, 0, dropHips: true), 0.5), isNull);
    });

    test('null when a joint is below the likelihood floor', () {
      expect(squatDepthSignal(frameAt(-0.2, 0, likelihood: 0.3), 0.5), isNull);
      expect(squatDepthSignal(frameAt(-0.2, 0, likelihood: 0.7), 0.5),
          isNotNull);
    });
  });

  group('RepCounterConfig', () {
    test('rejects thresholds whose hysteresis bands overlap', () {
      expect(
        () => RepCounter(
          config: const RepCounterConfig(topEnter: -0.05, bottomEnter: -0.10),
        ),
        throwsArgumentError,
      );
    });

    test('accepts the default ladder', () {
      expect(const RepCounterConfig().isOrdered, isTrue);
    });
  });

  group('counting a clean set', () {
    test('N clean reps count exactly N', () {
      for (final n in [1, 5, 12]) {
        final counter = RepCounter();
        var ms = 0;
        for (var i = 0; i < n; i++) {
          drive(counter, repFrames(startMs: ms));
          ms += 1200;
        }
        expect(counter.repCount, n, reason: '$n reps in, $n reps out');
        expect(counter.reps.length, n);
        expect(counter.phase, RepPhase.top);
      }
    });

    test('emits exactly one repCompleted event per rep', () {
      final counter = RepCounter();
      final events = <RepEvent>[];
      var ms = 0;
      for (var i = 0; i < 4; i++) {
        events.addAll(drive(counter, repFrames(startMs: ms)));
        ms += 1200;
      }
      final completed =
          events.where((e) => e.kind == RepEventKind.repCompleted).toList();
      expect(completed.length, 4);
      expect(completed.map((e) => e.repCount), [1, 2, 3, 4]);
      expect(completed.map((e) => e.rep!.index), [1, 2, 3, 4]);
    });

    test('walks top -> descending -> bottom -> ascending -> top', () {
      final counter = RepCounter();
      final events = drive(counter, repFrames(startMs: 0));
      final phases = events.map((e) => e.phase).toList();
      expect(
        phases,
        [
          RepPhase.descending,
          RepPhase.bottom,
          RepPhase.ascending,
          RepPhase.top,
        ],
      );
    });
  });

  group('noise rejection', () {
    test('jitter across the top threshold does not start or count a rep', () {
      final counter = RepCounter();
      // Arm at the top, then oscillate straddling topEnter (-0.15).
      counter.update(frameAt(-0.20, 0));
      for (var i = 0; i < 200; i++) {
        counter.update(frameAt(i.isEven ? -0.16 : -0.14, 10 + i * 20));
      }
      expect(counter.repCount, 0);
      expect(counter.phase, RepPhase.top);
    });

    test(
        'jitter big enough to cross topExit still cannot manufacture a rep',
        () {
      final counter = RepCounter();
      counter.update(frameAt(-0.20, 0));
      // Swings between the top zone and past topExit (-0.11) — enough to
      // flap the phase, nowhere near depth (-0.04).
      for (var i = 0; i < 200; i++) {
        counter.update(frameAt(i.isEven ? -0.16 : -0.09, 10 + i * 20));
      }
      expect(counter.repCount, 0,
          reason: 'a rep needs depth, not just movement');
    });

    test('jitter on top of a real set does not inflate the count', () {
      final counter = RepCounter();
      var ms = 0;
      for (var i = 0; i < 8; i++) {
        drive(counter, repFrames(startMs: ms, jitter: 0.015));
        ms += 1200;
      }
      expect(counter.repCount, 8);
    });

    test('settling noise after a rep does not double-count it', () {
      final counter = RepCounter();
      drive(counter, repFrames(startMs: 0));
      expect(counter.repCount, 1);
      for (var i = 0; i < 200; i++) {
        counter.update(frameAt(i.isEven ? -0.155 : -0.145, 2000 + i * 20));
      }
      expect(counter.repCount, 1);
    });
  });

  group('partial and malformed reps', () {
    test('a partial rep does not count', () {
      final counter = RepCounter();
      // Down to -0.09 (past topExit, short of depth) and back up.
      final frames = repFrames(startMs: 0, bottom: -0.09);
      final events = drive(counter, frames);
      expect(counter.repCount, 0);
      expect(
        events.last.kind,
        RepEventKind.repRejected,
        reason: 'never reached bottomEnter',
      );
      expect(events.last.rejectReason, RepRejectReason.incomplete);
    });

    test('a lap faster than a human is rejected as noise', () {
      final counter = RepCounter();
      // Full depth, but the whole lap takes 200ms.
      final events =
          drive(counter, repFrames(startMs: 0, stepMs: 10, halfFrames: 10));
      expect(counter.repCount, 0);
      expect(events.last.kind, RepEventKind.repRejected);
      expect(events.last.rejectReason, RepRejectReason.tooFast);
    });

    test('a lap just over the duration floor is accepted', () {
      final counter = RepCounter();
      // Careful: the floor applies to the MEASURED rep, not to the fixture's
      // total span. With halfFrames 10 the machine leaves the top on frame 5
      // and returns under topEnter on frame 18, so it measures 13 steps.
      // 13 * 50ms = 650ms, just over the 600ms floor. (13 * 35ms = 455ms
      // would be rejected even though the fixture spans 700ms end to end.)
      drive(counter, repFrames(startMs: 0, stepMs: 50, halfFrames: 10));
      expect(counter.repCount, 1);
      expect(counter.reps.single.durationMs, 650);
    });

    test('a lap under the floor once plateaus are excluded is rejected', () {
      final counter = RepCounter();
      // Spans 700ms end to end, but only 455ms of that is the rep itself.
      final events =
          drive(counter, repFrames(startMs: 0, stepMs: 35, halfFrames: 10));
      expect(counter.repCount, 0);
      expect(events.last.rejectReason, RepRejectReason.tooFast);
    });

    test('sinking back down mid-ascent stays one rep', () {
      final counter = RepCounter();
      counter.update(frameAt(-0.20, 0));
      counter.update(frameAt(-0.05, 100)); // descending
      counter.update(frameAt(0.00, 200)); // bottom
      counter.update(frameAt(-0.09, 300)); // ascending
      counter.update(frameAt(-0.02, 400)); // sank back to bottom
      counter.update(frameAt(-0.09, 500)); // ascending again
      counter.update(frameAt(-0.20, 900)); // top -> one rep
      expect(counter.repCount, 1);
    });

    test('starting mid-squat does not count the way up as a rep', () {
      final counter = RepCounter();
      // Camera opens at the bottom of a squat; user stands up.
      counter.update(frameAt(0.00, 0));
      counter.update(frameAt(-0.09, 200));
      counter.update(frameAt(-0.20, 800));
      expect(counter.repCount, 0);
      expect(counter.isArmed, isTrue, reason: 'now armed for the next rep');
      // The next real rep does count.
      drive(counter, repFrames(startMs: 1000));
      expect(counter.repCount, 1);
    });
  });

  group('unusable frames', () {
    test('low-likelihood frames are ignored entirely', () {
      final counter = RepCounter();
      drive(counter, repFrames(startMs: 0, likelihood: 0.3));
      expect(counter.repCount, 0);
      expect(counter.lastSignal, isNull, reason: 'no frame was accepted');
      expect(counter.isArmed, isFalse);
    });

    test('frames missing joints are ignored entirely', () {
      final counter = RepCounter();
      for (var i = 0; i < 40; i++) {
        counter.update(frameAt(-0.20 + i * 0.005, i * 50, dropHips: true));
      }
      expect(counter.repCount, 0);
      expect(counter.lastSignal, isNull);
    });

    test('a dropout mid-rep holds the phase rather than guessing', () {
      final counter = RepCounter();
      counter.update(frameAt(-0.20, 0));
      counter.update(frameAt(-0.05, 100));
      expect(counter.phase, RepPhase.descending);
      // Detector loses the hips for a few frames.
      for (var i = 0; i < 5; i++) {
        expect(counter.update(frameAt(0.0, 150 + i * 30, likelihood: 0.1)),
            isNull);
      }
      expect(counter.phase, RepPhase.descending);
      // ...and recovers.
      counter.update(frameAt(0.00, 400));
      expect(counter.phase, RepPhase.bottom);
    });

    test('a dropout does not break the count for the set', () {
      final counter = RepCounter();
      var ms = 0;
      for (var i = 0; i < 3; i++) {
        final frames = repFrames(startMs: ms);
        // Blank out two frames in the middle of each rep.
        for (var j = 0; j < frames.length; j++) {
          final f = frames[j];
          counter.update(
            (j == 5 || j == 6)
                ? frameAt(0.0, f.timestampMs, likelihood: 0.2)
                : f,
          );
        }
        ms += 1200;
      }
      expect(counter.repCount, 3);
    });
  });

  group('per-rep quality', () {
    test('a rep with no complaints is clean', () {
      final counter = RepCounter();
      drive(counter, repFrames(startMs: 0), feedback: [fb(0)]);
      expect(counter.reps.single.isClean, isTrue);
      expect(counter.cleanReps, 1);
      expect(counter.sloppyReps, 0);
    });

    test('a rep records the worst severity each rule reached', () {
      final counter = RepCounter();
      final frames = repFrames(startMs: 0);
      for (var i = 0; i < frames.length; i++) {
        counter.update(
          frames[i],
          // One bad frame at the bottom is enough to mark the rep.
          feedback: [fb(i == 10 ? 2 : 0), fb(1, rule: 'deadlift.back_angle')],
        );
      }
      final rep = counter.reps.single;
      expect(rep.maxSeverity, 2);
      expect(rep.isClean, isFalse);
      expect(rep.severityByRule['squat.depth'], 2);
      expect(rep.severityByRule['deadlift.back_angle'], 1);
      expect(rep.offendingRules,
          containsAll(<String>['squat.depth', 'deadlift.back_angle']));
    });

    test('quality does not leak between reps', () {
      final counter = RepCounter();
      drive(counter, repFrames(startMs: 0), feedback: [fb(2)]);
      drive(counter, repFrames(startMs: 1200), feedback: [fb(0)]);
      expect(counter.reps[0].isClean, isFalse);
      expect(counter.reps[1].isClean, isTrue);
      expect(counter.cleanReps, 1);
      expect(counter.sloppyReps, 1);
    });

    test('records depth and duration', () {
      final counter = RepCounter();
      drive(counter, repFrames(startMs: 0, stepMs: 50, halfFrames: 10));
      final rep = counter.reps.single;
      expect(rep.peakSignal, closeTo(0.0, 1e-9));
      // 13 steps of 50ms between leaving the top and returning to it — the
      // standing plateaus at either end are not part of the rep, so this is
      // shorter than the fixture's 1000ms span by design.
      expect(rep.durationMs, 650);
    });
  });

  group('reset', () {
    test('clears count, quality and arming', () {
      final counter = RepCounter();
      drive(counter, repFrames(startMs: 0));
      expect(counter.repCount, 1);
      counter.reset();
      expect(counter.repCount, 0);
      expect(counter.reps, isEmpty);
      expect(counter.phase, RepPhase.top);
      expect(counter.isArmed, isFalse);
      expect(counter.lastSignal, isNull);
    });

    test('counts again after a reset', () {
      final counter = RepCounter();
      drive(counter, repFrames(startMs: 0));
      counter.reset();
      drive(counter, repFrames(startMs: 5000));
      expect(counter.repCount, 1);
    });
  });

  group('injectable signal', () {
    test('a custom extractor drives the same machine', () {
      // Invert the sign: a "press" where the tracked value falls to finish.
      double? inverted(PoseFrame f, double minLikelihood) {
        final s = squatDepthSignal(f, minLikelihood);
        return s == null ? null : -s - 0.20;
      }

      final counter = RepCounter(signal: inverted);
      // With the inversion, a standing frame (-0.20) maps to 0.0, which is
      // the bottom zone — so the machine arms on a *deep* frame instead.
      counter.update(frameAt(0.05, 0)); // -> -0.25, top zone: arms
      expect(counter.isArmed, isTrue);
    });
  });
}
