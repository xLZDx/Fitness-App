import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/health/widgets/health_sync_card.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/hud_tokens.dart';
import '../../core/theme/hud_typography.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/hud/hud_metric.dart';
import '../../shared/widgets/hud/hud_scaffold.dart';
import '../../shared/widgets/hud/hud_surface.dart';
import '../auth/state/auth_providers.dart';
import '../moments/data/moment.dart';
import '../moments/state/moment_providers.dart';
import '../moments/widgets/day3_welcome_modal.dart';
import '../recovery/widgets/deload_banner.dart';
import '../safety/state/eligibility_providers.dart';
import '../safety/widgets/eligibility_notice.dart';
import '../equipment/data/catalog_labels.dart';
import '../equipment/state/equipment_providers.dart';
import '../programmes/data/programme_labels.dart';
import '../programmes/state/programme_providers.dart';
import '../workouts/data/session_digest.dart';
import '../workouts/state/day_result_providers.dart';
import '../workouts/state/session_digest_providers.dart';
import '../workouts/state/session_screening_providers.dart';
import 'data/home_dashboard.dart';
import 'data/suggestion_builder.dart';
import 'state/home_dashboard_providers.dart';
import 'state/suggestion_providers.dart';
import '../equipment/widgets/exercise_thumb.dart';

/// Home, rebuilt at MVP Gate M1 against the real HUD handoff
/// (`Fitness Glass Phone v1 - Sunset.dc.html`, the "Home" `sc-if` block).
///
/// ## What follows the handoff, and what does not
///
/// The identity/week strip, the day panel (ring, session line, CTA), the
/// seven-day week grid, the muscle-recovery panel and the quick-scan row are
/// the handoff's own spine and are built against its exact geometry via the
/// shared HUD widget kit (`hud_scaffold.dart`, `hud_metric.dart`,
/// `hud_surface.dart`).
///
/// Two deliberate departures from the handoff's pixels, both because the
/// alternative would be fabrication (`CLAUDE.md` §61, "no fake data"):
///
/// * The handoff's day panel carries a `READY {{recAvg}}` badge and a
///   readiness marker on a poor/mid/good zone bar. There is no single
///   "readiness" score anywhere in the domain layer — [muscleRecoveryProvider]
///   only reports a per-muscle ready/medium/recovering *status*. What is
///   shown is the one real, derivable number: the fraction of tracked muscle
///   groups currently `ready`. It is omitted entirely (not shown as 0%) when
///   there is no training history to derive it from, the same rule the old
///   recovery strip already enforced.
/// * The handoff's "Form coach" panel shows per-set Tempo/Depth/Symmetry
///   numbers. Home has no pipeline that produces those; inventing plausible
///   ones would be exactly the fake-ML-confidence CLAUDE.md forbids. The
///   panel is replaced by the app's real, working posture-check entry point
///   ([_PostureCheckCard]), kept from the previous build.
///
/// The muscle-recovery panel also drops the handoff's per-muscle percentage
/// bar for the same reason: [MuscleRecovery] carries an ordinal status, not a
/// measured percentage, so the row shows the status word, not an invented bar
/// length.
///
/// The app's own entry points the handoff has no equivalent for (AI plan,
/// posture check, health sync, deload notice, today's summary, upcoming
/// sessions, suggestions) are kept below the redesigned spine under their own
/// headings, unchanged from the previous build — deleting them to chase the
/// handoff more closely would strand working features the handoff was never
/// asked to depict.
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

    return HudScreenBody(
      children: [
        const _HudGreeting(),
        const _HudIdentityRow(),
        _HudDayPanel(
          upcoming: upcoming,
          digest: ref.watch(todayDigestProvider),
        ),
        const SizedBox(height: 14),
        const _HudWeekSection(),
        const SizedBox(height: 14),
        const _HudRecoveryPanel(),
        const SizedBox(height: 14),
        const _HudQuickScanRow(),
        const SizedBox(height: 20),
        _gutter(const DeloadBanner()),
        // R5's way in. Shown only once the day has something to summarise: a
        // permanent link to a screen that says "nothing finished today" is a
        // link to a disappointment.
        if (!ref.watch(todayResultProvider).isEmpty) ...[
          const SizedBox(height: 12),
          _gutter(const _SummaryLinkCard()),
        ],
        if (upcoming.length > 1) ...[
          const SizedBox(height: 20),
          _HudSectionTitle(l10n.homeSectionUpcoming),
          for (final s in upcoming.skip(1).take(3)) ...[
            _gutter(_UpcomingCard(screened: s)),
            const SizedBox(height: 12),
          ],
        ],
        const SizedBox(height: 8),
        _HudSectionTitle(l10n.homeSectionMore),
        _gutter(const _AiPlanCard()),
        const SizedBox(height: 12),
        _gutter(const _PostureCheckCard()),
        const SizedBox(height: 12),
        _gutter(const HealthSyncCard()),
        const SizedBox(height: 20),
        _HudSectionTitle(l10n.homeSectionSuggestions),
        // Gate M's floor on the surface a user actually lands on.
        //
        // `buildSuggestions` is a second workout-producing path, and gating it
        // by returning an empty list would have rendered as
        // `homeSuggestionsEmpty` — "nothing to suggest right now", which is a
        // different and untrue reason. The verdict is read here, where the
        // section is drawn, because that is where the wrong message would
        // have been shown.
        if (ref.watch(safetyContextProvider).valueOrNull
            case final c? when !c.allowsAnyTraining)
          _gutter(EligibilityNotice(
            key: const Key('home.suggestions.refused'),
            title: l10n.eligTrainingBlockedTitle,
            reasons: c.wholePersonBlocks,
            onReviewProfile: () => GoRouter.of(context).push('/onboarding'),
          ))
        else
          ...ref.watch(suggestionsProvider).when(
                loading: () => [_gutter(const _SuggestionsPlaceholder())],
                error: (e, _) =>
                    [_gutter(_SuggestionsMessage(l10n.homeCouldNotLoad('$e')))],
                data: (list) => list.isEmpty
                    ? [_gutter(_SuggestionsMessage(l10n.homeSuggestionsEmpty))]
                    : [
                        for (var i = 0; i < list.length; i++) ...[
                          _gutter(_SuggestionCard(
                            list[i],
                            gradient: AppPalette.tileGradients[
                                i % AppPalette.tileGradients.length],
                          )),
                          const SizedBox(height: 12),
                        ],
                      ],
              ),
      ],
    );
  }
}

