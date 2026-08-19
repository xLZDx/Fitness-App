import 'package:flutter/material.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';

/// Maps a ruler's value range onto pixels, and back.
///
/// Pulled out of the widget so the arithmetic that decides what a drag MEANS
/// is testable without a gesture, a binding or a frame. Everything here is
/// integer-stepped in units of [step] so a drag cannot produce 71.4837 kg.
class RulerScale {
  const RulerScale({
    required this.min,
    required this.max,
    required this.step,
    required this.pixelsPerStep,
  })  : assert(max > min),
        assert(step > 0),
        assert(pixelsPerStep > 0);

  final double min;
  final double max;

  /// The smallest change the ruler can express — 1 for centimetres, 0.5 for
  /// kilograms.
  final double step;

  /// How far the user must drag to move one [step].
  final double pixelsPerStep;

  int get stepCount => ((max - min) / step).round();

  /// Total scrollable width of the whole scale.
  double get extent => stepCount * pixelsPerStep;

  /// Distance from the scale's start to [value].
  double offsetFor(double value) =>
      ((value.clamp(min, max) - min) / step) * pixelsPerStep;

  /// The value at [offset], snapped to [step] and clamped to the range.
  ///
  /// Snapped on the way out rather than on the way in: a caller that holds a
  /// raw offset can keep dragging smoothly while every value it reports is a
  /// legal one.
  double valueAt(double offset) {
    final steps = (offset / pixelsPerStep).round();
    final raw = min + steps * step;
    return _quantise(raw.clamp(min, max));
  }

  /// Removes the floating-point dust that repeated `+ 0.5` accumulates —
  /// 72.50000000000001 renders as "72.5" today and as something else the
  /// moment anyone formats it with more precision.
  double _quantise(double v) {
    final steps = (v - min) / step;
    return min + steps.round() * step;
  }
}

/// The design's horizontal measure picker (`HRuler` / `VRuler` in `App.tsx`).
///
/// ## Why not a text field
///
/// The onboarding asked for height, weight and target weight with three number
/// keyboards. The design uses a ruler for all three, and the reason is not
/// decoration: a ruler cannot produce 1750 cm, cannot be left half-typed, and
/// shows the neighbouring values, so someone unsure between 72 and 73 sees
/// both. A number field's failure modes are all silent.
///
/// ## Never a spinner disguised as a scale
///
/// The value the parent holds is the one rendered. There is no internal
/// "pending" value that a rebuild could contradict — the same defect
/// `GlassTextField` had before R11's audit, where the field kept its own copy
/// and stopped agreeing with the draft.
class MeasureRuler extends StatefulWidget {
  const MeasureRuler({
    super.key,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    this.step = 1,
    this.unit = '',
    this.pixelsPerStep = 12,
    this.majorEvery = 5,
  });

  /// Null renders the range's midpoint as the resting position without
  /// claiming the user chose it — an unanswered question, not a default
  /// answer.
  final double? value;

  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double step;
  final String unit;
  final double pixelsPerStep;

  /// Every Nth tick is drawn tall and labelled.
  final int majorEvery;

  @override
  State<MeasureRuler> createState() => _MeasureRulerState();
}

class _MeasureRulerState extends State<MeasureRuler> {
  late double _offset;

  RulerScale get _scale => RulerScale(
        min: widget.min,
        max: widget.max,
        step: widget.step,
        pixelsPerStep: widget.pixelsPerStep,
      );

  @override
  void initState() {
    super.initState();
    _offset = _scale.offsetFor(widget.value ?? _midpoint);
  }

  double get _midpoint => widget.min + (widget.max - widget.min) / 2;

  @override
  void didUpdateWidget(MeasureRuler old) {
    super.didUpdateWidget(old);
    // Only when the value changed for a reason other than this widget's own
    // drag. Re-seeding on every rebuild would fight the finger.
    final incoming = widget.value ?? _midpoint;
    if (_scale.valueAt(_offset) != incoming) {
      _offset = _scale.offsetFor(incoming);
    }
  }

