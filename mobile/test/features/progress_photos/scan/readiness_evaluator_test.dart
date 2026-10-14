import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/progress_photos/scan/readiness_evaluator.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';

const aspect = 0.5625; // 9:16 portrait, isotropic frame space

PoseLandmark lm(LandmarkType t, double x, double y, [double l = 0.95]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: l);

PoseFrame frameOf(Map<LandmarkType, PoseLandmark> ls) =>
    PoseFrame(timestampMs: 0, aspectRatio: aspect, landmarks: ls);

/// A standing adult of estimated height [h] (frame fractions), crown at [top],
/// centred on [cx]. [spread] scales the left-right extents: 1 = facing the
/// camera, ~0.05 = profile.
PoseFrame body({
  double h = 0.75,
  double top = 0.10,
  double cx = aspect / 2,
  double spread = 1.0,
  double nose = 0.95,
  double ears = 0.95,
  double farSide = 0.95,
}) {
  final shoulderY = top + 0.18 * h;
  final hipY = shoulderY + 0.29 * h;
  final kneeY = shoulderY + 0.52 * h;
  final ankleY = shoulderY + 0.78 * h;
  final sw = 0.115 * h * 1.5 * spread; // half shoulder width
  final hw = 0.07 * h * 1.5 * spread;
  final kw = 0.06 * h * 1.5 * spread;
  return frameOf({
    LandmarkType.nose: lm(LandmarkType.nose, cx, top + 0.05 * h, nose),
    LandmarkType.leftEar:
        lm(LandmarkType.leftEar, cx - 0.03, top + 0.04 * h, ears),
    LandmarkType.rightEar:
        lm(LandmarkType.rightEar, cx + 0.03, top + 0.04 * h, ears),
    LandmarkType.leftShoulder:
        lm(LandmarkType.leftShoulder, cx - sw, shoulderY),
    LandmarkType.rightShoulder:
        lm(LandmarkType.rightShoulder, cx + sw, shoulderY, farSide),
    LandmarkType.leftHip: lm(LandmarkType.leftHip, cx - hw, hipY),
    LandmarkType.rightHip: lm(LandmarkType.rightHip, cx + hw, hipY, farSide),
    LandmarkType.leftKnee: lm(LandmarkType.leftKnee, cx - kw, kneeY),
    LandmarkType.rightKnee:
        lm(LandmarkType.rightKnee, cx + kw, kneeY, farSide),
    LandmarkType.leftAnkle: lm(LandmarkType.leftAnkle, cx - kw, ankleY),
    LandmarkType.rightAnkle:
        lm(LandmarkType.rightAnkle, cx + kw, ankleY, farSide),
  });
}

PoseFrame side({double nose = 0.9, double ears = 0.9}) =>
    body(spread: 0.05, nose: nose, ears: ears, farSide: 0.3);

const ev = ReadinessEvaluator();
ReadinessResult run(PoseFrame? f, ScanPose p,
        {double? lum = 0.5, bool away = false}) =>
    ev.evaluate(
        frame: f, luminance: lum, pose: p, userConfirmsFacingAway: away);