/// `margin:0 16px` — the handoff's panel gutter, applied to whatever still
/// needs it explicitly (the legacy glass cards kept below the spine; the new
/// HUD panels apply it themselves).
Widget _gutter(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: HudTokens.screenGutter),
      child: child,
    );

/// "Good evening" over the user's first name. Not in the handoff — which opens
/// straight on the identity/week strip — but the greeting is real, tested
/// behaviour from the previous build and the handoff was never asked to depict
/// it, so it is kept and restyled rather than deleted.
class _HudGreeting extends ConsumerWidget {
  const _HudGreeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final user = ref.watch(authUserProvider).valueOrNull;

    // First word only: the header is a greeting, and "Иван Коростелев" in
    // display type is a legal document, not a hello. An anonymous user has no
    // name at all, which is what `homeAthlete` is for.
    final full = user?.displayName.trim() ?? '';
    final name =
        full.isEmpty ? l10n.homeAthlete : full.split(RegExp(r'\s+')).first;

    final greeting = switch (greetingFor(DateTime.now())) {
      DayGreeting.morning => l10n.homeGreetingMorning,
      DayGreeting.afternoon => l10n.homeGreetingAfternoon,
      DayGreeting.evening => l10n.homeGreetingEvening,
    };

    return Padding(
      key: const Key('home.greeting'),
      padding: const EdgeInsets.fromLTRB(
          HudTokens.headerGutter, 6, HudTokens.headerGutter, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greeting, style: HudType.body(t, size: 12.5).overPhoto(t)),
          const SizedBox(height: 2),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HudType.screenTitle(t).overPhoto(t),
          ),
        ],
      ),
    );
  }
}

/// The handoff's top strip: `IVAN · STRENGTH BASE` / `Week 2 of 8` —
/// programme title and week when the user has enrolled in one (Gate P),
/// otherwise this week's plain schedule completion. Absent entirely when
/// there is nothing to report — see [PlanProgress.isEmpty].
class _HudIdentityRow extends ConsumerWidget {
  const _HudIdentityRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HudTokens t = context.hud;
    final programme = ref.watch(activeProgrammeProvider);
    final programmeProgress = ref.watch(activeProgrammeProgressProvider);

    String label;
    Key key;
    if (programme != null && programmeProgress != null) {
      final l = AppLocalizations.of(context);
      key = const Key('home.programmeProgress');
      label = '${ProgrammeLabels.title(l, programme.templateId, stored: programme.title)} · '
          '${l.programmeWeekOfWeeks(programmeProgress.week, programmeProgress.weeks)}';
    } else {
      final progress = ref.watch(planProgressProvider);
      if (progress.isEmpty) return const SizedBox.shrink();
      final l10n = AppLocalizations.of(context);
      key = const Key('home.planProgress');
      label = '${l10n.homeWeekPlan} · '
          '${l10n.homeWeekPlanCount(progress.done, progress.total)}';
    }

    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(
          HudTokens.headerGutter, 0, HudTokens.headerGutter, 12),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HudType.label(t, size: 10, color: t.textPrimary).overPhoto(t),
      ),
    );
  }
}

