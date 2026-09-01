/// Turns a scored [PoseTarget] into something that reads as a human body.
///
/// ## Why this file exists
///
/// The targets are authored as a **mid-line side view**: one shoulder, one
/// elbow, one wrist, one hip, one knee, one ankle. That is deliberate and it is
/// right for scoring — from the side the far arm and far leg are behind the
/// body, the detector's estimates for them are guesses, and scoring against a
/// guess fails people for standing at a slightly different angle.
///
/// It is wrong for *drawing*. Six points joined by five lines is half a
/// skeleton, and half a skeleton drawn over a person does not read as a person.
/// Operator, twice: *"человеческий силует привратился а закорючку"*, then again
/// after the first repair — *"силует до сих пор странный"*. A screen recording
/// of the coach settled what the second complaint was about: the outline was a
/// tall thin stalk with a large circle floating above it, nothing like a body.
///
/// Two separate faults produced that, and both are fixed here.
///
/// **One — the figure had one arm and one leg.** Repaired by mirroring: the
/// torso has width, so the near and far limb hang from opposite sides of it.
/// The mirrored joints are DRAWN ONLY. [PoseTarget.joints] — what
/// `poseMatchScore` reads — is untouched, so nothing about scoring changes.
///
/// **Two — the two axes were scaled by different numbers.** The painter used to
/// map `x * panelWidth, y * panelHeight`, and the panel is 9:16. A body authored
/// 0.16 wide and 0.67 tall came out 54 px by 399 px: horizontally squeezed by
/// 1.78x against the vertical. `pose_projection.dart` argued this was fine for
/// the silhouette "because those targets are authored in the box's own
/// coordinates" — that argument was mine and it was wrong. The numbers were
/// authored to look like a person, and "look like a person" is a claim about
/// proportion, which a per-axis scale destroys. [fitSilhouette] applies one
/// scale to both axes.
///
/// ## What build actually changes on screen
///
/// The operator asked for the outline to follow height and weight, so that a
/// 150 cm woman and a 2 m man are not offered the same shape. Height cannot do
/// that and it is worth being exact about why: the silhouette is fitted to the
/// panel, and a person's size in frame is set by how far they stand from the
/// phone, not by how tall they are. Scaling the outline by height would tell a
/// tall user to step back — which is not the instruction anyone wants.
///
/// What genuinely differs between those two bodies on a screen is **width**:
/// shoulder-to-hip ratio, which is strongly sexed, and overall breadth, which
/// tracks BMI. Both are used. Height enters only through the BMI it and weight
/// compute together.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'pose_landmark.dart';
import 'pose_target.dart';

/// How broad to draw the body, as multiples of its own torso length.
///
/// Fractions of torso rather than absolute numbers, so the proportions survive
/// [fitSilhouette] scaling the figure to whatever panel it is drawn in.
class BodyBuild {
  const BodyBuild({
    required this.shoulderHalfWidth,
    required this.hipHalfWidth,
    required this.limbThickness,
    required this.trunkHalfDepth,
  })  :
        // `buildSilhouette` divides by `shoulderHalfWidth * torso` to work out
        // how square to the camera a body is. Every build this file produces is
        // comfortably positive, so this is unreachable today — but a zero would
        // turn that into 0/0 and quietly draw a NaN figure rather than failing,
        // and a silhouette is exactly the kind of output where "quietly wrong"
        // survives a test run.
        assert(shoulderHalfWidth > 0, 'a body has some width'),
        assert(hipHalfWidth > 0, 'a body has some width'),
        assert(trunkHalfDepth > 0, 'a body has some depth'),
        assert(limbThickness > 0, 'a limb has some girth');

  /// Half the shoulder span, over torso length.
  final double shoulderHalfWidth;

  /// Half the hip span, over torso length.
  final double hipHalfWidth;

  /// Stroke width for limbs, over torso length.
  final double limbThickness;

  /// Half the trunk's FRONT-TO-BACK thickness, over torso length.
  ///
  /// The number a side view needs, and the one the file had no concept of
  /// until 2026-09-01. Every authored target is a side view, and the drawing
  /// widened all of them by [shoulderHalfWidth] — a number that describes how
  /// far apart two shoulders are when you are looking at someone's front.
  /// Applied to a profile it does not make a person wider, it makes a person
  /// TWO people: measured on the shipped squat, the two mirrored arms came out
  /// 0.10 apart on a torso 0.257 long — 0.40 of a torso length — and, because
  /// the offset runs perpendicular to a spine inclined 42 degrees in a deep
  /// squat, they came apart on the diagonal. That is the lattice the operator
  /// kept calling «закорючка», and no amount of re-tuning limb girth was going
  /// to fix a figure built to the wrong dimension.
  ///
  /// An adult torso is ~50 cm shoulder to hip and a chest is ~21 cm front to
  /// back, so the half-depth is ~0.21 of torso length. Against ~0.27 for a
  /// shoulder half-span, a profile trunk is about three quarters the width of
  /// the front-on one — which is what a person looks like from the side.
  ///
  /// This doc said ~0.13 until 2026-09-01, from a guess that a chest is a
  /// quarter as deep as the torso is long. It is not; 0.13 is a 13 cm-thick
  /// person. The value was corrected on the phone, and this text is corrected
  /// here because a maintainer reads the field's own contract, not the history
  /// below it, and would have "repaired" 0.21 back to the plank.
  final double trunkHalfDepth;

