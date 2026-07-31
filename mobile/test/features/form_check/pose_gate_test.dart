import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';

/// The gate that decides whether a frame is worth scoring at all.
///
/// Written from the operator's 2026-07-31 report (6 reps and 3 rule violations
/// counted from a selfie of a face) and from the two defects the review found
/// in the first version of the fix: it disabled push-ups outright, and it
/// blocked a squat whose shoulders sat near the top of frame.
PoseLandmark p(LandmarkType t, double x, double y, [double likelihood = 0.95]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: likelihood);

PoseFrame frame(Map<LandmarkType, PoseLandmark> ls) =>
    PoseFrame(timestampMs: 0, landmarks: ls);

const kSquatJoints = {
  LandmarkType.leftHip,
  LandmarkType.rightHip,
  LandmarkType.leftKnee,
  LandmarkType.rightKnee,
};

void main() {
  group('the face-only selfie has TWO signatures, and both must be caught', () {
    // Which one a device produces depends on how confident BlazePose is about
    // the joints it invents. Pinning only one of them would close half the
    // defect and leave the other half shipping.

    test('extrapolated joints below the confidence floor -> lowConfidence', () {
      final f = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.48, 0.15),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.52, 0.15),
        // Invented, and the model is not sure: the confidence signature.
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.48, 0.60, 0.65),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.52, 0.60, 0.65),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.48, 0.75, 0.60),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.52, 0.75, 0.60),
      });
      expect(gatePose(f, kSquatJoints), PoseGateVerdict.lowConfidence);
    });

    test('confident but collapsed torso -> implausibleGeometry', () {
      final f = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.48, 0.15),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.52, 0.15),
        // Invented, and the model is confident: hips land just under the chin.
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.48, 0.18),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.52, 0.18),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.48, 0.21),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.52, 0.21),
      });
      expect(gatePose(f, kSquatJoints), PoseGateVerdict.implausibleGeometry);
    });
  });

  group('the gate must not eat legitimate work', () {
    test('a real squat scores', () {
      final f = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.45, 0.25),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.55, 0.25),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.45, 0.55),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, 0.55),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, 0.65),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, 0.65),
      });
      expect(gatePose(f, kSquatJoints), PoseGateVerdict.ok);
    });

    test('a push-up scores — the torso is horizontal, not absent', () {
      // REGRESSION. The first version of this gate compared |hipY - shoulderY|
      // and demanded 0.10 of separation. In a plank that difference is ~0.03,
      // so every push-up frame was rejected as "impossible geometry" and
      // PushupAlignmentClassifier — one of the three shipped rules — never ran
      // again. A gate built to stop false alarms had become a false silence.
      final f = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.30, 0.50),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.30, 0.53),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.55, 0.52),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, 0.55),
        LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.80, 0.55),
      });
      expect(
        gatePose(f, const {
          LandmarkType.leftShoulder,
          LandmarkType.leftHip,
          LandmarkType.leftAnkle,
        }),
        PoseGateVerdict.ok,
      );
    });

    test('lying on a bench scores — same defect class as the push-up', () {
      final f = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.35, 0.50),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.35, 0.54),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.60, 0.52),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.60, 0.56),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.75, 0.55),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.75, 0.58),
      });
      expect(gatePose(f, kSquatJoints), PoseGateVerdict.ok);
    });

    test('a squat framed with the shoulders at the top edge still scores', () {
      // REGRESSION. SquatDepthClassifier used to declare both shoulders purely
      // so the torso check would run; the gate then edge-checked them like
      // inputs. Framing that put the shoulders near the top of frame returned
      // outOfFrame and depth was never scored — a rule that never reads
      // shoulders was blocked by shoulders.
      final f = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.45, 0.005),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.55, 0.005),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.45, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, 0.40),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, 0.60),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, 0.60),
      });
      expect(gatePose(f, kSquatJoints), PoseGateVerdict.ok);
    });
  });

  group('boundaries', () {
    PoseFrame withKnee(double y) => frame({
          LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.45, 0.25),
          LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.55, 0.25),
          LandmarkType.leftHip: p(LandmarkType.leftHip, 0.45, 0.55),
          LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, 0.55),
          LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, y),
          LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, y),
        });

    test('just inside the edge margin is scorable', () {
      expect(gatePose(withKnee(0.97), kSquatJoints), PoseGateVerdict.ok);
    });

    test('on the edge margin is not', () {
      expect(gatePose(withKnee(0.99), kSquatJoints), PoseGateVerdict.outOfFrame);
    });

    test('a missing joint is reported as missing, not as bad form', () {
      final f = frame({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.45, 0.55),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, 0.65),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, 0.65),
      });
      expect(gatePose(f, kSquatJoints), PoseGateVerdict.missingJoints);
    });

    test('a frame with no torso landmarks is not rejected for lacking one', () {
      // "Cannot tell" must never become "reject": the torso check is a
      // frame-level sanity signal, and its absence is not evidence of anything.
      final f = frame({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.45, 0.55),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, 0.55),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, 0.65),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, 0.65),
      });
      expect(gatePose(f, kSquatJoints), PoseGateVerdict.ok);
    });
  });

  group('verdict priority is explicit, not declaration order', () {
    test('lower priority wins when several rules are blocked differently', () {
      expect(PoseGateVerdict.missingJoints.priority,
          lessThan(PoseGateVerdict.lowConfidence.priority));
      expect(PoseGateVerdict.lowConfidence.priority,
          lessThan(PoseGateVerdict.outOfFrame.priority));
      expect(PoseGateVerdict.outOfFrame.priority,
          lessThan(PoseGateVerdict.implausibleGeometry.priority));
      expect(PoseGateVerdict.ok.isScorable, isTrue);
    });
  });

  group('evaluateGated', () {
    test('a face-only frame produces no feedback and names the reason', () {
      final f = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.48, 0.15),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.52, 0.15),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.48, 0.18),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.52, 0.18),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.48, 0.21),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.52, 0.21),
        LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.48, 0.24),
      });
      final r = evaluateGated([
        SquatDepthClassifier(),
        DeadliftHipHingeClassifier(),
        PushupAlignmentClassifier(),
      ], f);
      expect(r.scorable, isFalse);
      expect(r.feedback, isEmpty);
      expect(r.worst, isNull);
      expect(r.verdict, PoseGateVerdict.implausibleGeometry);
    });

    test('a real squat still produces feedback', () {
      final f = frame({
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.45, 0.25),
        LandmarkType.rightShoulder: p(LandmarkType.rightShoulder, 0.55, 0.25),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.45, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, 0.40),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, 0.55),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, 0.55),
      });
      final r = evaluateGated([SquatDepthClassifier()], f);
      expect(r.scorable, isTrue);
      expect(r.verdict, PoseGateVerdict.ok);
      expect(r.worst?.rule, 'squat.depth');
    });
  });

  group('the hip-hinge rule reports and never warns', () {
    // A correct Romanian deadlift measures 82.9 degrees at the bottom; a
    // genuinely rounded back at the same depth measures 77.7. The old rule
    // called anything under 150 "stop, your back is rounding", so it told a
    // correct lifter to stop and could not have distinguished the two classes
    // anyway — BlazePose has no spine landmark at any configuration.
    FormFeedback? hinge(double shoulderX, double shoulderY) {
      final f = frame({
        LandmarkType.leftShoulder:
            p(LandmarkType.leftShoulder, shoulderX, shoulderY),
        LandmarkType.rightShoulder:
            p(LandmarkType.rightShoulder, shoulderX, shoulderY),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.50, 0.50),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.50, 0.50),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.45, 0.70),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.45, 0.70),
      });
      return DeadliftHipHingeClassifier().evaluate(f);
    }

    test('a deep hinge is reported, not warned about', () {
      final fb = hinge(0.20, 0.50); // torso near horizontal
      expect(fb, isNotNull);
      expect(fb!.severity, 0, reason: 'this rule may not raise an alarm');
      expect(fb.cueKey, FormCueKey.deadliftHipHingeDeep);
    });

    test('standing tall is reported as shallow', () {
      final fb = hinge(0.50, 0.20); // torso vertical
      expect(fb!.severity, 0);
      expect(fb.cueKey, FormCueKey.deadliftHipHingeShallow);
    });

    test('no hinge angle can ever reach speaking severity', () {
      // CueGate's minSeverity is 1. Severity 0 across the whole range is what
      // makes "never warns" a property of the code rather than a promise.
      for (var x = 0.05; x < 0.95; x += 0.05) {
        expect(hinge(x, 0.50)!.severity, 0);
        expect(hinge(0.50, x)!.severity, 0);
      }
    });
  });
}
