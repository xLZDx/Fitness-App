import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_coordinate_space.dart';

/// The unit the whole form coach is written in.
///
/// Until 2026-07-31 nothing established it: `pose_landmark.dart` documented
/// "normalised 0..1", the detector passed ML Kit's values through untouched, and
/// ML Kit documents those as pixels. Every threshold in the gate, the rep
/// counter and the classifiers is a bare number compared against that field, so
/// the contract was load-bearing and unverified at the same time.
///
/// These tests pin the two things that matter: that the two candidate input
/// spaces are told apart with enormous margin, and that the conversion preserves
/// angles — which is the property the obvious normalisation would have silently
/// destroyed.

/// Angle at [b], in degrees. Same formula as `form_classifier.dart:_angleDeg`,
/// duplicated here on purpose: this test exists to check the *coordinates*, and
/// importing the production angle helper would let a change there mask a
/// regression here.
double angleDeg(
  (double, double) a,
  (double, double) b,
  (double, double) c,
) {
  final ab = math.atan2(a.$2 - b.$2, a.$1 - b.$1);
  final cb = math.atan2(c.$2 - b.$2, c.$1 - b.$1);
  var deg = (ab - cb) * 180 / math.pi;
  if (deg < 0) deg = -deg;
  if (deg > 180) deg = 360 - deg;
  return deg;
}

