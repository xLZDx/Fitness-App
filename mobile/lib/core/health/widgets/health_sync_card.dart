import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../shared/widgets/glass.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_semantic_colors.dart';
import '../health_models.dart';
import '../state/health_providers.dart';

/// Today's steps + activity-ring percent + sleep score.
/// Renders three states:
///   1. Permission not granted yet → ask CTA.
///   2. Granted but no data           → empty hint.
///   3. Granted with data             → 3-stat row.
class HealthSyncCard extends ConsumerWidget {
  const HealthSyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(healthAuthStatusProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (status) {
        if (status == HealthAuthStatus.unsupported) {
          // Unsupported has two very different meanings. On Android it usually
          // means Health Connect is missing or stale, which the user can fix —
          // so say so and offer the install. Elsewhere (web, desktop) health
          // data will never exist and a card would be noise. Hiding both cases
          // is why "Health Connect does not work" came with a blank screen.
          final fixable =
              ref.watch(healthSetupRequiredProvider).valueOrNull ?? false;
          if (!fixable) return const SizedBox.shrink();
          return _SetupCard(
            message: ref.watch(healthServiceProvider).lastErrorMessage ??
                'Health Connect is needed to sync steps, sleep and recovery.',
            onOpen: () =>
                ref.read(healthServiceProvider).openPlatformSetup(),
          );
        }
        if (status != HealthAuthStatus.granted) {
          return _AskCard(
            isLoading: ref.watch(healthAuthActionProvider).isLoading,
            errorText: ref.watch(healthAuthErrorProvider),
            onAsk: () =>
                ref.read(healthAuthActionProvider.notifier).request(),
          );
        }
        return ref.watch(todayHealthProvider).when(
              loading: () => const _LoadingTile(),
              error: (e, _) => GlassCard(
                tint: scheme.error,
                child: Text(AppLocalizations.of(context).healthHealthReadFailed(e),
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
              ),
              data: (snapshot) => _SnapshotCard(snapshot: snapshot),
            );
      },
    );
  }
}

class _AskCard extends StatelessWidget {
  const _AskCard({
    required this.isLoading,
    required this.onAsk,
    this.errorText,
  });
  final bool isLoading;
  final VoidCallback onAsk;

  /// Failure reason from the last authorization attempt (null = none).
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                    AppPalette.auroraTeal,
                    AppPalette.auroraLime,
                  ]),
                ),
                child: const Icon(Icons.monitor_heart_outlined,
                    color: AppSemanticColors.onGradientInk, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).healthSyncWithHealth,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context).healthSeeStepsSleepRecoveryHereCompleted,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isLoading ? null : onAsk,
              icon: isLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        // A FilledButton's foreground is `onPrimary`. White was
                        // right only for as long as `onPrimary` happened to be
                        // white, and nothing tied the two together.
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.onPrimary),
                      ),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(isLoading
                  ? AppLocalizations.of(context).healthAsking
                  : AppLocalizations.of(context).healthConnectHealth),
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).healthHealthConnectFailed(errorText!),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown when health data is unavailable for a reason the user can act on.
class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.message, required this.onOpen});

  final String message;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      key: const Key('health-setup-card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).healthHealthConnectRequired,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('health-setup-open'),
              onPressed: onOpen,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(AppLocalizations.of(context).healthGetHealthConnect),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();
  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: SizedBox(
        height: 72,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.snapshot});
  final HealthSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (snapshot == null) {
      return GlassCard(
        child: Text(
          AppLocalizations.of(context).healthNoHealthDataForTodayYet,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colors.textSecondary,
          ),
        ),
      );
    }
    final s = snapshot!;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).healthTodaySRecovery,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: AppLocalizations.of(context).healthSteps,
                  value: s.steps == null ? '--' : '${s.steps}',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: AppLocalizations.of(context).healthRing,
                  value: s.activityRingPercent == null
                      ? '--'
                      : '${s.activityRingPercent}%',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: AppLocalizations.of(context).healthSleep,
                  value: s.sleepScore == null ? '--' : '${s.sleepScore}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colors.textSecondary,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
