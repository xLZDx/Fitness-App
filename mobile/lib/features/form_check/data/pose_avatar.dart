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

import 'dart:math' as math;

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
/// `x -0.466..1.968 (bound 0.667)`, `y -2.173..3.015` on a real phone.
///
/// That is NOT a conversion defect, and the sentence here used to say it was.
/// Reading the same session from its start, the first 305 frames were entirely
/// in contract (`x 0.005..0.611` against the 0.667 bound); the verdict flipped
/// on frame 306 at `x = -0.030`, three percent past the left edge, and every
/// later excursion is continuous frame to frame. A mis-scaled axis would have
/// been wrong on frame one. Those coordinates are BlazePose extrapolating
/// joints past the frame edge, which is documented behaviour and which the
/// user's own body produces the moment a hand leaves the shot.
///
/// So this bound is not a workaround for a broken conversion. It is what stops
/// a legitimately extrapolated joint — a real ankle below the bottom of the
/// picture — from being drawn as a shredded figure.
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
  AvatarFarSideLatch? latch,
}) {
  final target = avatarTargetFrom(
    frame,
    minLikelihood: minLikelihood,
    latch: latch,
  );
  if (target == null) return _nothing;
  return buildSilhouette(target, build: build);
}

/// Reports [frame] as the body [buildSilhouette] draws, keeping the detector's
/// own left and right apart wherever both of them can be believed.
///
/// This used to pick ONE side and re-key it onto the left, on the reasoning
/// that an authored target is a mid-line side view and the live body should
/// look like one. That is true of a body standing side-on and false of a body
/// standing face-on, and the app ships face-on by default: the operator raised
/// one arm and the figure raised two, because the side that was dropped was
/// then reinvented by mirroring the side that was kept. Which arm "worked"
/// changed with body position for the same reason — it was whichever side won
/// the pick that frame.
///
/// Both sides are now reported under their own keys when both carry a torso.
/// `buildSilhouette` needs no mode flag to tell the two apart: the presence of
/// a right-keyed shoulder and hip IS the signal, and it degrades continuously
/// back to the mirrored figure as a turning body brings its shoulders into
/// line.
///
/// Returns null when neither side carries a torso, which is the only part that
/// is not optional: without a shoulder and a hip there is no spine, no axis to
/// mirror about, and nothing that would read as a person.
/// [latch] carries the far side across the frames the detector drops it in.
/// Optional, and null keeps the pure, frame-by-frame behaviour every existing
/// test asserts — see [AvatarFarSideLatch] for what it costs and what bounds it.
PoseTarget? avatarTargetFrom(
  PoseFrame frame, {
  double minLikelihood = 0.5,
  AvatarFarSideLatch? latch,
}) {
  final leftOk = _hasTorso(frame, _leftChain, minLikelihood);
  final rightOk = _hasTorso(frame, _rightChain, minLikelihood);
  if (!leftOk && !rightOk) {
    latch?.reset();
    return null;
  }

  final joints = <LandmarkType, (double, double)>{};
  void collect(List<LandmarkType> chain, List<LandmarkType> keys) {
    for (var i = 0; i < chain.length; i++) {
      final lm = frame.landmarks[chain[i]];
      if (lm == null) continue;
      if (lm.likelihood < minLikelihood) continue;
      if (!_drawable(lm, frame.aspectRatio)) continue;
      joints[keys[i]] = (lm.x, lm.y);
    }
  }

  // Which physical side of the body is the believable one this frame, and
  // which is the far one. The NEAR side is always emitted under the left keys
  // — that is what makes a one-sided figure a mid-line one, exactly like an
  // authored target, which `buildSilhouette` then mirrors back out to both
  // sides itself. Drawing a lone half-body would be the honest reading of the
  // data and an unusable picture.
  //
  // Written as near/far rather than as left/right because the latch below has
  // to work for a lifter standing either way round. It used to key off `leftOk`
  // directly, which meant a body whose reliable side was its RIGHT reset the
  // latch on every frame its left side flickered — the pre-G6 snap, alive for
  // half of all stances, under a test suite that only ever dropped the right
  // side. Found by review, not by the tests.
  final nearIsLeft = leftOk;
  final nearChain = nearIsLeft ? _leftChain : _rightChain;
  final farChain = nearIsLeft ? _rightChain : _leftChain;
  final farOk = leftOk && rightOk;

  collect(nearChain, _leftChain);
  if (farOk) collect(farChain, _rightChain);

  // Observed on a two-sided frame, held on a one-sided one. The near shoulder
  // and the torso length are what bound the hold in space — see
  // [AvatarFarSideLatch.gate].
  final nearShoulder = joints[LandmarkType.leftShoulder];
  final nearHip = joints[LandmarkType.leftHip];
  final torso = nearShoulder == null || nearHip == null
      ? 0.0
      : _distance(nearShoulder, nearHip);
  final far = latch?.gate(
    observed: farOk
        ? {
            for (final t in _rightChain)
              if (joints.containsKey(t)) t: joints[t]!,
          }
        : null,
    nearIsLeft: nearIsLeft,
    nearShoulder: nearShoulder,
    torso: torso,
    timestampMs: frame.timestampMs,
  );
  if (far != null && !farOk) joints.addAll(far);

  // The torso is the one hard requirement, and `_hasTorso` has already proved
  // it for whichever side got collected. A partial limb is dropped by
  // `buildSilhouette` on its own ("a partial limb is worse than none").
  if (!joints.containsKey(LandmarkType.leftShoulder) ||
      !joints.containsKey(LandmarkType.leftHip)) {
    return null;
  }

  return PoseTarget(id: 'live', joints: joints, bones: const []);
}