void main() {
  group('detectCoordinateSpace tells the two hypotheses apart', () {
    test('a body measured in pixels reads as pixels', () {
      // A standing person on a 480x640 frame: shoulders near the top, ankles
      // near the bottom. Hundreds of units of extent.
      final values = <double>[240, 96, 250, 300, 245, 470, 238, 610];
      expect(detectCoordinateSpace(values), PoseCoordinateSpace.pixels);
    });

    test('the same body already scaled to 0..1 reads as normalised', () {
      final values = <double>[0.50, 0.15, 0.52, 0.47, 0.51, 0.73, 0.49, 0.95];
      expect(detectCoordinateSpace(values), PoseCoordinateSpace.normalised);
    });

    test('normalised coordinates extrapolated past the frame still read as '
        'normalised', () {
      // BlazePose reports joints just outside the picture rather than omitting
      // them. That overshoot must not be mistaken for pixels, or a user with
      // their feet just below frame would be told the app is broken.
      final values = <double>[-0.30, -0.20, 1.25, 1.40];
      expect(detectCoordinateSpace(values), PoseCoordinateSpace.normalised);
    });

    test('the discriminator has two orders of magnitude of headroom', () {
      // The widest plausible normalised spread vs the narrowest plausible pixel
      // spread. If these ever approach each other the threshold needs revisiting
      // — this test is what would notice.
      const widestNormalised = 2.0; // -0.5 .. 1.5, heavy extrapolation
      const narrowestPixels = 200.0; // a small body on the smallest frame
      expect(widestNormalised, lessThan(kPixelSpaceThreshold));
      expect(narrowestPixels, greaterThan(kPixelSpaceThreshold));
      expect(narrowestPixels / widestNormalised, greaterThan(50));
    });

    test('too few values to have an extent falls back to the documented '
        'contract', () {
      // Not a guess dressed as a measurement: with no evidence, believe the
      // plugin's own doc rather than inventing an answer.
      expect(detectCoordinateSpace(const <double>[]),
          PoseCoordinateSpace.pixels);
      expect(detectCoordinateSpace(const <double>[0.5]),
          PoseCoordinateSpace.pixels);
    });

    test('NaN does not poison the measurement', () {
      final values = <double>[double.nan, 240, 96, 245, 610];
      expect(detectCoordinateSpace(values), PoseCoordinateSpace.pixels);
    });
  });

  group('the conversion preserves angles', () {
    // A Romanian deadlift at the bottom, measured in pixels on a 480x640 frame.
    // These are the coordinates behind the 82.9 deg figure in the deadlift
    // rule's doc comment.
    const shoulderPx = (150.0, 200.0);
    const hipPx = (300.0, 350.0);
    const kneePx = (280.0, 520.0);

    const w = 480.0;
    const h = 640.0;

    test('isotropic normalisation leaves the angle unchanged', () {
      final raw = angleDeg(shoulderPx, hipPx, kneePx);
      final n = PoseCoordinateNormaliser(
        space: PoseCoordinateSpace.pixels,
        imageWidth: w,
        imageHeight: h,
      );
      final converted = angleDeg(
        n.normalise(shoulderPx.$1, shoulderPx.$2),
        n.normalise(hipPx.$1, hipPx.$2),
        n.normalise(kneePx.$1, kneePx.$2),
      );
      expect(converted, closeTo(raw, 1e-9),
          reason: 'dividing both axes by one scalar is a similarity transform; '
              'angles are invariant under it');
    });

    test('the anisotropic normalisation this replaced does NOT', () {
      // The regression this whole file exists for. Dividing x by the width and
      // y by the height looks like normalisation and is a shear: it moves the
      // measured angle by more than the entire gap the deadlift rule was
      // claiming to resolve (correct RDL 82.9 deg vs rounded back 77.7 deg).
      final raw = angleDeg(shoulderPx, hipPx, kneePx);
      (double, double) skew((double, double) p) => (p.$1 / w, p.$2 / h);
      final skewed =
          angleDeg(skew(shoulderPx), skew(hipPx), skew(kneePx));

      expect((skewed - raw).abs(), greaterThan(3.0),
          reason: 'if this ever drops to ~0 the shear is gone and this test is '
              'no longer guarding anything -- check why before deleting it');
      expect((skewed - raw).abs(), greaterThan(5.2 / 2),
          reason: 'the error must be shown to be large relative to the 5.2 deg '
              'signal, not merely non-zero');
    });

    test('both input spaces land on the same output', () {
      // The same physical point, expressed both ways. If these diverged, the
      // detector would score differently depending on a branch nothing
      // downstream can see.
      const px = (150.0, 200.0);
      final norm = (px.$1 / w, px.$2 / h);

      final fromPixels = PoseCoordinateNormaliser(
        space: PoseCoordinateSpace.pixels,
        imageWidth: w,
        imageHeight: h,
      ).normalise(px.$1, px.$2);
      final fromNormalised = PoseCoordinateNormaliser(
        space: PoseCoordinateSpace.normalised,
        imageWidth: w,
        imageHeight: h,
      ).normalise(norm.$1, norm.$2);

      expect(fromPixels.$1, closeTo(fromNormalised.$1, 1e-12));
      expect(fromPixels.$2, closeTo(fromNormalised.$2, 1e-12));
    });
  });

  group('depth takes the same transform as x', () {
    // Nothing reads z today -- grepping lib/features/form_check finds no
    // consumer. That is exactly why this is pinned now: the first person to use
    // it will assume it is comparable with x, and if the two branches disagreed
    // nothing would tell them otherwise.
    const w = 480.0;
    const h = 640.0;

    test('a depth and an x of the same raw value convert identically', () {
      for (final space in PoseCoordinateSpace.values) {
        final n = PoseCoordinateNormaliser(
          space: space,
          imageWidth: w,
          imageHeight: h,
        );
        const raw = 120.0;
        expect(n.normaliseDepth(raw), closeTo(n.normalise(raw, 0).$1, 1e-12),
            reason: 'z shares x\'s scale in ML Kit, so it must share x\'s '
                'transform here -- $space branch');
      }
    });

    test('the two branches agree on the same physical depth', () {
      final fromPixels = PoseCoordinateNormaliser(
        space: PoseCoordinateSpace.pixels,
        imageWidth: w,
        imageHeight: h,
      ).normaliseDepth(120);
      final fromNormalised = PoseCoordinateNormaliser(
        space: PoseCoordinateSpace.normalised,
        imageWidth: w,
        imageHeight: h,
      ).normaliseDepth(120 / w);
      expect(fromPixels, closeTo(fromNormalised, 1e-12));
    });
  });

  group('the output contract', () {
    final n = PoseCoordinateNormaliser(
      space: PoseCoordinateSpace.pixels,
      imageWidth: 480,
      imageHeight: 640,
    );

    test('y spans 0..1 and x spans 0..aspectRatio', () {
      expect(n.aspectRatio, closeTo(0.75, 1e-12));
      expect(n.normalise(0, 0), (0.0, 0.0));
      final bottomRight = n.normalise(480, 640);
      expect(bottomRight.$2, closeTo(1.0, 1e-12));
      expect(bottomRight.$1, closeTo(n.aspectRatio, 1e-12),
          reason: 'the right edge of the picture must land exactly on the '
              'bound the gate checks x against');
    });

    test('a portrait frame has an aspect ratio below 1, so 0.9 is off-frame', () {
      // Stated as a coordinate fact here; `pose_gate_test.dart` is where the
      // gate is shown to act on it.
      expect(0.9, greaterThan(n.aspectRatio));
    });
  });
}
