import 'package:flutter/material.dart';

import '../../../core/theme/hud_tokens.dart' show HudMotionX;

/// What the frame is currently saying.
enum ScanFramePhase {
  /// Aim at something. A sweep line travels the frame.
  ready,

  /// A capture is being classified. The corners turn accent and a ring
  /// pulses outward.
  analyzing,
}

/// The reference's aiming frame, at the reference's geometry.
///
/// SCAN-G1 (core/SCAN_G1_SCOPE.md, R6). Everything here is a number read
/// from `core/design/reference/fitness_hud_v1/Fitness Glass Phone v1 -
/// Sunset.dc.html:187-191` (identical geometry in `Light.dc.html`):
///
///  * four corner brackets, `width:34px;height:34px` with a `2px solid`
///    border on two sides -- content-box, so the rendered box is **36x36**
///    (`scan_anchors.json` `bracket_*`), `20px` in from every edge of the
///    card, top-left radius `15px`, the other three `10px` (lines 187-190)
///    -- drawn as the CSS draws a bordered box's corner: the 2px stroke hugs
///    the outer edge, so its centre line runs 1px inside;
///  * a `2px` sweep line `20px` in from the sides, starting `18px` from the
///    top, `linear-gradient(90deg, transparent, rgba(255,255,255,.95),
///    transparent)`, animated `glassScan 3.4s ease-in-out infinite`
///    (line 191), whose keyframes (line 18) are `0% translateY(0) opacity 0;
///    12% opacity 1; 88% opacity 1; 100% translateY(196px) opacity 0`.
///
/// The previous frame was a 75%-of-preview box with proportional arms
/// (`_armFraction = 0.18`, radius 6): honest about the crop it stood for,
/// and nothing like the reference. The crop now follows the frame instead
/// (`core/camera/centre_crop.dart`, `viewfinderSourceRect`), so the frame
/// is free to be the design's fixed geometry -- and it is compared with the
/// design pixel by pixel (`tools/design/scan_fidelity_check.py`).
///
/// The analysing pulse is production-only (the reference has no analysing
/// state) and keeps its previous look; the sweep line hides while it runs so
/// "working" and "aim" stay two different pictures.
///
/// Decoration only -- the caller wraps it in [IgnorePointer]; a tap must land
/// on the preview underneath, never on this.
class ScanFrame extends StatefulWidget {
  const ScanFrame({
    super.key,
    required this.phase,
    required this.bracket,
    required this.accent,
    this.sweepVisible = true,
  });

  final ScanFramePhase phase;

  /// The bracket stroke: `rgba(255,255,255,.9)` on dark, `rgba(27,32,48,.42)`
  /// on light. Given by the caller, which owns the theme decision.
  final Color bracket;

  /// The analysing pulse's colour.
  final Color accent;

  /// False hides the sweep line without touching the brackets -- the
  /// evidence mode of the Scan page (R1) uses it.
  final bool sweepVisible;

  /// Geometry, public so the fidelity test can assert against it.
  static const double inset = 20;

  /// The bracket's outer box: 34px content + 2px border.
  static const double arm = 36;
  static const double stroke = 2;
  static const double radiusTopLeft = 15;
  static const double radiusOther = 10;
  static const double sweepTop = 18;
  static const double sweepHeight = 2;
  static const double sweepTravel = 196;
  static const Duration sweepPeriod = Duration(milliseconds: 3400);

