/// Circular and linear metrics: the rings, tracks, zone bars and rows the HUD
/// reports numbers with.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import 'hud_surface.dart' show HudKeyboardActivation;

/// One circular metric — track, glowing progress arc, optional dashed guide,
/// and whatever sits in the middle.
///
/// ## The sizes are per-screen and that is not an inconsistency
///
/// The handoff draws this ring at four sizes with four geometries: Home 112
/// (r 49, 2.5pt arc, dashed guide at r 38), Session 150 (r 66, 3pt, guide at
/// r 53), Progress 104 (r 45, 2.5pt, no guide) and Scan 78 (r 34, 2.5pt, no
/// guide). A single "158×158 circular metric" — which is what the brief asks
/// for — exists only on the form coach, and there it is a disc, not a ring.
/// Each call site passes its own numbers rather than a size token, because the
/// stroke and the guide do not scale linearly with the diameter in the source.
class HudRing extends StatelessWidget {
  const HudRing({
    super.key,
    required this.size,
    required this.radius,
    required this.progress,
    this.strokeWidth = 2.5,
    this.trackWidth = 1.5,
    this.guideRadius,
    this.guideDash = const <double>[2, 6],
    this.glowBlur = 7,
    this.color,
    this.child,
    this.semanticsLabel,
  });

  final double size;

  /// The arc's radius in the same coordinate space as [size] — `r` in the
  /// source's `<circle r="...">`, not a fraction.
  final double radius;

  /// 0..1. Values outside are clamped rather than wrapping: a progress of 1.2
  /// is a bug upstream and drawing 20% of a second lap would hide it.
  final double progress;

  final double strokeWidth;
  final double trackWidth;

  /// The faint dashed circle inside the arc. Null on the two rings that have
  /// none.
  final double? guideRadius;

  final List<double> guideDash;

  /// `drop-shadow(0 0 <n>px)` — 7 on Home and Progress, 9 on Session, 6 on
  /// Scan and on both light-theme rings.
  final double glowBlur;

  /// Overrides the arc colour, for a metric whose value carries a state
  /// (a technique score that has gone red).
  final Color? color;

  final Widget? child;

  /// What a screen reader says instead of reading the ring's inner text out of
  /// context. A ring with no label is announced by its child, which is usually
  /// a bare number and tells nobody anything.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final Widget painted = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0),
          radius: radius,
          strokeWidth: strokeWidth,
          trackWidth: trackWidth,
          guideRadius: guideRadius,
          guideDash: guideDash,
          glowBlur: glowBlur,
          track: t.ringTrack,
          stroke: color ?? t.ringStroke,
          guide: t.ringGuide,
          glow: t.ringGlow,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );

    if (semanticsLabel == null) return painted;
    return Semantics(
      label: semanticsLabel,
      value: '${(progress.clamp(0.0, 1.0) * 100).round()}%',
      child: ExcludeSemantics(child: painted),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.radius,
    required this.strokeWidth,
    required this.trackWidth,
    required this.guideRadius,
    required this.guideDash,
    required this.glowBlur,
    required this.track,
    required this.stroke,
    required this.guide,
    required this.glow,
  });

  final double progress;
  final double radius;
  final double strokeWidth;
  final double trackWidth;
  final double? guideRadius;
  final List<double> guideDash;
  final double glowBlur;
  final Color track;
  final Color stroke;
  final Color guide;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2);
    // The source's `transform:rotate(-90deg)` on the whole svg: the arc starts
    // at twelve o'clock and runs clockwise.
    const double start = -math.pi / 2;
    final double sweep = 2 * math.pi * progress;
    final Rect arcRect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..color = track,
    );

    if (guideRadius != null) {
      _dashedCircle(canvas, centre, guideRadius!, guideDash, guide);
    }

    if (sweep <= 0) return;

    // `drop-shadow(0 0 Npx c)` is a blurred copy under the shape, so it is
    // painted as a blurred stroke first and the crisp one over it. A
    // `MaskFilter` on the visible stroke would blur the stroke itself.
    //
    // `glowBlur` is passed straight through as `MaskFilter.blur`'s sigma, NOT
    // halved. CSSWG filter-effects-1 draws the length param of `drop-shadow()`
    // as the standard deviation directly -- the same fact `blurSigma()` in
    // `hud_tokens.dart` states, and this ring carried the identical /2 bug for
    // the identical wrong reason until the same review round caught it.
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = glow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur),
    );

    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = stroke,
    );
  }

  void _dashedCircle(
    Canvas canvas,
    Offset centre,
    double r,
    List<double> dash,
    Color colour,
  ) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colour;
    final double circumference = 2 * math.pi * r;
    final double on = dash[0];
    final double off = dash.length > 1 ? dash[1] : dash[0];
    final double step = on + off;
    if (step <= 0) return;
    final Rect rect = Rect.fromCircle(center: centre, radius: r);
    // Whole dashes only, distributed to close the loop exactly — a remainder
    // left at the seam is visible on a circle this small.
    final int count = math.max(1, (circumference / step).floor());
    final double unit = 2 * math.pi / count;
    final double onAngle = unit * (on / step);
    for (int i = 0; i < count; i++) {
      canvas.drawArc(rect, -math.pi / 2 + i * unit, onAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.trackWidth != trackWidth ||
      old.guideRadius != guideRadius ||
      old.glowBlur != glowBlur ||
      old.track != track ||
      old.stroke != stroke ||
      old.guide != guide ||
      old.glow != glow;
}

/// The number-and-caption block that sits inside a [HudRing].
class HudRingLabel extends StatelessWidget {
  const HudRingLabel({
    super.key,
    required this.value,
    required this.caption,
    this.valueSize = 40,
    this.valueColor,
    this.suffix,
  });

  final String value;
  final String caption;
  final double valueSize;
  final Color? valueColor;

  /// The smaller trailing part of a fraction — the `/4` in `3/4`.
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              value,
              style: HudType.bigNumber(t, size: valueSize, color: valueColor),
            ),
            if (suffix != null)
              Text(
                suffix!,
                style: HudType.bigNumber(
                  t,
                  size: valueSize / 2,
                  color: t.textTertiary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          caption.toUpperCase(),
          textAlign: TextAlign.center,
          style: HudType.ringLabel(t),
        ),
      ],
    );
  }
}

