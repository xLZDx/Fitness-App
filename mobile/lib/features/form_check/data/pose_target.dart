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
/// **Coordinates are isotropic, as of `FORMCOACH_TARGET_ISOTROPIC_2026-09-01`:**
/// x and y are both fractions of the frame's HEIGHT, exactly like
/// [PoseLandmark]. So y spans `0..1` and x spans `0..aspectRatio` — about
/// 0.56 on a 9:16 phone, 0.67 on a 2:3 one. Nothing multiplies these numbers
/// by a frame's aspect ratio any more, at either of the two places that used
/// to.
///
/// They did not start that way, and the history is the reason this paragraph
/// exists. x was originally authored as a fraction of frame WIDTH (0..1, the
/// convention an author reaches for without thinking), which two corrections
/// then compensated for at the point of use: `buildSilhouette` took an
/// `xScale` for drawing, and [poseMatchScore] multiplied by
/// `frame.aspectRatio` for scoring. Both were real fixes for real,
/// device-confirmed bugs — an outline clipped off-panel, and a perfect match
/// that could only score 0.74 — but they compensated at the wrong layer. A
/// target whose x is a fraction of WIDTH is a **different shape on every
/// phone**: measured across the fourteen shipped targets, the same authored
/// numbers drift by 0.1366 normalised radii between a 9:16 and a 3:4 camera,
/// which is 22.8% of the 0.6 offset that reduces a score to zero. A lifter
/// could pass on one handset and fail on another for no reason connected to
/// their body.
///
/// The migration was mechanical — every x multiplied once by 2/3, the aspect
/// of the reference device the current numbers were measured on — so the
/// shape is bit-for-bit unchanged there, and correct rather than merely
/// unchanged everywhere else. `pose_target_test.dart` asserts the invariant
/// directly: a physical pose scored at several frame aspect ratios must
/// produce the same number.
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
    this.unscoredJoints = const {},
  });

  /// Stable identifier, e.g. `squat.top`.
  final String id;

  final Map<LandmarkType, (double, double)> joints;

  /// Which joints to connect when drawing. Not used for scoring.
  final List<(LandmarkType, LandmarkType)> bones;

  /// Joints that are DRAWN but deliberately not judged.
  ///
  /// The score may only judge geometry that is both relevant to the movement
  /// and reliably observable from the view the user was told to stand in
  /// (GPT-PM, product decision, 2026-09-01). Those are two different sets, and
  /// before this they were forced to be the same set because [joints] served
  /// drawing and scoring at once.
  ///
  /// The squat's wrist is the case that forced the distinction, measured on an
  /// S23 across four correct reps: in normalised units the wrist's frame-to-
  /// frame spread was 0.53 while every other joint stayed within 0.08-0.26.
  /// The mechanism is projective, not a detector fault — at the bottom of a
  /// squat the forearm lies close to the camera axis, so it projects at 0.41
  /// of the upper arm where anatomy says 0.78, and small real movements swing
  /// its projection a long way. Judging it does not make the coach stricter
  /// about squatting; it makes the coach randomly strict about where the hands
  /// happen to point.
  ///
  /// The ELBOW joined it hours later, on the operator's own device and for a
  /// blunter reason: with the wrist excluded but the elbow still judged, a
  /// correct squat passed at 0.891 with the arms held forward and failed at
  /// 0.772 with the arms tucked at the sides. Same legs, same torso, same limb
  /// lengths — only the direction of the arms changed. Where a lifter puts
  /// their hands is not what a squat is judged on, and GPT-PM had declined the
  /// elbow in the previous round precisely because that evidence did not exist
  /// yet; it does now. With both excluded the two arm positions score 0.919
  /// and 0.919, and `pose_target_test.dart` asserts that equality rather than
  /// merely asserting both pass, so the invariance is the contract.
  ///
  /// A score therefore means "the SCORED target geometry was reached", never
  /// "every drawn part of the silhouette was matched".
  final Set<LandmarkType> unscoredJoints;

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
    LandmarkType.leftShoulder: (0.297, 0.26),
    LandmarkType.leftElbow: (0.304, 0.40),
    LandmarkType.leftWrist: (0.311, 0.53),
    LandmarkType.leftHip: (0.317, 0.53),
    LandmarkType.leftKnee: (0.317, 0.74),
    LandmarkType.leftAnkle: (0.311, 0.93),
  },
  bones: _sideViewBones,
);

