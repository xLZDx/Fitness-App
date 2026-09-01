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
  _b4();
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
      // Six since B4: the trunk gained a waist pair, which is what stops the
      // fill reading as a crate. Still "the trunk draws" — the claim this
      // assertion has always made.
      expect(figure.torso, hasLength(6), reason: 'the trunk still draws');
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

  // FORMCOACH_TARGET_XSCALE_2026-08-31: `target.joints` are authored with x as
  // a fraction of the frame's WIDTH (0..1), not of the isotropic space
  // `projectLandmark` draws in (0..frameAspect). Confirmed on a real device
  // (`video_2026-08-31_19-01-00.mp4`): the outline drew shoved hard right and
  // clipped off the panel. `xScale` is the fix.
  // FORMCOACH_TARGET_ISOTROPIC_2026-09-01 deleted `buildSilhouette`'s `xScale`
  // parameter along with the convention that needed it. What that group used to
  // assert -- "uncorrected, the outline spills past the right edge of a 9:16
  // frame; corrected, it fits" -- is now a property of the DATA rather than of
  // a parameter, so it is asserted directly on the shipped targets. The
  // parameter was removed rather than left at its harmless default because a
  // second, no-longer-needed x correction sitting in the drawing path is
  // exactly how the outline got shoved off-panel in the first place.
  group('every shipped target fits the narrowest frame it will be drawn on',
      () {
    // 9:16 is the tallest phone this runs on and therefore the tightest
    // horizontal budget: isotropic x may not exceed 0.5625 there.
    const narrowestFrame = 9 / 16;

    test('no outline claims to extend past the frame edge', () {
      for (final t in poseTargetsByTag.values.expand((p) => [p.$1, p.$2])) {
        final figure = buildSilhouette(t);
        expect(figure.bounds.left, greaterThanOrEqualTo(0.0),
            reason: '${t.id} starts left of the frame');
        expect(figure.bounds.right, lessThanOrEqualTo(narrowestFrame),
            reason: '${t.id} reaches ${figure.bounds.right.toStringAsFixed(3)}, '
                'past the $narrowestFrame that a 9:16 frame is wide');
      }
    });

    test('and the whole figure is inside the frame vertically too', () {
      for (final t in poseTargetsByTag.values.expand((p) => [p.$1, p.$2])) {
        final figure = buildSilhouette(t);
        expect(figure.bounds.top, greaterThanOrEqualTo(0.0),
            reason: '${t.id} starts above the frame');
        expect(figure.bounds.bottom, lessThanOrEqualTo(1.0),
            reason: '${t.id} reaches below the frame');
      }
    });

    test('does not mutate the authored target -- same contract as build', () {
      final before = Map.of(squatBottomTarget.joints);
      buildSilhouette(squatBottomTarget);
      expect(squatBottomTarget.joints, before);
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

/// B4 — the outline is a body, not thick sticks.
///
/// The operator rejected the drawing three times ("силует у тренера по прежнему
/// палочки"). The fix is structural: every part now arrives as a CLOSED outline
/// that the painter unions into one filled path, instead of bones stroked with
/// a wide round cap. These assert the structure, because a golden image would
/// go green on either version — both render exactly what they were asked to.
void _b4() {
  group('every part is a closed outline, not a stroked bone', () {
    test('a full target produces four limb outlines and a neck', () {
      final figure = buildSilhouette(squatTopTarget);
      // Two arms, two legs, one neck. Not "at least one" — a missing side is
      // the exact fault the two-sided figure was written to prevent.
      expect(figure.limbs.length, 5);
      for (final limb in figure.limbs) {
        expect(limb.length, greaterThanOrEqualTo(4),
            reason: 'an outline needs at least two points per side');
        expect(limb.length.isEven, isTrue,
            reason: 'one point per side, so the count is always even');
      }
    });

    test('limbs narrow towards the extremity', () {
      // The whole difference between a silhouette and a tube. Measured on the
      // outline itself: the width at the first joint must exceed the width at
      // the last.
      final figure = buildSilhouette(squatTopTarget);
      for (final limb in figure.limbs) {
        final half = limb.length ~/ 2;
        final atRoot = (limb.first - limb.last).distance;
        final atTip = (limb[half - 1] - limb[half]).distance;
        expect(atRoot, greaterThan(atTip),
            reason: 'this limb has the same width at both ends');
      }
    });

    test('the trunk has a waist', () {
      // Four points is a box. The waist pair is most of what makes the fill
      // read as a person rather than a crate.
      final figure = buildSilhouette(squatTopTarget);
      expect(figure.torso.length, 6);
    });

    test('the bounds cover the fill, not just the bones', () {
      // The outlines sit half a limb-width outside the segments they wrap. A
      // bounds computed from segments alone lets `fitSilhouette` clip an arm.
      final figure = buildSilhouette(squatTopTarget);
      final b = figure.bounds;
      for (final limb in figure.limbs) {
        for (final p in limb) {
          // Compared inclusively rather than with `Rect.contains`, which is
          // half-open: it excludes the right and bottom edges, so the very
          // point that DEFINES the bound reads as outside it. The first draft
          // of this test used `contains` and failed on a correct figure.
          expect(
            p.dx >= b.left && p.dx <= b.right &&
                p.dy >= b.top && p.dy <= b.bottom,
            isTrue,
            reason: 'outline point $p falls outside the reported bounds $b',
          );
        }
      }
    });

    test('a target with no torso produces no outlines either', () {
      const noHip = PoseTarget(
        id: 'fragment',
        joints: {LandmarkType.leftShoulder: (0.5, 0.3)},
        bones: [],
      );
      expect(buildSilhouette(noHip).limbs, isEmpty);
    });

    test('a missing ankle drops that whole limb, not half of it', () {
      // Same contract the segments already had: a partial limb is worse than
      // none. Asserted on the outlines too, or a half-drawn leg could come
      // back through the new path.
      final noAnkle = PoseTarget(
        id: 'partial',
        joints: {
          for (final e in squatTopTarget.joints.entries)
            if (e.key != LandmarkType.leftAnkle) e.key: e.value,
        },
        bones: const [],
      );
      final figure = buildSilhouette(noAnkle);
      // Two arms and a neck survive; both legs are gone.
      expect(figure.limbs.length, 3);
    });
  });
}
