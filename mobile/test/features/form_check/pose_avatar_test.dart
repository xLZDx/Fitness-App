import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_avatar.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';

/// The live pose, turned into a body.
///
/// Every assertion here is about a decision that was made deliberately in
/// `pose_avatar.dart` and would be silently reversible without one: which side
/// is believed, what happens to a coordinate the detector invented, and what
/// happens when there is no torso.

PoseLandmark p(
  LandmarkType t,
  double x,
  double y, [
  double likelihood = 0.95,
]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: likelihood);

/// A standing body, side-on, with both sides reported — the near one confident
/// and the far one whatever [farLikelihood] says.
PoseFrame standing({double farLikelihood = 0.95, double farOffset = 0.0}) =>
    PoseFrame(timestampMs: 0, landmarks: {
      LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.50, 0.30),
      LandmarkType.leftElbow: p(LandmarkType.leftElbow, 0.50, 0.44),
      LandmarkType.leftWrist: p(LandmarkType.leftWrist, 0.50, 0.56),
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.50, 0.58),
      LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.50, 0.74),
      LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.50, 0.90),
      LandmarkType.rightShoulder:
          p(LandmarkType.rightShoulder, 0.50 + farOffset, 0.30, farLikelihood),
      LandmarkType.rightElbow:
          p(LandmarkType.rightElbow, 0.50 + farOffset, 0.44, farLikelihood),
      LandmarkType.rightWrist:
          p(LandmarkType.rightWrist, 0.50 + farOffset, 0.56, farLikelihood),
      LandmarkType.rightHip:
          p(LandmarkType.rightHip, 0.50 + farOffset, 0.58, farLikelihood),
      LandmarkType.rightKnee:
          p(LandmarkType.rightKnee, 0.50 + farOffset, 0.74, farLikelihood),
      LandmarkType.rightAnkle:
          p(LandmarkType.rightAnkle, 0.50 + farOffset, 0.90, farLikelihood),
    });

