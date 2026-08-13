import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../equipment/data/catalog_labels.dart';
import '../equipment/state/equipment_providers.dart';
import '../workouts/data/day_result.dart';
import '../workouts/state/day_result_providers.dart';
import '../workouts/state/session_digest_providers.dart';

/// What the user just did, at the end of doing it.
///
/// ## What this screen does NOT show, and why
///
/// The design (`App.tsx:4620-4721`) has seven blocks. Four of them ship here:
/// the hero, the four numbers, the muscle bars and the next workout. Three do
/// not, and the reason is the same in each case — the app has no data for
/// them, and a summary that invents its own content is worse than a shorter
/// one:
///
///   * **"Личный рекорд!"** — needs a per-exercise best across history to
///     compare against. That comparison is real work (and belongs with the
///     progress charts of R6), not a badge that fires on a guess.
///   * **"Техника выполнения"** — three sentences about the user's form. The
///     technique coach records nothing against a session; there is no source
///     for these, and writing plausible ones would be fabricating feedback
///     about the user's own body.
///   * **"Ощущение нагрузки"** (RPE 1-5) — `WorkoutSessionExercise` carries a
///     `difficulty`, but per exercise, not per session, and it is captured
///     during the workout rather than after it. A session-level field is a
///     migration on live data, which is its own gate.
///
/// The design's "48-72 ч восстановления" line is dropped for the same reason:
/// it is a physiological claim, and this app has no basis for one.
class WorkoutSummaryPage extends ConsumerWidget {
  const WorkoutSummaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final result = ref.watch(todayResultProvider);

    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.summaryTitle),
      body: SmoothScrollList(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: result.isEmpty
            ? [_EmptyDay(l10n: l10n)]
            : [
                _Hero(result: result, l10n: l10n),
                const SizedBox(height: 20),
                _Stats(result: result, l10n: l10n),
                const SizedBox(height: 16),
                if (result.muscleShare.isNotEmpty) ...[
                  _MuscleLoad(result: result, l10n: l10n),
                  const SizedBox(height: 16),
                ],
                const _NextWorkout(),
                const SizedBox(height: 24),
                AppPrimaryButton(
                  key: const Key('summary.home'),
                  onPressed: () => GoRouter.of(context).go('/'),
                  label: l10n.summaryGoHome,
                ),
              ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.summaryNothingToday,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            l10n.summaryNothingTodayHint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.result, required this.l10n});
  final DayResult result;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The muscles the day was mostly about. Empty when nothing scheduled is in
    // the catalogue any more, in which case the headline stands alone rather
    // than trailing an empty line.
    final muscles =
        result.muscles.map((m) => CatalogLabels.muscle(l10n, m)).join(', ');

    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppPalette.auroraTeal, AppPalette.auroraLime],
            ),
          ),
          child: const Icon(Icons.check_rounded,
              size: 40, color: AppSemanticColors.onGradientInk),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.summaryDone,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        if (muscles.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            muscles,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.result, required this.l10n});
  final DayResult result;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // The weight tile is dropped rather than shown as "0" when nothing was
    // weighted: a bodyweight session is not a session that moved no load, and
    // a zero in a row of achievements reads as failure.
    final tiles = <(String, String)>[
      ('${result.totalMinutes}', l10n.summaryUnitMinutes),
      ('${result.exerciseCount}', l10n.summaryUnitExercises),
      ('${result.setCount}', l10n.summaryUnitSets),
      if (result.hasWeights)
        (_kg(result.volumeKg), l10n.summaryUnitKilograms),
    ];

    return Row(
      children: [
        for (final (value, label) in tiles) ...[
          Expanded(child: _StatTile(value: value, label: label)),
          if (label != tiles.last.$2) const SizedBox(width: 8),
        ],
      ],
    );
  }

  /// Whole kilograms. A tenth of a kilogram of total volume is noise, and
  /// "4820.0" is harder to read at a glance than "4820".
  static String _kg(double v) => v.round().toString();
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppPalette.auroraViolet,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colors.textSecondary)),
        ],
      ),
    );
  }
}

class _MuscleLoad extends StatelessWidget {
  const _MuscleLoad({required this.result, required this.l10n});
  final DayResult result;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Ranked the same way as `muscles`, but showing everything worked rather
    // than the headline's three: the bars are a breakdown, and a breakdown
    // that hides rows is not one.
    final entries = result.muscleShare.entries.toList()
      ..sort((a, b) {
        final byShare = b.value.compareTo(a.value);
        return byShare != 0 ? byShare : a.key.compareTo(b.key);
      });

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.summaryMuscleLoad,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final e in entries) ...[
            Row(
              children: [
                Expanded(
                  child: Text(CatalogLabels.muscle(l10n, e.key),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colors.textSecondary)),
                ),
                Text('${(e.value * 100).round()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: e.value,
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation(
                    AppPalette.auroraViolet),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _NextWorkout extends ConsumerWidget {
  const _NextWorkout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The same digest Home's hero reads, so "what is next" has one answer in
    // the app rather than two that can disagree.
    final next = ref.watch(todayDigestProvider);
    if (next.isEmpty) return const SizedBox.shrink();

    final muscles =
        next.muscles.map((m) => CatalogLabels.muscle(l10n, m)).join(', ');

    return GlassCard(
      onTap: () => GoRouter.of(context)
          .push('/workout/${next.sessions.first.exerciseId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.summaryNextWorkout,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: AppPalette.auroraViolet,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            muscles.isEmpty
                ? resolveExerciseTitle(
                    ref.watch(exerciseTitlesProvider),
                    next.sessions.first.exerciseId,
                    next.sessions.first.exerciseTitle)
                : muscles,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.homeTodayDigest(next.exerciseCount, next.totalMinutes),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
