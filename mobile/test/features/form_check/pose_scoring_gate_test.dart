import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_scoring_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';

/// Gate T3: a rep may only be judged on joints that are actually seen.
///
/// Every guard below has its OWN fixture that trips exactly one rule, plus a
/// positive control that trips none — a control shared between guards would let
/// one broken guard hide behind another.

PoseLandmark _lm(LandmarkType t, double x, double y, [double p = 0.95]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: p);

/// A whole body, side-on, comfortably inside a square frame. [overrides] replace
/// single landmarks; a null value removes the landmark.
PoseFrame _body({Map<LandmarkType, PoseLandmark?> overrides = const {}}) {
  final lm = <LandmarkType, PoseLandmark>{
    for (final e in {
      LandmarkType.leftShoulder: (0.50, 0.30),
      LandmarkType.rightShoulder: (0.52, 0.30),
      LandmarkType.leftElbow: (0.52, 0.42),
      LandmarkType.rightElbow: (0.54, 0.42),
      LandmarkType.leftWrist: (0.54, 0.52),
      LandmarkType.rightWrist: (0.56, 0.52),
      LandmarkType.leftHip: (0.50, 0.55),
      LandmarkType.rightHip: (0.52, 0.55),
      LandmarkType.leftKnee: (0.52, 0.75),
      LandmarkType.rightKnee: (0.54, 0.75),
      LandmarkType.leftAnkle: (0.50, 0.92),
      LandmarkType.rightAnkle: (0.52, 0.92),
    }.entries)
      e.key: _lm(e.key, e.value.$1, e.value.$2),
  };
  overrides.forEach((k, v) {
    if (v == null) {
      lm.remove(k);
    } else {
      lm[k] = v;
    }
  });
  return PoseFrame(timestampMs: 0, landmarks: lm);
}

final _squat = scoredJointsOf(squatBottomTarget);
final _curl = scoredJointsOf(curlBottomTarget);