/// A linear indicator: `height:5–6px; border-radius:3px`.
class HudProgressTrack extends StatelessWidget {
  const HudProgressTrack({
    super.key,
    required this.value,
    this.height = 5,
    this.color,
    this.glow = true,
    this.semanticsLabel,
  });

  final double value;
  final double height;

  /// A recovery row tints its own fill; a programme's week bar does not.
  final Color? color;

  /// `box-shadow: 0 0 12px -2px currentColor`. Deleted in the light theme,
  /// where a self-luminous bar over a white wash only smears.
  final bool glow;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final bool isDark = t.brightness == Brightness.dark;
    final Color fill = color ?? t.progressFill;
    final double v = value.clamp(0.0, 1.0);

    return Semantics(
      label: semanticsLabel,
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2 + 0.5),
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.trackFill,
              borderRadius: BorderRadius.circular(height / 2 + 0.5),
              border: t.trackBorder.a == 0
                  ? null
                  : Border.all(color: t.trackBorder, width: 1),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2 + 0.5),
                  gradient: isDark
                      ? LinearGradient(
                          colors: <Color>[
                            fill.withValues(alpha: 0.45),
                            fill,
                          ],
                        )
                      : null,
                  color: isDark ? null : fill,
                  boxShadow: glow && isDark
                      ? <BoxShadow>[
                          BoxShadow(
                            color: fill,
                            blurRadius: 12,
                            spreadRadius: -2,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The three-zone readiness ramp with a marker — `poor | mid | good` at fixed
/// widths, and a 2×13 pin at the current value.
class HudZoneBar extends StatelessWidget {
  const HudZoneBar({
    super.key,
    required this.value,
    this.height = 5,
    this.stops = const <double>[0.24, 0.58],
    this.semanticsLabel,
  });

  final double value;
  final double height;

  /// Where the zones change. The handoff's Home bar breaks at 24% and 58–60%;
  /// the form-coach strip breaks at 18–20% and 46–48%.
  final List<double> stops;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final double v = value.clamp(0.0, 1.0);

    return Semantics(
      label: semanticsLabel,
      value: '${(v * 100).round()}%',
      child: SizedBox(
        height: 13,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(height / 2 + 0.5),
              child: SizedBox(
                height: height,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: (stops[0] * 1000).round(),
                      child: ColoredBox(
                        color: t.zonePoor.withValues(alpha: 0.85),
                      ),
                    ),
                    Expanded(
                      flex: ((stops[1] - stops[0]) * 1000).round(),
                      child: ColoredBox(
                        color: t.zoneMid.withValues(alpha: 0.85),
                      ),
                    ),
                    Expanded(
                      flex: ((1 - stops[1]) * 1000).round(),
                      child: ColoredBox(
                        color: t.zoneGood.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: (c.maxWidth * v - 1).clamp(0.0, c.maxWidth - 2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 2,
                      height: 13,
                      decoration: BoxDecoration(
                        color: t.textPrimary,
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: t.brightness == Brightness.dark
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: t.textPrimary.withValues(alpha: 0.95),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// `label ......... value   hint` — the Form-coach and At-a-glance row.
class HudMetricRow extends StatelessWidget {
  const HudMetricRow({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.divider = true,
  });

  final String label;
  final String value;
  final String? hint;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: t.divider, width: 1)),
            )
          : null,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: HudType.bodyStrong(t).copyWith(color: t.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: HudType.bodyStrong(t).copyWith(fontWeight: FontWeight.w600),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: Text(
                hint!,
                textAlign: TextAlign.right,
                style: HudType.mono(
                  t,
                  size: 9.5,
                  weight: FontWeight.w400,
                  color: t.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `50×29`, handle 23, travel 21. Accent-lit and glowing when on.
class HudToggle extends StatelessWidget {
  const HudToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final bool live = onChanged != null;

    return Semantics(
      toggled: value,
      label: semanticLabel,
      enabled: live,
      child: HudKeyboardActivation(
        onActivate: live ? () => onChanged!(!value) : null,
        child: GestureDetector(
          onTap: live ? () => onChanged!(!value) : null,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            // The switch itself is 29 tall; the hit box is not.
            height: HudTokens.minTapTarget,
            width: HudTokens.minTapTarget + 6,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.ease,
                width: 50,
                height: 29,
                padding: const EdgeInsets.all(3),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color:
                      value ? t.accent : t.textPrimary.withValues(alpha: 0.12),
                  border: Border.all(
                    color: value
                        ? HudTokens.switchRingOn
                        : t.textPrimary.withValues(alpha: 0.30),
                    width: 1,
                  ),
                  boxShadow: value
                      ? <BoxShadow>[
                          BoxShadow(
                            color: t.accent,
                            blurRadius: 18,
                            spreadRadius: -4,
                          ),
                        ]
                      : null,
                ),
                child: Container(
                  width: 23,
                  height: 23,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // White in both themes: the handoff's own reason is that the
                    // handle has to read "on any frame", and an ink handle would
                    // disappear into the light theme's white glass.
                    color: value
                        ? HudTokens.switchHandleOn
                        : HudTokens.switchHandleOff,
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x59000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `icon tile · title / subtitle · chevron` — Profile's rows and Train's
/// shortcuts.
class HudSettingRow extends StatelessWidget {
  const HudSettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.divider = true,
    this.tileSize = 40,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Replaces the chevron — a toggle, a badge, a value.
  final Widget? trailing;

  final bool divider;
  final double tileSize;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;

    final Widget row = Container(
      constraints: const BoxConstraints(minHeight: HudTokens.minTapTarget),
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: t.divider, width: 1)),
            )
          : null,
      child: Row(
        children: <Widget>[
          Container(
            width: tileSize,
            height: tileSize,
            decoration: BoxDecoration(
              color: t.tileFill,
              borderRadius: BorderRadius.circular(tileSize * 0.45),
              border: Border.all(color: t.tileBorder, width: 1),
            ),
            child: Icon(icon, size: tileSize / 2, color: t.textPrimary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: HudType.rowTitle(t)),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: HudType.rowMeta(t)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing ??
              Icon(
                Icons.chevron_right,
                size: 18,
                color: t.textPrimary.withValues(alpha: 0.5),
              ),
        ],
      ),
    );

    if (onTap == null) return row;
    // Without ExcludeSemantics the inner Text nodes merge into the outer
    // Semantics and the row is announced twice -- `HudButton`'s doc comment
    // names this exact bug and this row carried an undone instance of it.
    return Semantics(
      button: true,
      label: title,
      child: ExcludeSemantics(child: InkWell(onTap: onTap, child: row)),
    );
  }
}
