import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_avatar.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart';

/// The outline goes on the user, not where it was drawn.
///
/// `poseMatchScore` has always been invariant to where the user stands and how
/// big they are. The outline was not: it was drawn at the coordinates it was
/// authored at. Photographed on an S23 at 20:30:17 with a real body in shot,
/// mid-squat: a large centred outline, the tracked figure offset from it, and
/// ТЕХНИКА reading 85%. Both halves were correct on their own terms and they
/// contradicted each other on screen — which is worse than either being wrong,
/// because the entire instruction to the user is "match the shape".
///
/// These tests pin the transform that closes that gap, and they use the real
/// joint coordinates from that session's log rather than invented ones.

PoseFrame _frame(Map<LandmarkType, (double, double)> joints,
    {double likelihood = 0.9, double aspectRatio = 2 / 3}) {
  return PoseFrame(
    timestampMs: 0,
    aspectRatio: aspectRatio,
    landmarks: {
      for (final e in joints.entries)
        e.key: PoseLandmark(
          type: e.key,
          x: e.value.$1,
          y: e.value.$2,
          likelihood: likelihood,
        ),
    },
  );
}

/// Repetition #3 of the S23 session, at its deepest frame, straight from
/// `logcat_reps.txt` in `reports/device-check-2026-09-02/`, relative to the
/// repository root rather than to this Flutter package. It scored 0.895 — a
/// clearly passing repetition, which is exactly the case where a visibly
/// separated outline is most confusing.
final _s23Rep3 = _frame(const {
  LandmarkType.leftShoulder: (0.410, 0.418),
  LandmarkType.leftElbow: (0.512, 0.505),
  LandmarkType.leftWrist: (0.629, 0.546),
  LandmarkType.leftHip: (0.250, 0.575),
  LandmarkType.leftKnee: (0.438, 0.566),
  LandmarkType.leftAnkle: (0.384, 0.739),
}, aspectRatio: 0.667);

(double, double) _centroidOf(Iterable<(double, double)> ps) {
  var cx = 0.0, cy = 0.0, n = 0;
  for (final p in ps) {
    cx += p.$1;
    cy += p.$2;
    n++;
  }
  return (cx / n, cy / n);
}

/// The joints the score actually compares — the same subset the alignment uses.
List<(double, double)> _scoredOf(PoseTarget t) => [
      for (final e in t.joints.entries)
        if (!t.unscoredJoints.contains(e.key)) e.value
    ];

List<(double, double)> _scoredLive(PoseFrame f, PoseTarget t) => [
      for (final e in t.joints.entries)
        if (!t.unscoredJoints.contains(e.key))
          (f.landmarks[e.key]!.x, f.landmarks[e.key]!.y)
    ];

double _rmsOf(List<(double, double)> ps) {
  final c = _centroidOf(ps);
  var sum = 0.0;
  for (final p in ps) {
    sum += math.pow(p.$1 - c.$1, 2) + math.pow(p.$2 - c.$2, 2);
  }
  return math.sqrt(sum / ps.length);
}

