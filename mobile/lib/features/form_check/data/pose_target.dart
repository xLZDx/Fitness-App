/// A target pose to stand in, and how closely a real body matches it.
///
/// ## Why the app needed this
///
/// Two rules have now been silenced for the same reason. The deadlift rule
/// measured hip flexion and called it spinal curvature. The squat rule compared
/// hip height with knee height in the picture and called it depth. Both were
/// asked to answer "is this technique correct" from an absolute number in a 2D
/// projection, and in both cases correct and incorrect execution produced
/// overlapping numbers — so no threshold could separate them, and the coach
/// confidently told a lifter doing it right to fix something.
///
/// Operator, after being told to squat deeper at the bottom of a squat:
/// *"ниже уже некуда было"*. He was right, and the fix he proposed is the one
/// implemented here: put the correct shape on the screen, let the user aim at
/// it, and score the match.
///
/// ## Why comparing to a target works where a threshold did not
///
/// [poseMatchScore] is invariant to **where** the user stands and **how big**
/// they appear. It centres both poses on their own centroid and scales both to
/// the same body size before comparing. Camera distance and framing — the
/// variables that made hip-versus-knee height meaningless — cancel out.
///
/// ## The limitation, stated plainly
///
/// Facing IS cancelled out, as of `FORMCOACH_TARGET_MIRROR_2026-09-01`:
/// [poseMatchScore] scores the pose against the target and against the
/// target's mirror image and keeps the better. Every shipped target is
/// authored from one side (`_sideViewBones` names only `left*` joints), and
/// before this a perfectly executed squat filmed from the OTHER side scored
/// 0.21 against the 0.80 pass mark — so a lifter who happened to stand the
/// wrong way round could not pass at any skill level, and heard "вы не дошли
/// до силуэта" on every rep. Which shoulder points at the lens is a framing
/// choice, not a technique error. Depth is unaffected: mirroring touches x
/// only.
///
/// Beyond that, this is still a 2D projection, so **viewing angle is not
/// cancelled out**. A
/// squat from the front and the same squat from the side are different shapes,
/// and this will score them differently. That is not a defect to be fixed here;
/// it is the reason the silhouette is drawn on screen. The outline tells the
/// user which view to present, and standing in it is what makes the comparison
/// valid. A target the user cannot see would inherit exactly the hidden
/// assumption that broke the two rules above.
library;

import 'dart:math' as math;

import 'pose_landmark.dart';

/// A named shape to match: joint positions for one phase of one movement.
///
/// **Correction, `FORMCOACH_TARGET_XSCALE_2026-08-31`:** this used to claim
/// coordinates were "in the same isotropic space as [PoseLandmark]". A real
/// device proved that false: x here is authored as a fraction of the frame's
/// WIDTH (0..1, the ordinary normalised-image convention an author reaches
/// for without thinking), while [PoseLandmark]'s isotropic space (see
/// `pose_coordinate_space.dart`) normalises x by HEIGHT, so it only spans
/// `0..aspectRatio` (~0.56 on a 9:16 phone). Drawing these joints straight
/// through `projectLandmark` — which assumes true isotropic input — put the
/// outline's centre (x~0.5) past the right edge of a `0..0.56` frame,
/// clipped off-panel. `buildSilhouette`'s `xScale` parameter is the fix for
/// **drawing**: pass `xScale: frameAspect` to convert on the way in.
///
/// **Correction, `FORMCOACH_MATCHSCORE_XSCALE_2026-08-31`, same day:**
/// [poseMatchScore] was left uncorrected above on the theory that fixing it
/// needed deliberate recalibration first. That was wrong — deferring it left
/// a live, reachable defect: a landmark set that is EXACTLY the target pose,
/// captured with a genuinely correct camera, scored only ~0.74 against the
/// unconverted target, below [kPoseMatchPassing] (0.80) for the best
/// possible match. No amount of correct technique could ever pass. Confirmed
/// live: the operator reported the fixed (centred) silhouette still saying
/// "вы не дошли до силуэта" — this is why. `poseMatchScore` now applies the
/// same `* frame.aspectRatio` correction to `target.joints`' x before
/// comparing. The existing calibration table below was NOT invalidated by
/// this — re-derived synthetically post-fix, a perfect isotropic match
/// scores 1.0 exactly (identity) and a small (±0.02) perturbation scores
/// ~0.81, landing almost exactly on the table's own "real body... nudged:
/// 0.114, 0.81" row, rather than off it. `_zeroScoreAtOffset` (0.6) and
/// [kPoseMatchPassing] (0.80) are kept unchanged.
///
/// Only their **relative** arrangement is scored — [poseMatchScore] removes
/// position and size before comparing. They are authored at plausible
/// screen positions so the same numbers can be drawn as the on-screen
/// outline without a second source of truth.
class PoseTarget {
  // No assert on joint count: `Map.length` is not readable in a const
  // expression, and these are const so they can be written as data. The
  // requirement — at least the four joints `poseMatchScore` needs before it
  // will answer at all — is enforced in `pose_target_test.dart` across every
  // shipped target instead.
  const PoseTarget({
    required this.id,
    required this.joints,
    required this.bones,
  });

