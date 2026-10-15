/// The calorie range control of the plan screen (design s24, D-82, Y-F6).
///
/// A CUSTOM two-thumb widget, not the stock `RangeSlider`: each thumb is its own
/// semantics node with increase/decrease actions of one step (10 kcal) and a
/// spoken value plus unit ("Lowest daily calories 1700 kilocalories"); hitting
/// a bound or the width limits is announced ("Minimum reached, 1200", "Range
/// cannot be narrower than 100"); and a non-drag alternative sits in the same
/// card: numeric steppers (+/-10 and +/-100) that edit the same state as the
/// thumbs. Touch targets are at least 48 dp. The widget is controlled: the
/// parent owns the range and persists it on `onChangeEnd`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/hud_tokens.dart';
import '../data/plan_calculator.dart';
import '../data/safety_clamps.dart';

/// Which limit stopped a move.
enum KcalSliderLimit { minBound, maxBound, minGap, maxGap }

/// The result of moving one thumb: the new range and the limit that stopped it
/// (null when the move was applied in full).
class KcalSliderMove {
  const KcalSliderMove(this.range, [this.limit]);

  final KcalRange range;
  final KcalSliderLimit? limit;
}

const int kKcalSliderStep = 10;
const int kKcalSliderBigStep = 100;

/// Pure move logic, shared by drag, semantics actions, keys and the steppers.
///
/// [target] is the wanted value of the moved thumb; it is snapped to the step,
/// then held inside the plan bounds and the allowed width (100..400 kcal).
KcalSliderMove moveKcalThumb({
  required PlanBounds bounds,
  required KcalRange range,
  required bool lowThumb,
  required int target,
  int step = kKcalSliderStep,
}) {
  const minW = SafetyClamps.minRangeWidthKcal;
  const maxW = SafetyClamps.maxRangeWidthKcal;
  final snapped = (target / step).round() * step;
  if (lowThumb) {
    final lowest = bounds.minKcal > range.high - maxW
        ? bounds.minKcal
        : range.high - maxW;
    final highest = range.high - minW;
    KcalSliderLimit? limit;
    var v = snapped;
    if (v < bounds.minKcal) {
      v = bounds.minKcal;
      limit = KcalSliderLimit.minBound;
    } else if (v < lowest) {
      v = lowest;
      limit = KcalSliderLimit.maxGap;
    } else if (v > highest) {
      v = highest;
      limit = KcalSliderLimit.minGap;
    }
    return KcalSliderMove(KcalRange(v, range.high), limit);
  }
  final lowest = range.low + minW;
  final upper = bounds.maxKcal < range.low + maxW
      ? bounds.maxKcal
      : range.low + maxW;
  KcalSliderLimit? limit;
  var v = snapped;
  if (v > bounds.maxKcal) {
    v = bounds.maxKcal;
    limit = KcalSliderLimit.maxBound;
  } else if (v > upper) {
    v = upper;
    limit = KcalSliderLimit.maxGap;
  } else if (v < lowest) {
    v = lowest;
    limit = KcalSliderLimit.minGap;
  }
  return KcalSliderMove(KcalRange(range.low, v), limit);
}

class KcalRangeSlider extends StatefulWidget {
  const KcalRangeSlider({
    super.key,
    required this.bounds,
    required this.range,
    required this.onChanged,
    required this.onChangeEnd,
    this.enabled = true,
  });

  final PlanBounds bounds;
  final KcalRange range;

  /// Live value while a thumb is being dragged.
  final ValueChanged<KcalRange> onChanged;

  /// The value to persist: drag end, semantics action, key or stepper press.
  final ValueChanged<KcalRange> onChangeEnd;
  final bool enabled;

  @override
  State<KcalRangeSlider> createState() => _KcalRangeSliderState();
}

class _KcalRangeSliderState extends State<KcalRangeSlider> {
  static const double _thumbBox = 48;
  static const double _thumbSize = 24;

