import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../workouts/widgets/plate_calculator.dart';
import '../workouts/widgets/warmup_calculator.dart';
import 'data/equipment_models.dart';
import 'state/equipment_providers.dart';
import 'widgets/equipment_report_sheet.dart';

class EquipmentDetailPage extends ConsumerWidget {
  const EquipmentDetailPage({super.key, required this.equipmentId});

  final String equipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final eq = ref.watch(equipmentByIdProvider(equipmentId));
    final ex = ref.watch(recommendedExercisesProvider(equipmentId));

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).equipmentEquipment),
      body: eq.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Could not load: $e')),
        data: (item) {
          if (item == null) {
            return _NotFound(equipmentId: equipmentId);
          }
          return SmoothScrollList(
            padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
            children: [
              GlassCard(
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(colors: [
                          AppPalette.auroraViolet,
                          AppPalette.auroraBlue,
                        ]),
                      ),
                      child: const Icon(Icons.fitness_center,
                          color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 2),
                          Text(
                            '${item.manufacturer} · ${item.category}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const _ToolsRow(),
              const SizedBox(height: 16),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context).equipmentAbout, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(item.description,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.report_gmailerrorred_outlined,
                            size: 18),
                        label: Text(AppLocalizations.of(context).equipmentReportBrokenEquipment),
                        onPressed: () async {
                          final sent = await EquipmentReportSheet.show(
                            context,
                            equipmentId: item.id,
                            equipmentName: item.name,
                          );
                          if (sent == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text(AppLocalizations.of(context).equipmentReportSentToMaintenanceThanks),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).equipmentRecommendedExercises,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 12),
              ...ex.when(
                loading: () => [const _ExerciseShimmer()],
                error: (e, _) => [
                  GlassCard(child: Text('Could not load exercises: $e')),
                ],
                data: (rec) {
                  if (rec.items.isEmpty) {
                    return [
                      GlassCard(
                        child: Text(
                          rec.hiddenForInjury > 0
                              ? 'Every exercise on this machine conflicts with your reported injuries. Try a different piece of equipment.'
                              : 'No curated exercises yet for this machine.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ];
                  }
                  final widgets = <Widget>[];
                  if (rec.hiddenForInjury > 0) {
                    widgets.add(_FilteredHint(count: rec.hiddenForInjury));
                    widgets.add(const SizedBox(height: 12));
                  }
                  for (final e in rec.items) {
                    widgets.add(_ExerciseCard(exercise: e));
                    widgets.add(const SizedBox(height: 12));
                  }
                  return widgets;
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: () => GoRouter.of(context).push('/workout/${exercise.id}'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                colors: AppPalette.tileGradients[
                    exercise.id.hashCode.abs() % AppPalette.tileGradients.length],
              ),
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exercise.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${exercise.durationMinutes} min',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  exercise.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.60),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredHint extends StatelessWidget {
  const _FilteredHint({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraTeal,
                AppPalette.auroraBlue,
              ]),
            ),
            child: const Icon(Icons.health_and_safety_outlined,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? 'Filtered out 1 exercise that conflicts with your injuries.'
                  : 'Filtered out $count exercises that conflict with your injuries.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseShimmer extends StatelessWidget {
  const _ExerciseShimmer();
  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

/// Plate-calculator + warm-up calculator chips. Identical UX to the
/// Workout Player's tools row — pulled here so users can pre-load
/// plates before starting a session.
class _ToolsRow extends StatelessWidget {
  const _ToolsRow();

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: const Column(
            children: [
              PlateCalculator(),
              SizedBox(height: 14),
              WarmupCalculator(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.fitness_center_rounded, size: 18),
          label: Text(AppLocalizations.of(context).equipmentPlates),
          labelStyle: theme.textTheme.labelLarge,
          onPressed: () => _openSheet(context),
        ),
        ActionChip(
          avatar:
              const Icon(Icons.local_fire_department_rounded, size: 18),
          label: Text(AppLocalizations.of(context).equipmentWarmUp),
          labelStyle: theme.textTheme.labelLarge,
          onPressed: () => _openSheet(context),
        ),
      ],
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.equipmentId});
  final String equipmentId;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner_outlined, size: 60),
            const SizedBox(height: 8),
            Text("We don't have $equipmentId in our catalog yet.",
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context).equipmentTryScanningADifferentCodeOr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