  void _drag(double dx) {
    setState(() {
      _offset = (_offset - dx).clamp(0.0, _scale.extent);
    });
    widget.onChanged(_scale.valueAt(_offset));
  }

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final scale = _scale;
    final current = scale.valueAt(_offset);
    final answered = widget.value != null;

    return Semantics(
      slider: true,
      value: _spoken(current),
      // Both required whenever `value` is set alongside an increase/decrease
      // action — Flutter asserts on the pair, and it is right to: a screen
      // reader announcing "175 cm, increase" with no idea what increasing
      // reaches is a control a blind user cannot aim.
      increasedValue: _spoken(scale.valueAt(_offset + widget.pixelsPerStep)),
      decreasedValue: _spoken(scale.valueAt(_offset - widget.pixelsPerStep)),
      onIncrease: () => _drag(-widget.pixelsPerStep),
      onDecrease: () => _drag(widget.pixelsPerStep),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
        // A tap anywhere commits the resting value, so a user who agrees with
        // where it already sits does not have to jiggle it to answer.
        onTap: () => widget.onChanged(current),
        child: Column(
          children: [
            Text(
              '${_format(current)} ${widget.unit}'.trim(),
              style: HudType.heroTitle(t)
                  .copyWith(
                      fontSize: 24,
                      color: answered ? t.accent : t.textSecondary)
                  .overPhoto(t),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 56,
              child: LayoutBuilder(
                builder: (context, constraints) => CustomPaint(
                  size: Size(constraints.maxWidth, 56),
                  painter: _RulerPainter(
                    scale: scale,
                    offset: _offset,
                    majorEvery: widget.majorEvery,
                    tick: t.textTertiary,
                    majorTick: t.textSecondary,
                    needle: t.accent,
                    label: t.textSecondary,
                    textDirection: Directionality.of(context),
                    labelStyle: HudType.label(t, size: 10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _format(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  String _spoken(double v) => '${_format(v)} ${widget.unit}'.trim();
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.scale,
    required this.offset,
    required this.majorEvery,
    required this.tick,
    required this.majorTick,
    required this.needle,
    required this.label,
    required this.textDirection,
    required this.labelStyle,
  });

  final RulerScale scale;
  final double offset;
  final int majorEvery;
  final Color tick;
  final Color majorTick;
  final Color needle;
  final Color label;
  final TextDirection textDirection;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.width / 2;
    final paint = Paint()..strokeWidth = 1.5;

    // Only the ticks that can be on screen. Drawing the whole scale would be
    // several hundred lines per frame for a widget 300px wide.
    final firstVisible =
        ((offset - centre) / scale.pixelsPerStep).floor().clamp(0, scale.stepCount);
    final lastVisible =
        ((offset + centre) / scale.pixelsPerStep).ceil().clamp(0, scale.stepCount);

    for (var i = firstVisible; i <= lastVisible; i++) {
      final x = centre + (i * scale.pixelsPerStep - offset);
      final major = i % majorEvery == 0;
      paint.color = major ? majorTick : tick;
      final h = major ? 22.0 : 12.0;
      canvas.drawLine(Offset(x, 30 - h), Offset(x, 30), paint);

      if (major) {
        final value = scale.min + i * scale.step;
        final tp = TextPainter(
          text: TextSpan(
            text: value == value.roundToDouble()
                ? value.round().toString()
                : value.toStringAsFixed(1),
            style: (labelStyle ?? const TextStyle(fontSize: 10))
                .copyWith(color: label),
          ),
          textDirection: textDirection,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 34));
      }
    }

    // The needle last, so it is never under a tick.
    canvas.drawLine(
      Offset(centre, 0),
      Offset(centre, 34),
      Paint()
        ..color = needle
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.offset != offset ||
      old.scale.min != scale.min ||
      old.scale.max != scale.max ||
      old.needle != needle;
}
