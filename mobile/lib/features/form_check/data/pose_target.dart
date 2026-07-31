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
/// This is still a 2D projection, so **viewing angle is not cancelled out**. A
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
/// Coordinates are in the same isotropic space as [PoseLandmark] (see
/// `pose_coordinate_space.dart`), but only their **relative** arrangement is
/// used — [poseMatchScore] removes position and size before comparing. They are
/// authored at plausible screen positions so the same numbers can be drawn as
/// the on-screen outline without a second source of truth.
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
    pairs.add(((lm.x, lm.y), entry.value));
  }
  // Fewer than four shared joints is a fragment, not a pose: the normalisation
  // below would happily scale two points onto any other two points and report
  // a perfect match.
  if (pairs.length < 4) return null;

  final live = _normalise([for (final p in pairs) p.$1]);
  final want = _normalise([for (final p in pairs) p.$2]);
  if (live == null || want == null) return null;

  var total = 0.0;
  for (var i = 0; i < live.length; i++) {
    final dx = live[i].$1 - want[i].$1;
    final dy = live[i].$2 - want[i].$2;
    total += math.sqrt(dx * dx + dy * dy);
  }
  final mean = total / live.length;
  final score = 1.0 - (mean / _zeroScoreAtOffset);
  return score.clamp(0.0, 1.0);
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
