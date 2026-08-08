import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/glass.dart';
import '../data/body_metrics.dart';

/// The design's `BMICard`, with the caveat the design does not carry.
///
/// Absent until both numbers exist: a card reading "BMI 0.0" for someone who
/// has not answered yet is stating a measurement about their body that is
/// false.
class BmiCard extends StatelessWidget {
  const BmiCard({super.key, required this.heightCm, required this.weightKg});

  final int? heightCm;
  final double? weightKg;

  @override
  Widget build(BuildContext context) {
    final bmi = bmiFor(heightCm: heightCm, weightKg: weightKg);
    if (bmi == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final band = bandFor(bmi);
    // Only the healthy band is drawn in the success colour. The other three
    // are neutral, not alarming: this screen is someone's first five minutes
    // in the app, and a red badge on a number that cannot tell muscle from
    // fat would be both discouraging and wrong.
    final tone = band == BmiBand.healthy
        ? theme.colors.success
        : theme.colors.textSecondary;

    return GlassCard(
      key: const Key('onb.bmiCard'),
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.onbBmiTitle(bmi.toStringAsFixed(1)),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _bandLabel(l10n, band),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: tone, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.onbBmiCaveat,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _bandLabel(AppLocalizations l10n, BmiBand b) => switch (b) {
        BmiBand.underweight => l10n.onbBmiUnderweight,
        BmiBand.healthy => l10n.onbBmiHealthy,
        BmiBand.overweight => l10n.onbBmiOverweight,
        BmiBand.obese => l10n.onbBmiObese,
      };
}

/// The design's `DeltaCard`: how far the target is from today.
///
/// Neither direction is styled as good. A gain is the goal for someone
/// bulking and the opposite for someone cutting, and at this point in the
/// questionnaire the app has not asked which.
class WeightDeltaCard extends StatelessWidget {
  const WeightDeltaCard({
    super.key,
    required this.currentKg,
    required this.targetKg,
  });

  final double? currentKg;
  final double? targetKg;

  @override
  Widget build(BuildContext context) {
    final delta = weightDelta(currentKg: currentKg, targetKg: targetKg);
    if (delta == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Rounded to the ruler's own resolution: the pickers move in half kilos,
    // so a delta with more precision than that is arithmetic noise.
    final rounded = (delta * 2).round() / 2;

    return GlassCard(
      key: const Key('onb.deltaCard'),
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        rounded == 0
            ? l10n.onbDeltaSame
            : l10n.onbDeltaTitle(_signed(rounded)),
        style: theme.textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  /// `+4` / `-2.5`. The sign is the information.
  static String _signed(double kg) {
    final text =
        kg == kg.roundToDouble() ? kg.round().toString() : kg.toStringAsFixed(1);
    return kg > 0 ? '+$text' : text;
  }
}
