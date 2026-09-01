import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_avatar.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_silhouette.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// Gate G6 — the far side, held across the frames the detector drops it in.
///
/// G5 established the defect by measurement and deferred the fix here by name:
/// the far side is gained and lost as ONE torso, so a body that blinks goes
/// from shoulder width to chest depth and back in a single frame — about a
/// fifth of its trunk. Nothing stateless can smooth that, because with no far
/// side observed there is no measurement to interpolate towards.
///
/// What is asserted here is the pair of bounds, not just the hold. A latch with
/// no expiry is a figure that will not turn; a latch with no distance check is
/// a far side pasted onto a body that walked away from it. Both are worse than
/// the snap.

PoseLandmark _p(LandmarkType t, double x, double y, [double l = 0.9]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: l);

/// A frontal body with both sides visible. [rightLikelihood] below the floor is
/// how a real dropout arrives — the joints are still reported, the detector has
/// simply stopped believing them.
PoseFrame _body({
  required int ts,
  double x = 0.50,
  double rightLikelihood = 0.9,
}) =>
    PoseFrame(timestampMs: ts, landmarks: {
      LandmarkType.leftShoulder: _p(LandmarkType.leftShoulder, x - 0.09, 0.30),
      LandmarkType.rightShoulder:
          _p(LandmarkType.rightShoulder, x + 0.09, 0.30, rightLikelihood),
      LandmarkType.leftHip: _p(LandmarkType.leftHip, x - 0.07, 0.58),
      LandmarkType.rightHip:
          _p(LandmarkType.rightHip, x + 0.07, 0.58, rightLikelihood),
      LandmarkType.leftKnee: _p(LandmarkType.leftKnee, x - 0.07, 0.78),
      LandmarkType.rightKnee:
          _p(LandmarkType.rightKnee, x + 0.07, 0.78, rightLikelihood),
      // Ankles as well as knees: `limbPair` drops a chain it cannot resolve
      // end to end ("a partial limb is worse than none"), so a body without
      // them draws no legs at all and the bone-naming tests below would be
      // asserting over the neck alone.
      LandmarkType.leftAnkle: _p(LandmarkType.leftAnkle, x - 0.07, 0.95),
      LandmarkType.rightAnkle:
          _p(LandmarkType.rightAnkle, x + 0.07, 0.95, rightLikelihood),
    });

double _trunkWidth(PoseFrame frame, {AvatarFarSideLatch? latch}) {
  final figure = buildPoseAvatar(frame, latch: latch);
  if (figure.torso.isEmpty) return 0;
  var min = double.infinity;
  var max = -double.infinity;
  for (final p in figure.torso) {
    if (p.dx < min) min = p.dx;
    if (p.dx > max) max = p.dx;
  }
  return max - min;
}

