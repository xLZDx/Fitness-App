/// The live body, drawn as the same figure the target outline already is.
///
/// ## Why this is an adapter and not a second geometry engine
///
/// The obvious way to draw a live avatar is to read all fifteen landmarks and
/// build a body from them directly — both arms, both legs, exactly where the
/// detector says they are. That was the first plan, and reviewing it against
/// the code killed it for a reason worth writing down.
///
/// The coach asks the user to stand **side-on** (`coach_intro_cards.dart`, the
/// "stand side on" card). From the side, the far arm and the far leg are behind
/// the body: BlazePose does not omit them, it **extrapolates** them, and the
/// numbers it produces for them are guesses that move frame to frame while the
/// user holds still. `pose_silhouette.dart`'s own header already documents this
/// as the reason the authored targets carry one side only.
///
/// Drawing those guesses is worse for an avatar than for a skeleton. A skeleton
/// draws each bone independently, so a bad far-side wrist is one line in the
/// wrong place. A filled body has to close: a far arm that jitters drags the
/// whole outline with it, and the figure breathes and tears where nothing about
/// the user moved.
///
/// So the avatar is built the same way the target is — from ONE side, mirrored
/// across the torso. [buildSilhouette] already does that, is already tested,
/// and already carries the B4 fix that unions the subpaths into one contour.
/// This file's whole job is to choose which side to believe and hand it over in
/// the shape that function reads.
///
/// ## What that costs, stated plainly
///
/// A mirrored body cannot show asymmetry. If the user's left knee collapses
/// inward and the right does not, this avatar draws both the same. That is a
/// real loss and it is the right trade here: the alternative is not "shows
/// asymmetry", it is "shows asymmetry that isn't there", because the far side's
/// coordinates are invented in exactly the stance the coach asks for. Posture
/// (R10) measures asymmetry from a FRONT-facing stand, where both sides are
/// genuinely visible, and reads the landmarks directly — that is the right
/// place for it, not here.
library;

import 'pose_landmark.dart';
import 'pose_silhouette.dart';
import 'pose_target.dart';

/// Nothing to draw.
const SilhouetteFigure _nothing = SilhouetteFigure(
  segments: [],
  torso: [],
  joints: [],
  head: null,
  limbThickness: 0,
);

/// The joints [buildSilhouette] reads, in the order a limb chain walks them.
const _leftChain = <LandmarkType>[
  LandmarkType.leftShoulder,
  LandmarkType.leftElbow,
  LandmarkType.leftWrist,
  LandmarkType.leftHip,
  LandmarkType.leftKnee,
  LandmarkType.leftAnkle,
];

const _rightChain = <LandmarkType>[
  LandmarkType.rightShoulder,
  LandmarkType.rightElbow,
  LandmarkType.rightWrist,
  LandmarkType.rightHip,
  LandmarkType.rightKnee,
  LandmarkType.rightAnkle,
];

/// How far outside the coordinate contract a landmark may sit and still be
/// drawn.
///
/// Deliberately far tighter than `PoseGateConfig.unitSanitySlack` (4.0), and
/// the difference is not an oversight. That number separates "body out of shot"
/// from "the conversion never ran" — a diagnosis, where being generous costs a
/// frame's delay. This one decides whether to put a point into a closed,
/// filled outline, where a single wild coordinate does not misplace one limb,
/// it tears the whole body open.
///
/// The bound matters because the app has measured itself outside it:
/// `form_check_page.dart`'s coordinate diagnostic recorded
/// `x -0.466..1.968 (bound 0.667)`, `y -2.173..3.015` on a real phone, and that
/// defect is still open. Until it is closed, this is what stops those frames
/// from being drawn as a shredded figure.
///
/// Half a unit of slack still admits the legitimate case BlazePose is
/// documented to produce — a joint extrapolated just past the frame edge, which
/// is a real ankle below the bottom of the picture and worth drawing.
const double _drawSlack = 0.5;

