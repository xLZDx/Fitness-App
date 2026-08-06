import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/glass.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/state/subscription_providers.dart';
import '../state/recovery_providers.dart';

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
                            ? "Recovery signals are pointing toward a "
                                "lighter week."
                            : verdict.reasons.first,
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
                    child: FilledButton.icon(
                      onPressed: action.isLoading
                          ? null
                          : () => ref
                              .read(deloadActionProvider.notifier)
                              .acceptNext7Days(),
                      icon: action.isLoading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                // Same as the health card: the button's own
                                // foreground, not a white that only coincided
                                // with it.
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.onPrimary),
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        action.isLoading
                            ? AppLocalizations.of(context).recoveryApplying
                            : 'Accept deload (50% volume × 7d)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          GoRouter.of(context).push('/subscription'),
                      icon: const Icon(Icons.lock_outline, size: 16),
                      label: Text(
                        AppLocalizations.of(context).recoveryBecomeASupporterToUnlock,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
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