void main() {
  group('a body is produced at all', () {
    test('POSITIVE CONTROL: a standing pose becomes a figure with a head', () {
      // Without this, every "nothing was drawn" assertion below passes for the
      // wrong reason.
      final figure = buildPoseAvatar(standing());

      expect(figure.head, isNotNull);
      expect(figure.torso, isNotEmpty);
      expect(figure.limbs, isNotEmpty,
          reason: 'the filled outlines are what makes this a body rather than '
              'a stick figure');
      expect(figure.bounds.height, greaterThan(0));
    });

    test('the figure has both arms and both legs from one side of the body',
        () {
      // Four limbs plus a neck, each a closed outline. The input carried one
      // usable side; mirroring is what puts the other one on screen.
      final figure = buildPoseAvatar(standing());

      expect(figure.limbs.length, 5,
          reason: 'two arms, two legs and a neck, mirrored from one side');
      for (final outline in figure.limbs) {
        expect(outline.length, greaterThanOrEqualTo(4),
            reason: 'a closed outline needs a side and a side back');
      }
    });
  });

  group('which side is believed', () {
    test('the confident side wins over the guessed one', () {
      // The far side is reported at every joint but the detector has no
      // confidence in any of them: the signature of a limb behind the body.
      // Its coordinates are displaced, so believing it would be visible.
      final t = avatarTargetFrom(standing(farLikelihood: 0.2, farOffset: 0.30));

      expect(t, isNotNull);
      expect(t!.joints[LandmarkType.leftShoulder]?.$1, closeTo(0.50, 1e-9),
          reason: 'the near shoulder at x=0.50, not the far one at x=0.80');
    });

    test('and the reverse, so this is a comparison and not a hard-coded side',
        () {
      // The same frame with the confidence swapped has to choose the other
      // side. A test that only ever proves "left wins" would pass just as well
      // against `return _leftChain;`.
      final frame = PoseFrame(timestampMs: 0, landmarks: {
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.50, 0.30, 0.2),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.50, 0.58, 0.2),
        LandmarkType.rightShoulder:
            p(LandmarkType.rightShoulder, 0.80, 0.30, 0.95),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.80, 0.58, 0.95),
      });

      final t = avatarTargetFrom(frame);

      expect(t, isNotNull);
      expect(t!.joints[LandmarkType.leftShoulder]?.$1, closeTo(0.80, 1e-9),
          reason: 'the right side was the confident one and must be re-keyed '
              'onto the left, which is the side buildSilhouette reads');
    });
  });

  group('coordinates that cannot be drawn', () {
    test('a joint far outside the contract is dropped, not drawn', () {
      // The real measurement from a phone: x ran to 1.968 against a bound of
      // 0.667. In a closed filled outline that point does not misplace a limb,
      // it tears the body open.
      final frame = PoseFrame(timestampMs: 0, aspectRatio: 0.5625, landmarks: {
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.28, 0.30),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.28, 0.58),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.28, 0.74),
        LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 1.968, 0.90),
      });

      final t = avatarTargetFrom(frame);

      expect(t, isNotNull, reason: 'the torso was fine; only the ankle was not');
      expect(t!.joints.containsKey(LandmarkType.leftAnkle), isFalse);
      expect(t.joints.containsKey(LandmarkType.leftKnee), isTrue,
          reason: 'one bad joint must not discard the ones around it');
    });

    test('a joint just past the frame edge is kept', () {
      // BlazePose extrapolates a joint slightly outside the picture rather than
      // omitting it, and an ankle just below the bottom edge is a real ankle.
      // Rejecting it would delete the feet of everyone standing close.
      final frame = PoseFrame(timestampMs: 0, landmarks: {
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.50, 0.30),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.50, 0.58),
        LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.50, 1.04),
      });

      final t = avatarTargetFrom(frame);

      expect(t?.joints.containsKey(LandmarkType.leftAnkle), isTrue);
    });

    test('a NaN coordinate is dropped rather than compared', () {
      final frame = PoseFrame(timestampMs: 0, landmarks: {
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.50, 0.30),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.50, 0.58),
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, double.nan, 0.74),
      });

      final t = avatarTargetFrom(frame);

      expect(t?.joints.containsKey(LandmarkType.leftKnee), isFalse);
    });
  });

  group('nothing is drawn rather than something wrong', () {
    test('an empty frame produces no figure', () {
      // This is the frame the detector now sends when it finds nobody.
      final figure = buildPoseAvatar(
        const PoseFrame(timestampMs: 0, landmarks: {}),
      );

      expect(figure.head, isNull);
      expect(figure.limbs, isEmpty);
      expect(figure.torso, isEmpty);
    });

    test('a frame with no torso produces no figure, however many limbs it has',
        () {
      // Without a shoulder and a hip there is no spine, so there is no axis to
      // mirror about and nothing that would read as a person.
      final frame = PoseFrame(timestampMs: 0, landmarks: {
        LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.50, 0.74),
        LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.50, 0.90),
        LandmarkType.rightKnee: p(LandmarkType.rightKnee, 0.55, 0.74),
        LandmarkType.rightAnkle: p(LandmarkType.rightAnkle, 0.55, 0.90),
      });

      expect(avatarTargetFrom(frame), isNull);
      expect(buildPoseAvatar(frame).head, isNull);
    });

    test('a torso the detector is only guessing at produces no figure', () {
      final frame = PoseFrame(timestampMs: 0, landmarks: {
        LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.50, 0.30, 0.2),
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.50, 0.58, 0.2),
        LandmarkType.rightShoulder:
            p(LandmarkType.rightShoulder, 0.55, 0.30, 0.2),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.55, 0.58, 0.2),
      });

      expect(avatarTargetFrom(frame), isNull);
    });
  });

  test('the figure follows the pose rather than being a fixed drawing', () {
    // The whole point of a live avatar. Two different poses must not produce
    // the same body.
    final tall = buildPoseAvatar(standing());
    final crouched = buildPoseAvatar(PoseFrame(timestampMs: 0, landmarks: {
      LandmarkType.leftShoulder: p(LandmarkType.leftShoulder, 0.50, 0.50),
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.50, 0.70),
      LandmarkType.leftKnee: p(LandmarkType.leftKnee, 0.62, 0.74),
      LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.50, 0.90),
    }));

    expect(crouched.head, isNotNull);
    expect(crouched.bounds.height, lessThan(tall.bounds.height),
        reason: 'a crouch occupies less height than standing tall');
  });
}
