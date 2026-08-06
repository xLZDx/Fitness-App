import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/glass.dart';

/// Pure ramp calculator. Returns 4 warm-up sets at 40 / 60 / 75 / 90% of
/// working weight. Reps descend (8 → 5 → 3 → 1) so total bar volume stays
/// reasonable while the nervous system gets primed.
///
/// The loadings are rounded to the nearest 2.5 kg (smallest plate pair).
/// Working sets below 40 kg get a 3-set ramp instead of 4 — a 60kg working
/// set with 4 warm-up sets is overkill.
class WarmupSet {
  const WarmupSet({
    required this.percent,
    required this.kg,
    required this.reps,
  });
  final int percent;
  final double kg;
  final int reps;
}

List<WarmupSet> rampForWorkingWeight(double workingKg) {
  if (workingKg < 40) {
    return [
      WarmupSet(percent: 50, kg: _round(workingKg * 0.5), reps: 8),
      WarmupSet(percent: 75, kg: _round(workingKg * 0.75), reps: 5),
      WarmupSet(percent: 90, kg: _round(workingKg * 0.9), reps: 3),
    ];
  }
  return [
    WarmupSet(percent: 40, kg: _round(workingKg * 0.4), reps: 8),
    WarmupSet(percent: 60, kg: _round(workingKg * 0.6), reps: 5),
    WarmupSet(percent: 75, kg: _round(workingKg * 0.75), reps: 3),
    WarmupSet(percent: 90, kg: _round(workingKg * 0.9), reps: 1),
  ];
}

double _round(double kg) => (kg / 2.5).round() * 2.5;

class WarmupCalculator extends StatefulWidget {
  const WarmupCalculator({super.key, this.initialWorkingKg = 80});
  final double initialWorkingKg;

  @override
  State<WarmupCalculator> createState() => _WarmupCalculatorState();
}

class _WarmupCalculatorState extends State<WarmupCalculator> {
  late double _working = widget.initialWorkingKg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ramp = rampForWorkingWeight(_working);

    return GlassCard(
      floating: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context).workoutsWarmUpCalculator,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(AppLocalizations.of(context).workoutsWorkingWeight,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colors.textSecondary,
                    )),
              ),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white.withValues(alpha: 0.32),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: const Icon(Icons.remove_rounded),
                        onPressed: () => setState(
                            () => _working = (_working - 2.5).clamp(0, 999)),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            AppLocalizations.of(context).workoutsKg(
                                _working.toStringAsFixed(
                                    _working == _working.truncateToDouble()
                                        ? 0
                                        : 1)),
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: const Icon(Icons.add_rounded),
                        onPressed: () => setState(() => _working += 2.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < ramp.length; i++) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: AppPalette
                      .tileGradients[i % AppPalette.tileGradients.length],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white.withValues(alpha: 0.30),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: AppSemanticColors.onGradientInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).workoutsKgReps(
                              ramp[i].kg == ramp[i].kg.truncateToDouble()
                                  ? ramp[i].kg.toInt()
                                  : ramp[i].kg,
                              ramp[i].reps),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppSemanticColors.onGradientInk,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          AppLocalizations.of(context)
                              .workoutsOfWorkingWeight(ramp[i].percent),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppSemanticColors.onGradientInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (i < ramp.length - 1) const SizedBox(height: 6),
          ],
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)
                .workoutsRampsPrimeYourNervousSystemWithout,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