/// The bottom of a squat, filmed from the side: hips travelled back and down to
/// about knee height, knees forward over the feet, torso inclined to balance.
///
/// **Re-authored from measurement, `FORMCOACH_SQUAT_BOTTOM_MEASURED_2026-09-01`.**
/// It used to be hand-authored, and the hand-authored numbers were not a human
/// shape. Converted into the space they are actually compared in, they gave a
/// thigh/shin ratio of 0.54 and a torso/thigh of 2.29, where a person is 1.00
/// and 1.18 — the only such outlier among the fourteen shipped targets, all of
/// which the same authoring hand produced. The consequence was not strictness
/// but INVERSION: instrumented on an S23, the deepest frame of four correct,
/// below-parallel reps scored 0.257 / 0.092 / 0.162 / 0.191, while a SHALLOWER
/// moment in the same rep scored 0.65-0.68. The coach was rewarding not
/// reaching depth, and said "вы не дошли до силуэта" on every repetition — the
/// complaint the operator raised against build after build.
///
/// The joints below are the median of those four measured deepest frames,
/// placed on `squatTopTarget`'s ankle and scaled to its thigh so the demo loop
/// does not change limb length between the two phases. The result is
/// anatomically consistent (thigh/shin 1.00, torso/thigh 1.22) and is a real
/// below-parallel squat: the hip sits 0.04 BELOW the knee, where the old
/// numbers put it level.
///
/// **Provenance, stated rather than implied:** one operator, one S23, four
/// correct deep repetitions, median geometry. Provisional. That is a small
/// sample for a population claim and is deliberately not presented as one —
/// it is preferred over the previous numbers only because those are now
/// demonstrated to be geometrically impossible for a human, and keeping known-
/// invalid invented numbers because the replacement sample is small would be
/// the worse choice (GPT-PM, 2026-09-01). MM-Fit (6,160 labelled reps, already
/// the source for `measured_rep_configs.dart`) is the intended refinement; its
/// archive is not on this machine today, so that is roadmap work, not a
/// blocker on correcting a live defect.
///
/// [kPoseMatchPassing] is NOT relaxed to accommodate this. The reference was
/// wrong, not the standard.
const squatBottomTarget = PoseTarget(
  id: 'squat.bottom',
  joints: {
    LandmarkType.leftShoulder: (0.344, 0.58),
    LandmarkType.leftElbow: (0.391, 0.712),
    LandmarkType.leftWrist: (0.519, 0.731),
    LandmarkType.leftHip: (0.171, 0.77),
    LandmarkType.leftKnee: (0.377, 0.73),
    LandmarkType.leftAnkle: (0.311, 0.93),
  },
  bones: _sideViewBones,
  unscoredJoints: {LandmarkType.leftWrist, LandmarkType.leftElbow},
);

/// A push-up at the top: one straight line from shoulder to ankle, arms under
/// the shoulders, filmed from the side.
const pushupTopTarget = PoseTarget(
  id: 'pushup.top',
  joints: {
    LandmarkType.leftShoulder: (0.183, 0.55),
    LandmarkType.leftElbow: (0.183, 0.68),
    LandmarkType.leftWrist: (0.183, 0.80),
    LandmarkType.leftHip: (0.317, 0.62),
    LandmarkType.leftKnee: (0.430, 0.70),
    LandmarkType.leftAnkle: (0.537, 0.78),
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
    LandmarkType.leftShoulder: (0.157, 0.72),
    LandmarkType.leftElbow: (0.243, 0.72),
    LandmarkType.leftWrist: (0.183, 0.80),
    LandmarkType.leftHip: (0.297, 0.73),
    LandmarkType.leftKnee: (0.417, 0.75),
    LandmarkType.leftAnkle: (0.537, 0.78),
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
    LandmarkType.leftShoulder: (0.313, 0.30),
    LandmarkType.leftElbow: (0.320, 0.46),
    LandmarkType.leftWrist: (0.327, 0.62),
    LandmarkType.leftHip: (0.333, 0.57),
    LandmarkType.leftKnee: (0.333, 0.77),
    LandmarkType.leftAnkle: (0.327, 0.95),
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
    LandmarkType.leftShoulder: (0.313, 0.30),
    LandmarkType.leftElbow: (0.320, 0.46),
    LandmarkType.leftWrist: (0.293, 0.31),
    LandmarkType.leftHip: (0.333, 0.57),
    LandmarkType.leftKnee: (0.333, 0.77),
    LandmarkType.leftAnkle: (0.327, 0.95),
  },
  bones: _sideViewBones,
);

