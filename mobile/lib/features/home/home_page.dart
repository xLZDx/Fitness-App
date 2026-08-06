import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/health/widgets/health_sync_card.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../moments/data/moment.dart';
import '../moments/state/moment_providers.dart';
import '../moments/widgets/day3_welcome_modal.dart';
import '../progress/data/progress_stats.dart';
import '../recovery/widgets/deload_banner.dart';
import '../workouts/state/session_screening_providers.dart';
import '../workouts/state/workout_log_providers.dart';
import 'data/suggestion_builder.dart';
import 'state/suggestion_providers.dart';
import '../equipment/widgets/exercise_thumb.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _maybeShowDay3Triggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_maybeShowDay3Triggered || !mounted) return;
      _maybeShowDay3Triggered = true;
      final repo = ref.read(momentRepositoryProvider);
      await repo.bumpLaunchCount();
      final shown = await repo.hasShown(MomentId.day3Welcome);
      final launches = await repo.launchCount();
      final firstLaunch = await repo.firstLaunchAt();
      final ok = shouldShowDay3Welcome(
        accountCreatedAt: firstLaunch ?? DateTime.now(),
        launchCount: launches,
        alreadyShown: shown,
      );
      if (!ok || !mounted) return;
      await Day3WelcomeModal.show(context);
      await repo.markShown(MomentId.day3Welcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final logs = ref.watch(workoutLogsProvider).valueOrNull ?? const [];
    // See the note in progress_page: `logs` is a window, the totals are not.
    final stats = deriveProgress(
      logs,
      totals: ref.watch(workoutTotalsProvider).valueOrNull,
    );
    // Screened, not merely filtered by date: a session is a snapshot of what
    // was safe when it was scheduled, and the user's injuries can have changed
    // since. Empty while the catalog and profile resolve, which is the same
    // empty the stream itself starts from.
    final upcoming = ref.watch(screenedUpcomingSessionsProvider).valueOrNull ??
        const <ScreenedSession>[];

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).homeHome),
      body: SmoothScrollList(
        padding: const EdgeInsets.fromLTRB(20, 88, 20, 110),
        children: [
          _HeroCard(),
          const SizedBox(height: 16),
          const _AiPlanCard(),
          const SizedBox(height: 16),
          const HealthSyncCard(),
          const SizedBox(height: 12),
          const DeloadBanner(),
          _SectionHeader(l10n.homeSectionToday),
          const SizedBox(height: 12),
          _TodayCard(upcoming: upcoming),
          if (upcoming.length > 1) ...[
            const SizedBox(height: 24),
            _SectionHeader(l10n.homeSectionUpcoming),
            const SizedBox(height: 12),
            for (final s in upcoming.skip(1).take(3)) ...[
              _UpcomingCard(screened: s),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 32),
          _SectionHeader(l10n.homeSectionQuickStats),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: AppLocalizations.of(context).homeWorkouts,
                  value: '${stats.total}',
                  gradient: AppPalette.tileGradients[0],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: AppLocalizations.of(context).homeStreak,
                  value: l10n.homeStreakDays(stats.currentStreakDays),
                  gradient: AppPalette.tileGradients[1],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: AppLocalizations.of(context).homeThisWeek,
                  value: '${stats.thisWeek}',
                  gradient: AppPalette.tileGradients[2],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _SectionHeader(l10n.homeSectionSuggestions),
          const SizedBox(height: 14),
          ...ref.watch(suggestionsProvider).when(
                loading: () => const [_SuggestionsPlaceholder()],
                error: (e, _) =>
                    [_SuggestionsMessage(l10n.homeCouldNotLoad('$e'))],
                data: (list) => list.isEmpty
                    ? [_SuggestionsMessage(l10n.homeSuggestionsEmpty)]
                    : [
                        for (var i = 0; i < list.length; i++) ...[
                          _SuggestionCard(
                            list[i],
                            gradient: AppPalette.tileGradients[
                                i % AppPalette.tileGradients.length],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
              ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleLarge?.copyWith(
        color: theme.colors.textSecondary,
      ),
    );
  }
}

class _GradientTile extends StatelessWidget {
  const _GradientTile({required this.icon, required this.gradient});
  final IconData icon;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(colors: gradient),
      ),
      child: Icon(icon, color: AppSemanticColors.onGradientInk),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.upcoming});
  final List<ScreenedSession> upcoming;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (upcoming.isEmpty) {
      return GlassCard(
        child: Row(
          children: [
            _GradientTile(
              icon: Icons.event_outlined,
              gradient: const [
                AppPalette.auroraTeal,
                AppPalette.auroraLime,
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.of(context).homeNoWorkoutsScheduled,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context).homePickAPlanOrScanA,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final screened = upcoming.first;
    final next = screened.session;
    return GlassCard(
      onTap: () => GoRouter.of(context).push('/workout/${next.exerciseId}'),
      child: Row(
        children: [
          _GradientTile(
            icon: screened.hiddenForInjury
                ? Icons.report_problem_outlined
                : Icons.event_available_outlined,
            gradient: screened.hiddenForInjury
                ? const [AppPalette.auroraPeach, AppPalette.auroraPink]
                : const [
                    AppPalette.auroraViolet,
                    AppPalette.auroraBlue,
                  ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(next.exerciseTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  screened.hiddenForInjury
                      ? l10n.equipmentScheduledHiddenForInjury
                      : AppLocalizations.of(context).notificationsMin(
                          formatScheduleLabel(l10n, next.scheduledFor),
                          next.durationMinutes),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: screened.hiddenForInjury
                        ? scheme.error
                        : theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: theme.colors.textSecondary),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.screened});
  final ScreenedSession screened;

  @override
  Widget build(BuildContext context) {
    final session = screened.session;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () => GoRouter.of(context).push('/workout/${session.exerciseId}'),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(
                colors: AppPalette.tileGradients[
                    session.exerciseId.hashCode.abs() %
                        AppPalette.tileGradients.length],
              ),
            ),
            child: const Icon(Icons.event_outlined,
                color: AppSemanticColors.onGradientInk, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(session.exerciseTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  screened.hiddenForInjury
                      ? l10n.equipmentScheduledHiddenForInjury
                      : AppLocalizations.of(context).notificationsMin(
                          formatScheduleLabel(l10n, session.scheduledFor),
                          session.durationMinutes),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: screened.hiddenForInjury
                        ? scheme.error
                        : theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A friendly schedule label: "Today 07:00", "Tomorrow 18:30", "Wed 14:00",
/// or "May 20 · 09:00" beyond the next week.
///
/// The weekday and month names come from `intl` and the locale, not from two
/// hard-coded English arrays. Nineteen names in an ARB file would have worked
/// for Russian and then been wrong for the next language, and wrong in a way
/// nobody would notice: Russian dates decline, and "20 мая" is not "мая 20".
/// `DateFormat` already knows that for every locale Flutter ships.
String formatScheduleLabel(AppLocalizations l10n, DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final target = DateTime(t.year, t.month, t.day);
  final diff = target.difference(today).inDays;
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  final time = '$hh:$mm';
  final locale = l10n.localeName;

  if (diff == 0) return l10n.homeScheduleToday(time);
  if (diff == 1) return l10n.homeScheduleTomorrow(time);
  if (diff > 1 && diff < 7) {
    return l10n.homeScheduleWeekday(DateFormat.E(locale).format(t), time);
  }
  return l10n.homeScheduleDate(DateFormat.MMMd(locale).format(t), time);
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard(this.s, {required this.gradient});
  final WorkoutSuggestion s;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      key: Key('suggestion-${s.exerciseId}'),
      padding: const EdgeInsets.all(14),
      // Opens the real exercise. This was `() {}` — the cards looked
      // interactive and led nowhere.
      onTap: () => GoRouter.of(context).push('/workout/${s.exerciseId}'),
      child: Row(
        children: [
          // Only a suggestion id is in scope here, not a catalog row, so
          // this renders the fallback tile — but through the shared widget,
          // so it is the same shape and radius as everywhere else.
          const ExerciseThumb(exercise: null, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.of(context)
                          .equipmentMin(s.durationMinutes),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  s.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionsPlaceholder extends StatelessWidget {
  const _SuggestionsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: SizedBox(
        height: 64,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

/// Honest empty/error state. Better than five plausible-looking cards that
/// were never based on anything.
class _SuggestionsMessage extends StatelessWidget {
  const _SuggestionsMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      key: const Key('suggestions-empty'),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colors.textSecondary,
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppPalette.auroraTeal,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).homeGoodMorning,
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: theme.colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).homeReadyToTrain,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).homeScanAMachineOrPickA,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => GoRouter.of(context).go('/scan'),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(colors: [
                  AppPalette.auroraViolet,
                  AppPalette.auroraBlue,
                ]),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.auroraBlue.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      color: AppSemanticColors.onGradientInk),
                  SizedBox(width: 10),
                  Text(
                    AppLocalizations.of(context).homeScanEquipment,
                    style: TextStyle(
                      color: AppSemanticColors.onGradientInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.gradient,
  });

  final String label;
  final String value;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(colors: gradient),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// "Today's plan" CTA. Routes to the AI workout generator. The killer
/// feature was hidden behind a URL until this card existed.
class _AiPlanCard extends StatelessWidget {
  const _AiPlanCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: () => GoRouter.of(context).push('/plan'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
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
                Text(
                  AppLocalizations.of(context).homeTodaySAdaptivePlan,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context)
                      .homeBuiltFromYourIntakeRatingsAnd,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: theme.colors.textSecondary),
        ],
      ),
    );
  }
}