  /// Neither sex assumed, nor any body composition known.
  static const unknown = BodyBuild(
    shoulderHalfWidth: 0.27,
    hipHalfWidth: 0.21,
    limbThickness: 0.16,
    // A chest, measured. Torso (shoulder to hip) is ~50 cm on an adult and the
    // chest is ~21 cm front to back, so the HALF-depth is ~0.21 of torso — not
    // the 0.13 this shipped with first. 0.13 is a 13 cm-thick person: correct
    // in kind (a depth, not a breadth) and still a plank, which is what the
    // demonstration looked like on the phone once it was finally visible.
    trunkHalfDepth: 0.21,
  );

  /// Derived from whatever the profile holds. Every argument is optional
  /// because every one of them is optional in the profile — a user who
  /// skipped the intake still gets a figure, just the average one.
  ///
  /// Ratios are the conventional adult ones: men carry the wider shoulder and
  /// the narrower hip, women the reverse. `nonBinary` and `preferNotToSay`
  /// take [unknown] rather than a guess, which is the whole point of offering
  /// those answers.
  static BodyBuild forBody({
    SilhouetteSex sex = SilhouetteSex.unspecified,
    int? heightCm,
    double? weightKg,
  }) {
    final base = switch (sex) {
      SilhouetteSex.male => const BodyBuild(
          shoulderHalfWidth: 0.31,
          hipHalfWidth: 0.19,
          limbThickness: 0.17,
          // Depth is far less sexed than breadth — the ratio that separates
          // the two conventional builds is a front-on one. A token difference
          // rather than none, so the profile still tracks the answer.
          trunkHalfDepth: 0.215,
        ),
      SilhouetteSex.female => const BodyBuild(
          shoulderHalfWidth: 0.25,
          hipHalfWidth: 0.24,
          limbThickness: 0.15,
          trunkHalfDepth: 0.20,
        ),
      SilhouetteSex.unspecified => unknown,
    };
    final k = _breadthFactor(heightCm: heightCm, weightKg: weightKg);
    if (k == 1.0) return base;
    return BodyBuild(
      shoulderHalfWidth: base.shoulderHalfWidth * k,
      hipHalfWidth: base.hipHalfWidth * k,
      limbThickness: base.limbThickness * k,
      // A heavier body is deeper as well as broader, so the profile has to
      // move with the same factor or the side view would ignore the intake
      // answers the front view uses.
      trunkHalfDepth: base.trunkHalfDepth * k,
    );
  }

  // Value equality, because the painter's `shouldRepaint` compares builds.
  // `forBody` returns a fresh instance on every provider read, so identity
  // would report "changed" on every camera frame and repaint the overlay
  // continuously — the exact cost `shouldRepaint` exists to avoid.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BodyBuild &&
          other.shoulderHalfWidth == shoulderHalfWidth &&
          other.hipHalfWidth == hipHalfWidth &&
          other.limbThickness == limbThickness &&
          other.trunkHalfDepth == trunkHalfDepth;

  @override
  int get hashCode => Object.hash(
      shoulderHalfWidth, hipHalfWidth, limbThickness, trunkHalfDepth);

  /// Breadth multiplier from BMI, 1.0 when it cannot be computed.
  ///
  /// Square root of the BMI ratio, not the ratio itself: mass grows with the
  /// square of a linear dimension, so a body 21% heavier for its height is
  /// about 10% broader, not 21%. Clamped hard at both ends — this is an
  /// outline to stand inside, and an outline that has become a caricature is
  /// harder to aim at, not more personal.
  static double _breadthFactor({int? heightCm, double? weightKg}) {
    if (heightCm == null || weightKg == null) return 1.0;
    if (heightCm < 90 || heightCm > 260) return 1.0;
    if (weightKg < 25 || weightKg > 350) return 1.0;
    final m = heightCm / 100.0;
    final bmi = weightKg / (m * m);
    return math.sqrt(bmi / 22.0).clamp(0.86, 1.32);
  }
}

/// Which of the two conventional builds to draw. Deliberately not the profile's
/// `Gender` — this file must not depend on the profile feature, and the mapping
/// from an identity question to a drawing proportion is a decision worth making
/// once, at the call site, in the open.
enum SilhouetteSex { male, female, unspecified }

