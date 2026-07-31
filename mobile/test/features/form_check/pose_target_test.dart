import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';

/// Matching a body against a target shape.
///
/// This replaces two rules that were withdrawn for the same reason: both asked
/// whether technique was correct by reading an absolute number out of a 2D
/// projection, and in both cases correct and incorrect execution produced
/// overlapping numbers. The properties below are what make this different --
/// and if any of them stops holding, the approach is back to being a threshold
/// in disguise.

PoseFrame frameFrom(Map<LandmarkType, (double, double)> joints,
        {double likelihood = 0.95}) =>
    PoseFrame(timestampMs: 0, landmarks: {
      for (final e in joints.entries)
        e.key: PoseLandmark(
          type: e.key,
          x: e.value.$1,
          y: e.value.$2,
          likelihood: likelihood,
        ),
    });

/// The target's own joints, optionally moved and resized as a rigid body.
PoseFrame poseOf(PoseTarget t,
    {double dx = 0, double dy = 0, double scale = 1}) {
  return frameFrom({
    for (final e in t.joints.entries)
      e.key: (e.value.$1 * scale + dx, e.value.$2 * scale + dy),
  });
}

void main() {
  group('the score means what it claims', () {
    test('the target matched exactly scores 1', () {
      expect(poseMatchScore(poseOf(squatBottomTarget), squatBottomTarget),
          closeTo(1.0, 1e-9));
    });

    test('standing somewhere else scores exactly the same', () {
      // Translation invariance. Without it the user would have to stand on a
      // specific spot on the floor, and every step sideways would read as bad
      // technique.
      final moved = poseOf(squatBottomTarget, dx: 0.21, dy: -0.13);
      expect(poseMatchScore(moved, squatBottomTarget), closeTo(1.0, 1e-9));
    });

    test('standing closer or further away scores exactly the same', () {
      // Scale invariance -- the property whose ABSENCE broke the depth rule.
      // Camera distance changed every number that rule compared.
      for (final s in [0.4, 0.75, 1.6, 2.5]) {
        final resized = poseOf(squatBottomTarget, scale: s, dx: 0.1);
        expect(poseMatchScore(resized, squatBottomTarget), closeTo(1.0, 1e-9),
            reason: 'scale $s must not change the verdict');
      }
    });

    test('standing tall does NOT match the bottom of a squat', () {
      // The discriminating case. If this scored high the whole idea is
      // decorative: the top and the bottom of a squat are the two poses the
      // coach most needs to tell apart.
      final score = poseMatchScore(poseOf(squatTopTarget), squatBottomTarget);
      expect(score, isNotNull);
      expect(score!, lessThan(kPoseMatchPassing),
          reason: 'a standing body scored ${score.toStringAsFixed(2)} against '
              'the bottom position');
    });

    test('a genuinely shallow squat FAILS', () {
      // The case that decides whether this feature is worth anything. Operator,
      // on the build that stopped judging: "все повторения правильные даже если
      // я неправильно делаю". Silence was the honest answer while the coach had
      // no target to compare against; it is not an acceptable resting place.
      //
      // Hips well above knees, torso upright — the fault the old depth rule was
      // trying and failing to detect.
      final shallow = frameFrom({
        LandmarkType.leftShoulder: (0.49, 0.36),
        LandmarkType.leftElbow: (0.50, 0.48),
        LandmarkType.leftWrist: (0.51, 0.60),
        LandmarkType.leftHip: (0.48, 0.62),
        LandmarkType.leftKnee: (0.52, 0.75),
        LandmarkType.leftAnkle: (0.49, 0.93),
      });
      final score = poseMatchScore(shallow, squatBottomTarget)!;
      expect(score, lessThan(kPoseMatchPassing),
          reason: 'scored ${score.toStringAsFixed(2)} — a half squat must not '
              'be accepted as a full one');
    });

    test('the passing threshold is not a knife edge', () {
      // A separation this narrow would mean the measure is not really
      // distinguishing the poses, just landing near the line. Both withdrawn
      // rules failed exactly here: correct and incorrect execution differed by
      // less than the noise.
      final good = poseMatchScore(
          frameFrom({
            LandmarkType.leftShoulder: (0.54, 0.50),
            LandmarkType.leftElbow: (0.55, 0.63),
            LandmarkType.leftWrist: (0.59, 0.71),
            LandmarkType.leftHip: (0.41, 0.76),
            LandmarkType.leftKnee: (0.58, 0.73),
            LandmarkType.leftAnkle: (0.50, 0.94),
          }),
          squatBottomTarget)!;
      final bad = poseMatchScore(poseOf(squatTopTarget), squatBottomTarget)!;
      expect(good - bad, greaterThan(0.4),
          reason: 'good=${good.toStringAsFixed(2)} bad=${bad.toStringAsFixed(2)}'
              ' — the gap between a real rep and a non-rep must be wide');
    });

    test('a push-up does not pass as a squat', () {
      final score = poseMatchScore(poseOf(pushupTopTarget), squatBottomTarget);
      expect(score!, lessThan(kPoseMatchPassing));
    });

    test('a nearly-right squat still passes', () {
      // The threshold has to admit real bodies, which are never exact. Every
      // joint nudged, in different directions.
      final wobbled = frameFrom({
        LandmarkType.leftShoulder: (0.54, 0.50),
        LandmarkType.leftElbow: (0.55, 0.63),
        LandmarkType.leftWrist: (0.59, 0.71),
        LandmarkType.leftHip: (0.41, 0.76),
        LandmarkType.leftKnee: (0.58, 0.73),
        LandmarkType.leftAnkle: (0.50, 0.94),
      });
      final score = poseMatchScore(wobbled, squatBottomTarget);
      expect(score!, greaterThanOrEqualTo(kPoseMatchPassing),
          reason: 'scored ${score.toStringAsFixed(2)}; a real body that is '
              'clearly in position must not be failed for being human');
    });
  });

  group('it refuses to guess', () {
    test('too few shared joints returns null, not a low score', () {
      // "Your knee is out of shot" and "your form is wrong" are different
      // statements. Reporting the first as the second is the failure this
      // whole feature exists to stop making.
      final partial = frameFrom({
        LandmarkType.leftShoulder: (0.5, 0.5),
        LandmarkType.leftHip: (0.5, 0.7),
      });
      expect(poseMatchScore(partial, squatBottomTarget), isNull);
    });

    test('three joints is still a fragment, not a pose', () {
      final three = frameFrom({
        LandmarkType.leftShoulder: (0.5, 0.5),
        LandmarkType.leftHip: (0.5, 0.7),
        LandmarkType.leftKnee: (0.5, 0.8),
      });
      expect(poseMatchScore(three, squatBottomTarget), isNull,
          reason: 'normalisation can fit any three points onto any other '
              'three well enough to look like a match');
    });

    test('low-confidence joints do not count towards the shape', () {
      final unsure = poseOf(squatBottomTarget);
      final degraded = PoseFrame(
        timestampMs: 0,
        landmarks: {
          for (final e in unsure.landmarks.entries)
            e.key: PoseLandmark(
              type: e.key,
              x: e.value.x,
              y: e.value.y,
              likelihood: 0.2,
            ),
        },
      );
      expect(poseMatchScore(degraded, squatBottomTarget), isNull);
    });

    test('a body collapsed to a point has no shape to compare', () {
      final collapsed = frameFrom({
        for (final k in squatBottomTarget.joints.keys) k: (0.5, 0.5),
      });
      expect(poseMatchScore(collapsed, squatBottomTarget), isNull);
    });
  });

  group('every target is drawable and self-consistent', () {
    test('every target carries enough joints to be scorable at all', () {
      // The constructor cannot assert this — const expressions cannot read
      // Map.length — so it is checked here, across every shipped target. A
      // target with three joints would silently return null forever, which
      // reads on screen as "the coach cannot see you" for a target that is
      // simply malformed.
      for (final t in [squatTopTarget, squatBottomTarget, pushupTopTarget]) {
        expect(t.joints.length, greaterThanOrEqualTo(4), reason: t.id);
      }
    });

    test('bones only connect joints the target actually has', () {
      for (final t in [squatTopTarget, squatBottomTarget, pushupTopTarget]) {
        for (final (a, b) in t.bones) {
          expect(t.joints.keys, contains(a), reason: '${t.id} bone start');
          expect(t.joints.keys, contains(b), reason: '${t.id} bone end');
        }
      }
    });

    test('targets sit inside a portrait frame, so they can be drawn', () {
      // Scoring normalises these away, but the same numbers are painted on
      // screen as the outline to stand in.
      for (final t in [squatTopTarget, squatBottomTarget, pushupTopTarget]) {
        for (final j in t.joints.values) {
          expect(j.$1, inInclusiveRange(0.0, 1.0), reason: t.id);
          expect(j.$2, inInclusiveRange(0.0, 1.0), reason: t.id);
        }
      }
    });

    test('the two squat phases are genuinely different shapes', () {
      // Guards the targets themselves, not the maths: if someone edits these
      // numbers until the two phases converge, rep detection against them
      // becomes meaningless and nothing else would notice.
      final score = poseMatchScore(poseOf(squatTopTarget), squatBottomTarget)!;
      expect(score, lessThan(0.6),
          reason: 'top vs bottom scored ${score.toStringAsFixed(2)}');
    });
  });
}