void main() {
  group('front pose', () {
    test('good frame is ready with no hint', () {
      final r = run(body(), ScanPose.front);
      expect(r.isReady, isTrue, reason: '${r.hint} ${r.shoulderRatio}');
      expect(r.hint, ReadinessHint.none);
      expect(r.heightFraction, closeTo(0.75, 1e-6));
    });

    test('too small -> stepCloser (distance fail only)', () {
      final r = run(body(h: 0.45, top: 0.25), ScanPose.front);
      expect(r.distance, CheckStatus.fail);
      expect(r.hint, ReadinessHint.stepCloser);
      expect(r.isReady, isFalse);
    });

    test('too big for the band -> stepBack', () {
      final r = run(body(h: 0.93, top: 0.03), ScanPose.front);
      expect(r.hint, ReadinessHint.stepBack);
    });

    test('feet cropped by the bottom edge -> stepBack', () {
      final r = run(body(top: 0.25), ScanPose.front);
      expect(r.distance, CheckStatus.fail);
      expect(r.hint, ReadinessHint.stepBack);
    });

    test('legs not visible but torso is -> stepBack, not centering advice', () {
      final ls = Map.of(body().landmarks)
        ..remove(LandmarkType.leftAnkle)
        ..remove(LandmarkType.rightAnkle);
      final r = run(frameOf(ls), ScanPose.front);
      expect(r.hint, ReadinessHint.stepBack);
      expect(r.isReady, isFalse);
    });

    test('off-centre -> centerYourself', () {
      final r = run(body(cx: 0.40), ScanPose.front);
      expect(r.position, CheckStatus.fail);
      expect(r.distance, CheckStatus.pass);
      expect(r.hint, ReadinessHint.centerYourself);
    });

    test('shoulders and hips invisible -> showFullBody', () {
      final ls = {
        for (final e in body().landmarks.entries)
          e.key: lm(e.key, e.value.x, e.value.y, 0.1),
      };
      final r = run(frameOf(ls), ScanPose.front);
      expect(r.hint, ReadinessHint.showFullBody);
      expect(r.distance, CheckStatus.unknown);
    });

    test('no frame at all is not ready', () {
      final r = run(null, ScanPose.front);
      expect(r.isReady, isFalse);
      expect(r.hint, ReadinessHint.showFullBody);
    });

    test('profile while front is requested -> faceCamera', () {
      final r = run(side(), ScanPose.front);
      expect(r.orientation, CheckStatus.fail);
      expect(r.hint, ReadinessHint.faceCamera);
    });

    test('wide shoulders but no face fails front (documented heuristic)', () {
      final r = run(body(nose: 0.1), ScanPose.front);
      expect(r.hint, ReadinessHint.faceCamera);
    });

    test('requireFaceForFront=false lets a faceless front pass', () {
      const e = ReadinessEvaluator(
          config: ReadinessConfig(requireFaceForFront: false));
      final r = e.evaluate(
          frame: body(nose: 0.1), luminance: 0.5, pose: ScanPose.front);
      expect(r.isReady, isTrue);
    });
  });

  group('lighting', () {
    test('dark -> moreLight and it outranks other failures', () {
      final r = run(body(h: 0.45, top: 0.25), ScanPose.front, lum: 0.10);
      expect(r.lighting, CheckStatus.fail);
      expect(r.distance, CheckStatus.fail);
      expect(r.hint, ReadinessHint.moreLight);
    });

    test('blown-out -> lessLight', () {
      expect(run(body(), ScanPose.front, lum: 0.97).hint,
          ReadinessHint.lessLight);
    });

    test('unknown luminance is not ready', () {
      final r = run(body(), ScanPose.front, lum: null);
      expect(r.lighting, CheckStatus.unknown);
      expect(r.isReady, isFalse);
    });

    test('boundary: exactly minLuminance passes', () {
      expect(run(body(), ScanPose.front, lum: 0.25).isReady, isTrue);
    });
  });

  group('side pose', () {
    test('profile with far-side joints occluded is ready', () {
      final r = run(side(), ScanPose.side);
      expect(r.isReady, isTrue, reason: '${r.hint} ${r.shoulderRatio}');
    });

    test('facing the camera while side requested -> turnSideways', () {
      final r = run(body(), ScanPose.side);
      expect(r.orientation, CheckStatus.fail);
      expect(r.hint, ReadinessHint.turnSideways);
    });

    test('profile with no head landmark at all is not ready', () {
      expect(run(side(nose: 0.05, ears: 0.05), ScanPose.side).isReady, isFalse);
    });
  });

  group('back pose', () {
    test('face absent + wide shoulders is ready', () {
      final r = run(body(nose: 0.05), ScanPose.back);
      expect(r.isReady, isTrue, reason: '${r.hint}');
    });

    test('face visible, no confirmation -> turnAround', () {
      final r = run(body(), ScanPose.back);
      expect(r.hint, ReadinessHint.turnAround);
    });

    test('user confirmation overrides a hallucinated face', () {
      final r = run(body(nose: 0.95), ScanPose.back, away: true);
      expect(r.isReady, isTrue);
    });

    test('confirmation does not excuse a profile', () {
      final r = run(side(), ScanPose.back, away: true);
      expect(r.hint, ReadinessHint.turnAround);
    });

    test('confirmation flag is ignored for front', () {
      final r = run(body(nose: 0.05), ScanPose.front, away: true);
      expect(r.isReady, isFalse);
    });
  });

  test('broken coordinate unit is reported as trackingProblem', () {
    final ls = {
      for (final e in body().landmarks.entries)
        e.key: lm(e.key, e.value.x * 600, e.value.y * 600),
    };
    final r = run(frameOf(ls), ScanPose.front);
    expect(r.hint, ReadinessHint.trackingProblem);
    expect(r.isReady, isFalse);
  });
}
