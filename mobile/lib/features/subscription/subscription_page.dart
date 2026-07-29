import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import 'data/subscription_models.dart';
import 'state/subscription_providers.dart';

/// "Support the mission" page (formerly Subscription).
///
/// The Stripe billing model is unchanged — three tiers, monthly recurring,
/// 14-day trial. The copy reframes those tiers as **recurring donations**
/// to the nonprofit so the language matches the 501(c)(3) framing.
///
/// Display labels per tier (model name → display label):
///   - free               → "Member"
///   - standard           → "Supporter"
///   - celebrityTrainer   → "Sustainer"
class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  /// Takes the localisations explicitly: this is a static helper with no
  /// BuildContext of its own, and the tier names are translated.
  static String tierLabel(AppLocalizations l10n, SubscriptionTier t) {
    switch (t) {
      case SubscriptionTier.free:
        return l10n.subscriptionMember;
      case SubscriptionTier.standard:
        return l10n.subscriptionSupporter;
      case SubscriptionTier.celebrityTrainer:
        return l10n.subscriptionSustainer;
    }
  }

  /// What the page should render given the current subscription state.
  ///   - [_PageState.picker]    fresh user; show the 3-tier picker.
  ///   - [_PageState.trialing]  local-only trial (no Stripe customer).
  ///   - [_PageState.paid]      Stripe-backed donation. Show the Manage card.
  _PageState _stateFor(Subscription? sub) {
    if (sub == null) return _PageState.picker;
    switch (sub.status) {
      case SubscriptionStatus.none:
      case SubscriptionStatus.expired:
        return _PageState.picker;
      case SubscriptionStatus.trial:
        return _PageState.trialing;
      case SubscriptionStatus.active:
      case SubscriptionStatus.cancelled:
        return _PageState.paid;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sub = ref.watch(currentSubscriptionProvider).valueOrNull;
    final tier = ref.watch(effectiveTierProvider);
    final action = ref.watch(subscriptionActionProvider);
    final state = _stateFor(sub);

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).aboutSupportTheMission),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          _StatusCard(sub: sub, effectiveTier: tier),
          const SizedBox(height: 16),
          const _MissionStrip(),
          const SizedBox(height: 24),

          if (state == _PageState.paid) ...[
            _ManagePlanCard(
              isLoading: action.isLoading,
              onTap: () =>
                  ref.read(subscriptionActionProvider.notifier).cancel(),
            ),
          ] else if (state == _PageState.trialing) ...[
            _UpgradeFromTrialCard(
              tier: sub!.tier,
              isLoading: action.isLoading,
              onUpgrade: () =>
                  ref.read(subscriptionActionProvider.notifier).chooseTier(sub.tier),
            ),
          ] else ...[
            Text(
              AppLocalizations.of(context).subscriptionChooseAWayToSupport,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context).subscriptionEveryLevelKeepsTheAppFree,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 12),
            const _PeriodToggle(),
            const SizedBox(height: 12),
            _PlanCard(
              tier: SubscriptionTier.free,
              title: AppLocalizations.of(context).subscriptionMember,
              price: 'Free forever',
              tagline:
                  'Full app access — workouts, scanning, injury filtering, progress.',
              features: const [
                'Full body-weight + equipment library',
                'Injury-aware filtering (always on)',
                'Workout logging + last-week chart',
                'Equipment QR scanning',
              ],
              currentTier: tier,
              isLoading: action.isLoading,
              onChoose: () =>
                  ref.read(subscriptionActionProvider.notifier).chooseTier(
                        SubscriptionTier.free,
                      ),
              cta: 'Stay a Member',
            ),
            const SizedBox(height: 12),
            _PlanCardForPeriod(
              tier: SubscriptionTier.standard,
              title: AppLocalizations.of(context).subscriptionSupporter,
              tagline:
                  'Funds the mission and unlocks long-term progress + reminders.',
              features: const [
                'Everything in Member',
                'Long-term progress charts',
                'Schedule + reminders',
                'Personalised "For you" feed',
                'Tax-deductible (501(c)(3) pending)',
              ],
              currentTier: tier,
              highlight: true,
              isLoading: action.isLoading,
              cta: 'Become a Supporter',
            ),
            const SizedBox(height: 12),
            _PlanCardForPeriod(
              tier: SubscriptionTier.celebrityTrainer,
              title: AppLocalizations.of(context).subscriptionSustainer,
              tagline:
                  'Powers celebrity-donated content + advanced analytics.',
              features: const [
                'Everything in Supporter',
                'Celebrity in-kind video donations',
                'AI form coach (when available)',
                'Body comp + advanced analytics',
                'Donor-wall recognition (opt-in)',
              ],
              currentTier: tier,
              isLoading: action.isLoading,
              cta: 'Become a Sustainer',
            ),
            const SizedBox(height: 16),
            _LearnMoreLink(),
          ],
          if (action.hasError) ...[
            const SizedBox(height: 12),
            _ErrorCard(
              error: action.error!,
              stackTrace: action.stackTrace,
            ),
          ],
        ],
      ),
    );
  }
}