  /// Stable identifier, e.g. `squat.top`.
  final String id;

  final Map<LandmarkType, (double, double)> joints;

  /// Which joints to connect when drawing. Not used for scoring.
  final List<(LandmarkType, LandmarkType)> bones;

  /// Where to draw a head, as `(x, y, radius)`, or null when the torso cannot
  /// be located.
  ///
  /// DRAWN, never scored. The scored set stays the six joints a side view
  /// actually shows, because from the side one arm and one leg are behind the
  /// body and the detector's estimates for them are guesses — comparing
  /// against a guess is how a target starts failing people for standing at a
  /// slightly different angle.
  ///
  /// But six dots joined by five lines is not a person. Operator, looking at
  /// it on his phone: *"человеческий силует привратился а закорючку"*. He is
  /// right, and it matters more than it sounds: the whole instruction is
  /// "stand inside this shape", which needs the shape to read as a body at a
  /// glance, from across a room, while moving.
  ///
  /// Derived rather than authored so it cannot drift out of step with the
  /// pose: the head sits above the shoulder along the hip-to-shoulder line,
  /// which keeps it over the chest when the torso inclines into a squat
  /// instead of hanging in the air where a standing head would have been.
  (double, double, double)? get head {
    final shoulder = joints[LandmarkType.leftShoulder];
    final hip = joints[LandmarkType.leftHip];
    if (shoulder == null || hip == null) return null;
    final dx = shoulder.$1 - hip.$1;
    final dy = shoulder.$2 - hip.$2;
    final torso = math.sqrt(dx * dx + dy * dy);
    if (torso <= 0) return null;
    // Proportions of a drawn figure, not of a person: far enough clear of the
    // shoulder to read as a neck, small enough not to dominate the outline.
    const reach = 0.42;
    const radius = 0.17;
    return (
      shoulder.$1 + dx / torso * torso * reach,
      shoulder.$2 + dy / torso * torso * reach,
      torso * radius,
    );
  }
}

/// The joints a side-view lower-body target is described by.
const _sideViewBones = <(LandmarkType, LandmarkType)>[
  (LandmarkType.leftShoulder, LandmarkType.leftHip),
  (LandmarkType.leftHip, LandmarkType.leftKnee),
  (LandmarkType.leftKnee, LandmarkType.leftAnkle),
  (LandmarkType.leftShoulder, LandmarkType.leftElbow),
  (LandmarkType.leftElbow, LandmarkType.leftWrist),
];

/// Standing tall, filmed from the side. The start and end of a squat.
const squatTopTarget = PoseTarget(
  id: 'squat.top',
  joints: {
    LandmarkType.leftShoulder: (0.47, 0.26),
    LandmarkType.leftElbow: (0.48, 0.40),
    LandmarkType.leftWrist: (0.49, 0.53),
    LandmarkType.leftHip: (0.50, 0.53),
    LandmarkType.leftKnee: (0.50, 0.74),
    LandmarkType.leftAnkle: (0.49, 0.93),
  },
  bones: _sideViewBones,
);

