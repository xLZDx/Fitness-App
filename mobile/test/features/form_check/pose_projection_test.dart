import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_projection.dart';

/// Putting a measured landmark on the preview.
///
/// The tempting one-liner is `x * width, y * height`, which is what the
/// silhouette painter does — correctly, because silhouette targets are AUTHORED
/// in the box's coordinates. A landmark is measured in the camera's, where both
/// axes were divided by the image height, so the frame is `aspectRatio` wide and
/// exactly 1.0 tall. Scaling the two axes by different numbers is a shear, and
/// the visible symptom is a straight back rendered as a bent one.
///
/// That exact mistake has already been made once in this feature, inside the
/// detector's own normalisation, and it cost a day to find because the output
/// looked plausible. Hence a named function with these tests rather than two
/// multiplications inside a painter.
void main() {
  group('a frame the same shape as the preview', () {
    // 9:16 into a 9:16 box: nothing is cropped, so the arithmetic is easy to
    // check by eye and the corners must land exactly on the corners.
    const aspect = 9 / 16;
    const canvas = Size(360, 640);

    test('the top-left of the frame is the top-left of the box', () {
      final p = projectLandmark(0, 0, frameAspect: aspect, canvas: canvas);
      expect(p.dx, closeTo(0, 1e-9));
      expect(p.dy, closeTo(0, 1e-9));
    });

    test('the bottom-right of the frame is the bottom-right of the box', () {
      final p = projectLandmark(aspect, 1, frameAspect: aspect, canvas: canvas);
      expect(p.dx, closeTo(360, 1e-9));
      expect(p.dy, closeTo(640, 1e-9));
    });

    test('the centre is the centre', () {
      final p =
          projectLandmark(aspect / 2, 0.5, frameAspect: aspect, canvas: canvas);
      expect(p.dx, closeTo(180, 1e-9));
      expect(p.dy, closeTo(320, 1e-9));
    });
  });

  group('shape is preserved, which is the whole point', () {
    const aspect = 3 / 4; // deliberately NOT the box's shape
    const canvas = Size(360, 640);

    test('both axes are scaled by the same number', () {
      // A square in camera space must come out square on screen. Under the
      // naive mapping this fails by the ratio between the two aspect ratios,
      // and every angle the coach measures would be wrong with it.
      final a = projectLandmark(0.2, 0.2, frameAspect: aspect, canvas: canvas);
      final b = projectLandmark(0.4, 0.4, frameAspect: aspect, canvas: canvas);
      expect(b.dx - a.dx, closeTo(b.dy - a.dy, 1e-9));
    });

    test('a vertical line stays vertical and a horizontal one horizontal', () {
      final top = projectLandmark(0.3, 0.1, frameAspect: aspect, canvas: canvas);
      final bottom =
          projectLandmark(0.3, 0.9, frameAspect: aspect, canvas: canvas);
      expect(top.dx, closeTo(bottom.dx, 1e-9));

      final left = projectLandmark(0.1, 0.5, frameAspect: aspect, canvas: canvas);
      final right =
          projectLandmark(0.6, 0.5, frameAspect: aspect, canvas: canvas);
      expect(left.dy, closeTo(right.dy, 1e-9));
    });

    test('the frame covers the box rather than fitting inside it', () {
      // `CameraPreview` in an expanded Stack fills the panel and loses the
      // overflow. Matching that means the crop, not letterboxing: the frame's
      // own edges fall OUTSIDE the box on the axis with the surplus.
      final left = projectLandmark(0, 0.5, frameAspect: aspect, canvas: canvas);
      final right =
          projectLandmark(aspect, 0.5, frameAspect: aspect, canvas: canvas);
      expect(left.dx, lessThan(0));
      expect(right.dx, greaterThan(canvas.width));
      // ...and the crop is symmetric, so the centre still reads as the centre.
      expect(left.dx + right.dx, closeTo(canvas.width, 1e-9));
    });
  });

  group('mirroring', () {
    const aspect = 9 / 16;
    const canvas = Size(360, 640);

    test('flips horizontally and leaves the vertical alone', () {
      final plain =
          projectLandmark(0.1, 0.3, frameAspect: aspect, canvas: canvas);
      final flipped = projectLandmark(0.1, 0.3,
          frameAspect: aspect, canvas: canvas, mirror: true);
      expect(flipped.dx, closeTo(canvas.width - plain.dx, 1e-9));
      expect(flipped.dy, closeTo(plain.dy, 1e-9));
    });

    test('is off unless asked for', () {
      // Whether the platform has already mirrored the front camera is a
      // per-device question. Assuming either way inside the maths would make
      // the overlay silently wrong on half the devices.
      final a = projectLandmark(0.1, 0.3, frameAspect: aspect, canvas: canvas);
      final b = projectLandmark(0.1, 0.3,
          frameAspect: aspect, canvas: canvas, mirror: false);
      expect(a, b);
    });
  });
}
