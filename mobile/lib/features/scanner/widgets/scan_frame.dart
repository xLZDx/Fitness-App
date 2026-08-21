import 'package:flutter/material.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/hud_tokens.dart' show HudMotionX;

/// What the frame is currently saying.
enum ScanFramePhase {
  /// Aim at something. A sweep line travels the frame.
  ready,

  /// A capture is being classified. The corners turn accent and a ring
  /// pulses outward.
  analyzing,
}

/// The design's aiming frame: four corner brackets, a sweep line, and a pulse
/// while a capture is classified (`App.tsx:2592-2614`).
///
/// ## Why this replaced a rectangle
///
/// The viewfinder drew a plain rounded outline at 75% of the preview. It
/// marked the right area and said nothing else: nothing distinguished "aim"
/// from "working", so a two-second classification looked like a frozen screen.
/// The prototype's frame carries both states, which is the whole reason it has
/// corners instead of a border.
///
/// ## The 75% is load-bearing, not styling
///
/// The classifier receives a centre crop of exactly that fraction
/// (`core/camera/centre_crop.dart`). The frame is sized as a fraction rather
/// than at the design's fixed 260px so it keeps meaning what it means on every
/// screen size: inside the brackets IS what gets classified. A fixed box would
/// be honest only on the one phone it was measured against.
///
/// Decoration only — the caller wraps it in [IgnorePointer]; a tap must land
/// on the preview underneath, never on this.
class ScanFrame extends StatefulWidget {
  const ScanFrame({
    super.key,
    required this.phase,
    this.fraction = 0.75,
  });

  final ScanFramePhase phase;

  /// Side of the frame as a fraction of the preview. Defaults to the crop the
  /// classifier actually receives.
  final double fraction;

  @override
  State<ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<ScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    // Not started here: `MediaQuery` (read by [_syncMotion]) is not safely
    // readable in `initState` -- `didChangeDependencies` runs immediately
    // after and is where this loop actually starts.
  }

  /// The sweep line and analyzing pulse are purely decorative, continuous,
  /// looping motion over a live camera preview -- exactly the kind of thing
  /// reduce motion exists to suppress. Whether the loop should be running is
  /// re-decided here rather than once: `didChangeDependencies` also fires if
  /// the OS accessibility setting flips while this screen is open.
  void _syncMotion() {
    if (context.reduceMotion) {
      if (_c.isAnimating) _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final analyzing = widget.phase == ScanFramePhase.analyzing;
    // White at 0.8 while aiming, per the design. It sits on a live camera
    // frame, whose colour nothing controls, which is the same reason the pose
    // colours carry no contrast guarantee -- and why the shape, not the hue,
    // is what communicates here.
    final bracket = analyzing ? colors.accentPrimary : Colors.white70;

    return Center(
      child: FractionallySizedBox(
        widthFactor: widget.fraction,
        heightFactor: widget.fraction,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return CustomPaint(
              painter: _ScanFramePainter(
                bracket: bracket,
                accent: colors.accentPrimary,
                t: _c.value,
                analyzing: analyzing,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({
    required this.bracket,
    required this.accent,
    required this.t,
    required this.analyzing,
  });

  final Color bracket;
  final Color accent;

  /// 0..1, looping.
  final double t;
  final bool analyzing;

  /// How far along each edge a corner bracket runs.
  static const _armFraction = 0.18;
  static const _stroke = 3.0;
  static const _radius = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final arm = size.shortestSide * _armFraction;
    final p = Paint()
      ..color = bracket
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void corner(Offset origin, double dx, double dy) {
      final path = Path()
        ..moveTo(origin.dx + dx * arm, origin.dy)
        ..lineTo(origin.dx + dx * _radius, origin.dy)
        ..quadraticBezierTo(origin.dx, origin.dy, origin.dx, origin.dy + dy * _radius)
        ..lineTo(origin.dx, origin.dy + dy * arm);
      canvas.drawPath(path, p);
    }

    corner(Offset.zero, 1, 1);
    corner(Offset(size.width, 0), -1, 1);
    corner(Offset(0, size.height), 1, -1);
    corner(Offset(size.width, size.height), -1, -1);

    if (analyzing) {
      // A ring expanding out of the frame, fading as it goes: the design's
      // `animate-pulse-ring`. It reads as "working" without a spinner, which
      // would compete with the classifier's own progress indicator.
      final grow = 28.0 * t;
      final ring = Paint()
        ..color = accent.withValues(alpha: (1 - t) * 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-grow, -grow, size.width + grow * 2,
              size.height + grow * 2),
          const Radius.circular(10),
        ),
        ring,
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = accent.withValues(alpha: 0.06),
      );
      return;
    }

    // Sweep line. Travels down and back so the eye is led across the whole
    // crop rather than snapping back to the top every cycle.
    final travel = t < 0.5 ? t * 2 : (1 - t) * 2;
    final y = size.height * travel;
    canvas.drawRect(
      Rect.fromLTWH(0, y - 1, size.width, 2),
      Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.9),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2)),
    );
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) =>
      old.t != t ||
      old.analyzing != analyzing ||
      old.bracket != bracket ||
      old.accent != accent;
}
