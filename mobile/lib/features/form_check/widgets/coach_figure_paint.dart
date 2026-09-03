/// The one way a coach figure is drawn.
///
/// G17. Three painters put a body or a skeleton on the coach panel — the
/// avatar (`_PoseAvatarPainter`, the user's own tracked body), the animated
/// demonstration for movements that have no reference clip
/// (`DemoFigurePainter`), and the camera-mode skeleton (`_SkeletonPainter`).
/// Until this file they were three implementations of what the design
/// reference specifies once (`core/design/reference/fitness_hud_v1/README.md`
/// §8: white bones 3–3.4 px, round caps, a green or red drop-shadow glow behind
/// them, white joint dots, a pulsing dashed ring on the joint a fault is
/// about), and the camera skeleton had drifted to violet 3 px lines with no
/// glow at all. The operator's 2026-09-04 instruction is that the figure looks
/// the same everywhere: the demonstration and the live figure are ONE visual
/// language. That is only true by construction if there is one implementation.
///
/// Every function takes a `place` that maps figure space to canvas pixels and
/// a `scale` (canvas pixels per figure unit), so the same code draws a body
/// projected through the camera (`projectLandmark`) and a body fitted to the
/// panel (`fitSilhouette`). Nothing here reads a provider or a theme: the
/// colours come in as arguments, which is what lets the goldens pin the avatar
/// pixel-for-pixel across the extraction — the drawing order and every
/// constant below are the avatar's, unchanged.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/pose_landmark.dart';
import '../data/pose_silhouette.dart';

/// The avatar's own body fill: near-black, faintly translucent, so a dark
/// figure reads as a shadow of a person over a dusk scene rather than a hole
/// cut in it.
const Color kCoachBodyFill = Color(0xE60A0912);

/// One filled body from a [SilhouetteFigure]: trunk, limbs, articulation
/// discs and head unioned into a single path so no internal seam is stroked.
///
/// The B4 lesson, kept: parts added as separate subpaths stroke every seam,
/// which is what made the old target outline read as a lattice of
/// quadrilaterals on a real phone. `Path.combine` resolves the overlaps into
/// one outline. The discs go in as ONE operand — `merge` folds its operand
/// into a body that grows with every call, so N boolean ops in a row cost
/// more than N times the first, and the avatar runs at the camera's frame
/// rate.
Path buildFigureBody(
  SilhouetteFigure figure,
  Offset Function(Offset) place,
  double scale,
) {
  var body = Path();
  void merge(Path part) {
    body = Path.combine(PathOperation.union, body, part);
  }

  if (figure.torso.isNotEmpty) {
    merge(Path()..addPolygon([for (final p in figure.torso) place(p)], true));
  }
  for (final limb in figure.limbs) {
    if (limb.length < 3) continue;
    merge(Path()..addPolygon([for (final p in limb) place(p)], true));
  }
  final discs = Path();
  var hasDiscs = false;
  for (final (centre, radius) in figure.blobs) {
    final at = place(centre);
    final r = radius * scale;
    // Defensive, and deliberately not asserted anywhere: every radius is a
    // product of positive constants and a torso length that `buildSilhouette`
    // has already refused to be zero, so nothing shipped reaches this. It
    // stays because a NaN in a path is a crash rather than a wrong picture,
    // and the limb loop above guards its own degenerate input the same way.
    if (!r.isFinite || r <= 0 || !at.dx.isFinite || !at.dy.isFinite) continue;
    discs.addOval(Rect.fromCircle(center: at, radius: r));
    hasDiscs = true;
  }
  if (hasDiscs) merge(discs);
  final head = figure.head;
  if (head != null) {
    merge(Path()
      ..addOval(
        Rect.fromCircle(center: place(head.$1), radius: head.$2 * scale),
      ));
  }
  return body;
}

/// Fills [body] dark and rims it faintly white — the avatar's look.
///
/// [limbWidth] is the figure's limb thickness in canvas pixels; the rim is
/// derived from it so a figure drawn small keeps a proportionate edge.
void paintFigureBody(Canvas canvas, Path body, {required double limbWidth}) {
  canvas.drawPath(body, Paint()..color = kCoachBodyFill);
  canvas.drawPath(
    body,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (limbWidth * 0.14).clamp(1.5, 4.0)
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.45),
  );
}

/// The bones of a figure as two paths: the ones the current fault is ABOUT
/// (both ends in [faultJoints]) and all of them.
///
/// `all` always holds every bone, because the white skeleton on top is drawn
/// in one pass regardless of any verdict — the reference keeps it white in
/// every state and carries colour on a layer behind it. A bone lights in the
/// fault colour only when BOTH of its ends are named: the thigh shares a hip
/// with the trunk and a knee with the shin, so an either-end rule would spread
/// a knee fault up the body and down the leg until most of the figure was red.
({Path all, Path fault, bool hasFault}) buildBonePaths(
  SilhouetteFigure figure,
  Offset Function(Offset) place, {
  Set<LandmarkType> faultJoints = const {},
}) {
  final bones = Path();
  final faultBones = Path();
  var hasFaultBones = false;
  final named = figure.segmentBones.length == figure.segments.length;
  for (var i = 0; i < figure.segments.length; i++) {
    final (a, b) = figure.segments[i];
    final pa = place(a);
    final pb = place(b);
    bones
      ..moveTo(pa.dx, pa.dy)
      ..lineTo(pb.dx, pb.dy);
    if (!named || faultJoints.isEmpty) continue;
    final (ja, jb) = figure.segmentBones[i];
    if (ja != null &&
        jb != null &&
        faultJoints.contains(ja) &&
        faultJoints.contains(jb)) {
      faultBones
        ..moveTo(pa.dx, pa.dy)
        ..lineTo(pb.dx, pb.dy);
      hasFaultBones = true;
    }
  }
  return (all: bones, fault: faultBones, hasFault: hasFaultBones);
}

