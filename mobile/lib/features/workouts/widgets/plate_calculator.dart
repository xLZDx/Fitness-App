import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/glass.dart';

/// Pure plate-loading solver. Greedy from the largest available plate down;
/// returns the plates per side that sum to (target - bar) / 2. When the
/// target can't be hit exactly, the closest *under* solution is returned
/// along with the residual so the UI can hint "load X kg, you'll be Y kg
/// short".
class PlateLoad {
  const PlateLoad({
    required this.platesPerSide,
    required this.totalLoaded,
    required this.targetKg,
    required this.barKg,
  });

  /// Plates from largest to smallest, per side. Multiply by 2 for both sides.
  final List<double> platesPerSide;

  /// Sum of bar + all plates on the bar.
  final double totalLoaded;

  final double targetKg;
  final double barKg;

  double get residualKg => targetKg - totalLoaded;

  bool get isExact => residualKg.abs() < 0.01;
}

/// Common plate denominations in kg (Olympic bumper). Pass a custom list to
/// the calculator widget if the gym uses a different set.
const defaultPlatesKg = <double>[25, 20, 15, 10, 5, 2.5, 1.25];

PlateLoad solvePlateLoad({
  required double targetKg,
  double barKg = 20,
  List<double> available = defaultPlatesKg,
}) {
  if (targetKg <= barKg) {
    return PlateLoad(
      platesPerSide: const [],
      totalLoaded: barKg,
      targetKg: targetKg,
      barKg: barKg,
    );
  }
  // Plate weight needed per side.
  var need = (targetKg - barKg) / 2.0;
  final plates = <double>[];
  // Greedy descent. With standard plate sets every load is achievable in
  // 0.625 kg increments — close enough for any gym I've ever seen.
  final descending = [...available]..sort((a, b) => b.compareTo(a));
  for (final p in descending) {
    while (need >= p - 0.001) {
      plates.add(p);
      need -= p;
    }
  }
  final perSideSum = plates.fold<double>(0, (a, b) => a + b);
  return PlateLoad(
    platesPerSide: List.unmodifiable(plates),
    totalLoaded: barKg + perSideSum * 2,
    targetKg: targetKg,
    barKg: barKg,
  );
}

/// Plate calculator UI. Bottom-sheet appropriate; can be embedded inline.
class PlateCalculator extends StatefulWidget {
  const PlateCalculator({super.key, this.initialTargetKg = 60});
  final double initialTargetKg;

  @override
  State<PlateCalculator> createState() => _PlateCalculatorState();
}

class _PlateCalculatorState extends State<PlateCalculator> {
  late double _target = widget.initialTargetKg;
  double _bar = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final load = solvePlateLoad(targetKg: _target, barKg: _bar);

    return GlassCard(
      floating: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fitness_center_rounded),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context).workoutsPlateCalculator,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          _Row(
            label: AppLocalizations.of(context).workoutsTargetWeight,
            child: _StepperPill(
              value: _target,
              suffix: 'kg',
              step: 2.5,
              onChanged: (v) => setState(() => _target = v),
            ),
          ),
          const SizedBox(height: 8),
          _Row(
            label: AppLocalizations.of(context).workoutsBarWeight,
            child: _StepperPill(
              value: _bar,
              suffix: 'kg',
              step: 5,
              onChanged: (v) => setState(() => _bar = v.clamp(0, 30)),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraTeal,
                AppPalette.auroraBlue,
              ]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).workoutsPerSide,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  load.platesPerSide.isEmpty
                      ? AppLocalizations.of(context).workoutsJustTheBar
                      : load.platesPerSide
                          .map((p) => p == p.truncateToDouble()
                              ? '${p.toInt()}kg'
                              : '${p}kg')
                          .join(' + '),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  load.isExact
                      ? 'Loaded total: ${load.totalLoaded.toStringAsFixed(2)} kg ✓'
                      : 'Loaded total: ${load.totalLoaded.toStringAsFixed(2)} kg '
                          '(${load.residualKg.toStringAsFixed(2)} kg short)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).workoutsPlatesAssumed25201510,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              )),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _StepperPill extends StatelessWidget {
  const _StepperPill({
    required this.value,
    required this.step,
    required this.onChanged,
    this.suffix = '',
  });

  final double value;
  final double step;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
            onPressed: () => onChanged(value - step),
          ),
          Expanded(
            child: Center(
              child: Text(
                value == value.truncateToDouble()
                    ? '${value.toInt()} $suffix'
                    : '$value $suffix',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(Icons.add_rounded),
            onPressed: () => onChanged(value + step),
          ),
        ],
      ),
    );
  }
}
