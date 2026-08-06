import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/glass.dart';
import 'data/subscription_models.dart';
import 'state/subscription_providers.dart';

/// "Support the mission" page (formerly Subscription).
///
/// The Stripe billing model is unchanged — three tiers, monthly recurring,
/// 14-day trial.
///
/// S0b removed the donation/nonprofit framing this copy used to carry.
/// There is no 501(c)(3) and no fiscal sponsorship, so calling a paid
/// subscription a "tax-deductible recurring donation" was a claim the
/// buyer could act on and be wrong about. These are subscriptions.
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sub = ref.watch(currentSubscriptionProvider).valueOrNull;
    final tier = ref.watch(effectiveTierProvider);
    final action = ref.watch(subscriptionActionProvider);
    final state = _stateFor(sub);

    return FrostedScaffold(
      appBar: GlassAppBar(
          title: AppLocalizations.of(context).aboutSupportTheMission),
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
              onUpgrade: () => ref
                  .read(subscriptionActionProvider.notifier)
                  .chooseTier(sub.tier),
            ),
          ] else ...[
            Text(
              AppLocalizations.of(context).subscriptionChooseAWayToSupport,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)
                  .subscriptionEveryLevelKeepsTheAppFree,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            const _PeriodToggle(),
            const SizedBox(height: 12),
            _PlanCard(
              tier: SubscriptionTier.free,
              title: AppLocalizations.of(context).subscriptionMember,
              price: l10n.subFreeForever,
              tagline: l10n.subMemberTagline,
              features: [
                l10n.subFeatureLibrary,
                l10n.subFeatureInjuryFilter,
                l10n.subFeatureLogging,
                l10n.subFeatureQr,
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
              tagline: l10n.subSupporterTagline,
              features: [
                l10n.subFeatureAllMember,
                l10n.subFeatureLongProgress,
                l10n.subFeatureSchedule,
                l10n.subFeatureForYou,
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
              tagline: l10n.subSustainerTagline,
              features: [
                l10n.subFeatureAllSupporter,
                l10n.subFeatureCelebrity,
                l10n.subFeatureFormCoach,
                l10n.subFeatureBodyComp,
                l10n.subFeatureDonorWall,
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
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.volunteer_activism_outlined,
              color: theme.colors.textSecondary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context)
                  .subscriptionWeReANonprofitSubscriptionsAre,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colors.textSecondary,
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
      child: AppTertiaryButton(
        onPressed: () => GoRouter.of(context).push('/about'),
        icon: Icons.info_outline_rounded,
        label:
            AppLocalizations.of(context).subscriptionLearnHowDonationsAreUsed,
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
    // Deliberately English and deliberately not localized: this is the text
    // the Copy button puts on the clipboard for a bug report, printed above a
    // stack trace. A Russian header on an English stack trace helps nobody.
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
                  AppLocalizations.of(context)
                      .subscriptionCouldNotUpdateDonation,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.error,
                  ),
                ),
              ),
              AppIconButton(
                tooltip: AppLocalizations.of(context).subscriptionCopyError,
                tone: AppButtonTone.destructive,
                size: AppButtonSize.compact,
                icon: Icons.copy_rounded,
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: _composePayload()));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)
                          .subscriptionErrorCopiedToClipboard),
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
                    color: AppSemanticColors.onGradientInk, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).subscriptionContinueAs(
                          _labelFor(AppLocalizations.of(context))),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)
                          .subscriptionTrialFeaturesStayOnPastThe,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.textSecondary,
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
                        valueColor: AlwaysStoppedAnimation<Color>(AppSemanticColors.onGradientInk),
                      ),
                    )
                  : Text(
                      AppLocalizations.of(context)
                          .subscriptionContinueWithStripe,
                      style: TextStyle(
                        color: AppSemanticColors.onGradientInk,
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
                    color: AppSemanticColors.onGradientInk, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)
                          .subscriptionManageDonationUpdateCardOrPause,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)
                          .subscriptionOpensTheSecureStripeDonorPortal,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.textSecondary,
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
                        valueColor: AlwaysStoppedAnimation<Color>(AppSemanticColors.onGradientInk),
                      ),
                    )
                  : Text(
                      AppLocalizations.of(context).subscriptionOpenDonorPortal,
                      style: TextStyle(
                        color: AppSemanticColors.onGradientInk,
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

  String _statusLabel(AppLocalizations l10n, SubscriptionStatus s) {
    switch (s) {
      case SubscriptionStatus.none:
        return l10n.subStatusNone;
      case SubscriptionStatus.trial:
        return l10n.subStatusTrial;
      case SubscriptionStatus.active:
        return l10n.subStatusActive;
      case SubscriptionStatus.cancelled:
        return l10n.subStatusCancelling;
      case SubscriptionStatus.expired:
        return l10n.subStatusExpired;
    }
  }

  String? _expiryLabel(AppLocalizations l10n) {
    final s = sub;
    if (s == null) return null;
    final endsAt = s.status == SubscriptionStatus.trial
        ? s.trialEndsAt
        : s.currentPeriodEndsAt;
    if (endsAt == null) return null;
    final daysLeft = endsAt.difference(DateTime.now()).inDays;
    if (daysLeft < 0) return l10n.subLapsedDaysAgo(-daysLeft);
    if (daysLeft == 0) return l10n.subEndsToday;
    if (daysLeft == 1) return l10n.subEndsTomorrow;
    return l10n.subEndsInDays(daysLeft);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final expiry = _expiryLabel(l10n);
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
                child: const Icon(Icons.favorite_outline, color: AppSemanticColors.onGradientInk),
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
                          l10n, sub?.status ?? SubscriptionStatus.none),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.textSecondary,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                                color: AppSemanticColors.onGradientInk,
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
                                color: theme.colors.textSecondary,
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
                          color: theme.colors.textSecondary,
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
                color: theme.colors.textSecondary,
              )),
          const SizedBox(height: 14),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 18, color: scheme.onSurface),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (onStartTrial != null) ...[
                Expanded(
                  child: AppSecondaryButton(
                    onPressed: isLoading ? null : onStartTrial,
                    size: AppButtonSize.compact,
                    label:
                        AppLocalizations.of(context).subscription14DayTrial,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: AppPrimaryButton(
                  onPressed: (isLoading || isCurrent) ? null : onChoose,
                  size: AppButtonSize.compact,
                  // 'Current' is a pre-existing hardcoded literal, not from
                  // this gate -- untouched, noted rather than silently fixed
                  // (out of scope for a button-component migration).
                  label: isCurrent ? 'Current' : cta,
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
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(selectedPeriodProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in _periods) ...[
            _PeriodPill(
              label: _shortLabel(l10n, p),
              isActive: p == selected,
              onTap: () => ref.read(selectedPeriodProvider.notifier).state = p,
              isPopular: p == SubscriptionPeriod.annual,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  String _shortLabel(AppLocalizations l10n, SubscriptionPeriod p) {
    switch (p) {
      case SubscriptionPeriod.monthly:
        return l10n.subPeriodMonthly;
      case SubscriptionPeriod.annual:
        return l10n.subPeriodAnnual;
      case SubscriptionPeriod.family2:
        return l10n.subPeriodFamily2;
      case SubscriptionPeriod.family4:
        return l10n.subPeriodFamily4;
      case SubscriptionPeriod.lifetime:
        return l10n.subPeriodLifetime;
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
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.30),
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
                : theme.colors.textSecondary,
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
    final l10n = AppLocalizations.of(context);
    final period = ref.watch(selectedPeriodProvider);
    final price = _priceLabelFor(l10n, tier, period);
    if (price == null) {
      // Unsupported combo — render a small note instead of hiding so the
      // user understands why the card "disappeared".
      final theme = Theme.of(context);
      return GlassCard(
        padding: const EdgeInsets.all(14),
        child: Text(
          AppLocalizations.of(context)
              .subscriptionIsNotAvailableOn(
                  title, period.label(AppLocalizations.of(context))),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colors.textSecondary,
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
          ? () => ref.read(subscriptionActionProvider.notifier).startTrial(tier)
          : null,
      cta: cta,
    );
  }

  /// Hard-coded price strings per (tier, period). Single source of truth
  /// for what the picker advertises; the actual amounts are enforced
  /// server-side by the Stripe price ids the Cloud Function looks up.
  String? _priceLabelFor(
      AppLocalizations l10n, SubscriptionTier t, SubscriptionPeriod p) {
    if (t == SubscriptionTier.standard) {
      switch (p) {
        case SubscriptionPeriod.monthly:
          return l10n.subPriceMonth(r'$9.99');
        case SubscriptionPeriod.annual:
          return l10n.subPriceYearEffective(r'$59.99', r'$5');
        case SubscriptionPeriod.family2:
          return l10n.subPriceMonthSeats(r'$14.99', 2);
        case SubscriptionPeriod.family4:
          return l10n.subPriceMonthSeats(r'$19.99', 4);
        case SubscriptionPeriod.lifetime:
          return null;
      }
    }
    switch (p) {
      case SubscriptionPeriod.monthly:
        return l10n.subPriceMonth(r'$19.99');
      case SubscriptionPeriod.annual:
        return l10n.subPriceYearEffective(r'$119.99', r'$9.99');
      case SubscriptionPeriod.lifetime:
        return l10n.subPriceLifetime(r'$499');
      case SubscriptionPeriod.family2:
      case SubscriptionPeriod.family4:
        return null;
    }
  }
}
