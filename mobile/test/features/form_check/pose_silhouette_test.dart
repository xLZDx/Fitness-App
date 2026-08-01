import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_silhouette.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';

/// The outline the user aims at.
///
/// Two faults are pinned here, both found by watching a screen recording of the
/// coach rather than by reading the code — which is the reason these are
/// geometric assertions and not a golden image. A golden would have gone green
/// on the broken version too, because the broken version rendered exactly what
/// it was asked to render.
void main() {
  /// Distance between two joints in a built figure, for proportion checks.
  double span(Rect r) => math.max(r.width, r.height);

  group('the figure is a body, not half a skeleton', () {
    test('a mid-line target with one arm produces two', () {
      final figure = buildSilhouette(squatTopTarget);

      // Six authored joints; a two-sided body has both arms, both legs and
      // four torso corners. The exact count is not the claim — "more than the
      // six that were authored" is.
      expect(figure.joints.length, greaterThan(squatTopTarget.joints.length));

      // Every drawn joint lies on one side of the torso axis or the other, and
      // both sides are populated. A one-sided figure fails this.
      final shoulder = squatTopTarget.joints[LandmarkType.leftShoulder]!;
      final hip = squatTopTarget.joints[LandmarkType.leftHip]!;
      final spine = Offset(shoulder.$1 - hip.$1, shoulder.$2 - hip.$2);
      final across = Offset(-spine.dy, spine.dx);
      var left = 0, right = 0;
      for (final j in figure.joints) {
        final v = j - Offset(hip.$1, hip.$2);
        final side = v.dx * across.dx + v.dy * across.dy;
        if (side > 1e-6) left++;
        if (side < -1e-6) right++;
      }
      expect(left, greaterThan(2), reason: 'no left-hand limbs drawn');
      expect(right, greaterThan(2), reason: 'no right-hand limbs drawn');
    });

    test('a target with no torso draws nothing rather than something wrong',
        () {
      const noHip = PoseTarget(
        id: 'fragment',
        joints: {
          LandmarkType.leftShoulder: (0.5, 0.3),
          LandmarkType.leftElbow: (0.5, 0.4),
        },
        bones: [],
      );
      expect(buildSilhouette(noHip).segments, isEmpty);
    });

    test('a partial limb is dropped, not drawn to a joint that is absent', () {
      const noAnkle = PoseTarget(
        id: 'no-ankle',
        joints: {
          LandmarkType.leftShoulder: (0.50, 0.26),
          LandmarkType.leftHip: (0.50, 0.53),
          LandmarkType.leftKnee: (0.50, 0.74),
        },
        bones: [],
      );
      final figure = buildSilhouette(noAnkle);
      // The trunk is a filled polygon, not segments, so the only segment left
      // is the neck: the leg chain needs an ankle, so neither the near nor the
      // far leg is drawn, and there is no arm chain at all.
      expect(figure.segments.length, 1);
      expect(figure.torso, hasLength(4), reason: 'the trunk still draws');
    });
  });

  group('one scale for both axes', () {
    // THE regression. The painter used to map x by panel width and y by panel
    // height. On this page's 9:16 panel that squeezed the body horizontally by
    // 1.78x, and the operator saw a stalk with a circle over it.
    test('proportions survive a panel of any shape', () {
      final figure = buildSilhouette(squatBottomTarget);
      final bounds = figure.bounds;

      double drawnAspect(Size panel) {
        final (scale, _) = fitSilhouette(bounds, panel);
        return (bounds.width * scale) / (bounds.height * scale);
      }

      final square = drawnAspect(const Size(400, 400));
      final tall = drawnAspect(const Size(360, 640));
      final wide = drawnAspect(const Size(900, 300));

      expect(tall, closeTo(square, 1e-9));
      expect(wide, closeTo(square, 1e-9));
      expect(square, closeTo(bounds.width / bounds.height, 1e-9));
    });

    test('the fitted figure stays inside the panel', () {
      final figure = buildSilhouette(pushupTopTarget);
      const panel = Size(360, 640);
      final (scale, origin) = fitSilhouette(figure.bounds, panel);

      for (final (a, b) in figure.segments) {
        for (final p in [a * scale + origin, b * scale + origin]) {
          expect(p.dx, inInclusiveRange(0, panel.width));
          expect(p.dy, inInclusiveRange(0, panel.height));
        }
      }
    });

    test('it is centred', () {
      final figure = buildSilhouette(squatTopTarget);
      const panel = Size(400, 800);
      final (scale, origin) = fitSilhouette(figure.bounds, panel);
      final b = figure.bounds;
      final left = b.left * scale + origin.dx;
      final right = b.right * scale + origin.dx;
      expect(panel.width - right, closeTo(left, 1e-6));
    });

    test('a degenerate figure does not divide by zero', () {
      final (scale, _) = fitSilhouette(Rect.zero, const Size(360, 640));
      expect(scale, 1.0);
      expect(scale.isFinite, isTrue);
    });
  });

  group('build', () {
    test('the two conventional builds differ where they should', () {
      final male = BodyBuild.forBody(sex: SilhouetteSex.male);
      final female = BodyBuild.forBody(sex: SilhouetteSex.female);
      expect(male.shoulderHalfWidth, greaterThan(female.shoulderHalfWidth));
      expect(male.hipHalfWidth, lessThan(female.hipHalfWidth));
    });

    test('an unanswered sex question is not guessed at', () {
      expect(BodyBuild.forBody(), BodyBuild.unknown);
      expect(
          BodyBuild.forBody(sex: SilhouetteSex.unspecified), BodyBuild.unknown);
    });

    test('a heavier body for the same height is drawn broader', () {
      final lean = BodyBuild.forBody(
          sex: SilhouetteSex.male, heightCm: 180, weightKg: 65);
      final heavy = BodyBuild.forBody(
          sex: SilhouetteSex.male, heightCm: 180, weightKg: 105);
      expect(heavy.shoulderHalfWidth, greaterThan(lean.shoulderHalfWidth));

      // Sub-linear, deliberately: mass goes as the cube of a linear dimension
      // and cross-section as the square, so 62% more mass is nothing like 62%
      // more width.
      final ratio = heavy.shoulderHalfWidth / lean.shoulderHalfWidth;
      expect(ratio, lessThan(105 / 65));
    });

    test('half an answer changes nothing', () {
      final base = BodyBuild.forBody(sex: SilhouetteSex.female);
      expect(BodyBuild.forBody(sex: SilhouetteSex.female, heightCm: 165), base);
      expect(
          BodyBuild.forBody(sex: SilhouetteSex.female, weightKg: 60.0), base);
    });

    test('nonsense measurements are ignored rather than drawn', () {
      final base = BodyBuild.forBody(sex: SilhouetteSex.male);
      // A typo'd height (a user entering metres, or a stray digit) would
      // otherwise produce a BMI of 3000 and a figure shaped like a wall.
      expect(
        BodyBuild.forBody(sex: SilhouetteSex.male, heightCm: 18, weightKg: 80),
        base,
      );
      expect(
        BodyBuild.forBody(
            sex: SilhouetteSex.male, heightCm: 180, weightKg: 900),
        base,
      );
    });

    test('extremes are clamped, so the outline stays aimable', () {
      final huge = BodyBuild.forBody(
          sex: SilhouetteSex.male, heightCm: 150, weightKg: 200);
      final tiny = BodyBuild.forBody(
          sex: SilhouetteSex.male, heightCm: 200, weightKg: 45);
      final neutral = BodyBuild.forBody(sex: SilhouetteSex.male);
      expect(huge.shoulderHalfWidth / neutral.shoulderHalfWidth,
          closeTo(1.32, 1e-9));
      expect(tiny.shoulderHalfWidth / neutral.shoulderHalfWidth,
          closeTo(0.86, 1e-9));
    });

    test('a broader build draws a wider figure', () {
      final narrow = buildSilhouette(squatTopTarget,
          build: BodyBuild.forBody(sex: SilhouetteSex.female));
      final broad = buildSilhouette(
        squatTopTarget,
        build: BodyBuild.forBody(
            sex: SilhouetteSex.male, heightCm: 175, weightKg: 110),
      );
      expect(broad.bounds.width, greaterThan(narrow.bounds.width));
    });

    test(
        'equal builds compare equal, so the overlay is not repainted per frame',
        () {
      // `silhouetteBuildProvider` returns a fresh instance on every read.
      // Without value equality `shouldRepaint` would be true on every camera
      // frame, which is the cost it exists to avoid.
      final a = BodyBuild.forBody(
          sex: SilhouetteSex.male, heightCm: 180, weightKg: 80);
      final b = BodyBuild.forBody(
          sex: SilhouetteSex.male, heightCm: 180, weightKg: 80);
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('scoring is untouched', () {
    // The whole point of building the figure in a separate file: the mirrored
    // limbs are drawn and never scored. If this ever fails, a user is being
    // judged against a far arm the detector was guessing at.
    test('every shipped target still carries exactly its authored joints', () {
      for (final target in [
        squatTopTarget,
        squatBottomTarget,
        pushupTopTarget,
        pushupBottomTarget,
      ]) {
        final before = Map.of(target.joints);
        buildSilhouette(target,
            build: BodyBuild.forBody(sex: SilhouetteSex.male));
        expect(target.joints, before, reason: '${target.id} was mutated');
        expect(
          target.joints.keys.every((k) => k.name.startsWith('left')),
          isTrue,
          reason: '${target.id} gained a right-side joint, which would be '
              'scored against a landmark the detector cannot see',
        );
      }
    });
  });

  group('the head', () {
    test('sits above the shoulders along the spine, not in the air', () {
      // In a squat the torso inclines; a head placed at a fixed offset would
      // float away from the chest. Checked on the bottom target, where the
      // spine is furthest from vertical.
      final figure = buildSilhouette(squatBottomTarget);
      final head = figure.head!;
      final shoulder = squatBottomTarget.joints[LandmarkType.leftShoulder]!;
      final hip = squatBottomTarget.joints[LandmarkType.leftHip]!;

      final spine = Offset(shoulder.$1 - hip.$1, shoulder.$2 - hip.$2);
      final toHead = head.$1 - Offset(shoulder.$1, shoulder.$2);
      final cosine = (spine.dx * toHead.dx + spine.dy * toHead.dy) /
          (spine.distance * toHead.distance);
      expect(cosine, closeTo(1.0, 1e-6),
          reason: 'the head is not on the hip-to-shoulder line');
    });

    test('is proportionate to the body it sits on', () {
      final figure = buildSilhouette(squatTopTarget);
      final head = figure.head!;
      // A radius somewhere between a tenth and a third of the whole figure:
      // the broken version drew a circle sized off the panel height while the
      // body was sized off its width, and it dominated the outline.
      final ratio = (head.$2 * 2) / span(figure.bounds);
      expect(ratio, inInclusiveRange(0.06, 0.35));
    });
  });
}
