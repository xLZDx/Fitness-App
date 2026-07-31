import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';

PoseLandmark p(LandmarkType t, double x, double y) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: 1.0);

PoseFrame frame(Map<LandmarkType, PoseLandmark> ls) =>
    PoseFrame(timestampMs: 0, landmarks: ls);

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
}
