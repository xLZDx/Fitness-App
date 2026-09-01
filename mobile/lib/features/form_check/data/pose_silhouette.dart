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
  });

  /// Half the shoulder span, over torso length.
  final double shoulderHalfWidth;

  /// Half the hip span, over torso length.
  final double hipHalfWidth;

  /// Stroke width for limbs, over torso length.
  final double limbThickness;

  /// Neither sex assumed, nor any body composition known.
  static const unknown = BodyBuild(
    shoulderHalfWidth: 0.27,
    hipHalfWidth: 0.21,
    limbThickness: 0.16,
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
        ),
      SilhouetteSex.female => const BodyBuild(
          shoulderHalfWidth: 0.25,
          hipHalfWidth: 0.24,
          limbThickness: 0.15,
        ),
      SilhouetteSex.unspecified => unknown,
    };
    final k = _breadthFactor(heightCm: heightCm, weightKg: weightKg);
    if (k == 1.0) return base;
    return BodyBuild(
      shoulderHalfWidth: base.shoulderHalfWidth * k,
      hipHalfWidth: base.hipHalfWidth * k,
      limbThickness: base.limbThickness * k,
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
          other.limbThickness == limbThickness;

  @override
  int get hashCode =>
      Object.hash(shoulderHalfWidth, hipHalfWidth, limbThickness);

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
  final twoSided = rShoulder != null && rHip != null;

  final shoulder = twoSided ? (lShoulder + rShoulder) / 2 : lShoulder;
  final hip = twoSided ? (lHip + rHip) / 2 : lHip;

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

  final sHalf = build.shoulderHalfWidth * torso;
  final hHalf = build.hipHalfWidth * torso;

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

  // How much the figure has to be widened beyond what was observed to still
  // read as a body, and this is what makes the two paths meet continuously
  // instead of snapping between them.
  //
  // Facing the camera, the shoulders are already the width of a person, so this
  // is ~0 and every joint is drawn where the detector actually saw it. Turned
  // side-on, the two shoulders collapse onto each other, this grows to the full
  // build width, and the figure becomes the mirrored one the side view needs.
  // Every angle between the two is a blend of the two, so a user turning on the
  // spot sees the drawing rotate rather than flip — the flicker class Gate A
  // existed to remove, avoided here by having no threshold to flicker across.
  final sObs = twoSided ? acrossOf(lShoulder, shoulder).abs() : 0.0;
  final hObs = twoSided ? acrossOf(lHip, hip).abs() : 0.0;
  final sWiden = sHalf > sObs ? sHalf - sObs : 0.0;
  final hWiden = hHalf > hObs ? hHalf - hObs : 0.0;

  final segments = <(Offset, Offset)>[];
  final joints = <Offset>[];
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
  final leftShoulder = lShoulder + across * (leftSign * sWiden);
  final rightShoulder = (rShoulder ?? shoulder) - across * (leftSign * sWiden);
  final leftHip = lHip + across * (leftSign * hWiden);
  final rightHip = (rHip ?? hip) - across * (leftSign * hWiden);

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
  final trunk = <Offset>[
    leftShoulder,
    rightShoulder,
    rightWaist,
    rightHip,
    leftHip,
    leftWaist,
  ];
  joints.addAll([leftShoulder, rightShoulder, leftHip, rightHip]);

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
    double widen,
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

    void draw(List<Offset> points, double sign) {
      final placed = <Offset>[];
      Offset? previous;
      for (var i = 0; i < points.length; i++) {
        final p = points[i] + across * (sign * widen * taper[i]);
        if (previous != null) segments.add((previous, p));
        joints.add(p);
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
    if (left != null && right != null) {
      draw(left, leftSign);
      draw(right, -leftSign);
      return;
    }

    final only = left ?? right;
    if (only == null) return;

    if (!twoSided) {
      // One-sided figure: the chain is the mid-line and both limbs come from
      // mirroring it. Every authored target lands here, unchanged.
      draw(only, 1.0);
      draw(only, -1.0);
      return;
    }

    // Two-sided torso, but only one of this pair survived — the far limb was
    // occluded, or the detector's confidence in it fell below the floor. Its
    // partner is reflected across the spine rather than translated, because
    // here the chain is off the mid-line and translating it would stack both
    // limbs on the same side of the body.
    final mirrored = [
      for (final p in only) p - across * (2 * acrossOf(p, hip)),
    ];
    final sign = identical(only, left) ? leftSign : -leftSign;
    draw(only, sign);
    draw(mirrored, -sign);
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
    sWiden,
    const [0.85, 0.72, 0.62],
    const [0.46, 0.36, 0.26],
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
    hWiden,
    const [1.0, 0.86, 0.74],
    const [0.62, 0.44, 0.30],
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

  // The neck joins the fill too, or the head floats clear of a body it is
  // supposed to be attached to — which is most of what made the old drawing
  // read as a circle balanced on sticks.
  final neckOutline = outlineOf(
    [shoulder, neckTop],
    [build.limbThickness * torso * 0.52, build.limbThickness * torso * 0.44],
  );
  if (neckOutline.isNotEmpty) limbs.add(neckOutline);

  return SilhouetteFigure(
    segments: segments,
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