/// The same two paths from raw landmarks rather than a built figure — the
/// camera-mode skeleton, which draws what the detector saw and nothing more.
///
/// A bone is drawn only when both ends exist. Reaching for a missing joint's
/// coordinate would put it at the origin, and a limb running to the top-left
/// corner looks like a detector that has lost its mind rather than one that
/// simply cannot see an ankle.
({Path all, Path fault, bool hasFault}) buildLandmarkBonePaths(
  Map<LandmarkType, PoseLandmark> landmarks,
  List<(LandmarkType, LandmarkType)> bones,
  Offset Function(PoseLandmark) place, {
  Set<LandmarkType> faultJoints = const {},
}) {
  final all = Path();
  final fault = Path();
  var hasFault = false;
  for (final (a, b) in bones) {
    final la = landmarks[a];
    final lb = landmarks[b];
    if (la == null || lb == null) continue;
    final pa = place(la);
    final pb = place(lb);
    all
      ..moveTo(pa.dx, pa.dy)
      ..lineTo(pb.dx, pb.dy);
    if (faultJoints.contains(a) && faultJoints.contains(b)) {
      fault
        ..moveTo(pa.dx, pa.dy)
        ..lineTo(pb.dx, pb.dy);
      hasFault = true;
    }
  }
  return (all: all, fault: fault, hasFault: hasFault);
}

/// The reference skeleton: an optional verdict glow BEHIND the bones, then a
/// soft white halo, then the white core.
///
/// The verdict is a GLOW behind the bone, not a recolour of it — the reference
/// keeps the skeleton itself white in every state (`README.md` §8: "кости 3–3.4
/// px, цвет #FFFFFF"). Two blurred passes approximate its stacked
/// `drop-shadow(0 0 5px)` + `drop-shadow(0 0 14px)`. When [glowColor] is null
/// there is no verdict and the skeleton is plain white — deliberate for the
/// camera-angle-confounded movements that must not be shown as right or
/// wrong, and for a demonstration, which has no verdict to give.
///
/// G6 narrowed WHERE the glow lands: when [bones]`.hasFault`, only the fault
/// bones glow and the rest of the body stays unlit — unlit rather than green,
/// because "the part I am not talking about" is not the same claim as "the
/// part I have approved". A fault that names nothing still lights everything,
/// deliberately: losing the verdict entirely because the region could not be
/// resolved would be a silent downgrade.
void paintSkeleton(
  Canvas canvas,
  ({Path all, Path fault, bool hasFault}) bones, {
  required double boneWidth,
  Color? glowColor,
}) {
  if (glowColor != null) {
    final target = bones.hasFault ? bones.fault : bones.all;
    canvas.drawPath(
      target,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = boneWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, boneWidth * 2.3)
        ..color = glowColor.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      target,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = boneWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, boneWidth * 0.9)
        ..color = glowColor.withValues(alpha: 0.85),
    );
  }

  canvas.drawPath(
    bones.all,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = boneWidth * 2.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, boneWidth * 1.4)
      ..color = Colors.white.withValues(alpha: 0.45),
  );
  canvas.drawPath(
    bones.all,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = boneWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.95),
  );
}

/// Joints last, so an articulation reads as a bright point rather than as a
/// thickening of the bone that runs through it.
void paintJointDots(
  Canvas canvas,
  Iterable<Offset> joints, {
  required double radius,
}) {
  final core = Paint()..color = Colors.white;
  for (final j in joints) {
    canvas.drawCircle(j, radius, core);
  }
}

/// The reference's marker for the offending joint: «пунктирный круг r=26,
/// `4 6`, пульсация 1.1 s» (`README.md` §8).
///
/// [phase] is where in the 1.1 s cycle the ring is, 0..1. Callers derive it
/// from the FRAME's own timestamp rather than from a ticker: the painters
/// already repaint on every frame, and a clock of their own would keep
/// animating a ring over a body the detector had stopped seeing — this one
/// stops exactly when the picture does.
void paintFaultRing(
  Canvas canvas,
  Offset centre, {
  required double boneWidth,
  required Color color,
  required double phase,
}) {
  // A single smooth swell rather than a sawtooth: the ring grows and settles
  // once per cycle instead of snapping back at the seam.
  final swell = 0.5 - 0.5 * math.cos(phase * 2 * math.pi);
  final radius = boneWidth * (3.4 + 0.9 * swell);
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = (boneWidth * 0.34).clamp(1.2, 3.0)
    ..strokeCap = StrokeCap.round
    ..color = color.withValues(alpha: 0.55 + 0.35 * swell);
  // The reference's `4 6` dash: four parts drawn to every six skipped, which
  // over a full turn is ten arcs of 0.4 of their slot. Drawn as arcs because
  // Flutter has no dashed stroke, and the arithmetic is the dash pattern
  // rather than a look-alike chosen by eye.
  const dashes = 10;
  const drawn = 4 / (4 + 6);
  const slot = 2 * math.pi / dashes;
  final box = Rect.fromCircle(center: centre, radius: radius);
  for (var d = 0; d < dashes; d++) {
    canvas.drawArc(box, d * slot + phase * slot, slot * drawn, false, ring);
  }
}

/// Where in the ring's 1.1 s cycle a frame at [timestampMs] falls.
double faultRingPhase(int timestampMs) {
  const cycleMs = 1100;
  return (timestampMs % cycleMs) / cycleMs;
}