/// A body ready to draw: line segments and a head, in the target's own
/// coordinate space.
class SilhouetteFigure {
  const SilhouetteFigure({
    required this.segments,
    required this.torso,
    required this.joints,
    required this.head,
    required this.limbThickness,
    this.limbs = const [],
    this.segmentBones = const [],
    this.jointTypes = const [],
  });

  /// Bones, as endpoint pairs. The torso is [torso], not a segment: drawn as
  /// four separate strokes it read as scaffolding rather than as a trunk,
  /// and in a deep squat — where the arms swing across the thighs — the whole
  /// figure came out as a tangle of bars with no centre to it.
  final List<(Offset, Offset)> segments;

  /// Shoulder-to-hip trunk, as a closed quad to fill. Empty when there is no
  /// torso to draw.
  final List<Offset> torso;

  /// Where to mark an articulation.
  final List<Offset> joints;

  /// Centre and radius, or null when the torso could not be located.
  final (Offset, double)? head;

  /// Which two joints each entry of [segments] runs between, index for index.
  ///
  /// G6. The live skeleton used to glow one colour for the whole body, off the
  /// single worst verdict, so "your back is rounding" lit the shins as brightly
  /// as the spine. A [FormClassifier] already declares the joints it reads
  /// (`requiredLandmarks`), so naming each bone is all that was missing to
  /// light only the part of the body the rule is actually about.
  ///
  /// Either end is null for a bone with no landmark of its own — the neck,
  /// which runs from the shoulder MID-POINT to a constructed point under the
  /// head, and every mirrored limb, whose points are a reflection of the
  /// observed side rather than an observation. A null end never matches a
  /// rule, which is the conservative direction: an unnamed bone stays neutral
  /// instead of being lit by a rule that never looked at it.
  ///
  /// Empty on the degenerate figures, and on any figure built before this
  /// existed — a painter must check the length rather than assuming it pairs
  /// up with [segments].
  final List<(LandmarkType?, LandmarkType?)> segmentBones;

  /// Which landmark each entry of [joints] is, index for index.
  ///
  /// Same idea and same caveats as [segmentBones]: null for a point with no
  /// landmark of its own, and empty on a figure built before this existed, so a
  /// painter must check the length rather than assume the lists pair up.
  ///
  /// This is what lets the reference's ring be drawn ON the joint a rule is
  /// about instead of on all of them.
  final List<LandmarkType?> jointTypes;

  /// Closed outlines — one per limb — ready to be filled as a single body.
  ///
  /// B4. [segments] describes bones; drawing them as thick round-capped lines
  /// produced a stick figure with fat strokes, which the operator rejected
  /// three times. A limb is not a line of constant width: an arm leaves the
  /// shoulder broad and narrows at the wrist, and only an outline can say so.
  /// Filling these together with [torso] and [head] under one non-zero path
  /// gives one continuous body instead of parts laid over each other.
  ///
  /// [segments] is kept: it is what the tests assert bone geometry with, and
  /// the demo overlay still reads it.
  final List<List<Offset>> limbs;

  /// In the same units as [segments].
  final double limbThickness;

  /// Everything the figure occupies, head included. Empty when there is
  /// nothing to draw.
  Rect get bounds {
    if (segments.isEmpty && torso.isEmpty && head == null) return Rect.zero;
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    void add(double x, double y) {
      if (x < l) l = x;
      if (y < t) t = y;
      if (x > r) r = x;
      if (y > b) b = y;
    }

    for (final (a, z) in segments) {
      add(a.dx, a.dy);
      add(z.dx, z.dy);
    }
    for (final p in torso) {
      add(p.dx, p.dy);
    }
    // The filled outlines sit half a limb-width outside the bones they wrap,
    // so a bounds computed from segments alone would let the fit clip an arm.
    for (final limb in limbs) {
      for (final p in limb) {
        add(p.dx, p.dy);
      }
    }
    final h = head;
    if (h != null) {
      add(h.$1.dx - h.$2, h.$1.dy - h.$2);
      add(h.$1.dx + h.$2, h.$1.dy + h.$2);
    }
    return Rect.fromLTRB(l, t, r, b);
  }
}

