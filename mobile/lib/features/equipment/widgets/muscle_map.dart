import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/material.dart';

/// Which muscles a movement loads, and how hard.
enum MuscleLoad { none, secondary, primary }

/// Front/back body chart that lights up the muscles an exercise works —
/// primary in full colour, supporting muscles dimmer.
///
/// Drawn with a CustomPainter rather than shipping an anatomy image: it scales
/// to any size, themes with the app, adds no asset weight, and the region
/// lookup stays testable as plain data.
///
/// Geometry lives in a normalised 0..1 box and bilateral muscles are defined
/// once for the left side and mirrored, which halves the coordinates to get
/// wrong and makes symmetry exact rather than hand-matched.
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
      aspectRatio: 16 / 13,
      child: CustomPaint(
        painter: _MuscleMapPainter(
          primary: primary,
          secondary: secondary,
          bodyColor: scheme.onSurface.withValues(alpha: 0.09),
          outlineColor: scheme.onSurface.withValues(alpha: 0.16),
          primaryColor: scheme.primary,
          secondaryColor: scheme.primary.withValues(alpha: 0.38),
          labelColor: scheme.onSurface.withValues(alpha: 0.55),
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Normalised geometry helpers. All coordinates are 0..1 inside the body box:
// x runs left-to-right across the shoulders, y from the crown to the feet.
// ---------------------------------------------------------------------------

/// Mirrors a path across the vertical midline (x -> 1 - x).
Path _mirrored(Path p) {
  final m = Matrix4.identity()
    ..translate(1.0, 0.0)
    ..scale(-1.0, 1.0, 1.0);
  return p.transform(m.storage);
}

/// Closed smooth blob through [pts], each point joined by a quadratic whose
/// control point is the midpoint offset outward. Good enough for organic
/// muscle shapes without hand-authoring every control point.
Path _blob(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 0; i < pts.length; i++) {
    final cur = pts[i];
    final next = pts[(i + 1) % pts.length];
    final mid = Offset((cur.dx + next.dx) / 2, (cur.dy + next.dy) / 2);
    path.quadraticBezierTo(cur.dx, cur.dy, mid.dx, mid.dy);
  }
  path.close();
  return path;
}

Path _oval(double cx, double cy, double rx, double ry) => Path()
  ..addOval(Rect.fromCenter(
      center: Offset(cx, cy), width: rx * 2, height: ry * 2));

Path _rounded(double l, double t, double r, double b, double radius) => Path()
  ..addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)));

/// The body outline both views share: head, neck, torso tapering to the waist,
/// arms hanging slightly away from the ribs, and legs.
///
/// Returned as ONE unioned path so the outline traces only the exterior. Filling
/// and stroking the parts separately left visible seams where the torso met the
/// legs and where the hands met the arms.
Path _silhouette() {
  final left = <Path>[
    // Upper arm + forearm, angled outward the way a relaxed arm hangs.
    _blob(const [
      Offset(0.262, 0.168),
      Offset(0.222, 0.250),
      Offset(0.192, 0.355),
      Offset(0.182, 0.450),
      Offset(0.232, 0.456),
      Offset(0.252, 0.350),
      Offset(0.296, 0.245),
    ]),
    // Hand.
    _oval(0.206, 0.482, 0.030, 0.040),
    // Leg: full at the hip, narrowing through the knee to the ankle.
    _blob(const [
      Offset(0.316, 0.452),
      Offset(0.306, 0.560),
      Offset(0.336, 0.660),
      Offset(0.352, 0.760),
      Offset(0.366, 0.880),
      Offset(0.446, 0.880),
      Offset(0.452, 0.755),
      Offset(0.468, 0.650),
      Offset(0.486, 0.545),
      Offset(0.490, 0.452),
    ]),
    // Foot, angled forward from the ankle.
    _blob(const [
      Offset(0.362, 0.874),
      Offset(0.352, 0.906),
      Offset(0.360, 0.924),
      Offset(0.446, 0.924),
      Offset(0.452, 0.900),
      Offset(0.450, 0.876),
    ]),
  ];

  final parts = <Path>[
    _oval(0.5, 0.052, 0.072, 0.061), // head
    _rounded(0.455, 0.098, 0.545, 0.150, 0.020), // neck
    // Torso: broad shoulders, a real waist, hips flaring again.
    _blob(const [
      Offset(0.246, 0.152),
      Offset(0.236, 0.232),
      Offset(0.296, 0.330),
      Offset(0.346, 0.400),
      Offset(0.312, 0.462),
      Offset(0.500, 0.492),
      Offset(0.688, 0.462),
      Offset(0.654, 0.400),
      Offset(0.704, 0.330),
      Offset(0.764, 0.232),
      Offset(0.754, 0.152),
      Offset(0.500, 0.126),
    ]),
    ...left,
    ...left.map(_mirrored),
  ];

  return parts.reduce((a, b) => Path.combine(PathOperation.union, a, b));
}

