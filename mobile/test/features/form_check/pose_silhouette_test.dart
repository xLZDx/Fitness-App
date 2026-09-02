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
/// A body facing the camera, with both sides observed [halfSpan] from the
/// mid-line. `0` is edge-on with the far side still detected.
PoseTarget frontOn(double halfSpan) => PoseTarget(
      id: 'front.$halfSpan',
      joints: {
        LandmarkType.leftShoulder: (0.28 + halfSpan, 0.30),
        LandmarkType.rightShoulder: (0.28 - halfSpan, 0.30),
        // Arms too: a real detector reports them, and without them
        // `buildSilhouette` builds no arm pair for a test to read.
        LandmarkType.leftElbow: (0.28 + halfSpan, 0.42),
        LandmarkType.rightElbow: (0.28 - halfSpan, 0.42),
        LandmarkType.leftWrist: (0.28 + halfSpan, 0.53),
        LandmarkType.rightWrist: (0.28 - halfSpan, 0.53),
        LandmarkType.leftHip: (0.28 + halfSpan, 0.55),
        LandmarkType.rightHip: (0.28 - halfSpan, 0.55),
        LandmarkType.leftKnee: (0.28 + halfSpan, 0.75),
        LandmarkType.rightKnee: (0.28 - halfSpan, 0.75),
        LandmarkType.leftAnkle: (0.28 + halfSpan, 0.93),
        LandmarkType.rightAnkle: (0.28 - halfSpan, 0.93),
      },
      bones: [],
    );


/// Torso length of [frontOn], which runs straight down from 0.30 to 0.55.
const frontOnTorso = 0.25;

/// Centre of a closed outline, used to measure how far apart a limb pair sits.
Offset centroid(List<Offset> poly) {
  var x = 0.0, y = 0.0;
  for (final p in poly) {
    x += p.dx;
    y += p.dy;
  }
  return Offset(x / poly.length, y / poly.length);
}

