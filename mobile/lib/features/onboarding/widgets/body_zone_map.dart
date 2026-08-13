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

/// Where each trainable zone sits on the same figure, in the same design box.
///
/// A second map rather than a reuse of [kBodyZoneRects]: the two questions do
/// not share a vocabulary. Limitations are joints — a knee, a wrist, an ankle,
/// each a small square where the joint is. Priorities are muscle groups — a
/// chest, a set of glutes — which are broad areas and sit in different places.
/// Mapping one onto the other would have put "back" on the neck's square and
/// left legs unreachable.
///
/// [FocusZone.fullBody] is deliberately ABSENT. "Everything" is not a place on
/// a drawing, and giving it one would mean either a rectangle that overlaps
/// every other zone (so a tap answers a question the user did not pick — the
/// exact fault the doc on [kBodyZoneRects] warns about) or an arbitrary patch
/// that means nothing. It stays a chip, where it reads correctly.
const Map<FocusZone, List<Rect>> kFocusZoneRects = {
  FocusZone.shoulders: [
    Rect.fromLTWH(17, 36, 18, 13),
    Rect.fromLTWH(65, 36, 18, 13),
  ],
  FocusZone.chest: [Rect.fromLTWH(36, 40, 28, 18)],
  FocusZone.arms: [
    Rect.fromLTWH(13, 62, 18, 44),
    Rect.fromLTWH(69, 62, 18, 44),
  ],
  FocusZone.back: [Rect.fromLTWH(36, 59, 28, 14)],
  FocusZone.core: [Rect.fromLTWH(36, 74, 28, 22)],
  FocusZone.glutes: [Rect.fromLTWH(34, 98, 32, 16)],
  FocusZone.legs: [
    Rect.fromLTWH(33, 116, 16, 80),
    Rect.fromLTWH(51, 116, 16, 80),
  ],
};

/// The zone a tap at [point] lands on, or null for a miss.
///
/// [size] is the rendered size; the point is scaled back into the design box
/// before testing, so the answer does not depend on how big the widget is.
/// Pure, and separate from the widget, because "does tapping the knee select
/// the knee" is the only question about this drawing worth asserting.
///
/// Generic over the zone vocabulary so the limitations map and the priorities
/// map get the same hit-testing, and a fix to it cannot land on one figure and
/// miss the other.
T? zoneAt<T>(Offset point, Size size, Map<T, List<Rect>> rects) {
  if (size.width <= 0 || size.height <= 0) return null;
  final p = Offset(
    point.dx * kBodyMapDesignSize.width / size.width,
    point.dy * kBodyMapDesignSize.height / size.height,
  );
  for (final entry in rects.entries) {
    for (final rect in entry.value) {
      if (rect.contains(p)) return entry.key;
    }
  }
  return null;
}

/// [zoneAt] against the limitations map. Kept as its own name because it is
/// what the existing callers and their tests say.
InjuryRegion? bodyZoneAt(Offset point, Size size) =>
    zoneAt(point, size, kBodyZoneRects);

/// A schematic figure whose regions can be tapped to mark a limitation.
///
/// It is a **shortcut, not the only control**. The chip grid beside it offers
/// every one of the same regions by name — which is what a screen reader, a
/// switch user, and anyone whose fingers are bigger than a 15pt square actually
/// use. Making the drawing the sole way to answer would have made a safety
/// question unanswerable for exactly the people most likely to have one.
class BodyZoneMap<T> extends StatelessWidget {
  /// The limitations figure — joints, written into [Injury.region].
  static BodyZoneMap<InjuryRegion> limitations({
    Key? key,
    required Set<InjuryRegion> selected,
    required ValueChanged<InjuryRegion> onToggle,
  }) =>
      BodyZoneMap<InjuryRegion>._(
        key: key,
        selected: selected,
        onToggle: onToggle,
        rects: kBodyZoneRects,
      );

  /// The priorities figure. Same drawing, different zones — see
  /// [kFocusZoneRects] for why they are not the same map.
  static BodyZoneMap<FocusZone> priorities({
    Key? key,
    required Set<FocusZone> selected,
    required ValueChanged<FocusZone> onToggle,
  }) =>
      BodyZoneMap<FocusZone>._(
        key: key,
        selected: selected,
        onToggle: onToggle,
        rects: kFocusZoneRects,
      );

  const BodyZoneMap._({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.rects,
  });

  final Set<T> selected;
  final ValueChanged<T> onToggle;
  final Map<T, List<Rect>> rects;

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
              final zone = zoneAt(details.localPosition, size, rects);
              if (zone != null) onToggle(zone);
            },
            child: CustomPaint(
              painter: _BodyPainter<T>(
                selected: selected,
                rects: rects,
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

class _BodyPainter<T> extends CustomPainter {
  const _BodyPainter({
    required this.selected,
    required this.rects,
    required this.silhouette,
    required this.outline,
  });

  final Set<T> selected;
  final Map<T, List<Rect>> rects;
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

    for (final entry in rects.entries) {
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
  bool shouldRepaint(_BodyPainter<T> old) =>
      old.selected.length != selected.length ||
      !old.selected.containsAll(selected) ||
      // Switching tabs swaps the whole zone vocabulary under the same painter
      // type. Without this the priorities figure could keep the limitations
      // rectangles until something else forced a repaint.
      !identical(old.rects, rects) ||
      old.silhouette != silhouette ||
      old.outline != outline;
}