/// Standing tall, arms hanging: the top of a hip hinge.
const hingeTopTarget = PoseTarget(
  id: 'hinge.top',
  joints: {
    LandmarkType.leftShoulder: (0.313, 0.26),
    LandmarkType.leftElbow: (0.320, 0.40),
    LandmarkType.leftWrist: (0.327, 0.53),
    LandmarkType.leftHip: (0.333, 0.53),
    LandmarkType.leftKnee: (0.333, 0.74),
    LandmarkType.leftAnkle: (0.327, 0.93),
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
    LandmarkType.leftShoulder: (0.413, 0.43),
    LandmarkType.leftElbow: (0.413, 0.57),
    LandmarkType.leftWrist: (0.413, 0.70),
    LandmarkType.leftHip: (0.267, 0.58),
    LandmarkType.leftKnee: (0.353, 0.75),
    LandmarkType.leftAnkle: (0.327, 0.93),
  },
  bones: _sideViewBones,
);

/// Standing tall: the top of a lunge.
const lungeTopTarget = PoseTarget(
  id: 'lunge.top',
  joints: {
    LandmarkType.leftShoulder: (0.313, 0.26),
    LandmarkType.leftElbow: (0.320, 0.40),
    LandmarkType.leftWrist: (0.327, 0.53),
    LandmarkType.leftHip: (0.333, 0.53),
    LandmarkType.leftKnee: (0.333, 0.74),
    LandmarkType.leftAnkle: (0.327, 0.93),
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
    LandmarkType.leftShoulder: (0.280, 0.35),
    LandmarkType.leftElbow: (0.287, 0.49),
    LandmarkType.leftWrist: (0.293, 0.62),
    LandmarkType.leftHip: (0.300, 0.62),
    LandmarkType.leftKnee: (0.400, 0.77),
    LandmarkType.leftAnkle: (0.407, 0.95),
  },
  bones: _sideViewBones,
);

