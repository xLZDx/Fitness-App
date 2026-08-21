import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../safety/widgets/eligibility_notice.dart';
import 'data/workout_plan.dart';
import 'plan_reason_text.dart';
import 'state/ai_planner_providers.dart';
import '../equipment/widgets/exercise_thumb.dart';

/// "AI workout generator" page. Surfaces the [GeneratedPlan] from the
/// pure builder. Reads:
///   - injury list (from profile)
///   - weekly per-muscle set deficit (from logged sessions)
///   - deload verdict
class AiPlannerPage extends ConsumerWidget {
  const AiPlannerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final planAsync = ref.watch(generatedPlanProvider);

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).aiplannerTodaySPlan),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            child: Text(
              AppLocalizations.of(context).aiplannerGeneratedFromYourIntakeInjuryFilter,
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
              child: Text(AppLocalizations.of(context).aiplannerCouldNotGenerate(e)),
            ),
            data: (outcome) {
              if (outcome == null) {
                return GlassCard(
                  child: Text(
                    AppLocalizations.of(context).aiplannerSignInAndCompleteOnboardingTo,
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              // The screening floor. Rendered instead of a plan, not above one:
              // a refusal shown next to a workout is a workout.
              if (outcome case PlanRefused(:final reasons)) {
                return EligibilityNotice(
                  key: const Key('planner.refused'),
                  title: AppLocalizations.of(context).eligTrainingBlockedTitle,
                  reasons: reasons,
                  onReviewProfile: () =>
                      GoRouter.of(context).push('/onboarding/edit'),
                );
              }
              final plan = (outcome as PlanReady).plan;
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
                                  color: AppSemanticColors.onGradientInk),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(planTitleText(AppLocalizations.of(context), plan.title),
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800)),
                                  Text(
                                    AppLocalizations.of(context).aiplannerMinIntensity(plan.estimatedMinutes, (plan.intensityFactor * 100).round()),
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                            planRationaleText(
                                AppLocalizations.of(context), plan.reasons),
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final ex in plan.exercises) ...[
                    GlassCard(
                      onTap: () =>
                          GoRouter.of(context).push('/workout/${ex.id}'),
                      child: Row(
                        children: [
                          ExerciseThumb(exercise: ex, size: 48),
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
                                  AppLocalizations.of(context).aiplannerMinMuscles(
                                      ex.durationMinutes,
                                      ex.muscles.take(2).join(', ')),
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(
                                    color: theme.colors.textSecondary,
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
