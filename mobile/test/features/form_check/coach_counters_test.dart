import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/coach_counters.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';

/// Gate G4 — what goes in the four trainer counters.
///
/// G3 built the panel and wired every column to an em-dash. The thing worth
/// testing here is not that four numbers appear: it is that each one is a
/// measurement of what its label claims, and that the em-dash comes BACK
/// wherever the measurement cannot be made. A panel that always shows a number
/// is the failure mode, not the goal — «симметрия 50/50» printed off a leg the
/// detector was guessing at would be the most reassuring lie on the screen.

const _config = RepCounterConfig();

RepQuality _rep({
  int startMs = 0,
  int endMs = 2000,
  double peakSignal = -0.02,
  int bottomHoldMs = 0,
  SideDepths? peakSides,
}) =>
    RepQuality(
      index: 1,
      startMs: startMs,
      endMs: endMs,
      peakSignal: peakSignal,
      severityByRule: const {},
      bottomHoldMs: bottomHoldMs,
      peakSides: peakSides,
    );

PoseLandmark _p(LandmarkType t, double y, double likelihood) => PoseLandmark(
      type: t,
      x: t.name.startsWith('left') ? 0.45 : 0.55,
      y: y,
      likelihood: likelihood,
    );

/// A frame with both legs, each side's knee placed independently so a test can
/// make one leg do more of the work than the other.
PoseFrame _legs({
  double hipY = 0.60,
  double leftKneeY = 0.72,
  double rightKneeY = 0.72,
  double likelihood = 0.9,
  double? rightLikelihood,
}) =>
    PoseFrame(timestampMs: 0, landmarks: {
      LandmarkType.leftHip: _p(LandmarkType.leftHip, hipY, likelihood),
      LandmarkType.rightHip:
          _p(LandmarkType.rightHip, hipY, rightLikelihood ?? likelihood),
      LandmarkType.leftKnee: _p(LandmarkType.leftKnee, leftKneeY, likelihood),
      LandmarkType.rightKnee:
          _p(LandmarkType.rightKnee, rightKneeY, rightLikelihood ?? likelihood),
    });