  KcalSliderLimit? _announced;
  double _dragStartValue = 0;
  double _dragDx = 0;
  late KcalRange _dragStartRange;

  String _spoken(AppLocalizations l10n, int v) =>
      l10n.nutritionKcalSpoken(NumberFormat.decimalPattern(
              Localizations.localeOf(context).toString())
          .format(v));

  String _num(int v) => NumberFormat.decimalPattern(
          Localizations.localeOf(context).toString())
      .format(v);

  void _announceLimit(AppLocalizations l10n, KcalSliderMove move, bool low) {
    final limit = move.limit;
    if (limit == null) {
      _announced = null;
      return;
    }
    if (limit == _announced) return;
    _announced = limit;
    final msg = switch (limit) {
      KcalSliderLimit.minBound =>
        l10n.nutritionSliderMinReached(_num(widget.bounds.minKcal)),
      KcalSliderLimit.maxBound =>
        l10n.nutritionSliderMaxReached(_num(widget.bounds.maxKcal)),
      KcalSliderLimit.minGap =>
        l10n.nutritionSliderGapMin(_num(SafetyClamps.minRangeWidthKcal)),
      KcalSliderLimit.maxGap =>
        l10n.nutritionSliderGapMax(_num(SafetyClamps.maxRangeWidthKcal)),
    };
    SemanticsService.announce(msg, Directionality.of(context));
  }

  /// Applies a discrete change (action, key, stepper) and persists it.
  void _commitStep(bool low, int delta) {
    final l10n = AppLocalizations.of(context);
    final current = low ? widget.range.low : widget.range.high;
    final move = moveKcalThumb(
      bounds: widget.bounds,
      range: widget.range,
      lowThumb: low,
      target: current + delta,
    );
    _announced = null;
    _announceLimit(l10n, move, low);
    if (move.range == widget.range) return;
    widget.onChanged(move.range);
    widget.onChangeEnd(move.range);
  }

  double _fraction(int value) {
    final span = widget.bounds.maxKcal - widget.bounds.minKcal;
    if (span <= 0) return 0;
    return ((value - widget.bounds.minKcal) / span).clamp(0.0, 1.0);
  }