/// The bottom of a squat, filmed from the side: hips travelled back and down to
/// about knee height, knees forward over the feet, torso inclined to balance.
///
/// Hand-authored from the movement, not measured off a person — which is
/// honest for a *shape* that scoring normalises for size and position, and
/// would not be honest for an absolute threshold. The numbers below say "hips
/// level with knees, torso inclined about 45 degrees", which is what a parallel
/// squat is; they do not claim to be anyone's actual body.
const squatBottomTarget = PoseTarget(
  id: 'squat.bottom',
  joints: {
    LandmarkType.leftShoulder: (0.52, 0.52),
    LandmarkType.leftElbow: (0.56, 0.62),
    LandmarkType.leftWrist: (0.58, 0.72),
    LandmarkType.leftHip: (0.42, 0.74),
    LandmarkType.leftKnee: (0.57, 0.75),
    LandmarkType.leftAnkle: (0.49, 0.93),
  },
  bones: _sideViewBones,
);

/// A push-up at the top: one straight line from shoulder to ankle, arms under
/// the shoulders, filmed from the side.
const pushupTopTarget = PoseTarget(
  id: 'pushup.top',
  joints: {
    LandmarkType.leftShoulder: (0.35, 0.55),
    LandmarkType.leftElbow: (0.35, 0.68),
    LandmarkType.leftWrist: (0.35, 0.80),
    LandmarkType.leftHip: (0.55, 0.62),
    LandmarkType.leftKnee: (0.72, 0.70),
    LandmarkType.leftAnkle: (0.88, 0.78),
  },
  bones: _sideViewBones,
);

/// The bottom of a push-up: chest close to the floor, elbows drawn back past
/// the ribs, the shoulder-to-ankle line still straight and now nearly flat.
///
/// The wrist does not move — it is on the floor — so the whole body rotates
/// about the toes and the arm folds. Segment lengths are held to within a few
/// percent of [pushupTopTarget]'s, because a demonstration that stretches the
/// forearm while it bends is read as a glitch rather than as a movement.
///
/// Used for the demonstration only. Scoring a push-up still compares against
/// the top position, which is a deliberate difference from the squat and worth
/// naming: the rep counter's signal is hip-versus-knee height, which does not
/// track a push-up at all, so there is no counted push-up rep for a bottom
/// target to judge yet.
const pushupBottomTarget = PoseTarget(
  id: 'pushup.bottom',
  joints: {
    LandmarkType.leftShoulder: (0.31, 0.72),
    LandmarkType.leftElbow: (0.44, 0.72),
    LandmarkType.leftWrist: (0.35, 0.80),
    LandmarkType.leftHip: (0.52, 0.73),
    LandmarkType.leftKnee: (0.70, 0.75),
    LandmarkType.leftAnkle: (0.88, 0.78),
  },
  bones: _sideViewBones,
);

// ---------------------------------------------------------------------------
// Targets for the `poseTargetId` tags the catalogue already carries.
//
// `exercises_vendor.json` tags 540 of its 1887 exercises with one of eight
// ids. Two of them — `squat` and `pushup` — had geometry above; the rest were
// labels pointing at nothing, so the coach could not coach them.
//
// ## Why these are authored rather than measured
//
// Measured first, and the measurement is what settled it. `scripts/pose/
// extract_pose_targets.py` ran MediaPipe over the catalogue's own posters and
// scored each for how nearly a side view it is — left and right joints
// coincide horizontally in a profile, and spread apart by roughly shoulder
// width head-on. Result across 44 posters covering all eight tags: **zero**
// usable side views. Nearly every score was 0.00, and even the one exercise
// whose id ends `_side_pov` scored 0.51 with 0.01 visibility. The posters are
// rendered head-on because that is what reads at thumbnail size, which is
// correct for their job and useless for this one.
//
// Tracing a frontal poster and shipping it as a side-view target would be
// worse than authoring: it would be wrong for the instruction on screen while
// looking like it came from data. So these follow `squatBottomTarget`'s
// precedent — the numbers describe the movement's geometry, and `poseMatchScore`
// normalises away position and size, so they never claim to be anyone's body.
//
// Segment lengths are held within a few percent between the two phases of each
// movement, for the reason `pushupBottomTarget` gives: a limb that changes
// length mid-demonstration reads as a glitch, not as a movement.
// ---------------------------------------------------------------------------