void main() {
  test('the defect is real, and this is it', () {
    // The positive control the whole gate rests on, measured rather than
    // quoted from G5's write-up. Without a latch, one frame of lost confidence
    // in the far side changes the drawn trunk by a fifth.
    final both = _trunkWidth(_body(ts: 0));
    final blinked = _trunkWidth(_body(ts: 33, rightLikelihood: 0.2));
    expect(both, greaterThan(0));
    expect((both - blinked).abs() / both, greaterThan(0.15),
        reason: 'both=$both blinked=$blinked — if this is small the gate has '
            'nothing to fix and the tests below are meaningless');
  });

  test('a blink no longer changes the drawing', () {
    final latch = AvatarFarSideLatch();
    final both = _trunkWidth(_body(ts: 0), latch: latch);
    final blinked =
        _trunkWidth(_body(ts: 33, rightLikelihood: 0.2), latch: latch);
    expect(blinked, closeTo(both, 1e-9));
  });

  test('and the far side comes back to the observation, not to the held copy',
      () {
    // A latch that kept serving its own copy after the detector recovered
    // would freeze the far side of a moving body — the failure mode a hold
    // invites, and invisible in a test that only ever drops the far side.
    final latch = AvatarFarSideLatch();
    buildPoseAvatar(_body(ts: 0), latch: latch);
    buildPoseAvatar(_body(ts: 33, rightLikelihood: 0.2), latch: latch);
    final target = avatarTargetFrom(_body(ts: 66), latch: latch);
    expect(target!.joints[LandmarkType.rightShoulder]!.$1, closeTo(0.59, 1e-9));
  });

  test('the hold expires on the clock', () {
    final latch = AvatarFarSideLatch(holdMs: 200);
    final both = _trunkWidth(_body(ts: 0), latch: latch);
    final held =
        _trunkWidth(_body(ts: 150, rightLikelihood: 0.2), latch: latch);
    expect(held, closeTo(both, 1e-9),
        reason: 'positive control: still inside the window');

    final expired =
        _trunkWidth(_body(ts: 400, rightLikelihood: 0.2), latch: latch);
    expect(expired, lessThan(both * 0.9),
        reason: 'a body that turned side-on and stayed there must reach its '
            'profile, not keep a far side it no longer has');
  });

  test('and expires early when the body moves away from where it was held', () {
    // The other bound. Time alone would keep drawing a far side at coordinates
    // the lifter has left.
    //
    // Asserted on the JOINTS the producer emits, not on the trunk width the
    // first draft of this test used. That draft passed with the distance check
    // deleted: a far side held at the old position beside a near side at the
    // new one produces a sheared torso whose width happens to fall on the same
    // side of the threshold as an honestly-narrow one. It was measuring a
    // consequence two layers downstream and could not tell the two apart.
    final latch = AvatarFarSideLatch(holdMs: 2000);
    avatarTargetFrom(_body(ts: 0), latch: latch);

    final stayed = avatarTargetFrom(
        _body(ts: 33, rightLikelihood: 0.2), latch: latch);
    expect(stayed!.joints.containsKey(LandmarkType.rightShoulder), isTrue,
        reason: 'positive control: a body that did NOT move keeps its held '
            'far side, so the assertion below is about the movement');

    // Re-primed by the positive control above, then moved a third of the frame
    // sideways — far past 0.12 of a torso.
    avatarTargetFrom(_body(ts: 66), latch: latch);
    final moved = avatarTargetFrom(
        _body(ts: 99, x: 0.75, rightLikelihood: 0.2), latch: latch);
    expect(moved!.joints.containsKey(LandmarkType.rightShoulder), isFalse,
        reason: 'the held far side describes a body that is no longer there');
  });

  test('a clock that runs backwards is a new stream, not a fresh latch', () {
    final latch = AvatarFarSideLatch();
    final both = _trunkWidth(_body(ts: 5000), latch: latch);
    final restarted =
        _trunkWidth(_body(ts: 0, rightLikelihood: 0.2), latch: latch);
    expect(restarted, lessThan(both * 0.9));
  });

  test('the invariant G5 settled survives the latch: the far side is still one '
      'torso', () {
    // `buildSilhouette` reads "is there a far side" off the presence of a
    // right-keyed shoulder AND hip. A latch that restored one without the
    // other would hand it the half-bilateral torso G5 proved unreachable and
    // deliberately stopped handling.
    final latch = AvatarFarSideLatch();
    avatarTargetFrom(_body(ts: 0), latch: latch);
    for (var ts = 33; ts < 200; ts += 33) {
      final t = avatarTargetFrom(_body(ts: ts, rightLikelihood: 0.2),
          latch: latch);
      expect(
          t!.joints.containsKey(LandmarkType.rightShoulder),
          t.joints.containsKey(LandmarkType.rightHip),
          reason: 'at ${ts}ms: half a torso reached the builder');
    }
  });

  test('nothing to draw resets the latch rather than leaving it primed', () {
    final latch = AvatarFarSideLatch();
    final both = _trunkWidth(_body(ts: 0), latch: latch);
    // An empty frame: the detector saying it cannot see anyone at all.
    expect(
        avatarTargetFrom(
            const PoseFrame(timestampMs: 33, landmarks: {}), latch: latch),
        isNull);
    final after =
        _trunkWidth(_body(ts: 66, rightLikelihood: 0.2), latch: latch);
    expect(after, lessThan(both * 0.9),
        reason: 'the body left the frame and came back in profile; the far '
            'side from before it left is not evidence about it now');
  });

  group('and which JOINTS a fault is about', () {
    // The one shipped rule entitled to fault a repetition — see
    // `FormClassifier.canFault`.
    final active = [PushupAlignmentClassifier()];

    FormFeedback fb(String rule, int severity) => FormFeedback(
          rule: rule,
          severity: severity,
          cueKey: FormCueKey.pushupAlignSagging,
        );

    test('a fault covers the joints its own rule declares', () {
      // Was `expect(joints, active.first.requiredLandmarks)` — an exact match.
      // That was the right claim while the region WAS the declared set, and it
      // was wrong: no bone has both ends in that set, so the highlight lit
      // nothing and fell back to the whole skeleton. The region is now widened
      // deliberately (`_faultRegion`), so the declared joints are a subset of
      // it rather than the whole of it, and the widening itself is asserted in
      // the "the two halves actually meet" group below.
      final joints = avatarFaultJoints(active, fb(active.first.rule, 2));
      expect(joints, containsAll(active.first.requiredLandmarks));
      expect(joints, isNotEmpty,
          reason: 'positive control: this rule declares joints at all');
      expect(joints, isNot(contains(LandmarkType.nose)),
          reason: 'widened along the body, not to the whole of it');
    });

    test('a clean verdict points at nothing', () {
      // Empty means "nowhere", never "everywhere". The painter decides WHETHER
      // to glow off the severity; this only ever says WHERE.
      expect(avatarFaultJoints(active, fb(active.first.rule, 0)), isEmpty);
    });

    test('no verdict at all points at nothing', () {
      expect(avatarFaultJoints(active, null), isEmpty);
    });

    test('a verdict from a rule that is no longer running points at nothing',
        () {
      // The movement changed mid-frame. Lighting the previous movement's
      // joints would be worse than lighting none.
      expect(avatarFaultJoints(active, fb('squat.depth', 2)), isEmpty);
    });
  });

  group('and the two halves actually meet', () {
    /// A whole frontal body, arms included, so every bone the skeleton can draw
    /// is present.
    PoseFrame whole() => PoseFrame(timestampMs: 0, landmarks: {
          LandmarkType.leftShoulder: _p(LandmarkType.leftShoulder, 0.41, 0.30),
          LandmarkType.rightShoulder:
              _p(LandmarkType.rightShoulder, 0.59, 0.30),
          LandmarkType.leftElbow: _p(LandmarkType.leftElbow, 0.38, 0.44),
          LandmarkType.rightElbow: _p(LandmarkType.rightElbow, 0.62, 0.44),
          LandmarkType.leftWrist: _p(LandmarkType.leftWrist, 0.36, 0.56),
          LandmarkType.rightWrist: _p(LandmarkType.rightWrist, 0.64, 0.56),
          LandmarkType.leftHip: _p(LandmarkType.leftHip, 0.43, 0.58),
          LandmarkType.rightHip: _p(LandmarkType.rightHip, 0.57, 0.58),
          LandmarkType.leftKnee: _p(LandmarkType.leftKnee, 0.43, 0.78),
          LandmarkType.rightKnee: _p(LandmarkType.rightKnee, 0.57, 0.78),
          LandmarkType.leftAnkle: _p(LandmarkType.leftAnkle, 0.43, 0.95),
          LandmarkType.rightAnkle: _p(LandmarkType.rightAnkle, 0.57, 0.95),
        });

    /// The painter's own rule: a bone lights when BOTH of its ends are in the
    /// fault region. Reproduced here rather than reached through the painter,
    /// because a CustomPainter's chosen colours are not observable from a
    /// widget test — which is precisely how this went unnoticed.
    List<(LandmarkType?, LandmarkType?)> litBones(
        SilhouetteFigure figure, Set<LandmarkType> region) {
      expect(figure.segmentBones.length, figure.segments.length);
      return [
        for (final b in figure.segmentBones)
          if (b.$1 != null &&
              b.$2 != null &&
              region.contains(b.$1) &&
              region.contains(b.$2))
            b,
      ];
    }

    test('a fault from the one rule that can fault lights REAL bones', () {
      // The test this gate should have had from the start, and the one whose
      // absence let G6 ship as dead code: it crosses the boundary between the
      // rule's declared joints and the skeleton's actual bone list. Both halves
      // were tested on their own and both were correct on their own; their
      // intersection was empty.
      final region = avatarFaultJoints(
        [PushupAlignmentClassifier()],
        const FormFeedback(
          rule: 'pushup.alignment',
          severity: 2,
          cueKey: FormCueKey.pushupAlignSagging,
        ),
      );
      final lit = litBones(buildPoseAvatar(whole()), region);
      expect(lit, isNotEmpty,
          reason: 'no bone had both ends in the region, so the glow falls back '
              'to the whole skeleton — the pre-G6 behaviour');
      expect(lit, contains((LandmarkType.leftHip, LandmarkType.leftKnee)));
      expect(lit, contains((LandmarkType.leftKnee, LandmarkType.leftAnkle)));
    });

    test('and it is a NARROWING — the arms stay dark', () {
      // The other half of the claim. A region that lit every bone would pass
      // the test above while being exactly the defect it was written for.
      final region = avatarFaultJoints(
        [PushupAlignmentClassifier()],
        const FormFeedback(
          rule: 'pushup.alignment',
          severity: 2,
          cueKey: FormCueKey.pushupAlignSagging,
        ),
      );
      final figure = buildPoseAvatar(whole());
      final lit = litBones(figure, region);
      expect(lit.length, lessThan(figure.segments.length));
      expect(lit, isNot(contains((LandmarkType.leftShoulder,
          LandmarkType.leftElbow))));
    });

    test('a fault is about a body, not about its left half', () {
      // Every classifier declares LEFT-keyed joints, because the avatar is
      // built from one side and mirrored. Lighting only the left leg for a
      // sagging hip would be reporting on a coordinate convention.
      final region = avatarFaultJoints(
        [PushupAlignmentClassifier()],
        const FormFeedback(
          rule: 'pushup.alignment',
          severity: 2,
          cueKey: FormCueKey.pushupAlignSagging,
        ),
      );
      expect(region, contains(LandmarkType.rightHip));
      expect(region, contains(LandmarkType.rightAnkle));
      final lit = litBones(buildPoseAvatar(whole()), region);
      expect(lit, contains((LandmarkType.rightHip, LandmarkType.rightKnee)));
    });
  });

  group('the ring lands on a joint that exists', () {
    const sagging = FormFeedback(
      rule: 'pushup.alignment',
      severity: 2,
      cueKey: FormCueKey.pushupAlignSagging,
    );

    test('the vertex is the joint the rule turns its angle on', () {
      // `_angleDeg(shoulder, hip, ankle)` — the hip is the middle argument, so
      // it is the vertex, and it is where a sag physically happens. Read off
      // the classifier rather than restated here, so the two cannot drift.
      expect(avatarFaultVertices([PushupAlignmentClassifier()], sagging),
          contains(PushupAlignmentClassifier().faultVertex));
    });

    test('and the figure really carries that joint, under that name', () {
      // The same intersection check the per-bone highlight needed and did not
      // have: a vertex the skeleton never names is a ring drawn on nothing,
      // and both halves would still pass their own tests.
      final figure = buildPoseAvatar(_body(ts: 0));
      expect(figure.jointTypes.length, figure.joints.length);
      final vertices =
          avatarFaultVertices([PushupAlignmentClassifier()], sagging);
      expect(vertices, isNotEmpty);
      final marked = [
        for (final t in figure.jointTypes)
          if (t != null && vertices.contains(t)) t,
      ];
      expect(marked, isNotEmpty,
          reason: 'the ring would be drawn on no joint at all');
    });

    test('a rule with no vertex gets no ring rather than an arbitrary one', () {
      // `SquatDepthClassifier` compares two heights; there is no angle and no
      // joint it turns on. Silence is the honest answer.
      expect(
          avatarFaultVertices([SquatDepthClassifier()],
              const FormFeedback(
                rule: 'squat.depth',
                severity: 2,
                cueKey: FormCueKey.squatDepthHalf,
              )),
          isEmpty);
    });

    test('and a clean rep gets none', () {
      expect(
          avatarFaultVertices([PushupAlignmentClassifier()],
              const FormFeedback(
                rule: 'pushup.alignment',
                severity: 0,
                cueKey: FormCueKey.pushupAlignStraight,
              )),
          isEmpty);
    });
  });

  group('the skeleton knows which bones a rule is about', () {
    test('every bone is named, index for index with the segments it pairs to',
        () {
      final figure = buildPoseAvatar(_body(ts: 0));
      expect(figure.segments, isNotEmpty);
      expect(figure.segmentBones.length, figure.segments.length);
    });

    test('a leg bone is named by its own two joints', () {
      final figure = buildPoseAvatar(_body(ts: 0));
      expect(
          figure.segmentBones,
          contains(
              (LandmarkType.leftHip, LandmarkType.leftKnee)),
          reason: 'without this the glow cannot tell a thigh from a spine');
    });

    test('and a mirrored limb is deliberately anonymous', () {
      // A one-sided target's limbs are drawn twice from one observation. The
      // reflection is where the far limb PROBABLY is; lighting it for a rule
      // that measured only the near one would be reporting on a guess.
      final sideOn = PoseFrame(timestampMs: 0, landmarks: {
        LandmarkType.leftShoulder: _p(LandmarkType.leftShoulder, 0.50, 0.30),
        LandmarkType.leftHip: _p(LandmarkType.leftHip, 0.50, 0.58),
        LandmarkType.leftKnee: _p(LandmarkType.leftKnee, 0.50, 0.78),
      });
      final figure = buildPoseAvatar(sideOn);
      expect(figure.segmentBones, isNotEmpty);
      expect(figure.segmentBones.where((b) => b.$1 == null && b.$2 == null),
          isNotEmpty,
          reason: 'the neck at least, and the mirrored leg');
    });
  });
}
