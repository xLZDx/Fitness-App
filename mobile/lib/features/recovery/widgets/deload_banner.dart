import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../deload_signal_text.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/glass.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/state/subscription_providers.dart';
import '../state/recovery_providers.dart';
import '../../../shared/widgets/app_buttons.dart';

/// Banner shown above the Today card when [detectDeload] flags the user
/// as needing recovery. Gated to Standard tier and above — the free
/// tier sees a "preview" version that points to the donation page.
class DeloadBanner extends ConsumerWidget {
  const DeloadBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verdict = ref.watch(deloadVerdictProvider);
    if (!verdict.shouldDeload) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tier = ref.watch(effectiveTierProvider);
    final isPremium = tier != SubscriptionTier.free;
    final action = ref.watch(deloadActionProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      // INTENTIONAL_LEGACY_EXCEPTION (HUD migration census,
      // core/plans/HUD_MIGRATION_CENSUS_2026-08-29.md): needs a flat
      // `tint` fill, the same capability gap already recorded for
      // scanner_page.dart's error cards -- neither HudPanel nor HudSurface
      // exposes a plain Color? override today.
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        tint: AppPalette.auroraPeach,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: const LinearGradient(colors: [
                      AppPalette.auroraPeach,
                      AppPalette.auroraPink,
                    ]),
                  ),
                  child: const Icon(Icons.bedtime_outlined,
                      color: AppSemanticColors.onGradientInk, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).recoveryAutoDeloadRecommended,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        verdict.reasons.isEmpty
                            ? AppLocalizations.of(context)
                                .recoveryDeloadGenericSignal
                            : deloadSignalText(AppLocalizations.of(context),
                                verdict.reasons.first),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (isPremium) ...[
                  Expanded(
                    child: AppPrimaryButton(
                      loading: action.isLoading,
                      onPressed: () => ref
                          .read(deloadActionProvider.notifier)
                          .acceptNext7Days(),
                      icon: Icons.check_rounded,
                      label: action.isLoading
                          ? AppLocalizations.of(context).recoveryApplying
                          : 'Accept deload (50% volume × 7d)',
                    ),
                  ),
                ] else if (ref.watch(entitlementResolvedProvider)) ...[
                  Expanded(
                    child: AppSecondaryButton(
                      onPressed: () =>
                          GoRouter.of(context).push('/subscription'),
                      icon: Icons.lock_outline,
                      label: AppLocalizations.of(context)
                          .recoveryBecomeASupporterToUnlock,
                    ),
                  ),
                ],
                // Third case, deliberately empty: the plan is not known yet.
                // The banner's advice above is worth reading on its own, and a
                // "become a supporter" button under it — shown to somebody who
                // already is one — is not.
              ],
            ),
            if (action.hasError) ...[
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).recoveryCouldNotApplyDeload(action.error ?? ''),
                style:
                    theme.textTheme.labelSmall?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