/// Standing tall with the arm hanging: the extended end of a curl.
///
/// "top" and "bottom" name where the MOVING part travels, as they do for the
/// squat and the push-up. For a curl the hand rises, so the curled position is
/// the top one.
const curlBottomTarget = PoseTarget(
  id: 'curl.bottom',
  joints: {
    LandmarkType.leftShoulder: (0.47, 0.30),
    LandmarkType.leftElbow: (0.48, 0.46),
    LandmarkType.leftWrist: (0.49, 0.62),
    LandmarkType.leftHip: (0.50, 0.57),
    LandmarkType.leftKnee: (0.50, 0.77),
    LandmarkType.leftAnkle: (0.49, 0.95),
  },
  bones: _sideViewBones,
);

/// The curled end: forearm rotated up, upper arm still hanging at the side.
///
/// The elbow does not move. That is the whole point of the shape — an elbow
/// that drifts forward is the most common way a curl turns into a swing, and
/// a target that moved it would be teaching the fault.
const curlTopTarget = PoseTarget(
  id: 'curl.top',
  joints: {
    LandmarkType.leftShoulder: (0.47, 0.30),
    LandmarkType.leftElbow: (0.48, 0.46),
    LandmarkType.leftWrist: (0.44, 0.31),
    LandmarkType.leftHip: (0.50, 0.57),
    LandmarkType.leftKnee: (0.50, 0.77),
    LandmarkType.leftAnkle: (0.49, 0.95),
  },
  bones: _sideViewBones,
);

/// Standing tall, arms hanging: the top of a hip hinge.
const hingeTopTarget = PoseTarget(
  id: 'hinge.top',
  joints: {
    LandmarkType.leftShoulder: (0.47, 0.26),
    LandmarkType.leftElbow: (0.48, 0.40),
    LandmarkType.leftWrist: (0.49, 0.53),
    LandmarkType.leftHip: (0.50, 0.53),
    LandmarkType.leftKnee: (0.50, 0.74),
    LandmarkType.leftAnkle: (0.49, 0.93),
  },
  bones: _sideViewBones,
);

/// The bottom of a hinge: hips travelled BACK, torso inclined, knees only
/// slightly bent, arms hanging straight down under the shoulders.
///
/// The distinction from `squatBottomTarget` is the entire reason a separate
/// shape exists: a squat drops the hips between the feet and keeps the shins
/// angled forward; a hinge sends the hips backwards and keeps the shins close
/// to vertical. Told to "squat deeper" during a Romanian deadlift, a user
/// would be right to ignore the coach.
const hingeBottomTarget = PoseTarget(
  id: 'hinge.bottom',
  joints: {
    LandmarkType.leftShoulder: (0.62, 0.43),
    LandmarkType.leftElbow: (0.62, 0.57),
    LandmarkType.leftWrist: (0.62, 0.70),
    LandmarkType.leftHip: (0.40, 0.58),
    LandmarkType.leftKnee: (0.53, 0.75),
    LandmarkType.leftAnkle: (0.49, 0.93),
  },
  bones: _sideViewBones,
);

/// Standing tall: the top of a lunge.
const lungeTopTarget = PoseTarget(
  id: 'lunge.top',
  joints: {
    LandmarkType.leftShoulder: (0.47, 0.26),
    LandmarkType.leftElbow: (0.48, 0.40),
    LandmarkType.leftWrist: (0.49, 0.53),
    LandmarkType.leftHip: (0.50, 0.53),
    LandmarkType.leftKnee: (0.50, 0.74),
    LandmarkType.leftAnkle: (0.49, 0.93),
  },
  bones: _sideViewBones,
);

/// The bottom of a lunge, front leg only: knee stacked over the ankle, shin
/// vertical, torso upright while the hips drop.
///
/// Only the front leg is described, because `_sideViewBones` is a left-side
/// chain and the trailing leg is behind the body where the detector is
/// guessing. A user standing side-on presents the front leg to the camera,
/// which is the leg the shape is about.
const lungeBottomTarget = PoseTarget(
  id: 'lunge.bottom',
  joints: {
    LandmarkType.leftShoulder: (0.42, 0.35),
    LandmarkType.leftElbow: (0.43, 0.49),
    LandmarkType.leftWrist: (0.44, 0.62),
    LandmarkType.leftHip: (0.45, 0.62),
    LandmarkType.leftKnee: (0.60, 0.77),
    LandmarkType.leftAnkle: (0.61, 0.95),
  },
  bones: _sideViewBones,
);

