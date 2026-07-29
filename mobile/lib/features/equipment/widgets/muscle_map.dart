import 'package:flutter/material.dart';

/// Which muscles a movement loads, and how hard.
enum MuscleLoad { none, secondary, primary }

/// Stylised front/back body chart that lights up the muscles an exercise
/// works — primary in full colour, supporting muscles dimmer.
///
/// Drawn with a CustomPainter rather than shipping an anatomy image: it
/// scales to any size, themes with the app, adds no asset weight, and the
/// region lookup stays testable as plain data.
class MuscleMap extends StatelessWidget {
  const MuscleMap({
    super.key,
    required this.primary,
    this.secondary = const [],
  });

  /// Muscle keys as used in the catalog (`quads`, `lats`, `core`, ...).
  final List<String> primary;
  final List<String> secondary;

  /// Resolves how hard a region is worked. Pure and exported for tests.
  static MuscleLoad loadFor(
    String region, {
    required List<String> primary,
    required List<String> secondary,
  }) {
    if (primary.contains(region)) return MuscleLoad.primary;
    if (secondary.contains(region)) return MuscleLoad.secondary;
    return MuscleLoad.none;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 16 / 11,
      child: CustomPaint(
        painter: _MuscleMapPainter(
          primary: primary,
          secondary: secondary,
          bodyColor: scheme.onSurface.withValues(alpha: 0.10),
          primaryColor: scheme.primary,
          secondaryColor: scheme.primary.withValues(alpha: 0.42),
          labelColor: scheme.onSurface.withValues(alpha: 0.55),
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

/// One muscle region: normalised rect (0..1 of the half-body box) + label.
class _Region {
  const _Region(this.key, this.rect);
  final String key;
  final Rect rect;
}

// Front view regions, normalised inside the left half of the canvas.
const _front = <_Region>[
  _Region('shoulders', Rect.fromLTWH(0.16, 0.16, 0.68, 0.09)),
  _Region('chest', Rect.fromLTWH(0.26, 0.24, 0.48, 0.13)),
  _Region('biceps', Rect.fromLTWH(0.08, 0.26, 0.13, 0.16)),
  _Region('forearms', Rect.fromLTWH(0.04, 0.42, 0.11, 0.15)),
  _Region('core', Rect.fromLTWH(0.32, 0.37, 0.36, 0.18)),
  _Region('quads', Rect.fromLTWH(0.28, 0.57, 0.44, 0.22)),
  _Region('calves', Rect.fromLTWH(0.31, 0.80, 0.38, 0.15)),
];

// Back view regions.
const _back = <_Region>[
  _Region('traps', Rect.fromLTWH(0.28, 0.15, 0.44, 0.10)),
  _Region('lats', Rect.fromLTWH(0.22, 0.25, 0.56, 0.16)),
  _Region('triceps', Rect.fromLTWH(0.08, 0.26, 0.13, 0.16)),
  _Region('back', Rect.fromLTWH(0.28, 0.34, 0.44, 0.09)),
  _Region('lower_back', Rect.fromLTWH(0.32, 0.43, 0.36, 0.09)),
  _Region('glutes', Rect.fromLTWH(0.28, 0.53, 0.44, 0.12)),
  _Region('hamstrings', Rect.fromLTWH(0.29, 0.65, 0.42, 0.16)),
];

class _MuscleMapPainter extends CustomPainter {
  _MuscleMapPainter({
    required this.primary,
    required this.secondary,
    required this.bodyColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.labelColor,
    required this.textDirection,
  });

  final List<String> primary;
  final List<String> secondary;
  final Color bodyColor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color labelColor;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final halfWidth = size.width / 2;
    _paintHalf(canvas, Offset.zero, Size(halfWidth, size.height), _front,
        'Front');
    _paintHalf(canvas, Offset(halfWidth, 0), Size(halfWidth, size.height),
        _back, 'Back');
  }

  void _paintHalf(Canvas canvas, Offset origin, Size half,
      List<_Region> regions, String caption) {
    final inset = half.width * 0.12;
    final box = Rect.fromLTWH(
      origin.dx + inset,
      origin.dy + half.height * 0.06,
      half.width - inset * 2,
      half.height * 0.82,
    );

    // Torso + limbs silhouette, deliberately simple: the point is which
    // regions light up, not anatomical illustration.
    final body = Paint()..color = bodyColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(box.left + box.width * 0.18, box.top + box.height * 0.10,
            box.width * 0.64, box.height * 0.85),
        Radius.circular(box.width * 0.16),
      ),
      body,
    );
    canvas.drawCircle(
      Offset(box.center.dx, box.top + box.height * 0.05),
      box.width * 0.10,
      body,
    );

    for (final r in regions) {
      final load = MuscleMap.loadFor(r.key,
          primary: primary, secondary: secondary);
      if (load == MuscleLoad.none) continue;
      final paint = Paint()
        ..color = load == MuscleLoad.primary ? primaryColor : secondaryColor;
      final rect = Rect.fromLTWH(
        box.left + r.rect.left * box.width,
        box.top + r.rect.top * box.height,
        r.rect.width * box.width,
        r.rect.height * box.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height * 0.35)),
        paint,
      );
    }

    final tp = TextPainter(
      text: TextSpan(
        text: caption,
        style: TextStyle(color: labelColor, fontSize: half.width * 0.09),
      ),
      textDirection: textDirection,
    )..layout();
    tp.paint(canvas,
        Offset(box.center.dx - tp.width / 2, box.bottom + half.height * 0.02));
  }

  @override
  bool shouldRepaint(covariant _MuscleMapPainter old) =>
      old.primary != primary ||
      old.secondary != secondary ||
      old.primaryColor != primaryColor;
}
