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
import '../auth/state/auth_providers.dart';
import '../moments/data/moment.dart';
import '../moments/state/moment_providers.dart';
import '../moments/widgets/day3_welcome_modal.dart';
import '../recovery/widgets/deload_banner.dart';
import '../equipment/data/catalog_labels.dart';
import '../workouts/data/session_digest.dart';
import '../workouts/state/day_result_providers.dart';
import '../workouts/state/session_digest_providers.dart';
import '../workouts/state/session_screening_providers.dart';
import 'data/home_dashboard.dart';
import 'data/suggestion_builder.dart';
import 'state/home_dashboard_providers.dart';
import 'state/suggestion_providers.dart';
import '../equipment/widgets/exercise_thumb.dart';

/// Home, rebuilt at R11a against the real design source.
///
/// The screen this replaces was never built from the Figma Make prototype: R1-R4
/// were scoped from an audit document's prose retelling of the design, and R9
/// recoloured the result. The operator's own words on seeing it on a device —
/// *"это не похоже на дизайн с фигмы, это старый дизайн только лайма
/// добавили"* — are the reason this gate exists.
///
/// The structure below follows `HomeScreen` in the prototype
/// (`xLZDx/ReviewExistingExamples` @ `8209787`, `src/App.tsx:2441-2548`):
/// greeting header → plan progress → today hero → quick scan → recovery strip →
/// week strip + three totals.
///
/// **Two deliberate departures, both because the alternative would be
/// fabrication:**
///
/// * The prototype's header carries a notification bell. There is no
///   notifications route in this app (`app_router.dart` registers 27 paths and
///   none of them is one), so the bell would be a control that does nothing.
/// * The prototype's progress bar reads "Силовая база · Неделя 2 из 8" — a
///   multi-week programme. No programme entity exists here; see
///   [derivePlanProgress] for what the bar shows instead and why.
///
/// The app's own entry points that the prototype has no equivalent for (AI
/// plan, posture check, health sync, suggestions) are kept, moved below the
/// design's spine under their own heading. Deleting them to match the
/// prototype more closely would strand four working features.
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
    final upcoming = ref.watch(screenedUpcomingSessionsProvider).valueOrNull ??
        const <ScreenedSession>[];

    return FrostedScaffold(
      // No GlassAppBar: the design's header IS the top of the scroll, and a
      // bar reading "Home" above a greeting that already names the user is the
      // same information twice.
      body: SmoothScrollList(
        padding: const EdgeInsets.fromLTRB(20, 54, 20, 110),
        children: [
          const _GreetingHeader(),
          const SizedBox(height: 14),
          const _PlanProgressBar(),
          _TodayHero(
            upcoming: upcoming,
            digest: ref.watch(todayDigestProvider),
          ),
          const SizedBox(height: 12),
          const _QuickScanCard(),
          const SizedBox(height: 20),
          const _RecoveryStrip(),
          const _WeekSection(),
          const SizedBox(height: 12),
          const DeloadBanner(),
          // R5's way in. Shown only once the day has something to summarise:
          // a permanent link to a screen that says "nothing finished today"
          // is a link to a disappointment.
          if (!ref.watch(todayResultProvider).isEmpty) ...[
            const SizedBox(height: 12),
            const _SummaryLinkCard(),
          ],
          if (upcoming.length > 1) ...[
            const SizedBox(height: 24),
            _SectionHeader(l10n.homeSectionUpcoming),
            const SizedBox(height: 12),
            for (final s in upcoming.skip(1).take(3)) ...[
              _UpcomingCard(screened: s),
              const SizedBox(height: 12),
            ],
          ],
          const SizedBox(height: 28),
          _SectionHeader(l10n.homeSectionMore),
          const SizedBox(height: 12),
          const _AiPlanCard(),
          const SizedBox(height: 12),
          const _PostureCheckCard(),
          const SizedBox(height: 12),
          const HealthSyncCard(),
          const SizedBox(height: 28),
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

/// "Good evening" over the user's name, per the prototype's header.
class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final user = ref.watch(authUserProvider).valueOrNull;

    // First word only: the header is a greeting, and "Иван Коростелев" in
    // 34pt display type is a legal document, not a hello. An anonymous user
    // has no name at all, which is what `homeAthlete` is for.
    final full = user?.displayName.trim() ?? '';
    final name = full.isEmpty ? l10n.homeAthlete : full.split(RegExp(r'\s+')).first;

    final greeting = switch (greetingFor(DateTime.now())) {
      DayGreeting.morning => l10n.homeGreetingMorning,
      DayGreeting.afternoon => l10n.homeGreetingAfternoon,
      DayGreeting.evening => l10n.homeGreetingEvening,
    };

    return Column(
      key: const Key('home.greeting'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

/// This week's schedule completion, as the prototype's header bar.
///
/// Renders nothing at all when the week holds no sessions — see
/// [PlanProgress.isEmpty].
class _PlanProgressBar extends ConsumerWidget {
  const _PlanProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(planProgressProvider);
    if (progress.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colors;

    return Padding(
      key: const Key('home.planProgress'),
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        borderRadius: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${l10n.homeWeekPlan} · '
                    '${l10n.homeWeekPlanCount(progress.done, progress.total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${progress.percent}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.accentPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 4,
                backgroundColor: colors.surfaceInteractive,
                valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The day, as the prototype's centrepiece: eyebrow, large title, muscle
/// chips, one line of shape, and a full-width accent CTA.
class _TodayHero extends StatelessWidget {
  const _TodayHero({required this.upcoming, required this.digest});

  final List<ScreenedSession> upcoming;

  /// The whole day, not just its first row — see [SessionDigest].
  final SessionDigest digest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colors;

    if (upcoming.isEmpty) {
      return GlassCard(
        key: const Key('home.heroEmpty'),
        borderRadius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeNoWorkoutsScheduled,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.homePickAPlanOrScanA,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            _AccentButton(
              label: l10n.homeTodaySAdaptivePlan,
              icon: Icons.auto_awesome,
              onTap: () => GoRouter.of(context).push('/plan'),
            ),
          ],
        ),
      );
    }

    final screened = upcoming.first;
    final next = screened.session;

    // A one-exercise day IS its exercise: "Back" tells the user less there
    // than "Pull-up" does.
    final title = (digest.exerciseCount > 1 && digest.muscles.isNotEmpty)
        ? digest.muscles
            .map((m) => CatalogLabels.muscle(l10n, m))
            .join(' · ')
        : next.exerciseTitle;

    return GlassCard(
      key: const Key('home.hero'),
      borderRadius: 22,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.surfacePrimary,
          colors.accentPrimary.withValues(alpha: 0.07),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.homeTodayIs(
              DateFormat.EEEE(l10n.localeName).format(next.scheduledFor),
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.accentPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          if (digest.muscles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in digest.muscles)
                  _Chip(label: CatalogLabels.muscle(l10n, m)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            screened.hiddenForInjury
                ? l10n.equipmentScheduledHiddenForInjury
                : l10n.homeTodayDigest(
                    digest.exerciseCount, digest.totalMinutes),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: screened.hiddenForInjury
                  ? theme.colorScheme.error
                  : colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          // The CTA is withheld when the day's first exercise is hidden for a
          // logged contraindication. Injury screening is a safety rule, not a
          // display filter (`core/CONVENTIONS.md`); a "Start workout" button
          // that opens work the screening just removed would defeat it.
          if (!screened.hiddenForInjury)
            _AccentButton(
              label: l10n.homeStartWorkout,
              icon: Icons.play_arrow_rounded,
              onTap: () =>
                  GoRouter.of(context).push('/workout/${next.exerciseId}'),
            ),
        ],
      ),
    );
  }
}

/// Full-width solid-accent CTA, per the prototype's primary button.
class _AccentButton extends StatelessWidget {
  const _AccentButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: colors.accentPrimary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: colors.onAccent),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.onAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A muscle tag on the hero.
class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceInteractive,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The prototype's "Незнакомый тренажёр?" row — the scanner's way in.
class _QuickScanCard extends StatelessWidget {
  const _QuickScanCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return GlassCard(
      key: const Key('home.quickScan'),
      borderRadius: 16,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () => GoRouter.of(context).go('/scan'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraViolet,
                AppPalette.auroraBlue,
              ]),
            ),
            child: const Icon(Icons.qr_code_scanner_rounded,
                color: AppSemanticColors.onGradientInk),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.homeUnfamiliarMachine,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.homeIdentifyWithCamera,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontally scrolling muscle-recovery cards.
///
/// Absent, not empty, when there is no history to derive it from — see
/// [deriveRecovery].
class _RecoveryStrip extends ConsumerWidget {
  const _RecoveryStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(muscleRecoveryProvider);
    if (rows.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colors;

    Color dot(RecoveryStatus s) => switch (s) {
          RecoveryStatus.ready => colors.success,
          RecoveryStatus.medium => colors.warning,
          RecoveryStatus.recovering => colors.danger,
        };
    String label(RecoveryStatus s) => switch (s) {
          RecoveryStatus.ready => l10n.homeRecoveryReady,
          RecoveryStatus.medium => l10n.homeRecoveryModerate,
          RecoveryStatus.recovering => l10n.homeRecoveryRecovering,
        };

    return Padding(
      key: const Key('home.recovery'),
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(l10n.homeSectionRecovery),
          const SizedBox(height: 10),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final r = rows[i];
                return GlassCard(
                  borderRadius: 14,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dot(r.status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        CatalogLabels.muscle(l10n, r.muscle),
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label(r.status),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The week strip plus the three totals under it.
class _WeekSection extends ConsumerWidget {
  const _WeekSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colors;
    final week = ref.watch(weekStripProvider);
    final totals = ref.watch(weekTotalsProvider);

    return Column(
      key: const Key('home.week'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l10n.homeThisWeek),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final cell in week) ...[
              Expanded(
                child: Column(
                  children: [
                    Text(
                      // Locale's own short weekday. Nineteen names in an ARB
                      // file would have been wrong for the next language.
                      DateFormat.E(l10n.localeName).format(cell.day),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cell.isToday
                            ? colors.accentPrimary
                            : colors.textDisabled,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: cell.done
                              ? colors.accentPrimary
                              : cell.isToday
                                  ? colors.accentPrimary
                                      .withValues(alpha: 0.2)
                                  : cell.isRest
                                      ? colors.surfaceInteractive
                                      : colors.surfacePrimary,
                          border: Border.all(
                            color: cell.isToday
                                ? colors.accentPrimary
                                : colors.outline,
                            width: cell.isToday ? 1.5 : 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (cell != week.last) const SizedBox(width: 4),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TotalCard(
                value: '${totals.workouts}',
                label: l10n.homeStatWorkouts,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TotalCard(
                // Whole kilos: a volume total is a scale reading, not a
                // measurement, and "5 820.4 kg" implies a precision the
                // logged plate weights do not have.
                value: NumberFormat.decimalPattern(l10n.localeName)
                    .format(totals.volumeKg.round()),
                label: l10n.homeStatVolume,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TotalCard(
                value: '${totals.personalRecords}',
                label: l10n.homeStatRecords,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One of the three numbers under the week strip.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colors.textSecondary),
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

class _SummaryLinkCard extends ConsumerWidget {
  const _SummaryLinkCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = ref.watch(todayResultProvider);

    return GlassCard(
      key: const Key('home.summaryLink'),
      onTap: () => GoRouter.of(context).push('/workout-summary'),
      child: Row(
        children: [
          _GradientTile(
            icon: Icons.check_circle_outline_rounded,
            gradient: const [AppPalette.auroraTeal, AppPalette.auroraLime],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.summaryTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  l10n.homeTodayDigest(
                      result.exerciseCount, result.totalMinutes),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colors.textSecondary),
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

/// Entry point for R10's posture check -- a card rather than a 6th bottom-nav
/// tab, per `core/plans/PLAN_R10_POSTURE_2026-08-08.md` section 4: the shell
/// is a fixed 5 tabs and none of them fit a static stand-and-check feature.
class _PostureCheckCard extends StatelessWidget {
  const _PostureCheckCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      key: const Key('home.postureCard'),
      onTap: () => GoRouter.of(context).push('/posture'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraLime,
                AppPalette.auroraTeal,
              ]),
            ),
            child: const Icon(Icons.accessibility_new_rounded,
                color: AppSemanticColors.onGradientInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).postureTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).postureHomeSubtitle,
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
