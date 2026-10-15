// T25 face_region_test (PRIV-01, PRIV-03 geometry half). The blur region must
// cover the head, and when it cannot be established the verdict FAILS CLOSED.
// Rectangles are hand-derived from design s9:
//   head box half-side = 1.5 * r, margin 15 %, extra headroom 0.3 * r * 1.15,
//   r = max(1.35 * maxDistFromHeadCentroid, 0.40 * shoulderWidth).
import 'dart:math' as math;

import 'package:fitness_app/features/body_scan/data/face_region.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:flutter_test/flutter_test.dart';

PoseLandmark _lm(LandmarkType t, double x, double y, [double p = 0.9]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: p);

PoseFrame _frame(List<PoseLandmark> l, {double aspect = 1.0}) => PoseFrame(
      timestampMs: 0,
      aspectRatio: aspect,
      landmarks: {for (final p in l) p.type: p},
    );

FrameRect _region(FaceRegionVerdict v) {
  expect(v.safe, isTrue, reason: 'expected a region, got ${v.failure}');
  return v.region!;
}

void expectRect(FrameRect r, double l, double t, double rt, double b,
    [double eps = 1e-4]) {
  expect(r.left, closeTo(l, eps), reason: 'left');
  expect(r.top, closeTo(t, eps), reason: 'top');
  expect(r.right, closeTo(rt, eps), reason: 'right');
  expect(r.bottom, closeTo(b, eps), reason: 'bottom');
}

final _shoulders = [
  _lm(LandmarkType.leftShoulder, 0.4, 0.35),
  _lm(LandmarkType.rightShoulder, 0.6, 0.35),
];