  Widget _thumb({
    required bool low,
    required double trackWidth,
    required AppLocalizations l10n,
    required HudTokens hud,
  }) {
    final value = low ? widget.range.low : widget.range.high;
    final label =
        low ? l10n.nutritionSliderLowLabel : l10n.nutritionSliderHighLabel;
    final span = widget.bounds.maxKcal - widget.bounds.minKcal;
    final left = _fraction(value) * trackWidth;
    final up = moveKcalThumb(
            bounds: widget.bounds,
            range: widget.range,
            lowThumb: low,
            target: value + kKcalSliderStep)
        .range;
    final down = moveKcalThumb(
            bounds: widget.bounds,
            range: widget.range,
            lowThumb: low,
            target: value - kKcalSliderStep)
        .range;
    return Positioned(
      left: left,
      top: 0,
      width: _thumbBox,
      height: _thumbBox,
      child: Semantics(
        container: true,
        slider: true,
        enabled: widget.enabled,
        label: label,
        value: _spoken(l10n, value),
        increasedValue: _spoken(l10n, low ? up.low : up.high),
        decreasedValue: _spoken(l10n, low ? down.low : down.high),
        onIncrease:
            widget.enabled ? () => _commitStep(low, kKcalSliderStep) : null,
        onDecrease:
            widget.enabled ? () => _commitStep(low, -kKcalSliderStep) : null,
        child: Focus(
          canRequestFocus: widget.enabled,
          onKeyEvent: (node, event) {
            if (event is KeyUpEvent || !widget.enabled) {
              return KeyEventResult.ignored;
            }
            final key = event.logicalKey;
            int? delta;
            if (key == LogicalKeyboardKey.arrowRight ||
                key == LogicalKeyboardKey.arrowUp) {
              delta = kKcalSliderStep;
            } else if (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowDown) {
              delta = -kKcalSliderStep;
            } else if (key == LogicalKeyboardKey.pageUp) {
              delta = kKcalSliderBigStep;
            } else if (key == LogicalKeyboardKey.pageDown) {
              delta = -kKcalSliderBigStep;
            }
            if (delta == null) return KeyEventResult.ignored;
            _commitStep(low, delta);
            return KeyEventResult.handled;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.enabled
                ? (_) {
                    _dragStartValue = value.toDouble();
                    _dragStartRange = widget.range;
                    _dragDx = 0;
                  }
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (d) {
                    _dragDx += d.delta.dx;
                    final dir = Directionality.of(context) == TextDirection.rtl
                        ? -1
                        : 1;
                    final target = _dragStartValue +
                        dir * _dragDx / (trackWidth <= 0 ? 1 : trackWidth) * span;
                    final move = moveKcalThumb(
                      bounds: widget.bounds,
                      range: _dragStartRange,
                      lowThumb: low,
                      target: target.round(),
                    );
                    _announceLimit(l10n, move, low);
                    if (move.range != widget.range) widget.onChanged(move.range);
                  }
                : null,
            onHorizontalDragEnd:
                widget.enabled ? (_) => widget.onChangeEnd(widget.range) : null,
            child: ExcludeSemantics(
              child: Center(
                child: Container(
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: BoxDecoration(
                    color: widget.enabled ? hud.accent : hud.textSecondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: hud.textPrimary, width: 2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepButton(
      {required String label,
      required String text,
      required VoidCallback? onPressed}) {
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      excludeSemantics: true,
      onTap: onPressed,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(text),
      ),
    );
  }

  Widget _stepperRow(AppLocalizations l10n, ThemeData theme, bool low) {
    final label =
        low ? l10n.nutritionSliderLowLabel : l10n.nutritionSliderHighLabel;
    final value = low ? widget.range.low : widget.range.high;
    final on = widget.enabled;
    String dec(int s) => l10n.nutritionStepperDecrease(label, _num(s));
    String inc(int s) => l10n.nutritionStepperIncrease(label, _num(s));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${_num(value)}', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stepButton(
                  label: dec(kKcalSliderBigStep),
                  text: '-$kKcalSliderBigStep',
                  onPressed:
                      on ? () => _commitStep(low, -kKcalSliderBigStep) : null),
              _stepButton(
                  label: dec(kKcalSliderStep),
                  text: '-$kKcalSliderStep',
                  onPressed:
                      on ? () => _commitStep(low, -kKcalSliderStep) : null),
              _stepButton(
                  label: inc(kKcalSliderStep),
                  text: '+$kKcalSliderStep',
                  onPressed:
                      on ? () => _commitStep(low, kKcalSliderStep) : null),
              _stepButton(
                  label: inc(kKcalSliderBigStep),
                  text: '+$kKcalSliderBigStep',
                  onPressed:
                      on ? () => _commitStep(low, kKcalSliderBigStep) : null),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final trackWidth =
              (constraints.maxWidth - _thumbBox).clamp(1.0, double.infinity);
          final lowX = _fraction(widget.range.low) * trackWidth;
          final highX = _fraction(widget.range.high) * trackWidth;
          return SizedBox(
            height: _thumbBox,
            child: Stack(
              children: [
                Positioned(
                  left: _thumbBox / 2,
                  right: _thumbBox / 2,
                  top: _thumbBox / 2 - 2,
                  height: 4,
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: hud.textSecondary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: _thumbBox / 2 + lowX,
                  width: (highX - lowX).clamp(0.0, double.infinity),
                  top: _thumbBox / 2 - 2,
                  height: 4,
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: hud.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                _thumb(low: true, trackWidth: trackWidth, l10n: l10n, hud: hud),
                _thumb(
                    low: false, trackWidth: trackWidth, l10n: l10n, hud: hud),
              ],
            ),
          );
        }),
        _stepperRow(l10n, theme, true),
        _stepperRow(l10n, theme, false),
      ],
    );
  }
}