void main() {
  group('nothing to report reports nothing', () {
    test('no completed rep leaves every counter blank', () {
      final c = coachCountersFor(null);
      expect(c.tempoSeconds, isNull);
      expect(c.amplitude, isNull);
      expect(c.symmetryLeftPercent, isNull);
      expect(c.pauseSeconds, isNull);
      expect(c.symmetryOffBy, isNull);
    });

    test('a movement with no defined full range gets no amplitude', () {
      // The default: a caller that cannot say what full depth means for this
      // movement passes nothing, and gets nothing back. Only the squat has an
      // answer — see `coachFullAmplitudeSignalFor`.
      final c = coachCountersFor(_rep(peakSignal: -0.02));
      expect(c.amplitude, isNull);
      expect(coachCountersFor(_rep(peakSignal: -0.02), fullAmplitudeSignal: 0)
          .amplitude,
          isNotNull,
          reason: 'positive control: the same rep DOES have an amplitude once '
              'a full-range reference is given');
    });
  });

  group('tempo is the repetition, top to top', () {
    test('a two-second rep reads two seconds', () {
      expect(coachCountersFor(_rep(startMs: 1000, endMs: 3000)).tempoSeconds,
          closeTo(2.0, 1e-9));
    });

    test('a clock that did not move is not a tempo', () {
      // Reachable from a hand-built record or a non-monotonic frame stream.
      // Zero seconds per repetition is not a slow rep, it is no reading.
      expect(coachCountersFor(_rep(startMs: 500, endMs: 500)).tempoSeconds,
          isNull);
    });
  });

  group('amplitude is depth against parallel, not against the gate', () {
    // The whole reason the denominator is parallel: `bottomEnter` is what makes
    // a rep count, so measuring against it would print 100% on every single
    // counted rep and 0% on nothing, forever.
    double? amp(double peak) =>
        coachCountersFor(_rep(peakSignal: peak), fullAmplitudeSignal: 0)
            .amplitude;

    test('hips level with the knees is the full reading', () {
      expect(amp(0.0), closeTo(1.0, 1e-9));
    });

    test('a rep that only just reached depth reads well under it', () {
      // -0.04 is `bottomEnter`. Against parallel that is 0.11 of the 0.15
      // travel — a real, reportable 73%, which is the number this counter
      // exists to be able to say.
      final v = amp(_config.bottomEnter)!;
      expect(v, closeTo(0.11 / 0.15, 1e-9));
      expect(v, lessThan(0.8));
    });

    test('below parallel is capped rather than reported as over-achievement',
        () {
      expect(amp(0.06), 1.0);
    });

    test('and a peak that never left the top floors at zero', () {
      expect(amp(-0.40), 0.0);
    });

    test('an infinite peak — the counter\'s own "no frame yet" sentinel — is '
        'not a reading', () {
      // `RepCounter._peakSignal` starts at negative infinity. A record built
      // before any frame arrived would otherwise clamp to a confident 0%.
      expect(
          coachCountersFor(_rep(peakSignal: double.negativeInfinity),
                  fullAmplitudeSignal: 0)
              .amplitude,
          isNull);
    });
  });

  group('symmetry is a split, and refuses to be one when it cannot see', () {
    CoachCounters withSides(double left, double right) =>
        coachCountersFor(_rep(peakSides: SideDepths(left: left, right: right)));

    test('a square lifter splits evenly', () {
      final c = withSides(-0.02, -0.02);
      expect(c.symmetryLeftPercent, 50);
      expect(c.symmetryOffBy, 0);
    });

    test('a side doing less of the work shows as the smaller share', () {
      // Left reaches -0.02 (0.13 of travel past the top gate), right only
      // -0.06 (0.09). Left is doing more, so left is the larger half.
      final c = withSides(-0.02, -0.06);
      expect(c.symmetryLeftPercent, greaterThan(50));
      expect(c.symmetryLeftPercent, (100 * 0.13 / 0.22).round());
    });

    test('and the reading is direction-blind when it is asked how lopsided',
        () {
      expect(withSides(-0.02, -0.06).symmetryOffBy,
          withSides(-0.06, -0.02).symmetryOffBy,
          reason: '49/51 and 51/49 are the same amount of lopsided');
    });

    test('a rep with no side reading at all stays blank', () {
      expect(coachCountersFor(_rep()).symmetryLeftPercent, isNull);
    });

    test('a lifter still standing has no work to divide', () {
      // Both sides above the top gate: the subtraction goes negative and there
      // is no total to take a share of. Silence, not a 50/50.
      expect(withSides(-0.30, -0.28).symmetryLeftPercent, isNull);
    });
  });

  group('pause is time held at the bottom', () {
    test('a held rep reports the hold', () {
      expect(coachCountersFor(_rep(bottomHoldMs: 400)).pauseSeconds,
          closeTo(0.4, 1e-9));
    });

    test('and a rep that bounced straight back up reports zero, not nothing',
        () {
      // Deliberately 0.0 rather than null: the app DID watch the bottom of this
      // rep and there was no hold. That is a measurement, and it is the one a
      // lifter bouncing out of the hole most needs to see.
      expect(coachCountersFor(_rep(bottomHoldMs: 0)).pauseSeconds, 0.0);
    });
  });

  group('the per-side extractor refuses an inferred leg', () {
    test('both legs seen clearly gives a reading', () {
      final sides = squatSideDepths(_legs(), _config.minSideLikelihood);
      expect(sides, isNotNull);
      expect(sides!.left, closeTo(0.60 - 0.72, 1e-9));
    });

    test('a far leg below the symmetry bar gives none, even though the rep '
        'counter would have accepted the same frame', () {
      // 0.6 clears `minLikelihood` (0.5) — the counter counts this frame and
      // is right to. It does not clear `minSideLikelihood` (0.7), because the
      // DIFFERENCE between two legs is the entire signal here and half of it
      // would be the model's prior rather than the lifter.
      expect(
          squatDepthSignal(_legs(rightLikelihood: 0.6), _config.minLikelihood),
          isNotNull,
          reason: 'positive control: the counter accepts this frame');
      expect(squatSideDepths(_legs(rightLikelihood: 0.6),
              _config.minSideLikelihood),
          isNull);
    });

    test('a missing leg gives none', () {
      final frame = PoseFrame(timestampMs: 0, landmarks: {
        LandmarkType.leftHip: _p(LandmarkType.leftHip, 0.6, 0.9),
        LandmarkType.leftKnee: _p(LandmarkType.leftKnee, 0.72, 0.9),
      });
      expect(squatSideDepths(frame, _config.minSideLikelihood), isNull);
    });
  });

  group('the counter records what the counters need', () {
    /// Drives one rep with an explicit hold at the bottom, so the hold is a
    /// number this test chose rather than a byproduct of a shared fixture.
    RepQuality? runRep({required int bottomFrames, int frameMs = 100}) {
      final counter = RepCounter(sideSignal: squatSideDepths);
      RepQuality? completed;
      var ts = 0;
      void feed(double hipY) {
        final e = counter.update(_legs(hipY: hipY).at(ts));
        if (e?.rep != null) completed = e!.rep;
        ts += frameMs;
      }

      for (var i = 0; i < 3; i++) {
        feed(0.42); // standing, signal -0.30
      }
      for (var y = 0.50; y < 0.70; y += 0.04) {
        feed(y);
      }
      for (var i = 0; i < bottomFrames; i++) {
        feed(0.71); // signal -0.01, past `bottomEnter`
      }
      for (var y = 0.66; y > 0.42; y -= 0.04) {
        feed(y);
      }
      feed(0.42);
      return completed;
    }

    test('the bottom hold is wall time between reaching depth and leaving it',
        () {
      final rep = runRep(bottomFrames: 5);
      expect(rep, isNotNull, reason: 'positive control: a rep completed');
      // 600ms, not the 500ms the five bottom frames alone suggest, and the
      // extra 100 is the hysteresis rather than an off-by-one: the machine
      // leaves the bottom when the signal falls below `bottomExit` (-0.08),
      // and the first frame of the ascent here is still at -0.06. The lifter
      // genuinely is at the bottom on that frame — that is what the band is
      // for — so the hold counts it.
      expect(rep!.bottomHoldMs, 600);
    });

    test('and a longer hold really does read longer', () {
      // The positive control that makes the number above a measurement rather
      // than a constant the code happens to produce.
      expect(runRep(bottomFrames: 9)!.bottomHoldMs,
          greaterThan(runRep(bottomFrames: 5)!.bottomHoldMs));
    });

    test('the side reading is taken at the deepest frame', () {
      final rep = runRep(bottomFrames: 4);
      expect(rep!.peakSides, isNotNull);
      // The bottom frames put the hip at 0.71 and both knees at 0.72.
      expect(rep.peakSides!.left, closeTo(-0.01, 1e-9));
    });

    test('a movement with no side extractor records none', () {
      // The default. Nothing about `squatSideDepths` is true of a push-up, and
      // the panel showing «—» there is the correct answer rather than a gap.
      final counter = RepCounter();
      RepQuality? completed;
      var ts = 0;
      void feed(double hipY) {
        final e = counter.update(_legs(hipY: hipY).at(ts));
        if (e?.rep != null) completed = e!.rep;
        ts += 100;
      }

      for (var i = 0; i < 3; i++) {
        feed(0.42);
      }
      for (var y = 0.50; y < 0.70; y += 0.04) {
        feed(y);
      }
      for (var i = 0; i < 3; i++) {
        feed(0.71);
      }
      for (var y = 0.66; y > 0.42; y -= 0.04) {
        feed(y);
      }
      feed(0.42);
      expect(completed, isNotNull);
      expect(completed!.peakSides, isNull);
    });
  });
}

extension on PoseFrame {
  /// The fixture builds a frame at t=0; a rep needs a clock.
  PoseFrame at(int ts) => PoseFrame(
        timestampMs: ts,
        landmarks: landmarks,
        aspectRatio: aspectRatio,
      );
}
