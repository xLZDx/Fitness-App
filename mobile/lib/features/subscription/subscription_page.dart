import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import 'data/subscription_models.dart';
import 'state/subscription_providers.dart';

class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sub = ref.watch(currentSubscriptionProvider).valueOrNull;
    final tier = ref.watch(effectiveTierProvider);
    final action = ref.watch(subscriptionActionProvider);

    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Subscription'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          _StatusCard(sub: sub, effectiveTier: tier),
          const SizedBox(height: 24),
          Text(
            'Plans',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 12),
          _PlanCard(
            tier: SubscriptionTier.free,
            title: 'Free',
            price: 'Free forever',
            tagline: 'Get started, log workouts, track basic progress.',
            features: const [
              'Full body-weight library',
              'Basic workout logging',
              'Last-week progress chart',
            ],
            currentTier: tier,
            isLoading: action.isLoading,
            onChoose: () =>
                ref.read(subscriptionActionProvider.notifier).chooseTier(
                      SubscriptionTier.free,
                    ),
          ),
          const SizedBox(height: 12),
          _PlanCard(
            tier: SubscriptionTier.standard,
            title: 'Standard',
            price: r'$9.99 / month',
            tagline:
                'Everything you need: full equipment catalog and reminders.',
            features: const [
              'Full equipment catalog',
              'Personalised "For you" feed',
              'Injury-aware filtering',
              'Schedule + reminders',
              'Long-term progress charts',
            ],
            currentTier: tier,
            highlight: true,
            isLoading: action.isLoading,
            onChoose: () =>
                ref.read(subscriptionActionProvider.notifier).chooseTier(
                      SubscriptionTier.standard,
                    ),
            onStartTrial: sub == null ||
                    sub.status == SubscriptionStatus.none ||
                    sub.status == SubscriptionStatus.expired
                ? () => ref
                    .read(subscriptionActionProvider.notifier)
                    .startTrial(SubscriptionTier.standard)
                : null,
          ),
          const SizedBox(height: 12),
          _PlanCard(
            tier: SubscriptionTier.celebrityTrainer,
            title: 'Celebrity trainer',
            price: r'$19.99 / month',
            tagline:
                'Premium video plans, AI form coach, advanced analytics.',
            features: const [
              'Everything in Standard',
              'Celebrity-led video plans',
              'AI form coach',
              'Body composition + advanced analytics',
              'Priority new content',
            ],
            currentTier: tier,
            isLoading: action.isLoading,
            onChoose: () =>
                ref.read(subscriptionActionProvider.notifier).chooseTier(
                      SubscriptionTier.celebrityTrainer,
                    ),
            onStartTrial: sub == null ||
                    sub.status == SubscriptionStatus.none ||
                    sub.status == SubscriptionStatus.expired
                ? () => ref
                    .read(subscriptionActionProvider.notifier)
                    .startTrial(SubscriptionTier.celebrityTrainer)
                : null,
          ),
          if (sub != null && (sub.status == SubscriptionStatus.trial ||
              sub.status == SubscriptionStatus.active ||
              sub.status == SubscriptionStatus.cancelled)) ...[
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: action.isLoading
                    ? null
                    : () => ref
                        .read(subscriptionActionProvider.notifier)
                        .cancel(),
                child: const Text('Manage subscription'),
              ),
            ),
          ],
          if (action.hasError) ...[
            const SizedBox(height: 12),
            GlassCard(
              child: Text(
                'Could not update subscription: ${action.error}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.sub, required this.effectiveTier});
  final Subscription? sub;
  final SubscriptionTier effectiveTier;

  String _tierLabel(SubscriptionTier t) {
    switch (t) {
      case SubscriptionTier.free:
        return 'Free';
      case SubscriptionTier.standard:
        return 'Standard';
      case SubscriptionTier.celebrityTrainer:
        return 'Celebrity trainer';
    }
  }

  String _statusLabel(SubscriptionStatus s) {
    switch (s) {
      case SubscriptionStatus.none:
        return 'No active subscription';
      case SubscriptionStatus.trial:
        return 'Trial';
      case SubscriptionStatus.active:
        return 'Active';
      case SubscriptionStatus.cancelled:
        return 'Cancelling at period end';
      case SubscriptionStatus.expired:
        return 'Expired';
    }
  }

  String? _expiryLabel() {
    final s = sub;
    if (s == null) return null;
    final endsAt = s.status == SubscriptionStatus.trial
        ? s.trialEndsAt
        : s.currentPeriodEndsAt;
    if (endsAt == null) return null;
    final daysLeft = endsAt.difference(DateTime.now()).inDays;
    if (daysLeft < 0) return 'Lapsed ${-daysLeft}d ago';
    if (daysLeft == 0) return 'Ends today';
    if (daysLeft == 1) return 'Ends tomorrow';
    return 'Ends in $daysLeft days';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expiry = _expiryLabel();
    return GlassCard(
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
                  gradient: LinearGradient(
                    colors: effectiveTier == SubscriptionTier.celebrityTrainer
                        ? const [
                            AppPalette.auroraPeach,
                            AppPalette.auroraPink,
                          ]
                        : effectiveTier == SubscriptionTier.standard
                            ? const [
                                AppPalette.auroraViolet,
                                AppPalette.auroraBlue,
                              ]
                            : const [
                                AppPalette.auroraTeal,
                                AppPalette.auroraLime,
                              ],
                  ),
                ),
                child: const Icon(Icons.workspace_premium_outlined,
                    color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tierLabel(effectiveTier),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLabel(
                          sub?.status ?? SubscriptionStatus.none),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (expiry != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                expiry,
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.tier,
    required this.title,
    required this.price,
    required this.tagline,
    required this.features,
    required this.currentTier,
    required this.onChoose,
    this.onStartTrial,
    this.highlight = false,
    this.isLoading = false,
  });

  final SubscriptionTier tier;
  final String title;
  final String price;
  final String tagline;
  final List<String> features;
  final SubscriptionTier currentTier;
  final VoidCallback onChoose;
  final VoidCallback? onStartTrial;
  final bool highlight;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCurrent = currentTier == tier;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: const LinearGradient(colors: [
                                AppPalette.auroraTeal,
                                AppPalette.auroraLime,
                              ]),
                            ),
                            child: const Text(
                              'CURRENT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        else if (highlight)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white.withValues(alpha: 0.40),
                            ),
                            child: Text(
                              'POPULAR',
                              style: TextStyle(
                                color: scheme.onSurface
                                    .withValues(alpha: 0.75),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(price,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(tagline,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.70),
              )),
          const SizedBox(height: 14),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded,
                      size: 18, color: scheme.onSurface),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(f,
                          style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (onStartTrial != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: isLoading ? null : onStartTrial,
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Start 14-day trial'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: (isLoading || isCurrent) ? null : onChoose,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(isCurrent ? 'Current plan' : 'Choose'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