void main() {
  _b4();
  /// Distance between two joints in a built figure, for proportion checks.
  double span(Rect r) => math.max(r.width, r.height);

  group('a side view is drawn at depth, not at shoulder breadth', () {
    // The fault that made every authored figure read as a lattice rather than
    // a person, found by putting the demonstration on its own screen and
    // looking at it on a phone. Every target in `pose_target.dart` is a
    // MID-LINE SIDE VIEW — the coach's own instruction is «встаньте боком к
    // камере» — and the drawing widened all of them by `shoulderHalfWidth`,
    // which describes how far apart two shoulders are when you are looking at
    // someone's front. Measured on the shipped squat before the fix: the two
    // mirrored arms sat 0.10 apart on a torso 0.257 long, and because the
    // offset runs perpendicular to a spine inclined 42 degrees in a deep
    // squat, they came apart on the diagonal.
    //
    // Geometric assertions rather than a golden, for the reason at the top of
    // this file: a golden goes green on the broken version too.


    /// Hip-to-shoulder length of an authored target.
    double torsoOf(PoseTarget t) {
      final s = t.joints[LandmarkType.leftShoulder]!;
      final h = t.joints[LandmarkType.leftHip]!;
      return Offset(s.$1 - h.$1, s.$2 - h.$2).distance;
    }

    test('the trunk is as deep as a chest, not as wide as two shoulders', () {
      const build = BodyBuild.unknown;
      for (final t in [squatTopTarget, squatBottomTarget]) {
        final figure = buildSilhouette(t, build: build);
        final torso = torsoOf(t);
        // `torso[0]` and `torso[1]` are the two shoulder corners of the trunk
        // hexagon (`buildSilhouette` winds it across the top first).
        final across = (figure.torso[0] - figure.torso[1]).distance;
        expect(across, closeTo(2 * build.trunkHalfDepth * torso, 1e-6),
            reason: '${t.id} trunk is not drawn at its depth');
        // The contract, stated against the dimension it is actually about: a
        // body seen edge-on is drawn narrower than the same body seen face-on.
        // (This compared `across` — a full width — against a HALF span until
        // 2026-09-01. It passed only because the depth was then an unrealistic
        // 0.13 of torso, so an accidentally-strict bound went unnoticed until
        // the depth was corrected to a real chest's.)
        expect(across, lessThan(2 * build.shoulderHalfWidth * torso),
            reason: '${t.id} a profile is not drawn at a front view width');
        expect(across, greaterThan(build.shoulderHalfWidth * torso),
            reason: '${t.id} and it is a chest, not a plank');
      }
    });

    test('the near and far limb overlap into one, rather than standing apart',
        () {
      // What a profile actually looks like: the far arm is BEHIND the near
      // one. A parallax wide enough to give the figure a far side, narrow
      // enough that the two outlines union into a single limb with depth.
      // Before the fix this separation exceeded the limb's own width, so the
      // union left two visibly separate bars.
      const build = BodyBuild.unknown;
      for (final t in [squatTopTarget, squatBottomTarget]) {
        final figure = buildSilhouette(t, build: build);
        final torso = torsoOf(t);
        // Arms are limbs 0 and 1, legs 2 and 3 — the order `buildSilhouette`
        // adds them in.
        final armGap =
            (centroid(figure.limbs[0]) - centroid(figure.limbs[1])).distance;
        final legGap =
            (centroid(figure.limbs[2]) - centroid(figure.limbs[3])).distance;
        // Widest point of each limb pair, from the girth table `limbPair` is
        // called with in `buildSilhouette` — the FIRST entry of each `girth`
        // list, which is a HALF-width, so the full width is twice it. Keep
        // these two literals in step with that table; they are duplicated here
        // deliberately, so that retuning girth has to be a conscious edit in
        // both places rather than silently relaxing this bound.
        final armWidth = 2 * 0.52 * build.limbThickness * torso;
        final legWidth = 2 * 0.80 * build.limbThickness * torso;
        expect(armGap, lessThan(armWidth),
            reason: '${t.id} arms are two bars, not one arm with depth');
        expect(legGap, lessThan(legWidth),
            reason: '${t.id} legs are two bars, not one leg with depth');
        expect(armGap, greaterThan(0.02 * torso),
            reason: '${t.id} a figure with no far side at all is flat');
      }
    });

    test('the trunk carries on past the hip joint, so a bent body has a seat',
        () {
      // The hip landmark is where the leg rotates, not where the body ends.
      // Stop the trunk there and a squat leaves an open triangle between torso
      // and thigh — the figure reads as a bent arrow rather than a person,
      // which is what the phone showed after both the depth and the fill were
      // already right. Nothing failed when this was added, so it gets its own
      // assertion rather than riding on the ones that did not notice.
      for (final t in [squatTopTarget, squatBottomTarget]) {
        final figure = buildSilhouette(t);
        final s = t.joints[LandmarkType.leftShoulder]!;
        final h = t.joints[LandmarkType.leftHip]!;
        final hip = Offset(h.$1, h.$2);
        final torso = (Offset(s.$1, s.$2) - hip).distance;
        // Unit vector from hip towards shoulder. A point of the trunk that sits
        // BELOW the hip projects negatively onto it.
        final up = (Offset(s.$1, s.$2) - hip) / torso;
        for (final corner in [figure.torso[3], figure.torso[4]]) {
          final d = corner - hip;
          final along = d.dx * up.dx + d.dy * up.dy;
          expect(along, lessThan(-0.05 * torso),
              reason: '${t.id} the trunk stops at the hip joint');
          expect(along, greaterThan(-0.35 * torso),
              reason: '${t.id} a seat, not a second torso below the hips');
        }
      }
    });

    test('the hips get their own depth, slightly greater than the chest', () {
      // The multiplier had no assertion of its own, so an edit to it — or to
      // the hip corners of the trunk hexagon — would have gone unnoticed while
      // the shoulder assertion above stayed green.
      const build = BodyBuild.unknown;
      final figure = buildSilhouette(squatTopTarget, build: build);
      final torso = torsoOf(squatTopTarget);
      // `torso[3]` and `torso[4]` are the hip corners: the hexagon is wound
      // across the top, down the right, across the bottom, back up the left.
      final hipAcross = (figure.torso[3] - figure.torso[4]).distance;
      expect(hipAcross, closeTo(2 * build.trunkHalfDepth * 1.1 * torso, 1e-6));
      expect(hipAcross,
          greaterThan((figure.torso[0] - figure.torso[1]).distance));
    });

    test('a body seen face-on is drawn where its shoulders were seen', () {
      // The other path, and the one that must not lose its breadth: when the
      // detector reports both shoulders well apart, the body really is facing
      // the camera and no widening is needed at all.
      const build = BodyBuild.unknown;
      const torso = 0.25; // 0.55 - 0.30, straight down
      // Comfortably wider than the build's own assumed half-span, so the
      // observation wins outright.
      final halfSpan = build.shoulderHalfWidth * torso * 1.2;
      final figure = buildSilhouette(frontOn(halfSpan));
      final across = (figure.torso[0] - figure.torso[1]).distance;
      expect(across, closeTo(2 * halfSpan, 1e-6),
          reason: 'drawn where it was observed, not widened or narrowed');
      expect(across, greaterThan(2 * build.trunkHalfDepth * torso * 1.5),
          reason: 'and nowhere near the profile dimension');
    });

    test('turning side-on narrows the body continuously, with no step at the '
        'moment the far side stops being detected', () {
      // The regression the first version of this gate introduced, caught in
      // review. Substituting depth for breadth on a `twoSided` BOOLEAN halves
      // the drawn body in a single frame the instant one shoulder's confidence
      // drops — which happens mid-turn, mid-rep and under motion blur. It is
      // the same flicker class an earlier gate was built to remove, moved onto
      // a different axis.
      //
      // The fix is that nothing switches: every dimension is interpolated by
      // how square to the camera the observation is, so the two-sided figure
      // at zero observed separation and the one-sided figure ARE the same
      // drawing.
      const torso = 0.25;
      double widthAt(double halfSpan) {
        final f = buildSilhouette(frontOn(halfSpan));
        return (f.torso[0] - f.torso[1]).distance;
      }

      // Monotone all the way down, with no jump anywhere along it.
      final spans = [for (var i = 10; i >= 0; i--) i / 10 * 0.09];
      final widths = [for (final s in spans) widthAt(s)];
      for (var i = 1; i < widths.length; i++) {
        expect(widths[i], lessThanOrEqualTo(widths[i - 1] + 1e-9),
            reason: 'width grew while the body turned away');
        expect((widths[i - 1] - widths[i]).abs(), lessThan(0.02),
            reason: 'a step, not a turn, between ${spans[i - 1]} and '
                '${spans[i]}');
      }

      // And the boundary itself: the last two-sided frame before the far side
      // is lost, against the one-sided frame that replaces it.
      const oneSided = PoseTarget(
        id: 'side.test',
        joints: {
          LandmarkType.leftShoulder: (0.28, 0.30),
          LandmarkType.leftHip: (0.28, 0.55),
          LandmarkType.leftKnee: (0.28, 0.75),
          LandmarkType.leftAnkle: (0.28, 0.93),
        },
        bones: [],
      );
      final lost = buildSilhouette(oneSided);
      expect(widthAt(0.0),
          closeTo((lost.torso[0] - lost.torso[1]).distance, 1e-9),
          reason: 'losing the far side must change nothing that was already '
              'edge-on');
      expect(widthAt(0.0),
          closeTo(2 * BodyBuild.unknown.trunkHalfDepth * torso, 1e-6));
    });

    test('the limb pair closes up as continuously as the trunk does', () {
      // The trunk test above walks `facing` through its whole range but reads
      // only `figure.torso`. The limb pair is driven by a SEPARATE interpolation
      // (`armWiden`/`legWiden`, against a parallax rather than the trunk depth),
      // so nothing was watching it: swapping its two arguments, or dropping its
      // clamp, would have left every test green and shown up only as a live
      // avatar whose arms jump apart mid-turn.
      double gapAt(double halfSpan, int a, int b) {
        final f = buildSilhouette(frontOn(halfSpan));
        return (centroid(f.limbs[a]) - centroid(f.limbs[b])).distance;
      }

      final spans = [for (var i = 10; i >= 0; i--) i / 10 * 0.09];
      for (final pair in [(0, 1), (2, 3)]) {
        final gaps = [for (final s in spans) gapAt(s, pair.$1, pair.$2)];
        for (var i = 1; i < gaps.length; i++) {
          expect(gaps[i], lessThanOrEqualTo(gaps[i - 1] + 1e-9),
              reason: 'limb pair $pair grew apart while the body turned away');
          expect((gaps[i - 1] - gaps[i]).abs(), lessThan(0.02),
              reason: 'a step, not a turn, in limb pair $pair between '
                  '${spans[i - 1]} and ${spans[i]}');
        }
        // Edge-on the pair is at the parallax, which is far tighter than the
        // breadth it would have used before the fix.
        expect(gaps.last, lessThan(0.14 * 0.25),
            reason: 'limb pair $pair is two people wide when edge-on');
        expect(gaps.last, greaterThan(0.0),
            reason: 'limb pair $pair has no far side at all');
      }
    });
  });

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

    /// A body whose observed shoulder and hip half-spans are [sh] and [hh],
    /// independent of any `BodyBuild`.
    ///
    /// The point of taking both explicitly: a fixture that derives its spans
    /// from the same constants the code reconstructs with proves only that the
    /// code is self-consistent. GPT-PM rejected exactly that, and it was right —
    /// a real detector's projected spans owe nothing to `BodyBuild`'s prior.
    PoseTarget body(double sh, double hh,
        {Set<LandmarkType> without = const {}, double tiltRadians = 0.0}) {
      // Tilted about the hips, because a real body is almost never square to
      // the frame: a squat leans, and the mid-line reconstruction has to hold
      // on a slanted axis rather than only on a vertical one.
      const pivot = Offset(0.28, 0.55);
      final c = math.cos(tiltRadians), s = math.sin(tiltRadians);
      (double, double) at(double x, double y) {
        final d = Offset(x, y) - pivot;
        final r = Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c) + pivot;
        return (r.dx, r.dy);
      }

      return PoseTarget(
        id: 'body.$sh.$hh.$tiltRadians',
        joints: <LandmarkType, (double, double)>{
          LandmarkType.leftShoulder: at(0.28 + sh, 0.30),
          LandmarkType.rightShoulder: at(0.28 - sh, 0.30),
          LandmarkType.leftElbow: at(0.28 + sh, 0.42),
          LandmarkType.rightElbow: at(0.28 - sh, 0.42),
          LandmarkType.leftWrist: at(0.28 + sh, 0.53),
          LandmarkType.rightWrist: at(0.28 - sh, 0.53),
          LandmarkType.leftHip: at(0.28 + hh, 0.55),
          LandmarkType.rightHip: at(0.28 - hh, 0.55),
          LandmarkType.leftKnee: at(0.28 + hh, 0.75),
          LandmarkType.rightKnee: at(0.28 - hh, 0.75),
          LandmarkType.leftAnkle: at(0.28 + hh, 0.93),
          LandmarkType.rightAnkle: at(0.28 - hh, 0.93),
        }..removeWhere((key, _) => without.contains(key)),
        bones: const [],
      );
    }

    test('a half-bilateral torso degrades to a profile, coherently', () {
      // What this asserts, and deliberately what it does NOT.
      //
      // A target carrying a far shoulder but no far hip (or the reverse) is a
      // torso with no measurable width: the pair that would have measured it is
      // incomplete. Three rounds of review on this gate went into trying to
      // reconstruct the missing end, and GPT-PM rejected every stateless
      // attempt with an exact counterexample — an anthropometric prior is
      // continuous only for a body matching the prior; a mid-line fitted
      // through the bilateral midpoints assumes an articulated squat has one
      // straight shoulder-to-ankle axis, and on this app's own deep-squat
      // geometry that misplaces the shoulder by a whole torso length.
      //
      // So the builder degrades instead of inventing: it draws the profile the
      // data structurally is. There is deliberately NO continuity assertion
      // here, because there is nothing for it to be continuous WITH — the live
      // producer cannot emit this shape at all, which is the invariant pinned
      // in `pose_avatar_test.dart` ("the far side is gained and lost as ONE
      // torso, never half of one"). What must hold is that the result is a
      // coherent figure rather than a NaN or a sheared one.
      const torso = 0.25;
      for (final missing in [
        LandmarkType.rightHip,
        LandmarkType.rightShoulder,
      ]) {
        final figure = buildSilhouette(body(0.06, 0.06, without: {missing}));
        expect(figure.torso, isNotEmpty, reason: '$missing: nothing drawn');
        for (final pt in [
          ...figure.torso,
          for (final l in figure.limbs) ...l
        ]) {
          expect(pt.dx.isFinite && pt.dy.isFinite, isTrue,
              reason: '$missing: a non-finite point reached the painter');
        }
        final across = (figure.torso[0] - figure.torso[1]).distance;
        expect(across,
            closeTo(2 * BodyBuild.unknown.trunkHalfDepth * torso, 1e-6),
            reason: '$missing: not drawn as the profile it structurally is');
        // Centred on one chain rather than sheared between two different
        // centres — which is what reading a surviving far joint through a
        // widening computed for a profile used to produce.
        final shoulderMid = (figure.torso[0] + figure.torso[1]) / 2;
        final hipMid = (figure.torso[3] + figure.torso[4]) / 2;
        expect((shoulderMid.dx - hipMid.dx).abs(), lessThan(0.01 * torso),
            reason: '$missing: the trunk is sheared between two centres');
      }
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

    test('depth follows the same answers breadth does', () {
      // `trunkHalfDepth` joined the sexed table and the weight scaling in the
      // same edit that introduced it, and neither was asserted — a maintainer
      // could have dropped it from `forBody`'s `k` scaling, or swapped the two
      // sexed constants, with the whole suite green. It is the ONLY dimension
      // an edge-on body is drawn at, so on the coach's own instruction
      // («встаньте боком к камере») it is the one that shows.
      final male = BodyBuild.forBody(sex: SilhouetteSex.male);
      final female = BodyBuild.forBody(sex: SilhouetteSex.female);
      expect(male.trunkHalfDepth, greaterThan(female.trunkHalfDepth));
      // Token, though: the ratio that separates the two conventional builds is
      // a front-on one, so depth must not fork as hard as breadth does.
      expect(male.trunkHalfDepth / female.trunkHalfDepth,
          lessThan(male.shoulderHalfWidth / female.shoulderHalfWidth));

      final lean = BodyBuild.forBody(
          sex: SilhouetteSex.male, heightCm: 180, weightKg: 65);
      final heavy = BodyBuild.forBody(
          sex: SilhouetteSex.male, heightCm: 180, weightKg: 105);
      expect(heavy.trunkHalfDepth, greaterThan(lean.trunkHalfDepth),
          reason: 'a heavier body is deeper, not only broader');
    });

    test('a body facing the camera is drawn to its own build, not a default',
        () {
      // The front-on half of the pair below. `turned()` interpolates towards
      // `build.shoulderHalfWidth`, so hard-coding that end to the default
      // would leave every side-view assertion green while every user facing
      // the camera got the same average figure — which is the whole point of
      // asking for the intake at all.
      //
      // A separation the builds both widen from, so the drawn width is the
      // build's and not the observation's.
      final target = frontOn(0.02);
      final narrow = buildSilhouette(target,
          build: BodyBuild.forBody(sex: SilhouetteSex.female));
      final broad = buildSilhouette(
        target,
        build: BodyBuild.forBody(
            sex: SilhouetteSex.male, heightCm: 175, weightKg: 110),
      );
      double trunk(SilhouetteFigure f) => (f.torso[0] - f.torso[1]).distance;
      expect(trunk(broad), greaterThan(trunk(narrow)));
    });

    test('a broader build draws a wider figure', () {
      // NOTE, 2026-09-01: `squatTopTarget` is a one-sided side view, so what
      // this now guards is `trunkHalfDepth`'s scaling, not
      // `shoulderHalfWidth`'s — the field the one-sided path used before the
      // profile fix. The front-on test just above covers breadth on a
      // two-sided body, so both are asserted; without it this one would have
      // silently stopped covering the field its name suggests.
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

  group('the body bends at its joints instead of coming to a point', () {
    // Found in `test/golden/form_coach_golden_test.dart`'s first image, and
    // findable no other way: every assertion in this file passed on the
    // version that produced it, because every bone WAS where it belonged.
    // Two tapered outlines meeting at an angle do not bend — they cross, and
    // their union comes to a point on the outside of the corner. At the bottom
    // of a squat, torso and thigh close to about 40 degrees and that point is
    // the seat, so the figure had a barb where a person is roundest and the
    // whole silhouette read as an arrowhead.

    test('every limb articulation carries a disc', () {
      // The trunk's own four corners are deliberately not in this list: they
      // are rounded by the two domes the next tests are about, one across the
      // shoulders and one across the seat, rather than by a disc each. A disc
      // per corner there would bulge the sides of the body instead of doming
      // its ends.
      final figure = buildSilhouette(squatBottomTarget);
      expect(figure.blobs, isNotEmpty);
      const limbEnds = {
        LandmarkType.leftElbow,
        LandmarkType.rightElbow,
        LandmarkType.leftWrist,
        LandmarkType.rightWrist,
        LandmarkType.leftKnee,
        LandmarkType.rightKnee,
        LandmarkType.leftAnkle,
        LandmarkType.rightAnkle,
      };
      var checked = 0;
      for (var i = 0; i < figure.joints.length; i++) {
        if (!limbEnds.contains(figure.jointTypes[i])) continue;
        checked++;
        final joint = figure.joints[i];
        expect(figure.blobs.any((b) => (b.$1 - joint).distance < 1e-9), isTrue,
            reason: 'no disc at ${figure.jointTypes[i]} $joint — that corner '
                'is still a point');
      }
      expect(checked, 8,
          reason: 'positive control: a two-sided figure has eight of them, so '
              'a loop that checked nothing would not pass this');
      for (final (_, r) in figure.blobs) {
        expect(r, greaterThan(0));
        expect(r.isFinite, isTrue);
      }
    });

    test('the seat disc reaches the corners it is there to round off', () {
      // The specific one. `torso` is wound shoulders-first, so entries 3 and 4
      // are the two bottom corners of the pelvis extension — the pair that
      // produced the barb. A disc that merely sits NEAR them changes nothing:
      // it has to reach them, or the union keeps the corner and gains a bump.
      final figure = buildSilhouette(squatBottomTarget);
      expect(figure.torso.length, 6);
      final corners = [figure.torso[3], figure.torso[4]];

      final rounding = figure.blobs.where((b) =>
          corners.every((c) => (c - b.$1).distance <= b.$2 + 1e-9));
      expect(rounding, isNotEmpty,
          reason: 'no disc covers both bottom corners of the trunk: the seat '
              'is still the sharpest point on the figure');
    });

    test('and the shoulders are domed the same way', () {
      final figure = buildSilhouette(squatBottomTarget);
      final corners = [figure.torso[0], figure.torso[1]];
      expect(
          figure.blobs.any((b) =>
              corners.every((c) => (c - b.$1).distance <= b.$2 + 1e-9)),
          isTrue);
    });

    test('the extremities are rounder than the limb they end', () {
      // This is the whole of the hands and feet. A fist is wider than the
      // wrist under it and a heel is wider than the ankle, and neither is a
      // shape this can know the DIRECTION of — an authored side view says
      // nothing about which way the toes point, and a foot drawn pointing the
      // wrong way is worse than no foot.
      final figure = buildSilhouette(squatTopTarget);
      double discAt(LandmarkType t) {
        final i = figure.jointTypes.indexOf(t);
        expect(i, greaterThanOrEqualTo(0), reason: '$t is not drawn');
        final at = figure.joints[i];
        return figure.blobs
            .firstWhere((b) => (b.$1 - at).distance < 1e-9)
            .$2;
      }

      // Against the outline's own half-width at that joint, which is the pair
      // of points straddling the last joint of the limb polygon. Reading the
      // girth constant out of the source instead would be asserting that a
      // number equals itself.
      //
      // The leg is found by WHERE IT ENDS, not by its point count. The first
      // draft took `limbs.firstWhere((l) => l.length == 6)` — and the arms are
      // built before the legs and have three joints each, so that is an arm.
      // It compared the ankle's disc against the WRIST's half-width, which is
      // narrower to begin with, so the assertion passed with the ankle's
      // rounding removed entirely: the test was structurally blind to the one
      // defect it names. Found in review, and it is the same failure class as
      // the anchor-on-an-import this project has hit before.
      final ankle = figure.joints[figure.jointTypes.indexOf(
          LandmarkType.leftAnkle)];
      Offset tipOf(List<Offset> limb) => (limb[2] + limb[3]) / 2;
      final leg = figure.limbs
          .where((l) => l.length == 6)
          .reduce((a, b) => (tipOf(a) - ankle).distance <=
                  (tipOf(b) - ankle).distance
              ? a
              : b);
      expect((tipOf(leg) - ankle).distance, lessThan(1e-9),
          reason: 'positive control: this outline really does end at the '
              'ankle, so its tip width is the shin and not an arm');

      final tip = (leg[2] - leg[3]).distance / 2;
      expect(discAt(LandmarkType.leftAnkle), greaterThan(tip),
          reason: 'the foot is no wider than the shin above it');
    });

    test('a hand pushes the bounds out past the wrist', () {
      // The consequence for `fitSilhouette`, which fits to these bounds: a
      // hand outside them is a hand clipped off at the edge of the panel.
      final figure = buildSilhouette(squatBottomTarget);
      final b = figure.bounds;
      for (final (centre, r) in figure.blobs) {
        expect(
          centre.dx - r >= b.left - 1e-9 &&
              centre.dx + r <= b.right + 1e-9 &&
              centre.dy - r >= b.top - 1e-9 &&
              centre.dy + r <= b.bottom + 1e-9,
          isTrue,
          reason: 'a disc at $centre radius $r escapes the bounds $b',
        );
      }
    });

    test('a figure with no torso has no discs either', () {
      const noHip = PoseTarget(
        id: 'fragment',
        joints: {LandmarkType.leftShoulder: (0.5, 0.3)},
        bones: [],
      );
      expect(buildSilhouette(noHip).blobs, isEmpty);
    });
  });
}
