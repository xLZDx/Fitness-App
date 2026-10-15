import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../data/day_totals.dart';
import 'food_format.dart';
import 'macro_bars.dart';

/// Day summary: a calm ring of eaten kcal against the plan range, the status
/// sentence, the SECONDARY "room left" text (D-78) and macro rows.
///
/// Wording is neutral: an empty day or a day below the range is "not over",
/// never "behind" or a failure, and the ring is not coloured as a warning. The
/// painted ring is excluded from semantics; one summary node carries the
/// numbers. With no plan ([targets] null) only the eaten amount is shown.
class DaySummaryRing extends StatelessWidget {
  const DaySummaryRing({
    super.key,
    required this.totals,
    required this.targets,
    required this.hasEntries,
  });

  final DayTotals totals;
  final DayTargets? targets;
  final bool hasEntries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final eaten = totals.totals.kcal.mid;
    final t = targets;
    final eatenText = fmtInt(context, eaten);
    final label = t == null
        ? l10n.foodDiaryRingLabelNoPlan(eatenText)
        : l10n.foodDiaryRingLabel(
            eatenText, fmtInt(context, t.kcalLow), fmtInt(context, t.kcalHigh));
    final progress = t == null || t.kcalHigh <= 0
        ? 0.0
        : (eaten / t.kcalHigh).clamp(0.0, 1.0);
    final status = t == null || !hasEntries
        ? null
        : switch (totals.status) {
            KcalStatus.below => l10n.foodDiaryStatusBelow,
            KcalStatus.within => l10n.foodDiaryStatusWithin,
            KcalStatus.above => l10n.foodDiaryStatusAbove,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: '${l10n.foodDiarySummaryTitle}. $label',
          excludeSemantics: true,
          child: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(160),
                    painter: _RingPainter(
                      progress: progress,
                      track: theme.colorScheme.surfaceContainerHighest,
                      fill: theme.colorScheme.primary,
                    ),
                  ),
                  // Inside the ring and scaled down, so 200 % text never
                  // overflows the fixed 160 dp circle.
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(eatenText, style: theme.textTheme.headlineMedium),
                          Text(l10n.foodUnitKcal('').trim(),
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(status, textAlign: TextAlign.center),
          ),
        if (t != null && hasEntries && totals.remainingKcal > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.foodDiaryRemaining(fmtInt(context, totals.remainingKcal)),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (totals.proteinMinimumReached)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.foodDiaryProteinReached,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        MacroBars(totals: totals.totals),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track, required this.fill});

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    if (progress > 0) {
      canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        base
          ..color = fill
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.track != track || old.fill != fill;
}