/// Lying flat, hands by the head: the bottom of a sit-up or crunch.
const situpBottomTarget = PoseTarget(
  id: 'situp.bottom',
  joints: {
    LandmarkType.leftShoulder: (0.152, 0.72),
    LandmarkType.leftElbow: (0.099, 0.61),
    LandmarkType.leftWrist: (0.179, 0.57),
    LandmarkType.leftHip: (0.319, 0.75),
    LandmarkType.leftKnee: (0.432, 0.68),
    LandmarkType.leftAnkle: (0.519, 0.78),
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
    LandmarkType.leftShoulder: (0.192, 0.59),
    LandmarkType.leftElbow: (0.132, 0.49),
    LandmarkType.leftWrist: (0.212, 0.45),
    LandmarkType.leftHip: (0.319, 0.75),
    LandmarkType.leftKnee: (0.432, 0.68),
    LandmarkType.leftAnkle: (0.519, 0.78),
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
    LandmarkType.leftShoulder: (0.313, 0.36),
    LandmarkType.leftElbow: (0.293, 0.50),
    LandmarkType.leftWrist: (0.333, 0.39),
    LandmarkType.leftHip: (0.333, 0.62),
    LandmarkType.leftKnee: (0.333, 0.80),
    LandmarkType.leftAnkle: (0.327, 0.96),
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
    LandmarkType.leftShoulder: (0.313, 0.36),
    LandmarkType.leftElbow: (0.313, 0.22),
    LandmarkType.leftWrist: (0.313, 0.09),
    LandmarkType.leftHip: (0.333, 0.62),
    LandmarkType.leftKnee: (0.333, 0.80),
    LandmarkType.leftAnkle: (0.327, 0.96),
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
/// **Limbs swing, they do not telescope** (`FORMCOACH_DEMO_ARTICULATED_2026-09-02`).
///
/// This used to lerp every joint independently, which is the obvious
/// implementation and is wrong for the same reason a straight line between two
/// points on a circle is not an arc: a joint travelling in a straight line
/// while the joint it hangs from travels in another one does not keep the bone
/// between them the same length. Measured on the shipped squat, whose thigh is
/// 0.210 at BOTH ends of the movement: 0.156 at t=0.25, **0.134 at t=0.5** —
/// 36% shorter half way through, and the forearm 22% shorter. The figure
/// demonstrating the movement pulled its own legs in and pushed them back out
/// once per loop.
///
/// Nothing caught it. `pose_target_test.dart`'s "limbs keep their length
/// between the two phases" measures the two AUTHORED poses and passed —
/// correctly, since the ends are exactly equal; the stretch only exists in the
/// frames between them, which nothing rendered or measured until
/// `test/golden/form_coach_golden_test.dart` drew one.
///
/// So the bones are walked instead: each one keeps a length interpolated
/// between its own two authored lengths and swings through the shorter of the
/// two arcs between its authored angles. The chain is anchored at the joint
/// that moves LEAST between the two poses — for a squat that is the ankle,
/// which is identical in both, so the feet stay planted and the body rotates
/// over them, which is what a squat is. Anchoring at a fixed joint instead
/// (the shoulder, say, because the bone list happens to start there) would
/// hang the body from the part that moves most and slide the feet along the
/// floor.
PoseTarget lerpPoseTarget(PoseTarget from, PoseTarget to, double t) {
  final k = t.clamp(0.0, 1.0);
  final shared = <LandmarkType>[
    for (final key in from.joints.keys)
      if (to.joints.containsKey(key)) key,
  ];
  final joints = <LandmarkType, (double, double)>{};

  if (k <= 0 || k >= 1) {
    // The ends are the authored poses themselves, not a reconstruction of
    // them. Polar arithmetic would land a few ulps away, and "the shape at the
    // bottom of the movement is the shape being scored" is worth more than the
    // three lines it costs to keep exact.
    final end = k <= 0 ? from : to;
    for (final key in shared) {
      joints[key] = end.joints[key]!;
    }
  } else {
    final links = <LandmarkType, List<LandmarkType>>{};
    for (final (a, b) in from.bones) {
      if (!shared.contains(a) || !shared.contains(b)) continue;
      (links[a] ??= <LandmarkType>[]).add(b);
      (links[b] ??= <LandmarkType>[]).add(a);
    }

    double drift(LandmarkType j) {
      final a = from.joints[j]!, b = to.joints[j]!;
      return math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
    }

    // Least-moving first, enum index to break ties: an anchor chosen by
    // iteration order would move when a target's joints were reordered, and a
    // drawing that changes because a map literal was rearranged is the kind of
    // dependency nobody remembers is there.
    final order = [...shared]..sort((a, b) {
        final byDrift = drift(a).compareTo(drift(b));
        return byDrift != 0 ? byDrift : a.index.compareTo(b.index);
      });

    /// One pass of the walk, [lead] first. Every joint then gets a turn at
    /// being an anchor, and all but the first of each connected group are
    /// already placed by the time their turn comes. What is left over is a
    /// joint no bone reaches — nothing constrains its length or its angle, so
    /// a straight line is the honest answer for it.
    Map<LandmarkType, (double, double)> walk(LandmarkType lead, double at) {
      final placed = <LandmarkType, (double, double)>{};
      void from0(LandmarkType anchor) {
        if (placed.containsKey(anchor)) return;
        final a = from.joints[anchor]!, b = to.joints[anchor]!;
        placed[anchor] =
            (a.$1 + (b.$1 - a.$1) * at, a.$2 + (b.$2 - a.$2) * at);
        final queue = <LandmarkType>[anchor];
        while (queue.isNotEmpty) {
          final parent = queue.removeAt(0);
          for (final child in links[parent] ?? const <LandmarkType>[]) {
            if (placed.containsKey(child)) continue;
            placed[child] =
                _swing(from, to, parent, child, placed[parent]!, at);
            queue.add(child);
          }
        }
      }

      from0(lead);
      for (final j in order) {
        from0(j);
      }
      return placed;
    }

    // **One anchor holds; a second still joint cannot be promised.**
    //
    // A push-up is authored with the wrist AND the ankle identical in both
    // phases — hands on the floor, toes on the floor — so "least displacement"
    // is a tie, settled here on enum index. Whichever wins, the OTHER contact
    // is placed six bones down the chain and creeps: measured across the loop,
    // 0.019 at the ankle when the wrist leads, 0.021 at the wrist when the
    // ankle leads. Swapping the anchor moves the error, it does not remove it,
    // and a tie-break that scored the candidates was tried and reverted for
    // exactly that reason — it added a nested walk per frame and made the
    // push-up marginally worse.
    //
    // The cause is not the anchor rule. A chain can hold two fixed ends only
    // if the bones between them are the same length in both poses, and the
    // push-up's are not: its shoulder-to-elbow stretches 33.8% between the two
    // authored phases. That is a known, deliberately deferred authoring defect
    // — see the exception list in `pose_target_test.dart`'s "limbs keep their
    // length between the two phases" — and re-measuring those targets from a
    // device is what fixes the creep. Interpolation cannot: asked to hold two
    // ends of a chain that changes length, it can only choose where to put the
    // discrepancy.
    joints.addAll(walk(order.first, k));
  }

  return PoseTarget(
    id: '${from.id}->${to.id}',
    joints: joints,
    // Bones name joint pairs, so any bone whose ends did not both survive
    // would draw a line to a joint that is not there.
    bones: from.bones
        .where((b) => joints.containsKey(b.$1) && joints.containsKey(b.$2))
        .toList(growable: false),
    // An interpolated pose is only ever DRAWN (the demo loop), never scored,
    // but carrying the exclusion is still the honest answer: an in-between
    // frame of a squat has the same unreliable wrist as its ends do. Taken
    // from `from` alone rather than unioned, because the two ends of one
    // movement are authored together and disagreeing about it would be the
    // authoring bug, not something to paper over here.
    unscoredJoints: from.unscoredJoints,
  );
}

/// Where [child] lands when its bone hangs off an already-placed [parent],
/// [k] of the way from one authored pose to the other.
///
/// The straight-line pose is still what aims the bone — this takes its
/// DIRECTION and replaces only its LENGTH, which is the whole defect and
/// nothing more. Interpolating each bone's angle instead is the tidier idea
/// and was tried first; it re-times the movement, because three bones each
/// turning at a constant rate do not move the joint on the end of them at a
/// constant rate. Measured on the squat: the shoulder reached only 29% of its
/// travel at the half way point, so the figure hung near the top and then
/// dropped. Where the author put the joints is the better guide to when the
/// body should be there.
(double, double) _swing(
  PoseTarget from,
  PoseTarget to,
  LandmarkType parent,
  LandmarkType child,
  (double, double) placed,
  double k,
) {
  double lengthIn(PoseTarget p) {
    final a = p.joints[parent]!, b = p.joints[child]!;
    final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
    return math.sqrt(dx * dx + dy * dy);
  }

  final lengthFrom = lengthIn(from);
  final length = lengthFrom + (lengthIn(to) - lengthFrom) * k;

  final a = from.joints[child]!, b = to.joints[child]!;
  var dx = a.$1 + (b.$1 - a.$1) * k - placed.$1;
  var dy = a.$2 + (b.$2 - a.$2) * k - placed.$2;
  var reach = math.sqrt(dx * dx + dy * dy);
  if (reach < 1e-9) {
    // The straight-line pose put the two ends of this bone on top of each
    // other, so there is no direction in it to borrow. Keep the one the bone
    // started from: a limb of the right length pointing where it already
    // pointed is a body, and a limb of the right length pointing nowhere in
    // particular is a division by zero.
    //
    // Stated rather than implied: this is the bone's direction in the AUTHORED
    // `from` pose, not its direction relative to where the parent has actually
    // been placed. Several links down a chain those differ, so the recovered
    // heading can be stale — the length stays right and the limb stays
    // attached, but it may point somewhere the rest of the body has rotated
    // away from. Not fixed, because fixing it means tracking each parent's own
    // rotation through the walk to compensate a case that no shipped target
    // reaches: the smallest `reach` measured across every bone of every
    // movement at t=0.5 is 0.075, eleven orders of magnitude off this branch.
    final p = from.joints[parent]!;
    dx = a.$1 - p.$1;
    dy = a.$2 - p.$2;
    reach = math.sqrt(dx * dx + dy * dy);
    if (reach < 1e-9) return placed;
  }
  return (placed.$1 + dx / reach * length, placed.$2 + dy / reach * length);
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
/// [target]'s joints are already in the same isotropic space as [frame]'s
/// landmarks, so nothing is converted here. That was not always true: until
/// `FORMCOACH_TARGET_ISOTROPIC_2026-09-01` this multiplied the target's x by
/// `frame.aspectRatio`, because the target held fractions of frame WIDTH. The
/// correction was necessary then and is wrong now — the data moved, so the
/// compensation had to go with it. Applying it on top of isotropic targets
/// would squash every shape horizontally by the aspect ratio.
double? poseMatchScore(
  PoseFrame frame,
  PoseTarget target, {
  double minLikelihood = 0.5,
}) {
  final pairs = <((double, double), (double, double))>[];
  for (final entry in target.joints.entries) {
    if (target.unscoredJoints.contains(entry.key)) continue;
    final lm = frame.landmarks[entry.key];
    if (lm == null || lm.likelihood < minLikelihood) continue;
    if (lm.x.isNaN || lm.y.isNaN) continue;
    final want = entry.value;
    pairs.add(((lm.x, lm.y), want));
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

/// Where a score was lost, joint by joint. Debug diagnostics only.
///
/// [poseMatchScore] answers with one number, and one number cannot distinguish
/// "the lifter is doing it wrong" from "the authored target is not the shape a
/// real body makes". Four consecutive live reps scoring 0.645/0.642/0.685/0.616
/// against a 0.80 pass mark is far too tight a cluster to be technique: that is
/// a fixed offset between two shapes, and this says which joints carry it.
///
/// Returns the same units the score is built from — normalised radii, where
/// [_zeroScoreAtOffset] (0.6) is the distance at which a joint contributes
/// nothing at all.
String? debugMatchBreakdown(
  PoseFrame frame,
  PoseTarget target, {
  double minLikelihood = 0.5,
}) {
  final types = <LandmarkType>[];
  final pairs = <((double, double), (double, double))>[];
  for (final entry in target.joints.entries) {
    if (target.unscoredJoints.contains(entry.key)) continue;
    final lm = frame.landmarks[entry.key];
    if (lm == null || lm.likelihood < minLikelihood) continue;
    if (lm.x.isNaN || lm.y.isNaN) continue;
    types.add(entry.key);
    pairs.add(((lm.x, lm.y), entry.value));
  }
  if (pairs.length < 4) return null;
  final live = _normalise([for (final p in pairs) p.$1]);
  final want = _normalise([for (final p in pairs) p.$2]);
  if (live == null || want == null) return null;

  final mirrored = [for (final p in want) (-p.$1, p.$2)];
  final useMirror = _meanOffset(live, mirrored) < _meanOffset(live, want);
  final ref = useMirror ? mirrored : want;

  final parts = <String>[];
  for (var i = 0; i < live.length; i++) {
    final dx = live[i].$1 - ref[i].$1;
    final dy = live[i].$2 - ref[i].$2;
    parts.add('${types[i].name}='
        '${math.sqrt(dx * dx + dy * dy).toStringAsFixed(2)}'
        '(dx${dx.toStringAsFixed(2)},dy${dy.toStringAsFixed(2)})');
  }
  return 'mirror=$useMirror ar=${frame.aspectRatio.toStringAsFixed(3)} '
      '${parts.join(' ')}';
}

/// The raw joints [target] would be scored against, as the detector saw them.
///
/// Debug diagnostics only, and deliberately RAW rather than normalised: a
/// candidate target has to be judged against the body's real geometry, and a
/// normalised dump has already had the very scale information removed that
/// tells whether the lifter reached depth.
String? debugJointDump(
  PoseFrame frame,
  PoseTarget target, {
  double minLikelihood = 0.5,
}) {
  final parts = <String>[];
  for (final t in target.joints.keys) {
    final lm = frame.landmarks[t];
    if (lm == null || lm.likelihood < minLikelihood) continue;
    parts.add('${t.name}=${lm.x.toStringAsFixed(3)},'
        '${lm.y.toStringAsFixed(3)}');
  }
  if (parts.isEmpty) return null;
  return 'ar=${frame.aspectRatio.toStringAsFixed(3)} ${parts.join(' ')}';
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
