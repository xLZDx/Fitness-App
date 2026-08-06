import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'data/celebrity_plan.dart';
import 'state/celebrity_plan_providers.dart';

/// Browse celebrity-led plans. Premium-gated to Sustainer tier.
class CelebrityPlansPage extends ConsumerWidget {
  const CelebrityPlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tier = ref.watch(effectiveTierProvider);
    final isPremium = tier == SubscriptionTier.celebrityTrainer;
    final plansAsync = ref.watch(celebrityPlansProvider);

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).celebrityplansCelebrityPlans),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            child: Text(
              AppLocalizations.of(context).celebrityplansPlansDonatedInKindByProfessional,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          plansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => GlassCard(child: Text(AppLocalizations.of(context).catalogError(e))),
            data: (plans) => Column(
              children: [
                for (final p in plans) ...[
                  _PlanCard(plan: p, locked: !isPremium),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          if (!isPremium) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => GoRouter.of(context).push('/subscription'),
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(AppLocalizations.of(context).celebrityplansBecomeASustainerToUnlock),
            ),
          ],
        ],
      ),
    );
  }
}

/// Localized title/bio for the built-in sample plans.
///
/// Keyed on the plan id rather than translating the stored strings: the
/// seed records live in Dart, not in the ARB pipeline, so anything shipped
/// in them would stay English forever. Real (non-sample) plans keep their
/// own text — those come from a donor and are theirs to word.
String _title(BuildContext context, CelebrityPlan plan) {
  if (!plan.isSample) return plan.title;
  final l = AppLocalizations.of(context);
  switch (plan.id) {
    case 'starter-strength-4w':
      return l.celebrityplansSampleStarterTitle;
    case 'low-back-friendly-6w':
      return l.celebrityplansSampleLowBackTitle;
    default:
      return plan.title;
  }
}

String _bio(BuildContext context, CelebrityPlan plan) {
  if (!plan.isSample) return plan.coachBio;
  final l = AppLocalizations.of(context);
  switch (plan.id) {
    case 'starter-strength-4w':
      return l.celebrityplansSampleStarterBio;
    case 'low-back-friendly-6w':
      return l.celebrityplansSampleLowBackBio;
    default:
      return plan.coachBio;
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.locked});
  final CelebrityPlan plan;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(colors: [
                    AppPalette.auroraPeach,
                    AppPalette.auroraPink,
                  ]),
                ),
                child: const Icon(Icons.star_rounded,
                    color: AppSemanticColors.onGradientInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title(context, plan),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      plan.isSample
                          ? AppLocalizations.of(context)
                              .celebrityplansWeeksOnly(plan.weeks)
                          : AppLocalizations.of(context)
                              .celebrityplansByWeeks(plan.coachName, plan.weeks),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (locked) const Icon(Icons.lock_outline, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(_bio(context, plan), style: theme.textTheme.bodySmall),
          if (plan.isSample) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.tertiaryContainer,
              ),
              child: Text(
                AppLocalizations.of(context).celebrityplansSampleBadge,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
          if (plan.isInKindDonation && !plan.isSample) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withValues(alpha: 0.30),
              ),
              child: Text(
                AppLocalizations.of(context).celebrityplansInKindDonation,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