/// The day, as the handoff's centrepiece panel: eyebrow + readiness badge,
/// title, ring + session facts + zone bar, and a full-width CTA.
class _HudDayPanel extends ConsumerWidget {
  const _HudDayPanel({required this.upcoming, required this.digest});

  final List<ScreenedSession> upcoming;

  /// The whole day, not just its first row — see [SessionDigest].
  final SessionDigest digest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final rows = ref.watch(muscleRecoveryProvider);
    final double? readiness = rows.isEmpty
        ? null
        : rows.where((r) => r.status == RecoveryStatus.ready).length /
            rows.length;

    if (upcoming.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: HudTokens.screenGutter),
        child: HudPanel(
          key: const Key('home.heroEmpty'),
          semanticLabel: l10n.homeNoWorkoutsScheduled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.homeNoWorkoutsScheduled,
                  style: HudType.heroTitle(t).inPanel(t)),
              const SizedBox(height: 6),
              Text(l10n.homePickAPlanOrScanA,
                  style: HudType.body(t, size: 12.5).inPanel(t)),
              const SizedBox(height: 16),
              HudButton(
                label: l10n.homeTodaySAdaptivePlan,
                icon: Icons.auto_awesome,
                onPressed: () => GoRouter.of(context).push('/plan'),
              ),
            ],
          ),
        ),
      );
    }

    final screened = upcoming.first;
    final next = screened.session;

    // A one-exercise day IS its exercise: "Back" tells the user less there
    // than "Pull-up" does.
    final title = (digest.exerciseCount > 1 && digest.muscles.isNotEmpty)
        ? digest.muscles.map((m) => CatalogLabels.muscle(l10n, m)).join(' · ')
        : resolveExerciseTitle(
            ref.watch(exerciseTitlesProvider), next.exerciseId, next.exerciseTitle);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HudTokens.screenGutter),
      child: HudPanel(
        key: const Key('home.hero'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    DateFormat.EEEE(l10n.localeName).format(next.scheduledFor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HudType.label(t).inPanel(t),
                  ),
                ),
                if (readiness != null) ...[
                  const SizedBox(width: 8),
                  _ReadyBadge(fraction: readiness),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: HudType.heroTitle(t).inPanel(t),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                HudRing(
                  size: 112,
                  radius: 49,
                  strokeWidth: 2.5,
                  trackWidth: 1.5,
                  guideRadius: 38,
                  progress: readiness ?? 0,
                  semanticsLabel: l10n.homeSectionRecovery,
                  child: HudRingLabel(
                    value: '${digest.exerciseCount}',
                    caption: l10n.homeRingExercises,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.homeSessionLabel.toUpperCase(),
                          style: HudType.label(t, size: 8.5).inPanel(t)),
                      const SizedBox(height: 3),
                      Text(
                        screened.hasWithheldExercise
                            ? l10n.homeSessionWithheld
                            : l10n.homeTodayDigest(
                                digest.exerciseCount, digest.totalMinutes),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HudType.bodyStrong(t, size: 12.5).inPanel(t).copyWith(
                              color: screened.hasWithheldExercise
                                  ? t.danger
                                  : null,
                            ),
                      ),
                      const SizedBox(height: 9),
                      if (readiness != null) ...[
                        Text(l10n.homeSectionRecovery.toUpperCase(),
                            style: HudType.label(t, size: 8.5).inPanel(t)),
                        const SizedBox(height: 3),
                        HudZoneBar(
                          value: readiness,
                          semanticsLabel: l10n.homeSectionRecovery,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // The CTA is withheld when any of the day's exercises is.
            // Screening is a safety rule, not a display filter — a "Start
            // workout" button that opens work the eligibility layer just
            // removed would defeat it. Home displays the day's state; it does
            // not decide whether the day may be trained.
            if (!screened.hasWithheldExercise) ...[
              const SizedBox(height: 16),
              HudButton(
                label: l10n.homeStartWorkout,
                icon: Icons.play_arrow_rounded,
                tone: HudButtonTone.accent,
                // `?day=` is what turns this from "open exercise one" into
                // "start today's workout": the player keys its log by the day
                // instead of by this exercise, so all of the day's exercises
                // land in ONE history entry and the strip can walk between
                // them.
                onPressed: () => GoRouter.of(context)
                    .push('/workout/${next.exerciseId}?day=${next.id}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The small "READY 74%" badge — the one real, derivable readiness number:
/// the fraction of tracked muscle groups the recovery model currently reports
/// as ready. Not shown when there is no training history to derive it from.
class _ReadyBadge extends StatelessWidget {
  const _ReadyBadge({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color dot = fraction >= 0.6
        ? t.zoneGood
        : fraction >= 0.3
            ? t.zoneMid
            : t.zonePoor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dot,
            boxShadow: t.brightness == Brightness.dark
                ? [BoxShadow(color: dot, blurRadius: 10)]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${l10n.homeRecoveryReady.toUpperCase()} ${(fraction * 100).round()}%',
          style: HudType.mono(t, size: 9.5).inPanel(t),
        ),
      ],
    );
  }
}

/// The seven-day week grid, bare over the photograph per the handoff, plus
/// the three totals underneath.
class _HudWeekSection extends ConsumerWidget {
  const _HudWeekSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final week = ref.watch(weekStripProvider);
    final totals = ref.watch(weekTotalsProvider);

    return Column(
      key: const Key('home.week'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HudSectionTitle(l10n.homeThisWeek),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: HudTokens.screenGutter),
          child: Row(
            children: [
              for (final cell in week) ...[
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        // Locale's own short weekday. Nineteen names in an
                        // ARB file would have been wrong for the next
                        // language.
                        DateFormat.E(l10n.localeName).format(cell.day),
                        maxLines: 1,
                        style: HudType.mono(
                          t,
                          size: 8.5,
                          em: 0.04,
                          color: cell.isToday ? t.accent : t.textTertiary,
                        ).overPhoto(t),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cell.done
                              ? t.accent
                              : cell.isToday
                                  ? t.accent.withValues(alpha: 0.5)
                                  : t.textTertiary.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                if (cell != week.last) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: HudTokens.screenGutter),
          child: Row(
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
    final HudTokens t = context.hud;
    return HudPanel(
      secondary: true,
      radius: HudTokens.radiusChip,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            child: Text(value, style: HudType.panelHeading(t).inPanel(t)),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HudType.rowMeta(t).inPanel(t),
          ),
        ],
      ),
    );
  }
}

/// The handoff's "Recovery" panel — muscle, status word, coloured dot.
/// Absent, not empty, when there is no history to derive it from — see
/// [deriveRecovery]. No numeric bar: [MuscleRecovery] carries an ordinal
/// status, not a measured percentage, and drawing one anyway would be a
/// precision the data does not have.
class _HudRecoveryPanel extends ConsumerWidget {
  const _HudRecoveryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(muscleRecoveryProvider);
    if (rows.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;

    Color dot(RecoveryStatus s) => switch (s) {
          RecoveryStatus.ready => t.zoneGood,
          RecoveryStatus.medium => t.zoneMid,
          RecoveryStatus.recovering => t.zonePoor,
        };
    String label(RecoveryStatus s) => switch (s) {
          RecoveryStatus.ready => l10n.homeRecoveryReady,
          RecoveryStatus.medium => l10n.homeRecoveryModerate,
          RecoveryStatus.recovering => l10n.homeRecoveryRecovering,
        };

    return Padding(
      key: const Key('home.recovery'),
      padding: const EdgeInsets.symmetric(horizontal: HudTokens.screenGutter),
      child: HudPanel(
        semanticLabel: l10n.homeSectionRecovery,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.homeSectionRecovery,
                style: HudType.panelTitle(t).inPanel(t)),
            const SizedBox(height: 10),
            for (final r in rows) ...[
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: dot(r.status)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      CatalogLabels.muscle(l10n, r.muscle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HudType.bodyStrong(t).inPanel(t),
                    ),
                  ),
                  Text(label(r.status), style: HudType.mono(t, size: 9.5, color: dot(r.status)).inPanel(t)),
                ],
              ),
              if (r != rows.last) ...[
                const SizedBox(height: 8),
                Divider(height: 1, color: t.divider),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The handoff's "Unfamiliar machine?" row — the scanner's way in.
class _HudQuickScanRow extends StatelessWidget {
  const _HudQuickScanRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HudTokens.screenGutter),
      child: HudPanel(
        key: const Key('home.quickScan'),
        secondary: true,
        radius: HudTokens.radiusSubPanel,
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
        semanticLabel: l10n.homeUnfamiliarMachine,
        onTap: () => GoRouter.of(context).go('/scan'),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.homeUnfamiliarMachine,
                      style: HudType.rowTitle(t, strong: true).inPanel(t)),
                  const SizedBox(height: 2),
                  Text(l10n.homeIdentifyWithCamera,
                      style: HudType.body(t, size: 11.5).inPanel(t)),
                ],
              ),
            ),
            Icon(Icons.qr_code_scanner_rounded, size: 24, color: t.textPrimary),
          ],
        ),
      ),
    );
  }
}