void main() {
  group('scoredJointsOf', () {
    test('squat scores four joints: the arm is drawn, not judged', () {
      expect(_squat, {
        LandmarkType.leftShoulder,
        LandmarkType.leftHip,
        LandmarkType.leftKnee,
        LandmarkType.leftAnkle,
      });
    });

    test('a curl scores six, wrist included', () {
      expect(_curl.length, 6);
      expect(_curl, contains(LandmarkType.leftWrist));
    });
  });

  group('reliabilityVerdict — one guard per fixture', () {
    test('POSITIVE CONTROL: a whole, confident, in-frame body is ok', () {
      expect(reliabilityVerdict(_body(), _squat), PoseGateVerdict.ok);
    });

    test('a scored joint the detector is guessing at -> lowConfidence', () {
      final f = _body(overrides: {
        LandmarkType.leftAnkle: _lm(LandmarkType.leftAnkle, 0.50, 0.92, 0.55),
      });
      expect(reliabilityVerdict(f, _squat), PoseGateVerdict.lowConfidence);
    });

    test('confident but on the frame edge -> outOfFrame', () {
      final f = _body(overrides: {
        LandmarkType.leftAnkle: _lm(LandmarkType.leftAnkle, 0.50, 0.99, 0.9),
      });
      expect(reliabilityVerdict(f, _squat), PoseGateVerdict.outOfFrame);
    });

    test('confident and in frame but a NaN coordinate -> unitMismatch', () {
      final f = _body(overrides: {
        LandmarkType.rightWrist:
            _lm(LandmarkType.rightWrist, double.nan, 0.5, 0.9),
      });
      expect(reliabilityVerdict(f, _squat), PoseGateVerdict.unitMismatch);
    });

    test('a scored joint not reported at all -> missingJoints', () {
      final f = _body(overrides: {LandmarkType.leftAnkle: null});
      expect(reliabilityVerdict(f, _squat), PoseGateVerdict.missingJoints);
    });

    test('a collapsed torso -> implausibleGeometry', () {
      final f = _body(overrides: {
        LandmarkType.leftShoulder: _lm(LandmarkType.leftShoulder, 0.50, 0.53),
        LandmarkType.rightShoulder: _lm(LandmarkType.rightShoulder, 0.52, 0.53),
      });
      expect(
          reliabilityVerdict(f, _squat), PoseGateVerdict.implausibleGeometry);
    });
  });

  group('the scored set is generic, not squat-shaped', () {
    final unreliableWrist = _body(overrides: {
      LandmarkType.leftWrist: _lm(LandmarkType.leftWrist, 0.54, 0.52, 0.3),
    });

    test('an unreliable wrist blocks a target that scores the wrist', () {
      expect(reliabilityVerdict(unreliableWrist, _curl),
          PoseGateVerdict.lowConfidence);
    });

    test('the same wrist does not block the squat, which never scores it', () {
      expect(reliabilityVerdict(unreliableWrist, _squat), PoseGateVerdict.ok);
    });
  });

  group('chooseScoringSide', () {
    final rightVisible = _body(overrides: {
      for (final t in [
        LandmarkType.leftShoulder,
        LandmarkType.leftHip,
        LandmarkType.leftKnee,
        LandmarkType.leftAnkle,
      ])
        t: _lm(t, 0.10, 0.10, 0.10),
    });

    test('left occluded, right visible -> right joints mapped, and ok', () {
      expect(reliabilityVerdict(rightVisible, _squat),
          PoseGateVerdict.lowConfidence,
          reason: 'positive control: scored as-is the frame is unreliable');
      final s = chooseScoringSide(rightVisible, _squat);
      expect(s.side, ScoringSide.right);
      expect(s.frame.landmarks[LandmarkType.leftKnee]!.x, 0.54);
      expect(s.frame.landmarks[LandmarkType.leftKnee]!.type,
          LandmarkType.leftKnee);
      expect(reliabilityVerdict(s.frame, _squat), PoseGateVerdict.ok);
    });

    test('left better or equal -> the frame is returned unchanged', () {
      final f = _body();
      final s = chooseScoringSide(f, _squat);
      expect(s.side, ScoringSide.left);
      expect(identical(s.frame, f), isTrue, reason: 'a tie stays on the left');
    });

    test(
        'right better but a counterpart missing -> the slot is empty, not '
        'the hidden left joint', () {
      final f = _body(overrides: {
        for (final t in [
          LandmarkType.leftShoulder,
          LandmarkType.leftHip,
          LandmarkType.leftKnee,
          LandmarkType.leftAnkle,
        ])
          t: _lm(t, 0.10, 0.10, 0.10),
        LandmarkType.rightAnkle: null,
      });
      final s = chooseScoringSide(f, _squat);
      expect(s.side, ScoringSide.right);
      expect(s.frame.landmarks.containsKey(LandmarkType.leftAnkle), isFalse);
      expect(
          reliabilityVerdict(s.frame, _squat), PoseGateVerdict.missingJoints);
    });
  });

  group('more edges', () {
    test('a NaN on a SCORED joint is a unit mismatch too', () {
      final f = _body(overrides: {
        LandmarkType.leftKnee: _lm(LandmarkType.leftKnee, double.nan, 0.75),
      });
      expect(reliabilityVerdict(f, _squat), PoseGateVerdict.unitMismatch);
    });

    test('a bilateral scored set is never remapped, even if right is better',
        () {
      final f = _body(overrides: {
        LandmarkType.leftKnee: _lm(LandmarkType.leftKnee, 0.10, 0.10, 0.10),
      });
      final scored = {LandmarkType.leftKnee, LandmarkType.rightKnee};
      final s = chooseScoringSide(f, scored);
      expect(s.side, ScoringSide.left);
      expect(identical(s.frame, f), isTrue);
    });

    test('elbow, wrist and ear map like the rest', () {
      final hiddenLeft = _body(overrides: {
        LandmarkType.leftElbow: _lm(LandmarkType.leftElbow, 0.1, 0.1, 0.1),
        LandmarkType.leftWrist: _lm(LandmarkType.leftWrist, 0.1, 0.1, 0.1),
      });
      final s = chooseScoringSide(hiddenLeft, {
        LandmarkType.leftElbow,
        LandmarkType.leftWrist,
      });
      expect(s.side, ScoringSide.right);
      expect(s.frame.landmarks[LandmarkType.leftElbow]!.x, 0.54);
      expect(s.frame.landmarks[LandmarkType.leftWrist]!.x, 0.56);
    });
  });

  group('combineGateVerdicts', () {
    test('a classifier verdict that is not ok wins', () {
      expect(
          combineGateVerdicts(
              PoseGateVerdict.missingJoints, PoseGateVerdict.ok),
          PoseGateVerdict.missingJoints);
      expect(
          combineGateVerdicts(
              PoseGateVerdict.unitMismatch, PoseGateVerdict.outOfFrame),
          PoseGateVerdict.unitMismatch);
    });

    test('otherwise the scoring verdict decides', () {
      expect(
          combineGateVerdicts(PoseGateVerdict.ok, PoseGateVerdict.outOfFrame),
          PoseGateVerdict.outOfFrame);
      expect(combineGateVerdicts(PoseGateVerdict.ok, PoseGateVerdict.ok),
          PoseGateVerdict.ok);
    });
  });
}
