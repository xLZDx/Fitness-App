/// Skeleton overlay of the guided scan (design s11, D-80): the major joints and
/// bones of the latest [PoseFrame] drawn over the preview.
///
/// Readiness is never conveyed by colour alone: a ready body is drawn with
/// solid bones and filled joints, a not-ready body with dashed bones and
/// hollow joints. The overlay is decorative for assistive technology
/// (`ExcludeSemantics`); the non-visual alternative is the four-row status
/// panel, the live-region hint and the haptic patterns.
///
/// Coordinates: `PoseFrame` is isotropic (x in 0..aspectRatio, y in 0..1). The
/// preview fills the screen, so a landmark maps to
/// `(x / aspectRatio * width, y * height)`.
library;

import 'package:flutter/material.dart';

import '../../form_check/data/pose_landmark.dart';

/// Bones to draw, as pairs of landmark types.
const List<(LandmarkType, LandmarkType)> kSkeletonBones = [
  (LandmarkType.leftShoulder, LandmarkType.rightShoulder),
  (LandmarkType.leftShoulder, LandmarkType.leftElbow),
  (LandmarkType.leftElbow, LandmarkType.leftWrist),
  (LandmarkType.rightShoulder, LandmarkType.rightElbow),
  (LandmarkType.rightElbow, LandmarkType.rightWrist),
  (LandmarkType.leftShoulder, LandmarkType.leftHip),
  (LandmarkType.rightShoulder, LandmarkType.rightHip),
  (LandmarkType.leftHip, LandmarkType.rightHip),
  (LandmarkType.leftHip, LandmarkType.leftKnee),
  (LandmarkType.leftKnee, LandmarkType.leftAnkle),
  (LandmarkType.rightHip, LandmarkType.rightKnee),
  (LandmarkType.rightKnee, LandmarkType.rightAnkle),
];

/// Landmarks below this likelihood are not drawn.
const double kSkeletonMinLikelihood = 0.3;

class SkeletonOverlay extends StatelessWidget {
  const SkeletonOverlay({
    super.key,
    required this.frame,
    required this.ready,
    this.readyColor = Colors.greenAccent,
    this.notReadyColor = Colors.orangeAccent,
  });

  final PoseFrame? frame;
  final bool ready;
  final Color readyColor;
  final Color notReadyColor;

  @override
  Widget build(BuildContext context) {
    final f = frame;
    if (f == null) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: IgnorePointer(
        child: CustomPaint(
          key: const Key('scan.skeleton'),
          size: Size.infinite,
          painter: SkeletonPainter(
            frame: f,
            ready: ready,
            color: ready ? readyColor : notReadyColor,
          ),
        ),
      ),
    );
  }
}

class SkeletonPainter extends CustomPainter {
  SkeletonPainter({
    required this.frame,
    required this.ready,
    required this.color,
  });

  final PoseFrame frame;
  final bool ready;
  final Color color;

  Offset? _point(LandmarkType t, Size size) {
    final l = frame.landmarks[t];
    if (l == null || l.likelihood < kSkeletonMinLikelihood) return null;
    final a = frame.aspectRatio <= 0 ? 1.0 : frame.aspectRatio;
    return Offset(l.x / a * size.width, l.y * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bone = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final (a, b) in kSkeletonBones) {
      final p = _point(a, size);
      final q = _point(b, size);
      if (p == null || q == null) continue;
      if (ready) {
        canvas.drawLine(p, q, bone);
      } else {
        _dashed(canvas, p, q, bone);
      }
    }
    final joint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = ready ? PaintingStyle.fill : PaintingStyle.stroke;
    for (final t in LandmarkType.values) {
      final p = _point(t, size);
      if (p != null) canvas.drawCircle(p, 5, joint);
    }
  }

  void _dashed(Canvas canvas, Offset p, Offset q, Paint paint) {
    const dash = 8.0;
    const gap = 6.0;
    final total = (q - p).distance;
    if (total == 0) return;
    final dir = (q - p) / total;
    var d = 0.0;
    while (d < total) {
      final end = d + dash > total ? total : d + dash;
      canvas.drawLine(p + dir * d, p + dir * end, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(SkeletonPainter old) =>
      old.frame != frame || old.ready != ready || old.color != color;
}