/// A panel-title-weight section heading (`700 20px`, plain case) — the
/// handoff's own "Form coach" / "Recovery" panel titles, reused for the
/// sections below the redesigned spine ("Upcoming", "More", "Suggested for
/// you"). Deliberately not [HudSectionHeader]: that widget is the small
/// uppercase-tracked micro-label the handoff uses for Profile's dividers, a
/// different and smaller role than a section's own bold heading.
class _HudSectionTitle extends StatelessWidget {
  const _HudSectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HudTokens.headerGutter, 10, HudTokens.headerGutter, 10),
      child: Text(label, style: HudType.panelHeading(t).overPhoto(t)),
    );
  }
}

/// "Today's plan" CTA. Routes to the AI workout generator. Kept unchanged
/// from the previous build — the handoff has no equivalent screen to redesign
/// it against.
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

/// Entry point for R10's posture check -- a card rather than a 6th bottom-nav
/// tab, per `core/plans/PLAN_R10_POSTURE_2026-08-08.md` section 4: the shell
/// is a fixed 5 tabs and none of them fit a static stand-and-check feature.
/// Also stands in for the handoff's "Form coach" panel — see the file doc
/// comment for why that panel's own numbers are not shown.
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

class _UpcomingCard extends ConsumerWidget {
  const _UpcomingCard({required this.screened});
  final ScreenedSession screened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = screened.session;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () => GoRouter.of(context)
          .push('/workout/${session.exerciseId}?day=${session.id}'),
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
                Text(
                    // B5b: a day can hold several exercises. The count goes on
                    // the title as a bare "+3" rather than a phrase, because
                    // "3 exercises" needs a Russian plural form for 1, 3 and 5
                    // and this tile has room for neither the string nor the
                    // mistake.
                    session.exerciseCount > 1
                        ? '${resolveExerciseTitle(ref.watch(exerciseTitlesProvider), session.exerciseId, session.exerciseTitle)}  +${session.exerciseCount - 1}'
                        : resolveExerciseTitle(
                            ref.watch(exerciseTitlesProvider),
                            session.exerciseId,
                            session.exerciseTitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  screened.hasWithheldExercise
                      ? l10n.homeSessionWithheld
                      : AppLocalizations.of(context).notificationsMin(
                          formatScheduleLabel(l10n, session.scheduledFor),
                          session.durationMinutes),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: screened.hasWithheldExercise
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
          // The catalog row now travels on the suggestion, so this reaches
          // the exercise's bundled poster. It used to be a `const` with
          // `exercise: null`, which meant every row in this list rendered the
          // fallback dumbbell tile and none of the 1764 bundled posters was
          // ever asked for — the "картинки не отображаются" the operator saw.
          ExerciseThumb(exercise: s.exercise, size: 48),
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
                  _reasonText(AppLocalizations.of(context), s),
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

/// Renders [WorkoutSuggestion.reason] in the user's language.
///
/// The builder is a pure function with no `BuildContext`, so it reports which
/// reason applies and this turns it into a sentence. Before the split, the
/// builder composed the sentence itself and a Russian Home screen read "You
/// have not trained hamstrings this week" — English string *and* an
/// untranslated catalog muscle tag. The muscle goes through `CatalogLabels`,
/// the same table every other screen uses, so it cannot be translated on the
/// exercise page and raw here.
String _reasonText(AppLocalizations l, WorkoutSuggestion s) =>
    switch (s.reason) {
      SuggestionReason.untrainedMuscle => l.suggestionReasonUntrainedMuscle(
          CatalogLabels.muscle(l, s.reasonMuscle ?? ''),
        ),
      SuggestionReason.cardioForWeightLoss => l.suggestionReasonCardioWeightLoss,
      SuggestionReason.cardioForEndurance => l.suggestionReasonCardioEndurance,
      SuggestionReason.buildsStrength => l.suggestionReasonBuildsStrength,
      SuggestionReason.buildsMuscle => l.suggestionReasonBuildsMuscle,
      SuggestionReason.fitsSessionLength => l.suggestionReasonFitsSessionLength,
      SuggestionReason.matchesProfile => l.suggestionReasonMatchesProfile,
    };

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