enum _PageState { picker, trialing, paid }

class _MissionStrip extends StatelessWidget {
  const _MissionStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.volunteer_activism_outlined,
              color: scheme.onSurface.withValues(alpha: 0.85), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).subscriptionWeReANonprofitSubscriptionsAre,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LearnMoreLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () => GoRouter.of(context).push('/about'),
        icon: const Icon(Icons.info_outline_rounded, size: 18),
        label: Text(AppLocalizations.of(context).subscriptionLearnHowDonationsAreUsed),
      ),
    );
  }
}

/// Surfaces an action error with a Copy button so the user can paste the
/// full message + stack trace into a bug report.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  String _composePayload() {
    final buffer = StringBuffer()
      ..writeln('Could not update donation:')
      ..writeln(error.toString());
    if (stackTrace != null) {
      buffer
        ..writeln()
        ..writeln(stackTrace.toString());
    }
    return buffer.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      tint: scheme.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: scheme.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).subscriptionCouldNotUpdateDonation,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.error,
                  ),
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context).subscriptionCopyError,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.copy_rounded,
                    size: 18, color: scheme.error),
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: _composePayload()));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context).subscriptionErrorCopiedToClipboard),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            error.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.error,
              fontFamily: 'monospace',
            ),
          ),
          if (stackTrace != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  stackTrace.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error.withValues(alpha: 0.85),
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpgradeFromTrialCard extends StatelessWidget {
  const _UpgradeFromTrialCard({
    required this.tier,
    required this.isLoading,
    required this.onUpgrade,
  });

  final SubscriptionTier tier;
  final bool isLoading;
  final VoidCallback onUpgrade;

  /// Same reason as tierLabel: a getter cannot reach a BuildContext, so the
  /// localisations are passed in from build().
  String _labelFor(AppLocalizations l10n) {
    switch (tier) {
      case SubscriptionTier.standard:
        return '${l10n.subscriptionSupporter} · \$9.99 / month';
      case SubscriptionTier.celebrityTrainer:
        return '${l10n.subscriptionSustainer} · \$19.99 / month';
      case SubscriptionTier.free:
        return l10n.subscriptionMember;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      onTap: isLoading ? null : onUpgrade,
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
                    AppPalette.auroraPeach,
                    AppPalette.auroraPink,
                  ]),
                ),
                child: const Icon(Icons.workspace_premium_outlined,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continue as ${_labelFor(AppLocalizations.of(context))}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context).subscriptionTrialFeaturesStayOnPastThe,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraPeach,
                AppPalette.auroraPink,
              ]),
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      AppLocalizations.of(context).subscriptionContinueWithStripe,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagePlanCard extends StatelessWidget {
  const _ManagePlanCard({required this.isLoading, required this.onTap});
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      onTap: isLoading ? null : onTap,
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
                    AppPalette.auroraViolet,
                    AppPalette.auroraBlue,
                  ]),
                ),
                child: const Icon(Icons.sync_alt_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).subscriptionManageDonationUpdateCardOrPause,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context).subscriptionOpensTheSecureStripeDonorPortal,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraViolet,
                AppPalette.auroraBlue,
              ]),
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      AppLocalizations.of(context).subscriptionOpenDonorPortal,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.sub, required this.effectiveTier});
  final Subscription? sub;
  final SubscriptionTier effectiveTier;

  String _statusLabel(SubscriptionStatus s) {
    switch (s) {
      case SubscriptionStatus.none:
        return 'Not yet supporting';
      case SubscriptionStatus.trial:
        return 'Trial';
      case SubscriptionStatus.active:
        return 'Supporting';
      case SubscriptionStatus.cancelled:
        return 'Pausing at period end';
      case SubscriptionStatus.expired:
        return 'Lapsed';
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
                child: const Icon(Icons.favorite_outline,
                    color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      SubscriptionPage.tierLabel(
                          AppLocalizations.of(context), effectiveTier),
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
    this.cta = 'Choose',
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
  final String cta;

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
                            child: Text(
                              AppLocalizations.of(context).subscriptionCurrent,
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
                              AppLocalizations.of(context).subscriptionPopular,
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
                    child: Text(AppLocalizations.of(context).subscription14DayTrial),
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
                  child: Text(isCurrent ? 'Current' : cta),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Period toggle pill row (Monthly / Annual / Family / Lifetime).
/// Lifetime is hidden for Standard tier; Family is hidden for Celebrity.
/// We show all four and rely on `_PlanCardForPeriod` to no-op the
/// unsupported combinations gracefully.
class _PeriodToggle extends ConsumerWidget {
  const _PeriodToggle();

  static const _periods = SubscriptionPeriod.values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedPeriodProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in _periods) ...[
            _PeriodPill(
              label: _shortLabel(p),
              isActive: p == selected,
              onTap: () =>
                  ref.read(selectedPeriodProvider.notifier).state = p,
              isPopular: p == SubscriptionPeriod.annual,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  String _shortLabel(SubscriptionPeriod p) {
    switch (p) {
      case SubscriptionPeriod.monthly:
        return 'Monthly';
      case SubscriptionPeriod.annual:
        return 'Annual · save ~50%';
      case SubscriptionPeriod.family2:
        return 'Family · 2';
      case SubscriptionPeriod.family4:
        return 'Family · 4';
      case SubscriptionPeriod.lifetime:
        return 'Lifetime';
    }
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isPopular = false,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isPopular;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isActive
              ? Colors.white
              : Colors.white.withValues(alpha: 0.30),
          border: isPopular && !isActive
              ? Border.all(color: AppPalette.auroraTeal, width: 1.4)
              : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: isActive
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.78),
          ),
        ),
      ),
    );
  }
}

