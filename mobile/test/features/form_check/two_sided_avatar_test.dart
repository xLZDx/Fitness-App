import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_avatar.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_silhouette.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';

/// The avatar reads the detector's own left and right.
///
/// This file exists because of a defect nobody's code could see and anybody's
/// eyes could: standing in front of the phone and raising ONE arm, the figure
/// raised TWO. Raising the other arm did nothing at all, and which arm "worked"
/// changed depending on where the user stood.
///
/// One cause explains all three symptoms. `avatarTargetFrom` chose a single
/// side per frame and re-keyed it onto the left; `buildSilhouette` then hung
/// that one chain off both sides of the body. So the drawn figure was always
/// bilaterally symmetric, always built from whichever side won that frame's
/// comparison, and the side that lost was not dropped — it was overwritten by a
/// copy of the side that won.
///
/// Symmetry is therefore the sharpest thing to assert, and most of what follows
/// asserts it in one direction or the other: a mirrored figure is symmetric by
/// construction, so a test that proves the drawing is NOT symmetric cannot pass
/// against the old code however the side comparison happens to resolve.

PoseLandmark p(
  LandmarkType t,
  double x,
  double y, [
  double likelihood = 0.95,
]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: likelihood);

/// The mid-line every case below is built around and measured against.
const double _midline = 0.50;

/// A body facing the camera, both arms hanging, both sides seen.
///
/// [raise] moves one wrist and elbow up and out. `null` leaves the body
/// symmetric, which is the control: the tests that demand asymmetry have to be
/// shown failing to find it when there is none.
PoseFrame facingCamera({
  LandmarkSide? raise,
  double leftLikelihood = 0.95,
  double rightLikelihood = 0.95,
  double halfSeparation = 0.10,
}) {
  final s = halfSeparation;
  final raisedLeft = raise == LandmarkSide.left;
  final raisedRight = raise == LandmarkSide.right;
  return PoseFrame(timestampMs: 0, landmarks: {
    LandmarkType.leftShoulder:
        p(LandmarkType.leftShoulder, _midline - s, 0.30, leftLikelihood),
    LandmarkType.leftElbow: p(LandmarkType.leftElbow,
        _midline - s - (raisedLeft ? 0.06 : 0.02), raisedLeft ? 0.20 : 0.44,
        leftLikelihood),
    LandmarkType.leftWrist: p(LandmarkType.leftWrist,
        _midline - s - (raisedLeft ? 0.10 : 0.03), raisedLeft ? 0.10 : 0.56,
        leftLikelihood),
    LandmarkType.leftHip: p(LandmarkType.leftHip, _midline - 0.08, 0.58,
        leftLikelihood),
    LandmarkType.leftKnee:
        p(LandmarkType.leftKnee, _midline - 0.08, 0.74, leftLikelihood),
    LandmarkType.leftAnkle:
        p(LandmarkType.leftAnkle, _midline - 0.08, 0.90, leftLikelihood),
    LandmarkType.rightShoulder:
        p(LandmarkType.rightShoulder, _midline + s, 0.30, rightLikelihood),
    LandmarkType.rightElbow: p(LandmarkType.rightElbow,
        _midline + s + (raisedRight ? 0.06 : 0.02), raisedRight ? 0.20 : 0.44,
        rightLikelihood),
    LandmarkType.rightWrist: p(LandmarkType.rightWrist,
        _midline + s + (raisedRight ? 0.10 : 0.03), raisedRight ? 0.10 : 0.56,
        rightLikelihood),
    LandmarkType.rightHip:
        p(LandmarkType.rightHip, _midline + 0.08, 0.58, rightLikelihood),
    LandmarkType.rightKnee:
        p(LandmarkType.rightKnee, _midline + 0.08, 0.74, rightLikelihood),
    LandmarkType.rightAnkle:
        p(LandmarkType.rightAnkle, _midline + 0.08, 0.90, rightLikelihood),
  });
}

/// Whether the drawn figure is its own mirror image about the mid-line.
///
/// Every point is reflected and matched to a partner in the original set. The
/// old code could produce nothing else, because it drew one chain twice.
bool isMirrorSymmetric(SilhouetteFigure figure, {double tolerance = 1e-6}) {
  final points = figure.joints;
  for (final o in points) {
    final reflected = Offset(2 * _midline - o.dx, o.dy);
    final hasPartner = points.any((q) =>
        (q.dx - reflected.dx).abs() <= tolerance &&
        (q.dy - reflected.dy).abs() <= tolerance);
    if (!hasPartner) return false;
  }
  return true;
}

/// Drawn points that are unambiguously a raised arm.
///
/// Above the shoulder line and clear of the mid-line: the second condition is
/// what excludes the head and the neck, which also sit above the shoulders and
/// which are not evidence about arms either way.
List<Offset> raisedArmPoints(SilhouetteFigure figure) => [
      for (final o in figure.joints)
        if (o.dy < 0.25 && (o.dx - _midline).abs() > 0.05) o,
    ];