/// Builds a two-sided body from a mid-line [target].
///
/// The torso axis runs hip-to-shoulder; everything is placed relative to it, so
/// the figure stays coherent as the torso inclines through a squat instead of
/// limbs drifting off a body that has rotated away from them.
///
/// Returns an empty figure when the target lacks a shoulder or a hip: without
/// those there is no torso, and without a torso there is no axis to mirror
/// about. Callers get nothing drawn rather than something wrong.
///
SilhouetteFigure buildSilhouette(
  PoseTarget target, {
  BodyBuild build = BodyBuild.unknown,
}) {
  Offset? at(LandmarkType t) {
    final j = target.joints[t];
    return j == null ? null : Offset(j.$1, j.$2);
  }

  // Left keys carry two different meanings, and which one applies is decided by
  // the DATA rather than by a mode flag.
  //
  // An authored target is one-sided: it is a side view drawn about the body's
  // mid-line, so `leftShoulder` IS the mid-line and both drawn sides come from
  // mirroring it. `pose_target.dart` contains no right-keyed joint at all, so
  // every authored target takes that path by construction and cannot regress
  // through the branch below.
  //
  // A live avatar built from a body facing the camera is two-sided: the
  // detector saw both shoulders in different places, and mirroring one of them
  // is what drew two raised arms when the user raised one. There the left key
  // means the actual left shoulder and the mid-line is the midpoint.
  final lShoulder = at(LandmarkType.leftShoulder);
  final lHip = at(LandmarkType.leftHip);
  if (lShoulder == null || lHip == null) {
    return const SilhouetteFigure(
      segments: [],
      torso: [],
      joints: [],
      head: null,
      limbThickness: 0,
    );
  }
  final rShoulder = at(LandmarkType.rightShoulder);
  final rHip = at(LandmarkType.rightHip);
  // Named per end, and then required TOGETHER — which is the whole of what
  // three rounds of review on this gate settled, so the names stay to make the
  // pairing visible rather than implied. See the block below `across` for why
  // there is no attempt to handle one without the other.
  final sTwo = rShoulder != null;
  final hTwo = rHip != null;

  final shoulder = sTwo && hTwo ? (lShoulder + rShoulder) / 2 : lShoulder;
  final hip = sTwo && hTwo ? (lHip + rHip) / 2 : lHip;

  final spine = shoulder - hip;
  final torso = spine.distance;
  if (torso <= 1e-9) {
    return const SilhouetteFigure(
      segments: [],
      torso: [],
      joints: [],
      head: null,
      limbThickness: 0,
    );
  }
  // Unit vector across the body. Perpendicular to the spine, so the shoulders
  // stay square to the torso however it is tilted.
  final across = Offset(-spine.dy / torso, spine.dx / torso);

  // Which dimension the drawing is allowed to use.
  //
  // A one-sided target IS a side view — `pose_target.dart` authors every one of
  // them about the body's mid-line, and the coach's own instruction is «встаньте
  // боком к камере». So the trunk's across-axis extent is its DEPTH, not the
  // span between two shoulders, and the two mirrored limbs are the near and far
  // one rather than a left and a right. See [BodyBuild.trunkHalfDepth] for what
  // using the wrong one of those produced.
  //
  /// Signed distance from [centre] along the across-axis: how far to one side
  /// of the body a point sits, positive towards the drawn left.
  double acrossOf(Offset p, Offset centre) {
    final d = p - centre;
    return d.dx * across.dx + d.dy * across.dy;
  }

  // Which way round the observation is. A one-sided target has its chain ON the
  // mid-line, so this is 0 and the `>= 0` picks +1 — the side the old code
  // always drew the left limb on. Nothing about the authored figures moves.
  final leftSign = acrossOf(lShoulder, shoulder) >= 0 ? 1.0 : -1.0;

  // How far from the mid-line the observation ACTUALLY put each end. Zero for a
  // one-sided target, where the chain is the mid-line and there is nothing to
  // measure.
  final sObs = sTwo && hTwo ? acrossOf(lShoulder, shoulder).abs() : 0.0;
  final hObs = sTwo && hTwo ? acrossOf(lHip, hip).abs() : 0.0;

  // A torso with one far joint but not the other does not occur, and this is
  // where three rounds of review converged (2026-09-01).
  //
  // GPT-PM found, correctly, that gating `facing` on an aggregate `twoSided`
  // let one dropped landmark snap the trunk 20%. Two attempts to reconstruct
  // the missing end followed, and it rejected both: the first scaled the
  // surviving end by `BodyBuild`'s shoulder-to-hip ratio, which is only
  // continuous for a body that matches the prior; the second projected onto a
  // line through the bilateral midpoints, and a squat is ARTICULATED — hip to
  // ankle is not the torso's axis, and on the app's own deep-squat geometry
  // that line puts the reconstructed shoulder up to a whole torso length away.
  // Both objections were exact, and the second is worse than the defect it
  // replaced.
  //
  // Its own instruction was the answer: degrade rather than invent an axis. So
  // there is no reconstruction here at all — a half-bilateral torso is drawn as
  // the profile it structurally is.
  //
  // What makes that safe rather than a retreat is that the state is
  // UNREACHABLE from the live path, which is the only caller with a continuity
  // requirement. `avatarTargetFrom` emits right-keyed joints solely inside
  // `if (leftOk && rightOk)`, and `_hasTorso` has already put the right
  // shoulder AND the right hip through the identical three checks `collect`
  // applies — non-null, the same likelihood floor, the same `_drawable` bound.
  // So `rShoulder != null` if and only if `rHip != null`, and the far side is
  // gained and lost as one. Pinned by a test in `pose_avatar_test.dart`.
  //
  // The transition that IS reachable is all-or-nothing: both far torso joints
  // at once, when a body turns or the detector blinks. No stateless builder can
  // interpolate that — with no far side observed there is no measurement to
  // interpolate towards — so the honest place to soften it is hysteresis at the
  // producer, where the previous frame is still in hand. Recorded as follow-up
  // work rather than guessed at here.
  final twoSided = sTwo && hTwo;

  // How square to the camera the body is: 0 edge-on, 1 fully front-on.
  //
  // This is the number the whole widening hangs off, and it replaced a
  // `twoSided ? breadth : depth` switch that reintroduced exactly the class of
  // defect the paragraph below was written to prevent. Caught in review of this
  // gate, and the reviewer was right: a hard switch halves the drawn body in a
  // single frame at the moment one shoulder's confidence drops, which is a
  // thing that happens mid-turn, mid-rep and under motion blur.
  //
  // A one-sided authored target is edge-on by definition, so it lands at 0 and
  // gets the profile dimensions. A live body turning on the spot walks the
  // range continuously — and, because the same factor drives every dimension
  // below, so does everything drawn from it.
  //
  // Always off the shoulders, and it no longer needs the far one. `sObs` is the
  // distance from the near shoulder to the body's mid-line, and the mid-line is
  // reconstructed above from whatever bilateral pairs the frame does have — so
  // losing the far shoulder changes nothing here at all.
  //
  // Reading it off the hips instead, when the shoulders were the pair that went
  // missing, was the last remnant of the same switch: it makes the measurement
  // depend on the body matching `BodyBuild`'s shoulder-to-hip ratio, and on a
  // body with equal spans it still moved `facing` from 0.889 to a clamped 1.0
  // and the trunk by 2.5% on one lost landmark.
  final facing = twoSided
      ? (sObs / (build.shoulderHalfWidth * torso)).clamp(0.0, 1.0)
      : 0.0;

  /// Interpolates a dimension between what a profile needs and what a front
  /// view needs, by [facing].
  double turned(double side, double front) => side + (front - side) * facing;

  // The trunk's across-axis half-extent. Front-on that is half a shoulder span;
  // edge-on it is half a chest's DEPTH — see [BodyBuild.trunkHalfDepth] for
  // what using the front-on number on a profile produced.
  final sHalf = turned(build.trunkHalfDepth * torso,
      build.shoulderHalfWidth * torso);
  // Hips are marginally deeper than the chest, front to back.
  final hHalf =
      turned(build.trunkHalfDepth * 1.1 * torso, build.hipHalfWidth * torso);

  // How much the figure has to be widened beyond what was observed to still
  // read as a body, and this is what makes the two paths meet continuously
  // instead of snapping between them.
  //
  // Facing the camera, the shoulders are already the width of a person, so this
  // is ~0 and every joint is drawn where the detector actually saw it. Turned
  // side-on, the two shoulders collapse onto each other, this grows to the
  // profile's own width, and the figure becomes the mirrored one the side view
  // needs. Every angle between the two is a blend of the two, so a user turning
  // on the spot sees the drawing rotate rather than flip — the flicker class
  // Gate A existed to remove, avoided here by having no threshold to flicker
  // across.
  final sWiden = sHalf > sObs ? sHalf - sObs : 0.0;
  final hWiden = hHalf > hObs ? hHalf - hObs : 0.0;

  // How far apart to draw the near and far limb of a pair.
  //
  // Edge-on this is a PARALLAX, not the trunk's depth: in a profile the far arm
  // is directly behind the near one, and separating them by the width of the
  // body draws a second person standing beside the first. Enough that the
  // figure has a far side at all, small enough that the two outlines overlap
  // and union into one limb with depth to it. Front-on it converges on the
  // observed separation, so each limb is drawn where it was actually seen.
  const parallax = 0.055;
  //
  // These are TARGETS, not widenings: how far from the mid-line each limb of a
  // pair belongs. `limbPair` subtracts whatever separation it can actually see
  // in that pair, because it is the only place that knows. Computing the
  // subtraction here, off the shoulders, was the same defect as the trunk's —
  // a detector can lose the far HIP and keep both arms, and the arms would then
  // have had a full profile parallax added to a separation they already had.
  final armTarget = turned(parallax * torso, build.shoulderHalfWidth * torso);
  final legTarget = turned(parallax * torso, build.hipHalfWidth * torso);

  final segments = <(Offset, Offset)>[];
  // Index for index with `segments`. Appended in the same statements, so the
  // two cannot fall out of step without the append itself being edited.
  final segmentBones = <(LandmarkType?, LandmarkType?)>[];
  final joints = <Offset>[];
  // Index for index with `joints`, appended in the same statements.
  final jointTypes = <LandmarkType?>[];
  final limbs = <List<Offset>>[];

  /// Turns a polyline into a closed outline that narrows along its length.
  ///
  /// B4. Each point gets its own half-width, and the outline runs down one
  /// side and back up the other. At a bend the offset direction is the average
  /// of the two adjacent segment normals, so a flexed elbow keeps its
  /// thickness instead of pinching — the artefact that makes a naive
  /// per-segment offset look broken exactly where a joint is.
  List<Offset> outlineOf(List<Offset> pts, List<double> halfWidths) {
    if (pts.length < 2) return const [];
    Offset normalAt(int i) {
      Offset dir;
      if (i == 0) {
        dir = pts[1] - pts[0];
      } else if (i == pts.length - 1) {
        dir = pts[i] - pts[i - 1];
      } else {
        final a = pts[i] - pts[i - 1];
        final b = pts[i + 1] - pts[i];
        final na = a.distance, nb = b.distance;
        dir = (na > 1e-9 ? a / na : Offset.zero) +
            (nb > 1e-9 ? b / nb : Offset.zero);
      }
      final d = dir.distance;
      if (d <= 1e-9) return across;
      return Offset(-dir.dy / d, dir.dx / d);
    }

    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final n = normalAt(i) * halfWidths[i];
      left.add(pts[i] + n);
      right.add(pts[i] - n);
    }
    return [...left, ...right.reversed];
  }

  // Observed position, widened outward. One-sided, `lShoulder` is the mid-line
  // and `sWiden` is the whole build half-width, so these are exactly the four
  // synthesised corners the authored figures have always had.
  //
  // `twoSided`, not `rShoulder != null`, and the difference is a real defect
  // found by a test for exactly this state (2026-09-01). A detector that keeps
  // the far SHOULDER and loses the far HIP — occlusion, a turn, one
  // low-confidence frame — is not two-sided, so `sObs`, `facing` and `sWiden`
  // were all computed as if the body were edge-on. Reading the surviving
  // `rShoulder` here anyway then widened a pair already 0.12 apart by a full
  // profile half-width each, drawing a trunk twice its proper width and
  // sheared against hips still centred on the mid-line. Either half was
  // self-consistent; using one of each was not.
  //
  // Where a far joint was not seen it is SYNTHESISED as the mirror of the near
  // one about the centre, rather than collapsed onto the centre itself. With
  // `sObs`/`hObs` at 0 — a genuinely one-sided target — the mirror IS the
  // centre, so every authored figure is unchanged; with an estimated centre it
  // is the far side that end would have had.
  final farShoulder =
      twoSided ? rShoulder : shoulder - across * (leftSign * sObs);
  final farHip = twoSided ? rHip : hip - across * (leftSign * hObs);
  final leftShoulder = lShoulder + across * (leftSign * sWiden);
  final rightShoulder = farShoulder - across * (leftSign * sWiden);
  final leftHip = lHip + across * (leftSign * hWiden);
  final rightHip = farHip - across * (leftSign * hWiden);

  // B4: six points, not four. A shoulders-to-hips quad has straight sides and
  // reads as a box; a real trunk narrows at the waist and that single pair of
  // points is most of what turns the outline into a person. Wound across the
  // top, down the right, across the bottom, up the left — anything else and
  // the polygon crosses itself.
  final waistCentre = hip + spine * 0.45;
  // Measured off the corners actually drawn, not off the build alone, so a
  // narrow body seen face-on does not get a waist wider than its shoulders.
  // One-sided these are `sHalf` and `hHalf` and the number is unchanged.
  final waistHalf = (acrossOf(leftShoulder, shoulder).abs() +
          acrossOf(leftHip, hip).abs()) *
      0.5 *
      0.82;
  final leftWaist = waistCentre + across * waistHalf;
  final rightWaist = waistCentre - across * waistHalf;

  // A pelvis, and it is the difference between a figure and a lattice.
  //
  // The hip LANDMARK is the joint the leg rotates about, not the bottom of the
  // body: a real trunk carries on past it as the pelvis and the seat. Ending
  // the trunk exactly at that point leaves an open triangle between the torso
  // and the thigh wherever the two are at an angle to each other — which is
  // every frame of a squat, and is precisely where a squat is most in need of
  // reading as a person. Extending the bottom of the trunk along the spine puts
  // mass in that corner, so the union closes it and the thigh grows out of a
  // body instead of hinging off a point.
  //
  // Found on a phone at the bottom of the demonstration squat, where the figure
  // still read as a bent arrow after both the depth and the fill were correct.
  final seat = -spine / torso * (0.16 * torso);
  final trunk = <Offset>[
    leftShoulder,
    rightShoulder,
    rightWaist,
    rightHip + seat,
    leftHip + seat,
    leftWaist,
  ];
  joints.addAll([leftShoulder, rightShoulder, leftHip, rightHip]);
  jointTypes.addAll(const [
    LandmarkType.leftShoulder,
    LandmarkType.rightShoulder,
    LandmarkType.leftHip,
    LandmarkType.rightHip,
  ]);

  /// Draws the body's two matching limbs, each from its own observation where
  /// there is one.
  ///
  /// This used to take a single chain and hang it off both sides, which is
  /// right for a one-sided authored figure and wrong for a live body facing the
  /// camera. On a real phone it meant raising one arm drew TWO raised arms, and
  /// raising the other drew nothing — the detector's own left and right were
  /// never both read, so one of them was always being invented from the other.
  ///
  /// The offset still tapers along the chain — an arm leaves the shoulder at the
  /// shoulder's width and converges as it descends, which is what arms do — but
  /// it is now only the WIDENING, so it vanishes as the real separation grows.
  void limbPair(
    List<LandmarkType> leftChain,
    List<LandmarkType> rightChain,
    /// How far from the mid-line each limb of this pair belongs.
    double targetHalf,
    List<double> taper,
    List<double> girth,
  ) {
    List<Offset>? resolve(List<LandmarkType> chain) {
      final points = <Offset>[];
      for (final t in chain) {
        final p = at(t);
        if (p == null) return null; // a partial limb is worse than none
        points.add(p);
      }
      return points;
    }

    /// [chain] names the joints [points] came from, or is null when they are a
    /// mirrored copy of the other side. A mirrored limb is a reflection, not an
    /// observation: it is drawn where the far limb PROBABLY is, and lighting it
    /// for a rule that measured only the near one would be reporting on a
    /// guess.
    void draw(
      List<Offset> points,
      double sign,
      double widen, {
      List<LandmarkType>? chain,
    }) {
      final placed = <Offset>[];
      Offset? previous;
      LandmarkType? previousType;
      for (var i = 0; i < points.length; i++) {
        final p = points[i] + across * (sign * widen * taper[i]);
        final type = chain == null || i >= chain.length ? null : chain[i];
        if (previous != null) {
          segments.add((previous, p));
          segmentBones.add((previousType, type));
        }
        previousType = type;
        joints.add(p);
        jointTypes.add(type);
        placed.add(p);
        previous = p;
      }
      // The outline, in the same pass and off the same placed points, so the
      // filled body and the bones it was built from can never disagree.
      final outline = outlineOf(placed, [
        for (final g in girth) build.limbThickness * torso * g,
      ]);
      if (outline.isNotEmpty) limbs.add(outline);
    }

    final left = resolve(leftChain);
    final right = resolve(rightChain);

    // Both seen: each limb is drawn where it was seen. This is the case that
    // was broken, and it is the case the default view is in.
    //
    // The widening is measured from THIS pair, not from the shoulders. A
    // detector that keeps both arms and loses the far hip is not `twoSided`, so
    // a shoulder-derived widening would be the full profile parallax — added on
    // top of a separation these two limbs already have.
    if (left != null && right != null) {
      final mid = (left.first + right.first) / 2;
      final obs = acrossOf(left.first, mid).abs();
      final widen = targetHalf > obs ? targetHalf - obs : 0.0;
      draw(left, leftSign, widen, chain: leftChain);
      draw(right, -leftSign, widen, chain: rightChain);
      return;
    }

    final only = left ?? right;
    if (only == null) return;

    if (!twoSided) {
      // One-sided figure: the chain is the mid-line and both limbs come from
      // mirroring it. Every authored target lands here, unchanged.
      //
      // The chain IS named on both, unlike the far-side mirror below: a
      // one-sided target has no near and far side to confuse, so both copies
      // stand for the same observed joints seen from the side.
      final chain = left != null ? leftChain : rightChain;
      draw(only, 1.0, targetHalf, chain: chain);
      draw(only, -1.0, targetHalf, chain: chain);
      return;
    }

    // A torso with a far side, but only one of this pair survived — the far limb was
    // occluded, or the detector's confidence in it fell below the floor. Its
    // partner is reflected across the spine rather than translated, because
    // here the chain is off the mid-line and translating it would stack both
    // limbs on the same side of the body.
    final mirrored = [
      for (final p in only) p - across * (2 * acrossOf(p, hip)),
    ];
    final sign = identical(only, left) ? leftSign : -leftSign;
    final chain = identical(only, left) ? leftChain : rightChain;
    // Same rule again: the reflection already puts the two limbs
    // `acrossOf(only.first, hip)` either side of the spine, so widen only by
    // what is still missing.
    final obs = acrossOf(only.first, hip).abs();
    final widen = targetHalf > obs ? targetHalf - obs : 0.0;
    draw(only, sign, widen, chain: chain);
    // Deliberately unnamed — see `draw`.
    draw(mirrored, -sign, widen);
  }

  // `girth` is the half-width at each joint, as a multiple of the build's own
  // limb thickness. Arms are slimmer than legs and both narrow towards the
  // extremity — a constant width is what made the old drawing read as tubing.
  limbPair(
    const [
      LandmarkType.leftShoulder,
      LandmarkType.leftElbow,
      LandmarkType.leftWrist,
    ],
    const [
      LandmarkType.rightShoulder,
      LandmarkType.rightElbow,
      LandmarkType.rightWrist,
    ],
    armTarget,
    const [0.85, 0.72, 0.62],
    // Half-widths at shoulder / elbow / wrist, as multiples of limb thickness.
    // 0.52 x 0.16 x a 50 cm torso is an 8 cm upper arm tapering to a 4.5 cm
    // wrist, which is a person; the 0.46/0.36/0.26 this shipped with was a
    // pipe of near-constant bore.
    const [0.52, 0.38, 0.26],
  );
  limbPair(
    const [
      LandmarkType.leftHip,
      LandmarkType.leftKnee,
      LandmarkType.leftAnkle,
    ],
    const [
      LandmarkType.rightHip,
      LandmarkType.rightKnee,
      LandmarkType.rightAnkle,
    ],
    legTarget,
    const [1.0, 0.86, 0.74],
    // And a thigh is far heavier than an arm: 0.80 x 0.16 x 50 cm is a 13 cm
    // thigh narrowing to a 5 cm ankle. Drawn at an arm's girth, the legs were
    // the single loudest reason the figure read as a stick drawing.
    const [0.80, 0.50, 0.32],
  );

  // Head and neck. Placed along the spine so it stays over the chest when the
  // torso inclines, rather than hanging where a standing head would have been.
  final up = Offset(spine.dx / torso, spine.dy / torso);
  // The neck reaches the head rather than stopping short of it: `reach -
  // radius` is exactly where the skull's underside is, and a stub any shorter
  // leaves the head floating clear of the shoulders — which is most of what
  // made the old figure read as a circle balanced on a stick.
  const reach = 0.40;
  const radius = 0.17;
  const neck = reach - radius + 0.01;
  final headCentre = shoulder + up * (torso * reach);
  final neckTop = shoulder + up * (torso * neck);
  segments.add((shoulder, neckTop));
  // The neck runs from the shoulder MID-POINT, which is not a landmark, to a
  // point constructed under the head. Neither end is a joint any rule can have
  // measured.
  segmentBones.add((null, null));

  // The neck joins the fill too, or the head floats clear of a body it is
  // supposed to be attached to — which is most of what made the old drawing
  // read as a circle balanced on sticks.
  final neckOutline = outlineOf(
    [shoulder, neckTop],
    [build.limbThickness * torso * 0.52, build.limbThickness * torso * 0.44],
  );
  if (neckOutline.isNotEmpty) limbs.add(neckOutline);

  assert(
    segmentBones.length == segments.length,
    'every bone must be named, even if the name is (null, null): a painter '
    'reads these two lists index for index',
  );
  assert(
    jointTypes.length == joints.length,
    'every joint must be named too, for the same reason',
  );
  return SilhouetteFigure(
    segments: segments,
    segmentBones: segmentBones,
    jointTypes: jointTypes,
    torso: trunk,
    joints: joints,
    head: (headCentre, torso * radius),
    limbThickness: build.limbThickness * torso,
    limbs: limbs,
  );
}

