import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import 'state/ai_planner_providers.dart';

/// "AI workout generator" page. Surfaces the [GeneratedPlan] from the
/// pure builder. Reads:
///   - injury list (from profile)
///   - personalisation profile (from logs + difficulty ratings)
///   - deload verdict
class AiPlannerPage extends ConsumerWidget {
  const AiPlannerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final planAsync = ref.watch(generatedPlanProvider);

    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Today\'s plan'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            child: Text(
              'Generated from your intake (injury filter), recent ratings, '
              'and recovery signals. Updates daily.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          planAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => GlassCard(
              tint: theme.colorScheme.error,
              child: Text('Could not generate: $e'),
            ),
            data: (plan) {
              if (plan == null) {
                return GlassCard(
                  child: Text(
                    'Sign in and complete onboarding to see a plan.',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(colors: [
                                  AppPalette.auroraTeal,
                                  AppPalette.auroraBlue,
                                ]),
                              ),
                              child: const Icon(Icons.auto_awesome,
                                  color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(plan.title,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800)),
                                  Text(
                                    '${plan.estimatedMinutes} min · '
                                    'intensity ${(plan.intensityFactor * 100).round()}%',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(plan.rationale,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final ex in plan.exercises) ...[
                    GlassCard(
                      onTap: () =>
                          GoRouter.of(context).go('/workout/${ex.id}'),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: AppPalette.tileGradients[
                                    ex.id.hashCode.abs() %
                                        AppPalette.tileGradients.length],
                              ),
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ex.title,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w800)),
                                Text(
                                  '${ex.durationMinutes} min · ${ex.muscles.take(2).join(", ")}',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