void main() {
  group('the outline is placed on the body it is scored against', () {
    test('a body that IS the target, moved and resized, gets it back exactly',
        () {
      // The strongest statement of what this transform means: when the live
      // body is a pure similarity of the target, aligning the target must
      // reproduce the body joint for joint. Any residual here is the transform
      // itself being wrong, with no pose difference to hide behind.
      const k = 0.41; // the user stands further away
      const dx = 0.19, dy = -0.22; // and off to one side
      final moved = {
        for (final e in squatBottomTarget.joints.entries)
          e.key: (e.value.$1 * k + dx, e.value.$2 * k + dy)
      };
      final frame = _frame(moved);

      final align = alignTargetToFrame(frame, squatBottomTarget);
      expect(align, isNotNull);
      expect(align!.mirror, isFalse);
      expect(align.scale, closeTo(k, 1e-9));

      for (final e in squatBottomTarget.joints.entries) {
        final got = align(e.value);
        expect(got.$1, closeTo(moved[e.key]!.$1, 1e-9), reason: '${e.key} x');
        expect(got.$2, closeTo(moved[e.key]!.$2, 1e-9), reason: '${e.key} y');
      }
      // And the score agrees it is a perfect match, which is the point: the
      // picture and the number now come from the same arithmetic.
      expect(poseMatchScore(frame, squatBottomTarget), closeTo(1.0, 1e-9));
    });

    test('a body facing the other way is mirrored, not stretched onto itself',
        () {
      // `poseMatchScore` scores both facings and keeps the better one. If the
      // placement did not make the same choice, a user filmed from their other
      // side would see a high score under an outline facing away from them.
      const axis = 0.5;
      final flipped = {
        for (final e in squatBottomTarget.joints.entries)
          e.key: (2 * axis - e.value.$1, e.value.$2)
      };
      final frame = _frame(flipped);

      final align = alignTargetToFrame(frame, squatBottomTarget);
      expect(align, isNotNull);
      expect(align!.mirror, isTrue);
      expect(align.scale, closeTo(1.0, 1e-9));
      for (final e in squatBottomTarget.joints.entries) {
        final got = align(e.value);
        expect(got.$1, closeTo(flipped[e.key]!.$1, 1e-9), reason: '${e.key} x');
        expect(got.$2, closeTo(flipped[e.key]!.$2, 1e-9), reason: '${e.key} y');
      }
    });

    test('an unmirrored body is left unmirrored', () {
      // The positive control for the test above. Without it, an
      // `alignTargetToFrame` that always reported `mirror: true` would pass
      // there and draw every outline back to front.
      final align = alignTargetToFrame(_s23Rep3, squatBottomTarget);
      expect(align, isNotNull);
      expect(align!.mirror, isFalse);
    });
  });

  group('the gap this closes, measured on the device recording', () {
    test('the outline was a fifth of a frame away from the body it scored 0.895',
        () {
      // The defect, in numbers rather than in a screenshot. Both figures are
      // drawn through the same projection, so a centroid gap in this space is
      // a visible gap on the panel: 0.18 of the frame height is roughly 270
      // logical pixels on the S23's coach panel.
      final target = _centroidOf(_scoredOf(squatBottomTarget));
      final body = _centroidOf(_scoredLive(_s23Rep3, squatBottomTarget));
      final gap = math.sqrt(math.pow(target.$1 - body.$1, 2) +
          math.pow(target.$2 - body.$2, 2));
      expect(gap, greaterThan(0.15),
          reason: 'the recorded frame no longer shows the separation these '
              'tests exist to fix');

      // The score, meanwhile, was almost 0.9 — which is what made it confusing
      // rather than merely wrong.
      expect(poseMatchScore(_s23Rep3, squatBottomTarget), greaterThan(0.85));
    });

    test('and after alignment the two sit on each other', () {
      final align = alignTargetToFrame(_s23Rep3, squatBottomTarget)!;
      final placed = [for (final p in _scoredOf(squatBottomTarget)) align(p)];
      final body = _scoredLive(_s23Rep3, squatBottomTarget);

      // The hip is the anchor, so it lands exactly. Everything else lands as
      // close as the shapes themselves agree.
      final hip = align(squatBottomTarget.joints[LandmarkType.leftHip]!);
      expect(hip.$1,
          closeTo(_s23Rep3.landmarks[LandmarkType.leftHip]!.x, 1e-12));
      expect(hip.$2,
          closeTo(_s23Rep3.landmarks[LandmarkType.leftHip]!.y, 1e-12));

      // One anchored joint is not enough — pinning a hip while the rest of the
      // figure is the wrong size still draws two unrelated bodies. What is left
      // over per joint must be the shape difference the 0.895 already
      // describes, and nothing more: a fraction of the gap the outline used to
      // sit at.
      var worst = 0.0;
      for (var i = 0; i < placed.length; i++) {
        worst = math.max(
            worst,
            math.sqrt(math.pow(placed[i].$1 - body[i].$1, 2) +
                math.pow(placed[i].$2 - body[i].$2, 2)));
      }
      expect(worst, lessThan(0.06));
      // And it really is closer than before: the centroid gap the test above
      // measures at 0.19 has to have gone somewhere.
      final movedCentre = _centroidOf(placed);
      final bodyCentre = _centroidOf(body);
      final residual = math.sqrt(math.pow(movedCentre.$1 - bodyCentre.$1, 2) +
          math.pow(movedCentre.$2 - bodyCentre.$2, 2));
      expect(residual, lessThan(0.02));
    });
  });

  group('the outline keeps ONE size while the user moves', () {
    // The regression the golden caught, and the reason this is not the score's
    // own normalisation. The first version scaled by RMS radius over the
    // scored joints — a property of the POSE — so a user standing tall in front
    // of a deep-squat target measured 1.687 target radii and the outline
    // ballooned off the panel. That state is not an edge case: it is where
    // every set begins.
    final standing = _frame(const {
      LandmarkType.leftShoulder: (0.22, 0.26),
      LandmarkType.leftHip: (0.24, 0.54),
      LandmarkType.leftKnee: (0.24, 0.74),
      LandmarkType.leftAnkle: (0.24, 0.93),
      LandmarkType.leftElbow: (0.19, 0.40),
      LandmarkType.leftWrist: (0.17, 0.53),
    }, aspectRatio: 9 / 16);

    test('a standing body does not inflate a squat outline', () {
      final align = alignTargetToFrame(standing, squatBottomTarget);
      expect(align, isNotNull);
      // The same body, the same target, under the rule that shipped: 1.09
      // rather than 1.687.
      expect(align!.scale, lessThan(1.25),
          reason: 'the outline is drawn 1.25x its authored size or larger, '
              'which is how it left the panel the first time');
      expect(poseMatchScore(standing, squatBottomTarget), lessThan(0.5),
          reason: 'positive control: this body is NOT in the target pose, so '
              'the size above cannot be coming from a good match');
    });

    test('and the same body squatting is drawn at almost the same size', () {
      // The property the anchor exists for, stated directly: the outline must
      // not resize under the user as they move through the movement. Both
      // frames are the same person — the S23 recording and this fixture are
      // not, so this compares the standing fixture against itself bent.
      final squatting = _frame(const {
        LandmarkType.leftShoulder: (0.25, 0.44),
        LandmarkType.leftHip: (0.20, 0.70),
        LandmarkType.leftKnee: (0.33, 0.70),
        LandmarkType.leftAnkle: (0.26, 0.93),
        LandmarkType.leftElbow: (0.30, 0.57),
        LandmarkType.leftWrist: (0.38, 0.60),
      }, aspectRatio: 9 / 16);

      final a = alignTargetToFrame(standing, squatBottomTarget)!;
      final b = alignTargetToFrame(squatting, squatBottomTarget)!;
      expect((a.scale - b.scale).abs() / a.scale, lessThan(0.1),
          reason: 'the outline changes size by more than a tenth between the '
              'top and the bottom of a repetition');

      // Under the score's own normalisation the same pair differed far more,
      // which is what made the picture unusable rather than merely imprecise.
      final rmsRatio = _rmsOf(_scoredLive(squatting, squatBottomTarget)) /
          _rmsOf(_scoredLive(standing, squatBottomTarget));
      expect((1 - rmsRatio).abs(), greaterThan(0.1),
          reason: 'positive control: the pose-dependent measure this replaced '
              'really does move between these two frames');
    });
  });

  group('it anchors where the body is DRAWN, not where a joint was recorded',
      () {
    // Raised by review and then found on the device before the review landed:
    // every test above builds its live body as a pure similarity of the
    // target, and under a pure similarity ANY fixed anchor reproduces the
    // mapping exactly — so four "gets it back exactly" tests say nothing about
    // which point is the anchor. On the S23 at 21:12 the outline sat half a
    // hip-width to one side of the user: right size, right posture, not on top
    // of them.
    //
    // `buildSilhouette` runs a body's spine through the midpoint of a pair
    // when both sides are observed and through the single joint when only one
    // is. A shipped target authors one side, a real frame has two — so the
    // anchor has to follow that rule rather than always reading `leftHip`.
    final twoSided = _frame(const {
      // A wide body, so left hip and midline are far apart: 0.09 in x, which
      // is a fifth of this body's own height. A left-joint anchor cannot pass
      // this by accident.
      LandmarkType.leftShoulder: (0.30, 0.30),
      LandmarkType.rightShoulder: (0.48, 0.30),
      LandmarkType.leftHip: (0.31, 0.58),
      LandmarkType.rightHip: (0.49, 0.58),
      LandmarkType.leftKnee: (0.32, 0.76),
      LandmarkType.leftAnkle: (0.32, 0.94),
    });

    test('a two-sided body is anchored on its midline', () {
      final align = alignTargetToFrame(twoSided, squatBottomTarget)!;
      final placed = align(squatBottomTarget.joints[LandmarkType.leftHip]!);
      // The midpoint of the two hips, not the left one.
      expect(placed.$1, closeTo(0.40, 1e-12));
      expect(placed.$2, closeTo(0.58, 1e-12));
      expect(placed.$1, isNot(closeTo(0.31, 0.02)),
          reason: 'anchored on the recorded left hip, which is where the '
              'outline drifted off the body on the device');
    });

    test('and sized by the distance between those midlines', () {
      // The same substitution has to reach the scale, or the outline is put in
      // the right place at a size measured from a different pair of points.
      final align = alignTargetToFrame(twoSided, squatBottomTarget)!;
      const shoulderMid = (0.39, 0.30), hipMid = (0.40, 0.58);
      final liveTorso = math.sqrt(math.pow(shoulderMid.$1 - hipMid.$1, 2) +
          math.pow(shoulderMid.$2 - hipMid.$2, 2));
      final wantTorso = math.sqrt(math.pow(
              squatBottomTarget.joints[LandmarkType.leftShoulder]!.$1 -
                  squatBottomTarget.joints[LandmarkType.leftHip]!.$1,
              2) +
          math.pow(
              squatBottomTarget.joints[LandmarkType.leftShoulder]!.$2 -
                  squatBottomTarget.joints[LandmarkType.leftHip]!.$2,
              2));
      expect(align.scale, closeTo(liveTorso / wantTorso, 1e-12));
    });

    test('a far side the detector is unsure of is left out of the midline', () {
      // Not a detail: a low-confidence far-side joint is usually a guess about
      // a limb the camera cannot see, and averaging it in drags the midline
      // off the body — the exact drift this group exists to remove, caused by
      // the fix for it.
      final unsureFarSide = _frame(const {
        LandmarkType.leftShoulder: (0.30, 0.30),
        LandmarkType.leftHip: (0.31, 0.58),
        LandmarkType.leftKnee: (0.32, 0.76),
        LandmarkType.leftAnkle: (0.32, 0.94),
      });
      final sure = alignTargetToFrame(unsureFarSide, squatBottomTarget)!;

      final withJunk = PoseFrame(
        timestampMs: 0,
        aspectRatio: unsureFarSide.aspectRatio,
        landmarks: {
          ...unsureFarSide.landmarks,
          LandmarkType.rightHip: const PoseLandmark(
              type: LandmarkType.rightHip, x: 0.9, y: 0.1, likelihood: 0.2),
        },
      );
      final withJunkAlign = alignTargetToFrame(withJunk, squatBottomTarget)!;
      expect(withJunkAlign.bodyCentre, sure.bodyCentre,
          reason: 'a hip the detector gave 0.2 confidence to moved the anchor');
      expect(withJunkAlign.scale, sure.scale);
    });
  });

  group('and it declines to guess', () {
    test('three shared joints is a fragment, not a placement', () {
      // The same floor `poseMatchScore` has, and for the same reason: a
      // transform fitted to too few points will land them perfectly on any
      // other points and say nothing. Drawn, that is an outline sliding around
      // the panel on noise.
      final partial = _frame(const {
        LandmarkType.leftShoulder: (0.41, 0.42),
        LandmarkType.leftHip: (0.25, 0.58),
        LandmarkType.leftKnee: (0.44, 0.57),
        // no ankle, and the wrist and elbow are unscored for this target
        LandmarkType.leftWrist: (0.63, 0.55),
        LandmarkType.leftElbow: (0.51, 0.51),
      });
      expect(alignTargetToFrame(partial, squatBottomTarget), isNull);
      expect(poseMatchScore(partial, squatBottomTarget), isNull,
          reason: 'the two must agree on when a body cannot be read');
    });

    test('a joint the detector barely saw does not count', () {
      final unsure = _frame({
        for (final e in squatBottomTarget.joints.entries) e.key: e.value
      }, likelihood: 0.2);
      expect(alignTargetToFrame(unsure, squatBottomTarget), isNull);
    });

    test('a torso far longer than any real body is not scaled up either', () {
      // The guard `alignTargetToBody` needs, added for gate G14 -- and
      // corrected once already. The first version cited a *reconstruction*
      // of the S23 report from `PoseUnitProbe`'s session-accumulated extent,
      // which GPT-PM's round-1 review correctly rejected: that probe folds
      // in every frame and every landmark since the controller was built, so
      // its logged min/max cannot be attributed to one frame's shoulder and
      // hip. This version uses a REAL single-frame reading instead: captured
      // live on a Mi 9T Pro, 2026-09-03, reproducing the same trigger (step
      // out of frame mid-set) with the `[align]` log added in response to
      // that review. `reports/device-check-2026-09-02/` logcat, 13:51:35.894 --
      // `liveShoulder=(0.526, 0.176) liveHip=(0.536, 0.806) liveTorso=0.630`.
      // Both joints individually pass `pose_avatar.dart`'s own +-0.5 draw
      // slack (meant for a real ankle legitimately extrapolated just past the
      // frame edge) while sitting near opposite corners of that widened box.
      // In the same session, nine matched, correctly-scored reps measured
      // 0.252-0.256 at their deepest frame -- within noise of `wantTorso`
      // (0.257) -- so 0.630 is not a framing choice, it is the defect.
      final stretched = _frame({
        for (final e in squatBottomTarget.joints.entries) e.key: e.value,
        LandmarkType.leftShoulder: (0.5262, 0.1756),
        LandmarkType.leftHip: (0.5359, 0.8056),
      });
      expect(alignTargetToFrame(stretched, squatBottomTarget), isNull);
    });

    test(
        'and the same, fed through the actual production path rather than '
        'the guard in isolation', () {
      // The unit test above hand-builds a body map and calls
      // `alignTargetToFrame`, which only filters by likelihood/NaN. The live
      // screen never calls that -- it reads `stabilisedBodyProvider`, which
      // runs `avatarTargetFrom` first (`pose_avatar.dart`), and THAT filters
      // every joint through `_drawable`'s own +-0.5 slack before this
      // function ever sees it. Flagged in review: a unit test on the guard
      // alone cannot say whether the bad coordinates actually survive that
      // upstream filtering unchanged, only that IF they arrive here, they are
      // rejected. This confirms the first half too, with the same real
      // single-frame numbers from the Mi 9T Pro reproduction above, at 0.9
      // likelihood -- comfortably above both `avatarTargetFrom`'s 0.5 floor
      // and the 0.70 "trusted" threshold the probe itself used.
      final wildFrame = _frame({
        // Knee and ankle at plausible, unremarkable positions -- their job is
        // only to keep `live.length >= 4` past `alignTargetToBody`'s own
        // "too few shared joints" floor, so the torso guard is the check
        // this test actually exercises rather than that earlier one. Not a
        // claim about what the real bad frame's knee/ankle were -- only the
        // shoulder and hip were captured by the `[align]` log.
        LandmarkType.leftKnee: squatBottomTarget.joints[LandmarkType.leftKnee]!,
        LandmarkType.leftAnkle:
            squatBottomTarget.joints[LandmarkType.leftAnkle]!,
        LandmarkType.leftShoulder: (0.5262, 0.1756),
        LandmarkType.leftHip: (0.5359, 0.8056),
      }, likelihood: 0.9);

      final body = avatarTargetFrom(wildFrame);
      expect(body, isNotNull,
          reason: 'positive control: a shoulder+hip pair this confident is '
              'a torso `avatarTargetFrom` should still report');
      expect(alignTargetToBody(body!.joints, squatBottomTarget), isNull);
    });

    test('a real, well-matched torso is not rejected by the same guard', () {
      // The guard's other failure mode is not tested by anything above: a
      // threshold set too low would reject good frames too, and both tests
      // above only ever feed it bad ones. Positive control, using the
      // deepest frame of a real passing rep from the same Mi 9T Pro session
      // (`[rep] #1 ... peak=0.866 pass=0.8 missed=false`), not a fixture:
      // `leftShoulder=0.483,0.493 leftHip=0.292,0.657`, torso 0.252 --
      // within noise of `wantTorso` 0.257, and comfortably under the 0.40
      // cutoff that rejects the bad frame above.
      final goodRep = _frame(const {
        LandmarkType.leftShoulder: (0.483, 0.493),
        LandmarkType.leftElbow: (0.540, 0.618),
        LandmarkType.leftWrist: (0.632, 0.643),
        LandmarkType.leftHip: (0.292, 0.657),
        LandmarkType.leftKnee: (0.488, 0.630),
        LandmarkType.leftAnkle: (0.427, 0.809),
      }, aspectRatio: 0.667);
      expect(alignTargetToFrame(goodRep, squatBottomTarget), isNotNull);
    });

    test(
        'a real, closer-than-usual body with a genuinely reliable tracking '
        'read is not rejected either, even mid-band', () {
      // GPT-PM round 3, correcting round 2: `gate=PoseGateVerdict.ok` and a
      // low silhouette match are not the same signal -- a correctly tracked
      // person can simply be in a shape that does not match the target
      // (they had not reached depth yet), and that must not be read as
      // "the coordinates are unusable for placement". This is the case
      // round 2's search did not produce: a real sample, `gate=ok` (not
      // `lowConfidence`), squarely inside the previously-untested band.
      // Deepest frame of rep #25, same Mi 9T Pro session, requested as a
      // deliberately closer-than-usual, well-EXECUTED attempt
      // (`reports/device-check-2026-09-02/mi9_close_good_match_repro_logcat.txt`):
      // `match=0.210` (they were not at depth: `hipMinusKnee=0.104`, well
      // short of the ~0 the target needs) but `gate=PoseGateVerdict.ok` --
      // the low match is explained by pose, not by broken tracking.
      // `leftShoulder=0.345,0.486 leftHip=0.186,0.777`, torso 0.332 -- well
      // inside the 0.26-0.40 band round 2 could not populate, and well clear
      // of the 0.461 pathological floor. The guard must let this through.
      final closerReliableRep = _frame(const {
        LandmarkType.leftShoulder: (0.345, 0.486),
        LandmarkType.leftElbow: (0.418, 0.648),
        LandmarkType.leftWrist: (0.524, 0.556),
        LandmarkType.leftHip: (0.186, 0.777),
        LandmarkType.leftKnee: (0.414, 0.663),
        LandmarkType.leftAnkle: (0.484, 0.796),
      }, aspectRatio: 0.667);
      expect(
          alignTargetToFrame(closerReliableRep, squatBottomTarget), isNotNull);
    });

    test(
        'the closest real attempt this investigation could capture is also '
        'rejected, and it was already unreliable by the app\'s own signals',
        () {
      // GPT-PM's round-2 finding: proving the reject side rejects a clearly
      // bad frame is not enough to justify an absolute cutoff, because
      // `liveTorso` also grows for a genuine body standing closer to the
      // camera -- so the cutoff could equally be rejecting a valid close
      // user. Asked the operator to hold a squat progressively closer to a
      // Mi 9T Pro to find that boundary directly. Every rep that stayed
      // under ~0.26 matched normally. The closest sustained attempt reached
      // liveTorso 0.454-0.470 across 8 consecutive real frames
      // (`reports/device-check-2026-09-02/mi9_close_distance_repro_logcat.txt`,
      // 14:16:06.7-08.9) -- but that same rep independently scored
      // `gate=PoseGateVerdict.lowConfidence` and `match=0.193`, well under
      // the 0.80 pass mark. This is the real coordinate pair at the middle
      // of that cluster (14:16:07.242): not a synthetic near-boundary guess,
      // and not proof the 0.26-0.40 band is empty of legitimate bodies --
      // only that the one real sample this investigation could produce
      // there was already flagged unreliable by the app's own confidence
      // and match signals, independent of this guard.
      final closestRealAttempt = _frame({
        LandmarkType.leftKnee: squatBottomTarget.joints[LandmarkType.leftKnee]!,
        LandmarkType.leftAnkle:
            squatBottomTarget.joints[LandmarkType.leftAnkle]!,
        LandmarkType.leftShoulder: (0.3369, 0.3688),
        LandmarkType.leftHip: (0.1261, 0.7725),
      });
      expect(alignTargetToFrame(closestRealAttempt, squatBottomTarget), isNull);
    });

    test('a body with no extent is not scaled to infinity', () {
      // Every joint on one point. `scale` is a ratio of RMS radii, so this is
      // the division the guard exists for — without it the outline would be
      // drawn at zero size, or the transform would carry a NaN into a Path and
      // crash rather than draw a wrong picture.
      final collapsed = _frame({
        for (final k in squatBottomTarget.joints.keys) k: (0.5, 0.5)
      });
      expect(alignTargetToFrame(collapsed, squatBottomTarget), isNull);
    });
  });

  test('every shipped target can be placed on a body doing it', () {
    // Not just the squat. Each target is turned into a body standing somewhere
    // else at a different size, and must be recoverable — a target whose
    // scored joints are too few or coincident would fail here rather than in
    // front of a user.
    for (final t in allShippedTargets) {
      final moved = <LandmarkType, (double, double)>{
        for (final e in t.joints.entries)
          e.key: (e.value.$1 * 0.63 + 0.05, e.value.$2 * 0.63 + 0.11)
      };
      final align = alignTargetToFrame(_frame(moved), t);
      expect(align, isNotNull, reason: '${t.id} cannot be placed');
      expect(align!.scale, closeTo(0.63, 1e-9), reason: t.id);
      for (final e in t.joints.entries) {
        final got = align(e.value);
        expect(got.$1, closeTo(moved[e.key]!.$1, 1e-9), reason: '${t.id} ${e.key}');
        expect(got.$2, closeTo(moved[e.key]!.$2, 1e-9), reason: '${t.id} ${e.key}');
      }
    }
  });
}