/// Lying flat, hands by the head: the bottom of a sit-up or crunch.
const situpBottomTarget = PoseTarget(
  id: 'situp.bottom',
  joints: {
    LandmarkType.leftShoulder: (0.30, 0.72),
    LandmarkType.leftElbow: (0.22, 0.61),
    LandmarkType.leftWrist: (0.34, 0.57),
    LandmarkType.leftHip: (0.55, 0.75),
    LandmarkType.leftKnee: (0.72, 0.68),
    LandmarkType.leftAnkle: (0.85, 0.78),
  },
  bones: _sideViewBones,
);

/// Curled up: the torso has rotated about the hip, the feet have not moved.
///
/// The hip is the pivot and stays put, which is what separates a crunch from
/// a hip flexor raise — the shape says "fold the ribs toward the hips", not
/// "pull yourself up by the legs".
const situpTopTarget = PoseTarget(
  id: 'situp.top',
  joints: {
    LandmarkType.leftShoulder: (0.36, 0.59),
    LandmarkType.leftElbow: (0.27, 0.49),
    LandmarkType.leftWrist: (0.39, 0.45),
    LandmarkType.leftHip: (0.55, 0.75),
    LandmarkType.leftKnee: (0.72, 0.68),
    LandmarkType.leftAnkle: (0.85, 0.78),
  },
  bones: _sideViewBones,
);

/// Racked at the shoulders: the bottom of an overhead press.
///
/// The whole figure sits lower in the frame than the squat's does, so the
/// locked-out arm above still has room. Absolute position is irrelevant to
/// scoring and matters only to the drawn outline, which must not run off the
/// top of the panel.
const overheadPressBottomTarget = PoseTarget(
  id: 'overhead_press.bottom',
  joints: {
    LandmarkType.leftShoulder: (0.47, 0.36),
    LandmarkType.leftElbow: (0.44, 0.50),
    LandmarkType.leftWrist: (0.50, 0.39),
    LandmarkType.leftHip: (0.50, 0.62),
    LandmarkType.leftKnee: (0.50, 0.80),
    LandmarkType.leftAnkle: (0.49, 0.96),
  },
  bones: _sideViewBones,
);

/// Locked out overhead: elbow and wrist stacked over the shoulder.
///
/// Stacked, not forward. A press finished in front of the head is the fault
/// this shape is meant to make visible.
const overheadPressTopTarget = PoseTarget(
  id: 'overhead_press.top',
  joints: {
    LandmarkType.leftShoulder: (0.47, 0.36),
    LandmarkType.leftElbow: (0.47, 0.22),
    LandmarkType.leftWrist: (0.47, 0.09),
    LandmarkType.leftHip: (0.50, 0.62),
    LandmarkType.leftKnee: (0.50, 0.80),
    LandmarkType.leftAnkle: (0.49, 0.96),
  },
  bones: _sideViewBones,
);