/// Wrapper around [_PlanCard] that derives the price string + decides
/// whether the plan is purchasable for the currently-selected period.
/// Returns an empty SizedBox when the (tier, period) combo is invalid
/// (e.g. Family on Celebrity, Lifetime on Standard).
class _PlanCardForPeriod extends ConsumerWidget {
  const _PlanCardForPeriod({
    required this.tier,
    required this.title,
    required this.tagline,
    required this.features,
    required this.currentTier,
    required this.isLoading,
    required this.cta,
    this.highlight = false,
  });

  final SubscriptionTier tier;
  final String title;
  final String tagline;
  final List<String> features;
  final SubscriptionTier currentTier;
  final bool isLoading;
  final String cta;
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(selectedPeriodProvider);
    final price = _priceLabelFor(tier, period);
    if (price == null) {
      // Unsupported combo — render a small note instead of hiding so the
      // user understands why the card "disappeared".
      final theme = Theme.of(context);
      return GlassCard(
        padding: const EdgeInsets.all(14),
        child: Text(
          '$title is not available on ${period.displayLabel}.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );
    }
    return _PlanCard(
      tier: tier,
      title: title,
      price: price,
      tagline: tagline,
      features: features,
      currentTier: currentTier,
      highlight: highlight,
      isLoading: isLoading,
      onChoose: () => ref
          .read(subscriptionActionProvider.notifier)
          .chooseTier(tier, period: period),
      onStartTrial: period == SubscriptionPeriod.monthly
          ? () => ref
              .read(subscriptionActionProvider.notifier)
              .startTrial(tier)
          : null,
      cta: cta,
    );
  }

  /// Hard-coded price strings per (tier, period). Single source of truth
  /// for what the picker advertises; the actual amounts are enforced
  /// server-side by the Stripe price ids the Cloud Function looks up.
  String? _priceLabelFor(SubscriptionTier t, SubscriptionPeriod p) {
    if (t == SubscriptionTier.standard) {
      switch (p) {
        case SubscriptionPeriod.monthly:
          return r'$9.99 / month · tax-deductible';
        case SubscriptionPeriod.annual:
          return r'$59.99 / year · ~$5/mo effective';
        case SubscriptionPeriod.family2:
          return r'$14.99 / month · 2 seats';
        case SubscriptionPeriod.family4:
          return r'$19.99 / month · 4 seats';
        case SubscriptionPeriod.lifetime:
          return null;
      }
    }
    switch (p) {
      case SubscriptionPeriod.monthly:
        return r'$19.99 / month · tax-deductible';
      case SubscriptionPeriod.annual:
        return r'$119.99 / year · ~$9.99/mo effective';
      case SubscriptionPeriod.lifetime:
        return r'$499 lifetime · one-time donor';
      case SubscriptionPeriod.family2:
      case SubscriptionPeriod.family4:
        return null;
    }
  }
}