/// Front-view muscle groups. Keys match the catalog's muscle tags.
Map<String, List<Path>> _frontMuscles() {
  Path deltoid() => _blob(const [
        Offset(0.268, 0.156),
        Offset(0.250, 0.198),
        Offset(0.268, 0.240),
        Offset(0.322, 0.232),
        Offset(0.334, 0.180),
      ]);
  Path pec() => _blob(const [
        Offset(0.330, 0.188),
        Offset(0.318, 0.240),
        Offset(0.360, 0.276),
        Offset(0.480, 0.268),
        Offset(0.486, 0.192),
        Offset(0.400, 0.176),
      ]);
  Path bicep() => _blob(const [
        Offset(0.238, 0.245),
        Offset(0.216, 0.290),
        Offset(0.228, 0.330),
        Offset(0.272, 0.322),
        Offset(0.278, 0.258),
      ]);
  Path forearm() => _blob(const [
        Offset(0.208, 0.352),
        Offset(0.186, 0.400),
        Offset(0.184, 0.446),
        Offset(0.222, 0.446),
        Offset(0.234, 0.386),
      ]);
  Path quad() => _blob(const [
        Offset(0.338, 0.492),
        Offset(0.320, 0.566),
        Offset(0.336, 0.648),
        Offset(0.396, 0.674),
        Offset(0.450, 0.634),
        Offset(0.464, 0.548),
        Offset(0.442, 0.486),
      ]);
  Path calf() => _blob(const [
        Offset(0.366, 0.712),
        Offset(0.352, 0.775),
        Offset(0.372, 0.836),
        Offset(0.420, 0.828),
        Offset(0.432, 0.760),
        Offset(0.418, 0.706),
      ]);

  return {
    'shoulders': [deltoid(), _mirrored(deltoid())],
    'chest': [pec(), _mirrored(pec())],
    'biceps': [bicep(), _mirrored(bicep())],
    'forearms': [forearm(), _mirrored(forearm())],
    // Abs as three tapering pairs plus a lower block: reads as a midsection
    // rather than one flat slab, and narrows toward the navel like a real one.
    'core': [
      for (var row = 0; row < 3; row++) ...[
        _rounded(0.416 + row * 0.006, 0.286 + row * 0.048,
            0.497, 0.328 + row * 0.048, 0.016),
        _rounded(0.503, 0.286 + row * 0.048,
            0.584 - row * 0.006, 0.328 + row * 0.048, 0.016),
      ],
      _rounded(0.434, 0.430, 0.566, 0.468, 0.018),
    ],
    'quads': [quad(), _mirrored(quad())],
    'calves': [calf(), _mirrored(calf())],
  };
}

/// Back-view muscle groups.
Map<String, List<Path>> _backMuscles() {
  Path tricep() => _blob(const [
        Offset(0.232, 0.248),
        Offset(0.212, 0.292),
        Offset(0.226, 0.334),
        Offset(0.268, 0.324),
        Offset(0.272, 0.260),
      ]);
  Path lat() => _blob(const [
        Offset(0.330, 0.228),
        Offset(0.316, 0.296),
        Offset(0.368, 0.382),
        Offset(0.470, 0.392),
        Offset(0.484, 0.288),
        Offset(0.436, 0.216),
      ]);
  Path glute() => _blob(const [
        Offset(0.352, 0.424),
        Offset(0.338, 0.466),
        Offset(0.364, 0.504),
        Offset(0.452, 0.498),
        Offset(0.474, 0.452),
        Offset(0.428, 0.418),
      ]);
  Path hamstring() => _blob(const [
        Offset(0.340, 0.540),
        Offset(0.328, 0.604),
        Offset(0.346, 0.664),
        Offset(0.428, 0.658),
        Offset(0.456, 0.596),
        Offset(0.444, 0.536),
      ]);

  return {
    // Traps: the diamond from the neck out to both shoulders.
    'traps': [
      _blob(const [
        Offset(0.500, 0.158),
        Offset(0.352, 0.192),
        Offset(0.412, 0.248),
        Offset(0.500, 0.264),
        Offset(0.588, 0.248),
        Offset(0.648, 0.192),
      ]),
    ],
    'lats': [lat(), _mirrored(lat())],
    'triceps': [tricep(), _mirrored(tricep())],
    // Mid-back / rhomboids, between the shoulder blades.
    'back': [_rounded(0.430, 0.262, 0.570, 0.348, 0.020)],
    // Erectors running down to the pelvis.
    'lower_back': [_rounded(0.444, 0.352, 0.556, 0.462, 0.024)],
    'glutes': [glute(), _mirrored(glute())],
    'hamstrings': [hamstring(), _mirrored(hamstring())],
  };
}