/// Every movement the coach can demonstrate, keyed by the catalogue's own
/// `poseTargetId`, as `(top, bottom)`.
///
/// One registry rather than a list per call site: `pose_target_test.dart` used
/// to enumerate targets by hand and had silently never covered
/// [pushupBottomTarget] at all, so its invariants — enough joints to score,
/// bones that reference real joints, coordinates inside the frame — did not
/// apply to a shipped target. Anything added below is covered from the moment
/// it is added.
///
/// ## `calf_raise` is absent, and cannot be added here
///
/// Seven of the catalogue's eight tags appear. The eighth is not an omission
/// and not work left for later: the movement is not expressible in this
/// representation. The scored set is shoulder, elbow, wrist, hip, knee and
/// ankle — there is no heel and no toe. A calf raise moves the whole body
/// straight up on an unchanging skeleton, and [poseMatchScore] removes
/// position and size before comparing, so both ends of the movement normalise
/// to the *same* shape. A pair would score every attempt identically,
/// including a rep never performed.
///
/// Representing it needs a landmark below the ankle — a change to
/// [LandmarkType] and to what the detector is asked for, which is a larger
/// decision than adding a shape and should be made when something else needs
/// feet too. The 17 exercises tagged `calf_raise` stay uncoached, visibly,
/// rather than being handed a target that cannot judge them.
/// The pair is **(start, end)**, not (top, bottom) — and the distinction cost
/// a round of failing tests, so it is stated here rather than inferred.
///
/// A target's own name says where the BODY is: `curl.top` is the curled
/// position, because that is where the hand ends up. `RepCounter`'s phases say
/// where the SIGNAL is: its `top` phase is the LOW end of the number. For a
/// squat those agree — standing is both the top of the body's travel and the
/// low end of the depth signal. For a curl they are opposite ends, and reading
/// the pair as (top, bottom) put the counter's start at the curled position,
/// where it could never begin a rep.
///
/// So: `.$1` is where the movement STARTS and the counter idles; `.$2` is what
/// the user is trying to reach, which is also what `poseTargetProvider` scores
/// and what `lerpPoseTarget` animates towards.
const poseTargetsByTag = <String, (PoseTarget, PoseTarget)>{
  'squat': (squatTopTarget, squatBottomTarget),
  'pushup': (pushupTopTarget, pushupBottomTarget),
  'curl': (curlBottomTarget, curlTopTarget),
  'hinge': (hingeTopTarget, hingeBottomTarget),
  'lunge': (lungeTopTarget, lungeBottomTarget),
  'situp': (situpBottomTarget, situpTopTarget),
  'overhead_press': (overheadPressBottomTarget, overheadPressTopTarget),
};

/// Flat view of [poseTargetsByTag], derived rather than written twice.
List<PoseTarget> get allShippedTargets =>
    [for (final p in poseTargetsByTag.values) ...[p.$1, p.$2]];

/// A pose part-way between two targets, for drawing a movement instead of a
/// position.
///
/// Only joints present in BOTH ends survive: a joint that appears half way
/// through would pop into existence mid-demonstration. [t] is clamped, so a
/// caller driving this from an animation that overshoots — a spring curve, an
/// `AnimationController` with a `Curves.elasticOut` — cannot fling the limbs
/// past either end of the movement.
PoseTarget lerpPoseTarget(PoseTarget from, PoseTarget to, double t) {
  final k = t.clamp(0.0, 1.0);
  final joints = <LandmarkType, (double, double)>{};
  for (final entry in from.joints.entries) {
    final b = to.joints[entry.key];
    if (b == null) continue;
    final a = entry.value;
    joints[entry.key] = (
      a.$1 + (b.$1 - a.$1) * k,
      a.$2 + (b.$2 - a.$2) * k,
    );
  }
  return PoseTarget(
    id: '${from.id}->${to.id}',
    joints: joints,
    // Bones name joint pairs, so any bone whose ends did not both survive
    // would draw a line to a joint that is not there.
    bones: from.bones
        .where((b) => joints.containsKey(b.$1) && joints.containsKey(b.$2))
        .toList(growable: false),
  );
}

/// Below this the pose is not the target pose. The operator's number.
const double kPoseMatchPassing = 0.80;

/// Mean joint offset, in normalised body radii, at which the score reaches zero.
///
/// **Calibrated, not chosen.** Measured mean offsets against the squat-bottom
/// target, over the cases this has to separate:
///
/// | pose | offset | score at 0.6 |
/// |---|---|---|
/// | the target itself | 0.000 | 1.00 |
/// | a real body clearly in position, every joint nudged | 0.114 | 0.81 |
/// | a genuinely shallow squat — hips above knees, torso upright | 0.348 | 0.42 |
/// | standing tall | 0.430 | 0.28 |
/// | a push-up | 1.221 | 0.00 |
///
/// The constraint is two-sided: at least 0.568 or a real human fails, under
/// 1.741 or a shallow squat passes. The window between them is wide, which is
/// the evidence that this measure separates the classes at all — the two rules
/// withdrawn before this one each had a window of zero, because correct and
/// incorrect execution produced overlapping numbers.
///
/// 0.6 sits at the bottom of that window: as strict as it can be while still
/// admitting a real body.
const double _zeroScoreAtOffset = 0.6;