/// The live [frame] as a body, or an empty figure when it should not be drawn.
///
/// [minLikelihood] is the floor for the joints that decide the torso. Lower
/// than `PoseGateConfig.minLikelihood` (0.7) on purpose: the gate is deciding
/// whether to SCORE a rep, where a guessed joint produces a false verdict about
/// someone's technique. This decides whether to draw a picture, where the cost
/// of being slightly wrong is a figure that wobbles and the cost of being too
/// strict is a screen that shows nothing while the user is plainly standing
/// there.
SilhouetteFigure buildPoseAvatar(
  PoseFrame frame, {
  BodyBuild build = BodyBuild.unknown,
  double minLikelihood = 0.5,
}) {
  final target = avatarTargetFrom(
    frame,
    minLikelihood: minLikelihood,
  );
  if (target == null) return _nothing;
  return buildSilhouette(target, build: build);
}

/// Picks the more believable side of [frame] and returns it in the shape
/// [buildSilhouette] reads — always keyed by the LEFT landmark types, because
/// that is the side the authored targets use and the side that function looks
/// for.
///
/// Returns null when neither side carries a torso, which is the only part that
/// is not optional: without a shoulder and a hip there is no spine, no axis to
/// mirror about, and nothing that would read as a person.
PoseTarget? avatarTargetFrom(
  PoseFrame frame, {
  double minLikelihood = 0.5,
}) {
  final chain = _betterSide(frame, minLikelihood);
  if (chain == null) return null;

  final joints = <LandmarkType, (double, double)>{};
  for (var i = 0; i < chain.length; i++) {
    final lm = frame.landmarks[chain[i]];
    if (lm == null) continue;
    if (lm.likelihood < minLikelihood) continue;
    if (!_drawable(lm, frame.aspectRatio)) continue;
    // Re-keyed onto the left side regardless of which side it came from: this
    // is a mid-line side view now, exactly like an authored target, and
    // `buildSilhouette` mirrors it back out to both sides itself.
    joints[_leftChain[i]] = (lm.x, lm.y);
  }

  // The torso is the one hard requirement. A partial limb is dropped by
  // `buildSilhouette` on its own ("a partial limb is worse than none"); a
  // missing torso has to stop us here.
  if (!joints.containsKey(LandmarkType.leftShoulder) ||
      !joints.containsKey(LandmarkType.leftHip)) {
    return null;
  }

  return PoseTarget(id: 'live', joints: joints, bones: const []);
}

/// Which side to believe: the one whose torso is confident, and then whose
/// whole chain is.
///
/// Summed likelihood rather than a count of present joints. A side with all six
/// joints reported at 0.3 apiece is the detector guessing a limb it cannot see;
/// a side with four joints at 0.9 is one it can. Counting would prefer the
/// first.
List<LandmarkType>? _betterSide(PoseFrame frame, double minLikelihood) {
  double score(List<LandmarkType> chain) {
    final shoulder = frame.landmarks[chain[0]];
    final hip = frame.landmarks[chain[3]];
    // No torso, no side. Returning a negative rather than zero so a side
    // without one always loses to a side with one, even a faint one.
    if (shoulder == null || hip == null) return -1;
    if (shoulder.likelihood < minLikelihood ||
        hip.likelihood < minLikelihood) {
      return -1;
    }
    if (!_drawable(shoulder, frame.aspectRatio) ||
        !_drawable(hip, frame.aspectRatio)) {
      return -1;
    }
    var total = 0.0;
    for (final t in chain) {
      final lm = frame.landmarks[t];
      if (lm == null) continue;
      if (!_drawable(lm, frame.aspectRatio)) continue;
      total += lm.likelihood;
    }
    return total;
  }

  final left = score(_leftChain);
  final right = score(_rightChain);
  if (left < 0 && right < 0) return null;
  return right > left ? _rightChain : _leftChain;
}

/// Is this coordinate close enough to the contract to put in a filled outline.
bool _drawable(PoseLandmark lm, double aspectRatio) {
  if (lm.x.isNaN || lm.y.isNaN) return false;
  if (lm.x < -_drawSlack || lm.x > aspectRatio + _drawSlack) return false;
  if (lm.y < -_drawSlack || lm.y > 1.0 + _drawSlack) return false;
  return true;
}