void main() {
  group('head landmarks present', () {
    test('nose + two ears, shoulder width 0.2: r = 0.08, box 0.362/0.0344/0.638/0.338', () {
      // centroid (0.5, 0.2); spread 0.05 -> 0.0675 < 0.4 * 0.2 = 0.08 -> r 0.08
      // half = 1.5 * 0.08 * 1.15 = 0.138; headroom 0.3 * 0.08 * 1.15 = 0.0276
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.nose, 0.5, 0.2),
        _lm(LandmarkType.leftEar, 0.45, 0.2),
        _lm(LandmarkType.rightEar, 0.55, 0.2),
        ..._shoulders,
      ]));
      expectRect(_region(v), 0.362, 0.0344, 0.638, 0.338);
    });
    test('a wide head spread dominates the shoulders: ears 0.2 apart -> r 0.135', () {
      // spread 0.1 * 1.35 = 0.135; half 1.725 * 0.135 = 0.232875;
      // headroom 0.345 * 0.135 = 0.046575 -> top would be negative: clamped to 0.
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.nose, 0.5, 0.2),
        _lm(LandmarkType.leftEar, 0.4, 0.2),
        _lm(LandmarkType.rightEar, 0.6, 0.2),
        ..._shoulders,
      ]));
      expectRect(_region(v), 0.267125, 0.0, 0.732875, 0.432875);
    });
    test('head likelihood 0.29 is ignored, 0.30 is used', () {
      List<PoseLandmark> withEars(double p) => [
            _lm(LandmarkType.nose, 0.5, 0.2),
            _lm(LandmarkType.leftEar, 0.3, 0.2, p),
            _lm(LandmarkType.rightEar, 0.7, 0.2, p),
            ..._shoulders,
          ];
      // ignored: only the nose -> r = 0.08, the small box of the first test.
      expectRect(_region(computeFaceRegion(_frame(withEars(0.29)))), 0.362,
          0.0344, 0.638, 0.338);
      // used: spread 0.2 -> r 0.27 -> half 0.46575, headroom 0.09315.
      final big = _region(computeFaceRegion(_frame(withEars(0.30))));
      expectRect(big, 0.03425, 0.0, 0.96575, 0.66575);
    });
    test('the box contains every head landmark (property over varied poses)', () {
      final rnd = math.Random(7);
      for (var i = 0; i < 50; i++) {
        final cx = 0.2 + rnd.nextDouble() * 0.6;
        final cy = 0.1 + rnd.nextDouble() * 0.3;
        final d = 0.01 + rnd.nextDouble() * 0.12;
        final pts = [
          _lm(LandmarkType.nose, cx, cy),
          _lm(LandmarkType.leftEar, cx - d, cy - d / 3),
          _lm(LandmarkType.rightEar, cx + d, cy + d / 3),
          _lm(LandmarkType.leftShoulder, cx - 0.1, cy + 0.15),
          _lm(LandmarkType.rightShoulder, cx + 0.1, cy + 0.15),
        ];
        final r = _region(computeFaceRegion(_frame(pts)));
        for (final p in pts.take(3)) {
          expect(p.x, greaterThanOrEqualTo(r.left), reason: 'run $i');
          expect(p.x, lessThanOrEqualTo(r.right), reason: 'run $i');
          expect(p.y, greaterThanOrEqualTo(r.top), reason: 'run $i');
          expect(p.y, lessThanOrEqualTo(r.bottom), reason: 'run $i');
        }
      }
    });
    test('only a nose and no shoulders: radius 0 -> cannotSize (fail closed)', () {
      final v = computeFaceRegion(_frame([_lm(LandmarkType.nose, 0.5, 0.2)]));
      expect(v.safe, isFalse);
      expect(v.failure, FaceRegionFailure.cannotSize);
      expect(v.region, isNull);
    });
    test('one shoulder hidden: width = 0.45 * torso (same-side hip) -> r 0.07209', () {
      // torso = hypot(0.02, 0.4) = 0.4004997; width 0.180225; r = 0.072090;
      // half = 0.124355, headroom 0.024871 around the nose (0.5, 0.2).
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.nose, 0.5, 0.2),
        _lm(LandmarkType.leftShoulder, 0.4, 0.3),
        _lm(LandmarkType.rightShoulder, 0.6, 0.3, 0.1), // hidden
        _lm(LandmarkType.leftHip, 0.42, 0.7),
      ]));
      expectRect(_region(v), 0.375645, 0.050774, 0.624355, 0.324355);
    });
    test('one shoulder hidden and no usable hip: cannot size', () {
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.nose, 0.5, 0.2),
        _lm(LandmarkType.leftShoulder, 0.4, 0.3),
        _lm(LandmarkType.leftHip, 0.42, 0.7, 0.1),
      ]));
      expect(v.failure, FaceRegionFailure.cannotSize);
    });
    test('the box is clamped to the image: left/top at 0', () {
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.nose, 0.02, 0.03),
        _lm(LandmarkType.leftShoulder, 0.0, 0.4),
        _lm(LandmarkType.rightShoulder, 0.4, 0.4),
      ]));
      // r = 0.4 * 0.4 = 0.16; half 0.276; headroom 0.0552
      expectRect(_region(v), 0.0, 0.0, 0.296, 0.306);
    });
    test('the box is clamped to the aspect-ratio width and to y = 1', () {
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.nose, 0.45, 0.9),
        _lm(LandmarkType.leftShoulder, 0.1, 0.5),
        _lm(LandmarkType.rightShoulder, 0.4, 0.5),
      ], aspect: 0.5));
      final r = _region(v);
      expect(r.right, 0.5);
      expect(r.bottom, 1.0);
      expect(r.left, closeTo(0.45 - 1.725 * 0.12, 1e-6));
    });
  });

  group('no head landmarks (back view): crown estimate', () {
    test('H = (ankle - shoulder) / 0.78; crown 0.10 H above; half-side 0.14 H', () {
      // shoulders y 0.3, ankles y 0.9: span 0.6, H = 0.769231, crown y
      // 0.3 - 0.076923 = 0.223077, half = 0.14 * 0.769231 * 1.15 = 0.123846.
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.leftShoulder, 0.4, 0.3),
        _lm(LandmarkType.rightShoulder, 0.6, 0.3),
        _lm(LandmarkType.leftAnkle, 0.45, 0.9),
        _lm(LandmarkType.rightAnkle, 0.55, 0.9),
      ]));
      expectRect(_region(v), 0.376154, 0.099231, 0.623846, 0.346923);
    });
    test('a single visible ankle is enough', () {
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.leftShoulder, 0.4, 0.3),
        _lm(LandmarkType.rightShoulder, 0.6, 0.3),
        _lm(LandmarkType.rightAnkle, 0.55, 0.9),
      ]));
      expectRect(_region(v), 0.376154, 0.099231, 0.623846, 0.346923);
    });
    test('a low-likelihood head landmark does not count as a head', () {
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.nose, 0.5, 0.1, 0.29),
        _lm(LandmarkType.leftShoulder, 0.4, 0.3),
        _lm(LandmarkType.rightShoulder, 0.6, 0.3),
        _lm(LandmarkType.leftAnkle, 0.45, 0.9),
      ]));
      expectRect(_region(v), 0.376154, 0.099231, 0.623846, 0.346923);
    });
  });

  group('fail closed (PRIV-03)', () {
    test('a null frame -> noLandmarks', () {
      final v = computeFaceRegion(null);
      expect(v.safe, isFalse);
      expect(v.failure, FaceRegionFailure.noLandmarks);
    });
    test('an empty landmark map -> noLandmarks', () {
      expect(computeFaceRegion(_frame(const [])).failure,
          FaceRegionFailure.noLandmarks);
    });
    test('no head AND no shoulders -> cannotSize', () {
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.leftKnee, 0.4, 0.6),
        _lm(LandmarkType.leftAnkle, 0.4, 0.9),
      ]));
      expect(v.failure, FaceRegionFailure.cannotSize);
    });
    test('shoulders but no ankle (and no head) -> cannotSize', () {
      expect(computeFaceRegion(_frame(_shoulders)).failure,
          FaceRegionFailure.cannotSize);
    });
    test('ankles but only one shoulder (and no head) -> cannotSize', () {
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.leftShoulder, 0.4, 0.3),
        _lm(LandmarkType.leftAnkle, 0.45, 0.9),
      ]));
      expect(v.failure, FaceRegionFailure.cannotSize);
    });
    test('ankles above the shoulders (nonsense pose) -> cannotSize', () {
      final v = computeFaceRegion(_frame([
        _lm(LandmarkType.leftShoulder, 0.4, 0.6),
        _lm(LandmarkType.rightShoulder, 0.6, 0.6),
        _lm(LandmarkType.leftAnkle, 0.45, 0.2),
      ]));
      expect(v.failure, FaceRegionFailure.cannotSize);
    });
    test('every failure verdict has no region, so nothing can be blurred-and-uploaded', () {
      for (final v in [
        computeFaceRegion(null),
        computeFaceRegion(_frame([_lm(LandmarkType.nose, 0.5, 0.2)])),
      ]) {
        expect(v.region, isNull);
        expect(v.safe, isFalse);
        expect(v.failure, isNotNull);
      }
    });
  });

  group('rectangles', () {
    test('width and height', () {
      const r = FrameRect(0.1, 0.2, 0.4, 0.8);
      expect(r.width, closeTo(0.3, 1e-12));
      expect(r.height, closeTo(0.6, 1e-12));
    });
    test('toPixels scales BOTH axes by the image height and clamps to the image', () {
      const r = FrameRect(0.362, 0.0344, 0.638, 0.338);
      final px = r.toPixels(imageWidth: 1000, imageHeight: 2000);
      expect(px.left, 724);
      expect(px.top, 69); // 68.8 rounds to 69
      expect(px.right, 1000); // 1276 clamped to the image width
      expect(px.bottom, 676);
      expect(px.width, 276);
      expect(px.height, 607);
    });
    test('toPixels never goes negative or past the height', () {
      const r = FrameRect(-0.2, -0.2, 2.0, 2.0);
      final px = r.toPixels(imageWidth: 300, imageHeight: 400);
      expect((px.left, px.top, px.right, px.bottom), (0, 0, 300, 400));
    });
  });

  test('config constants', () {
    expect(FaceRegionConfig.minLikelihood, 0.3);
    expect(FaceRegionConfig.radiusFromHeadSpread, 1.35);
    expect(FaceRegionConfig.radiusFromShoulders, 0.40);
    expect(FaceRegionConfig.halfSideOfRadius, 1.5);
    expect(FaceRegionConfig.extraUpOfRadius, 0.3);
    expect(FaceRegionConfig.marginFraction, 0.15);
    expect(FaceRegionConfig.torsoToShoulderWidth, 0.45);
    expect(FaceRegionConfig.shoulderToAnkleOfHeight, 0.78);
    expect(FaceRegionConfig.crownAboveShoulderOfHeight, 0.10);
    expect(FaceRegionConfig.crownHalfSideOfHeight, 0.14);
  });
}