/// How closely [frame] matches [target], from 0 (nothing alike) to 1 (exact).
///
/// Invariant to translation and to scale, which is the entire point: the user
/// standing a step to the left, or two metres further from the phone, is doing
/// the same movement and must score the same.
///
/// Returns null when the frame does not carry enough of the target's joints to
/// judge — "cannot tell" is not a low score, and reporting it as one would tell
/// a user their form is wrong when the truth is that their knee is out of shot.
///
/// **Correction, `FORMCOACH_MATCHSCORE_XSCALE_2026-08-31`**: [target]'s x is
/// authored as a fraction of the frame's WIDTH (see the class doc), so it is
/// multiplied by [frame]'s own `aspectRatio` before comparing — the same
/// correction `buildSilhouette`'s `xScale` applies for drawing, using the
/// live frame's own aspect rather than an assumed one. Proven necessary, not
/// theoretical: a live landmark set that is EXACTLY the target pose, captured
/// correctly (genuinely isotropic x), scored only ~0.74 against the
/// uncorrected target — below [kPoseMatchPassing] for the best possible
/// match, which cannot be fixed by better technique. Every existing test
/// before this fix compared the target against poses DERIVED from the
/// target's own (equally wrong-convention) joints, which cancels the bug out
/// by construction and is why it went uncaught -- see
/// `pose_target_test.dart`'s `frameFrom`/`poseOf` and the new
/// `FORMCOACH_MATCHSCORE_XSCALE_2026-08-31` test group, which uses an
/// independently isotropic frame instead.
double? poseMatchScore(
  PoseFrame frame,
  PoseTarget target, {
  double minLikelihood = 0.5,
}) {
  final pairs = <((double, double), (double, double))>[];
  for (final entry in target.joints.entries) {
    final lm = frame.landmarks[entry.key];
    if (lm == null || lm.likelihood < minLikelihood) continue;
    if (lm.x.isNaN || lm.y.isNaN) continue;
    final want = entry.value;
    pairs.add(((lm.x, lm.y), (want.$1 * frame.aspectRatio, want.$2)));
  }
  // Fewer than four shared joints is a fragment, not a pose: the normalisation
  // below would happily scale two points onto any other two points and report
  // a perfect match.
  if (pairs.length < 4) return null;

  final live = _normalise([for (final p in pairs) p.$1]);
  final want = _normalise([for (final p in pairs) p.$2]);
  if (live == null || want == null) return null;

  // Which side the lifter turns towards the camera is a framing choice, not a
  // technique error, so the target is matched against both facings and the
  // better one wins. Negating x after `_normalise` is a true mirror: the points
  // are already centred on their own centroid, so the reflection axis is the
  // body's own midline and the RMS radius is unchanged.
  final mean = math.min(
    _meanOffset(live, want),
    _meanOffset(live, [for (final p in want) (-p.$1, p.$2)]),
  );
  final score = 1.0 - (mean / _zeroScoreAtOffset);
  return score.clamp(0.0, 1.0);
}

/// Mean point-to-point distance between two already-normalised poses.
double _meanOffset(List<(double, double)> a, List<(double, double)> b) {
  var total = 0.0;
  for (var i = 0; i < a.length; i++) {
    final dx = a[i].$1 - b[i].$1;
    final dy = a[i].$2 - b[i].$2;
    total += math.sqrt(dx * dx + dy * dy);
  }
  return total / a.length;
}

/// Centres on the centroid and scales to unit RMS radius.
///
/// RMS radius rather than, say, torso length: every joint contributes, so one
/// badly-tracked landmark cannot rescale the whole comparison. Returns null for
/// a degenerate set — all points identical — which has no size to scale by.
List<(double, double)>? _normalise(List<(double, double)> points) {
  var cx = 0.0;
  var cy = 0.0;
  for (final p in points) {
    cx += p.$1;
    cy += p.$2;
  }
  cx /= points.length;
  cy /= points.length;

  var sumSq = 0.0;
  for (final p in points) {
    final dx = p.$1 - cx;
    final dy = p.$2 - cy;
    sumSq += dx * dx + dy * dy;
  }
  final rms = math.sqrt(sumSq / points.length);
  if (rms < 1e-9) return null;

  return [for (final p in points) ((p.$1 - cx) / rms, (p.$2 - cy) / rms)];
}
