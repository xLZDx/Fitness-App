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
    test('hip well above knee = severity 2', () {
      final f = frame({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.5, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.5, 0.40),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.5, 0.55),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.5, 0.55),
      });
      final fb = c.evaluate(f);
      expect(fb!.severity, 2);
    });
  });

  group('worstFeedback', () {
    test('returns highest-severity from a set of classifiers', () {
      final classifiers = [
        SquatDepthClassifier(),
        DeadliftHipHingeClassifier(),
      ];
      // Bad squat depth (severity 2) alongside a neutral spine (severity 0).
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
      });
      final w = worstFeedback(classifiers, f);
      expect(w!.severity, 2);
      expect(w.rule, 'squat.depth');
    });
  });
}
