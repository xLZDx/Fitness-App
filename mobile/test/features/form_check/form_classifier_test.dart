import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';

PoseLandmark p(LandmarkType t, double x, double y) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: 1.0);

PoseFrame frame(Map<LandmarkType, PoseLandmark> ls) =>
    PoseFrame(timestampMs: 0, landmarks: ls);

/// A rule that runs happily and finds nothing wrong — the shape every future
/// rule will have, and the one no shipped rule has yet.
class _Quiet implements FormClassifier {

  /// No vertex: a test double has no angle to turn on, and a ring drawn on a
  /// joint no rule measured would point at nothing.
  @override
  LandmarkType? get faultVertex => null;
  /// False, matching what it does: this double never returns feedback at all,
  /// so claiming it could fault a rep would be a lie the verdict logic reads.
  @override
  bool get canFault => false;

  @override
  String get rule => 'test.quiet';

  @override
  Set<LandmarkType> get requiredLandmarks => const {
        LandmarkType.leftShoulder,
        LandmarkType.leftHip,
        LandmarkType.leftAnkle,
      };

  @override
  FormFeedback? evaluate(PoseFrame frame) => null;
}

void main() {
  group('SquatDepthClassifier', () {
    final c = SquatDepthClassifier();
    test('returns null when joints missing', () {
      expect(c.evaluate(frame({})), isNull);
    });
    test('hip below knee = severity 0', () {
      final f = frame({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.5, 0.6),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.5, 0.6),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.5, 0.55),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.5, 0.55),
      });
      final fb = c.evaluate(f);
      expect(fb!.severity, 0);
    });
    test('hip well above knee is REPORTED, never warned about', () {
      final f = frame({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.5, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.5, 0.40),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.5, 0.55),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.5, 0.55),
      });
      final fb = c.evaluate(f);
      expect(fb!.cueKey, FormCueKey.squatDepthHalf,
          reason: 'the observation is still recorded');
      expect(fb.severity, 0, reason: 'but it may not raise an alarm');
    });

    test('no hip position can ever reach speaking severity', () {
      // Operator, 2026-07-31, on video: eight squats scored 0 clean / 8 with
      // errors, the coach saying "sit deeper" -- "ниже уже некуда было".
      //
      // hipY vs kneeY in image space is not a property of the squat, it is a
      // property of where the phone stands: the same depth projects differently
      // from floor height and from hip height. No threshold separates a shallow
      // squat from a deep one filmed low, so this rule is not entitled to an
      // alarm until the silhouette match gives it a target to compare against.
      for (var hipY = 0.10; hipY < 0.95; hipY += 0.05) {
        final f = frame({
          LandmarkType.leftHip: p(LandmarkType.leftHip, 0.5, hipY),
          LandmarkType.rightHip: p(LandmarkType.rightHip, 0.5, hipY),
          LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.5, 0.55),
          LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.5, 0.55),
        });
        expect(c.evaluate(f)!.severity, 0, reason: 'hipY=$hipY');
      }
    });
  });

  group('worstFeedback', () {
    test('returns highest-severity from a set of classifiers', () {
      final classifiers = [
        PushupAlignmentClassifier(),
        SquatDepthClassifier(),
        DeadliftHipHingeClassifier(),
      ];
      // A sagging body line (severity 2) alongside two report-only rules.
      //
      // The push-up rule is the only one left that may warn: the squat-depth
      // and hip-hinge rules both measure quantities that do not separate good
      // technique from bad, so both report at severity 0.
      //
      // Shoulders are in the frame because `worstFeedback` is gated now
      // (`gatePose`): a rule only runs when the joints it declares are
      // present, confident, inside the frame and geometrically believable.
      // Without a shoulder line there is no torso to believe in, which is
      // precisely the check that stops a face-only selfie being scored.
      final f = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.5, 0.25),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.5, 0.25),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.5, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.5, 0.40),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.5, 0.55),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.5, 0.55),
        // The push-up rule reads shoulder-hip-ankle. Off to the side, so the
        // body line is bent rather than straight: ~112 deg, well under the
        // 155 deg that separates a nudge from a stop.
        LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.75, 0.50),
      });
      final w = worstFeedback(classifiers, f);
      expect(w!.severity, 2);
      expect(w.rule, 'pushup.alignment');
    });
  });

  group('a readable frame that nobody complained about', () {
    // "No rule had anything to say" used to be reported as `missingJoints`,
    // the same answer as "there is no body in this picture". Everything
    // downstream drops an unscorable frame before the rep counter sees it, so
    // a rule that stays quiet on a good repetition would have stopped the
    // count dead while the screen blamed the user's framing. It has never
    // shown up in the app only because all three shipped rules emit a
    // severity-0 observation on every single frame.
    final good = frame({
      LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.45, 0.20),
      LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.55, 0.20),
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.45, 0.45),
      LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, 0.45),
      LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, 0.70),
      LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, 0.70),
      LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.45, 0.88),
    });

    test('is scorable', () {
      final r = evaluateGated([_Quiet()], good);
      expect(r.scorable, isTrue);
      expect(r.verdict, PoseGateVerdict.ok);
      expect(r.feedback, isEmpty);
      expect(r.worst, isNull);
    });

    test('is still blocked when the rule could not run', () {
      // The quiet rule needs an ankle; without one the verdict must name the
      // real problem rather than falling through to "ok, nothing to say".
      final noAnkle =
          frame({...good.landmarks}..remove(LandmarkType.leftAnkle));
      final r = evaluateGated([_Quiet()], noAnkle);
      expect(r.scorable, isFalse);
      expect(r.verdict, PoseGateVerdict.missingJoints);
    });

    test('with no rules at all, the frame-level checks still decide', () {
      // A movement may ship with no per-frame rules — the silhouette judges
      // the rep instead. That must not disable rep counting, and it must not
      // wave through a frame the gate would reject.
      expect(evaluateGated(const [], good).scorable, isTrue);

      final selfie = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.48, 0.15),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.52, 0.15),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.48, 0.18),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.52, 0.18),
      });
      expect(evaluateGated(const [], selfie).scorable, isFalse,
          reason: 'a head-and-shoulders selfie has no believable torso');
    });
  });
}