/// Holds the far side of the body across the frames the detector loses it in.
///
/// G6, and the item G5 deferred here by name. The far side is gained and lost
/// as ONE torso — `avatarTargetFrom` emits right-keyed joints only inside
/// `leftOk && rightOk`, and `_hasTorso` applies the identical checks, an
/// invariant `pose_avatar_test.dart` pins — so a body loses BOTH far torso
/// joints at once. `buildSilhouette` then reads `facing` as 0 and draws the
/// trunk at chest depth instead of shoulder width: about a fifth of its width,
/// gone and back in one frame, every time the detector blinks.
///
/// No stateless builder can smooth that. With no far side observed there is no
/// measurement to interpolate towards — which is exactly why the fix belongs
/// here, at the producer, where the previous frame is still in hand.
///
/// **Bounded in time AND in space, deliberately.** A latch that only expired on
/// a clock would paste a stale far side onto a body that had walked away from
/// it; one that only checked distance would hold a guess indefinitely on
/// someone standing still. So the held joints are dropped as soon as either
/// [holdMs] passes or the NEAR shoulder moves further than [maxDriftFraction]
/// of a torso from where it was when the latch was taken. Inside both bounds
/// the far side is a good description of a body that has not moved; outside
/// either, it is fiction.
class AvatarFarSideLatch {
  AvatarFarSideLatch({
    this.holdMs = 200,
    this.maxDriftFraction = 0.12,
  });

  /// How long a lost far side may keep being drawn.
  ///
  /// 200ms is a `PRODUCT_HEURISTIC`: about six frames at the camera's rate,
  /// which covers the blink-length dropouts this exists for, and short enough
  /// that a genuine turn to the side reaches its profile within a fifth of a
  /// second rather than lingering as a body that will not turn.
  final int holdMs;

  /// How far the near shoulder may travel before the held far side is stale,
  /// as a fraction of the shoulder-to-hip distance.
  ///
  /// Measured in torsos rather than in frame units so it means the same thing
  /// for a lifter close to the camera and one across the room.
  final double maxDriftFraction;

  Map<LandmarkType, (double, double)>? _far;
  (double, double)? _anchor;
  double _torso = 0;
  int _atMs = 0;
  bool _nearIsLeft = true;

  /// Forget everything. Call when the stream restarts or the mode is left.
  void reset() {
    _far = null;
    _anchor = null;
    _torso = 0;
    _atMs = 0;
  }

  /// The far-side joints to draw this frame, or null for none.
  ///
  /// [observed] is what the detector actually reported for the far side this
  /// frame — non-null and non-empty means there is nothing to latch for, and
  /// the fresh observation both wins and becomes the new held value.
  /// [nearIsLeft] says which physical side of the body was believable this
  /// frame. A held far side only describes the body it was taken from: if the
  /// lifter turns so that the OTHER side becomes the near one, the joints held
  /// belong to the side that is now nearest the camera and drawing them as the
  /// far one would fold the body through itself.
  Map<LandmarkType, (double, double)>? gate({
    required Map<LandmarkType, (double, double)>? observed,
    required bool nearIsLeft,
    required (double, double)? nearShoulder,
    required double torso,
    required int timestampMs,
  }) {
    if (observed != null && observed.isNotEmpty) {
      _far = Map.unmodifiable(observed);
      _anchor = nearShoulder;
      _torso = torso;
      _atMs = timestampMs;
      _nearIsLeft = nearIsLeft;
      return _far;
    }

    final held = _far;
    if (held == null) return null;
    if (nearIsLeft != _nearIsLeft) {
      reset();
      return null;
    }

    // A clock that went backwards is a new stream, not a 0ms-old latch.
    final age = timestampMs - _atMs;
    if (age < 0 || age > holdMs) {
      reset();
      return null;
    }

    final anchor = _anchor;
    if (anchor == null || nearShoulder == null || _torso <= 0) {
      reset();
      return null;
    }
    final dx = nearShoulder.$1 - anchor.$1;
    final dy = nearShoulder.$2 - anchor.$2;
    if (dx * dx + dy * dy >
        (maxDriftFraction * _torso) * (maxDriftFraction * _torso)) {
      reset();
      return null;
    }
    return held;
  }
}

double _distance((double, double) a, (double, double) b) {
  final dx = a.$1 - b.$1;
  final dy = a.$2 - b.$2;
  return math.sqrt(dx * dx + dy * dy);
}

/// Whether this side carries a shoulder and a hip worth drawing.
///
/// Both, or neither: a spine needs two ends. The likelihood floor and the
/// coordinate bound are the same ones the joints themselves face, so a torso
/// that passes here cannot be dropped by [_drawable] afterwards.
bool _hasTorso(
  PoseFrame frame,
  List<LandmarkType> chain,
  double minLikelihood,
) {
  final shoulder = frame.landmarks[chain[0]];
  final hip = frame.landmarks[chain[3]];
  if (shoulder == null || hip == null) return false;
  if (shoulder.likelihood < minLikelihood || hip.likelihood < minLikelihood) {
    return false;
  }
  return _drawable(shoulder, frame.aspectRatio) &&
      _drawable(hip, frame.aspectRatio);
}

/// Is this coordinate close enough to the contract to put in a filled outline.
bool _drawable(PoseLandmark lm, double aspectRatio) {
  if (lm.x.isNaN || lm.y.isNaN) return false;
  if (lm.x < -_drawSlack || lm.x > aspectRatio + _drawSlack) return false;
  if (lm.y < -_drawSlack || lm.y > 1.0 + _drawSlack) return false;
  return true;
}
