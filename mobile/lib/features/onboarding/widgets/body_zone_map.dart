import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../profile/data/profile_models.dart';

/// The design box every rectangle below is expressed in. The widget scales to
/// whatever width it is given and keeps this aspect ratio, so the numbers can
/// be read as "roughly a person" rather than as pixels.
const Size kBodyMapDesignSize = Size(100, 220);

/// Where each screenable region sits on the figure, in design-box coordinates.
///
/// Non-overlapping on purpose. A front-facing drawing has no honest place for
/// "upper back" and "chest" at once, and two zones sharing pixels means a tap
/// answers a question the user did not pick — so the back regions take the band
/// of the torso where they read correctly and nothing is stacked.
///
/// Exposed for the test: hit-testing geometry is the one part of a drawing that
/// can be wrong without looking wrong.
const Map<InjuryRegion, List<Rect>> kBodyZoneRects = {
  InjuryRegion.neck: [Rect.fromLTWH(43, 27, 14, 9)],
  InjuryRegion.shoulder: [
    Rect.fromLTWH(19, 37, 18, 14),
    Rect.fromLTWH(63, 37, 18, 14),
  ],
  InjuryRegion.upperBack: [Rect.fromLTWH(39, 37, 22, 20)],
  InjuryRegion.elbow: [
    Rect.fromLTWH(13, 75, 17, 13),
    Rect.fromLTWH(70, 75, 17, 13),
  ],
  InjuryRegion.wrist: [
    Rect.fromLTWH(11, 103, 17, 12),
    Rect.fromLTWH(72, 103, 17, 12),
  ],
  InjuryRegion.lowerBack: [Rect.fromLTWH(38, 59, 24, 23)],
  InjuryRegion.hip: [Rect.fromLTWH(34, 85, 32, 18)],
  InjuryRegion.knee: [
    Rect.fromLTWH(34, 139, 15, 15),
    Rect.fromLTWH(51, 139, 15, 15),
  ],
  InjuryRegion.ankle: [
    Rect.fromLTWH(34, 185, 15, 13),
    Rect.fromLTWH(51, 185, 15, 13),
  ],
};

/// The region a tap at [point] lands on, or null for a miss.
///
/// [size] is the rendered size; the point is scaled back into the design box
/// before testing, so the answer does not depend on how big the widget is.
/// Pure, and separate from the widget, because "does tapping the knee select
/// the knee" is the only question about this drawing worth asserting.
InjuryRegion? bodyZoneAt(Offset point, Size size) {
  if (size.width <= 0 || size.height <= 0) return null;
  final p = Offset(
    point.dx * kBodyMapDesignSize.width / size.width,
    point.dy * kBodyMapDesignSize.height / size.height,
  );
  for (final entry in kBodyZoneRects.entries) {
    for (final rect in entry.value) {
      if (rect.contains(p)) return entry.key;
    }
  }
  return null;
}

/// A schematic figure whose regions can be tapped to mark a limitation.
///
/// It is a **shortcut, not the only control**. The chip grid beside it offers
/// every one of the same regions by name — which is what a screen reader, a
/// switch user, and anyone whose fingers are bigger than a 15pt square actually
/// use. Making the drawing the sole way to answer would have made a safety
/// question unanswerable for exactly the people most likely to have one.
class BodyZoneMap extends StatelessWidget {
  const BodyZoneMap({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<InjuryRegion> selected;
  final ValueChanged<InjuryRegion> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: kBodyMapDesignSize.width / kBodyMapDesignSize.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final zone = bodyZoneAt(details.localPosition, size);
              if (zone != null) onToggle(zone);
            },
            child: CustomPaint(
              painter: _BodyPainter(
                selected: selected,
                silhouette: theme.colors.surfaceInteractive,
                outline: theme.colors.outline,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  const _BodyPainter({
    required this.selected,
    required this.silhouette,
    required this.outline,
  });

  final Set<InjuryRegion> selected;
  final Color silhouette;
  final Color outline;

  /// The body itself: head, torso, arms, legs. Purely decorative — nothing here
  /// is tappable, so it is drawn first and the zones sit on top of it.
  void _paintFigure(Canvas canvas, double sx, double sy) {
    final paint = Paint()..color = silhouette;
    Rect scaled(double l, double t, double w, double h) =>
        Rect.fromLTWH(l * sx, t * sy, w * sx, h * sy);
    RRect rounded(Rect r) =>
        RRect.fromRectAndRadius(r, Radius.circular(6 * sx));

    canvas.drawCircle(Offset(50 * sx, 16 * sy), 12 * sx, paint);
    canvas.drawRRect(rounded(scaled(34, 34, 32, 72)), paint);
    canvas.drawRRect(rounded(scaled(16, 40, 16, 76)), paint);
    canvas.drawRRect(rounded(scaled(68, 40, 16, 76)), paint);
    canvas.drawRRect(rounded(scaled(34, 104, 14, 96)), paint);
    canvas.drawRRect(rounded(scaled(52, 104, 14, 96)), paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / kBodyMapDesignSize.width;
    final sy = size.height / kBodyMapDesignSize.height;
    _paintFigure(canvas, sx, sy);

    for (final entry in kBodyZoneRects.entries) {
      final isOn = selected.contains(entry.key);
      final fill = Paint()
        ..color = isOn
            ? AppPalette.auroraLime.withValues(alpha: 0.85)
            : Colors.transparent;
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isOn ? 2 : 1
        ..color = isOn ? AppPalette.auroraLimeDeep : outline;
      for (final r in entry.value) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left * sx, r.top * sy, r.width * sx, r.height * sy),
          Radius.circular(5 * sx),
        );
        if (isOn) canvas.drawRRect(rect, fill);
        canvas.drawRRect(rect, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.selected.length != selected.length ||
      !old.selected.containsAll(selected) ||
      old.silhouette != silhouette ||
      old.outline != outline;
}