/// One scale for both axes, centred, with a margin.
///
/// Returns the transform as `(scale, offset)`: a point `p` in figure space is
/// drawn at `p * scale + offset`. Callers scale stroke widths by the same
/// number, which is the only way the outline keeps its proportions in a panel
/// of any shape.
(double, Offset) fitSilhouette(
  Rect figure,
  Size panel, {
  double margin = 0.08,
}) {
  if (figure.width <= 0 && figure.height <= 0) return (1.0, Offset.zero);
  final usable = Size(
    panel.width * (1 - margin * 2),
    panel.height * (1 - margin * 2),
  );
  // Guard both axes against a zero extent: a figure that is exactly flat — a
  // push-up drawn without a head, say — has no height to divide by.
  final sx =
      figure.width > 1e-9 ? usable.width / figure.width : double.infinity;
  final sy =
      figure.height > 1e-9 ? usable.height / figure.height : double.infinity;
  var scale = math.min(sx, sy);
  if (!scale.isFinite || scale <= 0) scale = 1.0;
  final drawn = Size(figure.width * scale, figure.height * scale);
  final offset = Offset(
    (panel.width - drawn.width) / 2 - figure.left * scale,
    (panel.height - drawn.height) / 2 - figure.top * scale,
  );
  return (scale, offset);
}