final _silhouetteCache = _silhouette();

/// Clips every muscle shape to the body outline.
///
/// Hand-tuned coordinates drift out of the silhouette the moment the outline
/// changes — narrowing the torso pushed the deltoids, lats and traps outside it,
/// which rendered as shapes sheared off in mid-air. Intersecting makes overflow
/// structurally impossible instead of something to re-check by eye. Done once at
/// startup, not per frame.
Map<String, List<Path>> _clipped(Map<String, List<Path>> muscles) {
  return {
    for (final e in muscles.entries)
      e.key: [
        for (final shape in e.value)
          Path.combine(PathOperation.intersect, shape, _silhouetteCache),
      ],
  };
}

final _frontCache = _clipped(_frontMuscles());
final _backCache = _clipped(_backMuscles());

/// Geometry accessors for tests. The shapes are hand-authored coordinates, so
/// the useful assertion is structural — every group still lands inside the body
/// and none of them clipped away to nothing.
@visibleForTesting
Map<String, List<Path>> debugFrontMuscles() => _frontCache;

@visibleForTesting
Map<String, List<Path>> debugBackMuscles() => _backCache;

@visibleForTesting
Path debugSilhouette() => _silhouetteCache;

class _MuscleMapPainter extends CustomPainter {
  _MuscleMapPainter({
    required this.primary,
    required this.secondary,
    required this.bodyColor,
    required this.outlineColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.labelColor,
    required this.textDirection,
  });

  final List<String> primary;
  final List<String> secondary;
  final Color bodyColor;
  final Color outlineColor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color labelColor;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final halfWidth = size.width / 2;
    _paintHalf(canvas, Offset.zero, Size(halfWidth, size.height), _frontCache,
        'Front');
    _paintHalf(canvas, Offset(halfWidth, 0), Size(halfWidth, size.height),
        _backCache, 'Back');
  }

  void _paintHalf(Canvas canvas, Offset origin, Size half,
      Map<String, List<Path>> muscles, String caption) {
    // Reserve room for the caption, then fit a body-proportioned box (roughly
    // 1 : 2.2) inside what is left so the figure never stretches.
    final captionRoom = half.height * 0.10;
    final available = Size(half.width, half.height - captionRoom);
    var boxHeight = available.height;
    var boxWidth = boxHeight / 2.2;
    if (boxWidth > available.width * 0.92) {
      boxWidth = available.width * 0.92;
      boxHeight = boxWidth * 2.2;
    }
    final box = Rect.fromLTWH(
      origin.dx + (half.width - boxWidth) / 2,
      origin.dy + (available.height - boxHeight) / 2,
      boxWidth,
      boxHeight,
    );

    Path scaled(Path p) => p.transform(
          (Matrix4.identity()
                ..translate(box.left, box.top)
                ..scale(box.width, box.height, 1.0))
              .storage,
        );

    final bodyPaint = Paint()..color = bodyColor;
    final outlinePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = box.width * 0.012
      ..strokeJoin = StrokeJoin.round;

    final body = scaled(_silhouetteCache);
    canvas.drawPath(body, bodyPaint);
    canvas.drawPath(body, outlinePaint);

    for (final entry in muscles.entries) {
      final load = MuscleMap.loadFor(entry.key,
          primary: primary, secondary: secondary);
      if (load == MuscleLoad.none) continue;
      final paint = Paint()
        ..color = load == MuscleLoad.primary ? primaryColor : secondaryColor;
      for (final shape in entry.value) {
        canvas.drawPath(scaled(shape), paint);
      }
    }

    final tp = TextPainter(
      text: TextSpan(
        text: caption,
        style: TextStyle(color: labelColor, fontSize: half.width * 0.085),
      ),
      textDirection: textDirection,
    )..layout();
    tp.paint(
      canvas,
      Offset(box.center.dx - tp.width / 2, box.bottom + captionRoom * 0.15),
    );
  }

  // Compared by CONTENT, not identity: the parent rebuilds these lists on
  // every build, so reference comparison repainted every frame while a genuine
  // change to the same list instance would have been missed.
  @override
  bool shouldRepaint(covariant _MuscleMapPainter old) =>
      !listEquals(old.primary, primary) ||
      !listEquals(old.secondary, secondary) ||
      old.primaryColor != primaryColor ||
      old.secondaryColor != secondaryColor ||
      old.bodyColor != bodyColor;
}