void main() {
  group('one raised arm is drawn as one raised arm', () {
    test('CONTROL: a body with both arms down is drawn symmetric', () {
      // Without this the asymmetry assertions below would pass for a figure
      // that is asymmetric by accident — a rounding artefact, a stray joint —
      // rather than because an arm moved.
      final figure = buildPoseAvatar(facingCamera());

      expect(isMirrorSymmetric(figure), isTrue,
          reason: 'nothing about this body distinguishes its two sides');
      expect(raisedArmPoints(figure), isEmpty,
          reason: 'both arms are down, so nothing may be drawn above the '
              'shoulders away from the mid-line');
    });

    test('raising the right arm raises exactly one arm, on the right', () {
      final figure = buildPoseAvatar(facingCamera(raise: LandmarkSide.right));

      final raised = raisedArmPoints(figure);
      expect(raised, isNotEmpty,
          reason: 'the arm the detector saw raised must appear raised');
      expect(raised.every((o) => o.dx > _midline), isTrue,
          reason: 'ONE arm went up. Points above the shoulders on both sides '
              'of the body is the defect this file exists for');
      expect(isMirrorSymmetric(figure), isFalse);
    });

    test('and raising the left arm raises exactly one arm, on the left', () {
      // The mirror of the case above, and not a formality: a fix that
      // hard-coded "believe the right chain" would pass the previous test and
      // fail this one, and it would reproduce the operator's report exactly —
      // one arm works, the other does nothing.
      final figure = buildPoseAvatar(facingCamera(raise: LandmarkSide.left));

      final raised = raisedArmPoints(figure);
      expect(raised, isNotEmpty);
      expect(raised.every((o) => o.dx < _midline), isTrue);
      expect(isMirrorSymmetric(figure), isFalse);
    });

    test('the raised side does not depend on which side is more confident', () {
      // The old code picked by summed likelihood, so the drawn figure changed
      // with the detector's confidence rather than with the body. That is why
      // which arm "worked" moved as the user moved. Both confidences are varied
      // here while the same arm stays raised.
      for (final (left, right) in const [(0.95, 0.60), (0.60, 0.95)]) {
        final figure = buildPoseAvatar(facingCamera(
          raise: LandmarkSide.right,
          leftLikelihood: left,
          rightLikelihood: right,
        ));

        final raised = raisedArmPoints(figure);
        expect(raised, isNotEmpty, reason: 'confidences $left/$right');
        expect(raised.every((o) => o.dx > _midline), isTrue,
            reason: 'the body did not change between these two frames, so the '
                'drawing must not either (confidences $left/$right)');
      }
    });
  });

  group('the side view is unchanged, and that is what protects the targets',
      () {
    test('an authored target still draws a symmetric figure', () {
      // Every shipped target is a mid-line side view: `pose_target.dart`
      // contains no right-keyed joint at all. So they take the mirrored path by
      // construction and cannot reach the branch above. This asserts the
      // consequence rather than the grep.
      final target = squatBottomTarget;
      final figure = buildSilhouette(target);

      expect(figure.limbs, isNotEmpty);
      expect(
        target.joints.keys.any((t) => t.name.startsWith('right')),
        isFalse,
        reason: 'if a right-keyed joint is ever authored, this figure stops '
            'being mirrored and the test below stops meaning anything',
      );
    });

    test('a body seen side-on is still drawn with two arms', () {
      // Side-on, both shoulders land on the same point. The far chain is then
      // either believed — and coincides with the near one — or dropped. Neither
      // may produce a one-armed figure.
      final sideOn = facingCamera(halfSeparation: 0.0);
      final figure = buildPoseAvatar(sideOn);

      expect(figure.limbs.length, 5,
          reason: 'two arms, two legs and a neck, as before this change');
      expect(isMirrorSymmetric(figure), isTrue,
          reason: 'a mid-line body has no asymmetry to draw');
    });

    test('a far limb the detector lost is reflected, not stacked', () {
      // Two-sided torso, but the far arm fell below the likelihood floor. The
      // surviving arm has to be reflected across the spine to stand in for it.
      // Translating it instead — which is what the mirrored path does — would
      // put both arms on the same side of the body.
      final frame = facingCamera();
      final missingFarArm = PoseFrame(
        timestampMs: 0,
        landmarks: {
          for (final e in frame.landmarks.entries)
            if (e.key != LandmarkType.rightElbow &&
                e.key != LandmarkType.rightWrist)
              e.key: e.value,
        },
      );

      final figure = buildPoseAvatar(missingFarArm);
      final arms = [
        for (final o in figure.joints)
          if (o.dy > 0.33 && o.dy < 0.60) o,
      ];

      expect(arms.where((o) => o.dx < _midline), isNotEmpty);
      expect(arms.where((o) => o.dx > _midline), isNotEmpty,
          reason: 'the lost arm must be replaced on its own side of the body');
    });
  });

  test('a body turning on the spot changes width continuously', () {
    // The earlier plan for this fix was a stance discriminator with hysteresis,
    // because a hard switch between "mirrored" and "two-sided" would flip the
    // figure frame to frame near the boundary — the flicker class Gate A
    // existed to remove.
    //
    // There is no boundary to flicker across. The widening applied to each side
    // is whatever the observation is SHORT of a body's width, so it falls to
    // zero exactly as the real separation reaches it. This measures that: the
    // drawn shoulder width over a body rotating from face-on to side-on must
    // never jump.
    double drawnShoulderWidth(double halfSeparation) {
      final figure =
          buildPoseAvatar(facingCamera(halfSeparation: halfSeparation));
      // `torso` is wound leftShoulder, rightShoulder, ... — the first two
      // points are the drawn corners.
      return (figure.torso[0].dx - figure.torso[1].dx).abs();
    }

    var previous = drawnShoulderWidth(0.0);
    for (var i = 1; i <= 40; i++) {
      final width = drawnShoulderWidth(i * 0.005);
      expect((width - previous).abs(), lessThan(0.02),
          reason: 'shoulder width jumped between separations '
              '${(i - 1) * 0.005} and ${i * 0.005}: $previous -> $width');
      previous = width;
    }

    expect(drawnShoulderWidth(0.20), greaterThan(drawnShoulderWidth(0.0)),
        reason: 'a body presenting its full width must be drawn wider than a '
            'body edge-on, or the observation is being ignored');
  });
}