  @override
  State<ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<ScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: ScanFrame.sweepPeriod);
    // Not started here: `MediaQuery` (read by [_syncMotion]) is not safely
    // readable in `initState` -- `didChangeDependencies` runs immediately
    // after and is where this loop actually starts.
  }

  /// The sweep line and analyzing pulse are purely decorative, continuous,
  /// looping motion over a live camera preview -- exactly the kind of thing
  /// reduce motion exists to suppress. Whether the loop should be running is
  /// re-decided here rather than once: `didChangeDependencies` also fires if
  /// the OS accessibility setting flips while this screen is open.
  ///
  /// Stopped at `t = 0`, where the reference's own keyframes put the sweep at
  /// opacity 0 -- so a reduced-motion user sees the brackets alone, and a
  /// golden taken at rest is the same picture the reference renders paused.
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
    final bool analyzing = widget.phase == ScanFramePhase.analyzing;
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, _) {
        return CustomPaint(
          painter: _ScanFramePainter(
            bracket: analyzing ? widget.accent : widget.bracket,
            accent: widget.accent,
            t: _c.value,
            analyzing: analyzing,
            sweep: widget.sweepVisible && !analyzing,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// `glassScan`'s opacity track: `0% 0; 12% 1; 88% 1; 100% 0`, each keyframe
/// interval eased the way the declared `ease-in-out` eases it.
@visibleForTesting
double scanSweepOpacity(double t) {
  if (t < 0.12) return Curves.easeInOut.transform(t / 0.12);
  if (t < 0.88) return 1;
  return 1 - Curves.easeInOut.transform((t - 0.88) / 0.12);
}

/// `glassScan`'s transform track: `translateY(0)` to `translateY(196px)`
/// over the whole period, `ease-in-out`.
@visibleForTesting
double scanSweepOffset(double t) =>
    ScanFrame.sweepTravel * Curves.easeInOut.transform(t.clamp(0, 1));

class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({
    required this.bracket,
    required this.accent,
    required this.t,
    required this.analyzing,
    required this.sweep,
  });

  final Color bracket;
  final Color accent;

  /// 0..1, looping.
  final double t;
  final bool analyzing;
  final bool sweep;

  @override
  void paint(Canvas canvas, Size size) {
    const double inset = ScanFrame.inset;
    const double arm = ScanFrame.arm;
    const double half = ScanFrame.stroke / 2;
    final Paint p = Paint()
      ..color = bracket
      ..strokeWidth = ScanFrame.stroke
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;

    // One corner of a CSS bordered box: the outer edge of the border sits on
    // the box edge, so the stroke's centre line is `half` inside it, and the
    // rounded corner's centre line has radius `r - half`. `sx`/`sy` are the
    // corner's direction (+1 grows right/down), `ox`/`oy` its box corner.
    void corner(double ox, double oy, double sx, double sy, double r) {
      final double cx = ox + sx * half;
      final double cy = oy + sy * half;
      final double rr = r - half;
      final Path path = Path()
        ..moveTo(cx, oy + sy * arm)
        ..lineTo(cx, cy + sy * rr)
        ..arcToPoint(
          Offset(cx + sx * rr, cy),
          radius: Radius.circular(rr),
          clockwise: sx * sy > 0,
        )
        ..lineTo(ox + sx * arm, cy);
      canvas.drawPath(path, p);
    }

    corner(inset, inset, 1, 1, ScanFrame.radiusTopLeft);
    corner(size.width - inset, inset, -1, 1, ScanFrame.radiusOther);
    corner(inset, size.height - inset, 1, -1, ScanFrame.radiusOther);
    corner(size.width - inset, size.height - inset, -1, -1,
        ScanFrame.radiusOther);

    if (analyzing) {
      // A ring expanding out of the frame, fading as it goes: the design's
      // `animate-pulse-ring`. It reads as "working" without a spinner, which
      // would compete with the classifier's own progress indicator.
      final Rect window = Rect.fromLTRB(
          inset, inset, size.width - inset, size.height - inset);
      final double grow = 28.0 * t;
      final Paint ring = Paint()
        ..color = accent.withValues(alpha: (1 - t) * 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          window.inflate(grow),
          const Radius.circular(10),
        ),
        ring,
      );
      canvas.drawRect(window, Paint()..color = accent.withValues(alpha: 0.06));
      return;
    }

    if (!sweep) return;
    final double opacity = scanSweepOpacity(t);
    if (opacity <= 0) return;
    final Rect line = Rect.fromLTWH(
      inset,
      ScanFrame.sweepTop + scanSweepOffset(t),
      size.width - inset * 2,
      ScanFrame.sweepHeight,
    );
    canvas.drawRect(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            const Color(0x00FFFFFF),
            Color.fromRGBO(255, 255, 255, 0.95 * opacity),
            const Color(0x00FFFFFF),
          ],
        ).createShader(line),
    );
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) =>
      old.t != t ||
      old.analyzing != analyzing ||
      old.sweep != sweep ||
      old.bracket != bracket ||
      old.accent != accent;
}
