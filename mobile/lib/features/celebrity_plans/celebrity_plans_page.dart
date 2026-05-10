import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
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
      appBar: const GlassAppBar(title: 'Celebrity plans'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            child: Text(
              'Plans donated in-kind by professional coaches and trainers. '
              'Every plan respects the injury filter you set in '
              'onboarding — no need to sub exercises in.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          plansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => GlassCard(child: Text('Error: $e')),
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
              onPressed: () => GoRouter.of(context).go('/subscription'),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Become a Sustainer to unlock'),
            ),
          ],
        ],
      ),
    );
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
                    color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      'by ${plan.coachName} · ${plan.weeks} weeks',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (locked) const Icon(Icons.lock_outline, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(plan.coachBio, style: theme.textTheme.bodySmall),
          if (plan.isInKindDonation) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withValues(alpha: 0.30),
              ),
              child: const Text(
                'IN-KIND DONATION',
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
