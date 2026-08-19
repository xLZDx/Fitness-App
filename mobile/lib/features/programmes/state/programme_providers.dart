import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/data/exercise_filter.dart';
import '../../equipment/state/equipment_providers.dart';
import '../../profile/data/profile_models.dart';
import '../../workouts/data/scheduled_session.dart';
import '../../workouts/state/scheduled_session_providers.dart';
import '../data/mock_programme_repository.dart';
import '../data/programme.dart';
import '../data/programme_repository.dart';
import '../../safety/data/eligibility.dart';
import '../../safety/state/eligibility_providers.dart';
import '../data/programme_builder.dart';
import '../data/programme_schedule.dart';
import '../data/programme_specs.dart';
import '../data/programme_templates.dart';

/// Persistence provider for programme enrolments. Default is the in-memory
/// mock; `main.dart` overrides it with the Firestore-backed impl — same
/// pattern as `scheduledSessionRepositoryProvider`.
final programmeRepositoryProvider = Provider<ProgrammeRepository>((ref) {
  final repo = MockProgrammeRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Every programme the signed-in user has ever enrolled in, newest first.
///
/// MVP-1: awaits `authUserProvider.future` rather than sampling
/// `.valueOrNull`, which collapsed "auth still restoring" and "genuinely
/// signed out" into the same branch — reachable on every cold start, not
/// just under adversarial timing.
final programmesProvider = StreamProvider<List<Programme>>((ref) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield const <Programme>[];
    return;
  }
  final repo = ref.watch(programmeRepositoryProvider);
  yield* repo.watch(user.uid);
});

/// The one programme currently in progress, or null.
///
/// "At most one active programme" is enforced here, not in the model: two
/// `status: active` rows are a data anomaly the UI defends against rather
/// than a state [Programme] forbids, the same relationship
/// [WorkoutSessionStatus] has with an in-progress session. Picks the most
/// recently started if that anomaly ever occurs, rather than crashing on it.
final activeProgrammeProvider = Provider<Programme?>((ref) {
  final all = ref.watch(programmesProvider).valueOrNull ?? const [];
  for (final p in all) {
    if (p.status == ProgrammeStatus.active) return p;
  }
  return null;
});

/// [ProgrammeProgress] for [activeProgrammeProvider], or null when nothing is
/// active. Home's header bar and the Workouts "current programme" card both
/// read this rather than deriving it themselves, so they cannot disagree
/// about what week it is.
final activeProgrammeProgressProvider = Provider<ProgrammeProgress?>((ref) {
  final programme = ref.watch(activeProgrammeProvider);
  if (programme == null) return null;
  final scheduled =
      ref.watch(scheduledSessionsProvider).valueOrNull ?? const [];
  return deriveProgrammeProgress(programme, scheduled);
});

/// Imperative controller for enrolling in a programme and for bolting one
/// extra session onto the active one. Surfaces an AsyncValue so the UI can
/// render loading/error the same way `ScheduleSessionAction` does.
final programmeActionProvider =
    NotifierProvider<ProgrammeAction, AsyncValue<void>>(ProgrammeAction.new);

class ProgrammeAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  /// Enrols the user in [template]: writes the [Programme] row, then writes
  /// every [ScheduledSession] `buildProgrammeSchedule` generates for it.
  ///
  /// Any previously-active programme is marked `abandoned` first — enrolling
  /// in a second programme while one is running is how the user expresses
  /// "I am switching", not "I am now doing two programmes at once"; nothing
  /// in this app's Home header or Workouts card has a way to show two.
  /// Its already-scheduled rows are left exactly as they are: abandoning a
  /// programme does not retroactively cancel workouts the user may have
  /// already done or still plans to do.
  Future<void> enroll(ProgrammeTemplate template) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot enrol in a programme while signed out');
      }
      final repo = ref.read(programmeRepositoryProvider);

      final current = ref.read(activeProgrammeProvider);
      if (current != null) {
        await repo.save(
            user.uid,
            current.copyWith(
              status: ProgrammeStatus.abandoned,
              endedAt: DateTime.now(),
            ));
      }

      // B5a. Until now the enrolled programme was a verbatim copy of the
      // template and the schedule was built from an injury-screened catalogue,
      // so the 34-question profile changed nothing about what got scheduled:
      // someone who answered "at home, bodyweight, three days" and enrolled in
      // `strength_base` received four days a week of barbell work.
      final profile = await ref.read(screeningProfileProvider.future);

      final startedAt = DateTime.now();
      // B5d. Resolved BEFORE the row is built, because the row's own
      // `daysPerWeek` has to be the number of days actually scheduled: naming
      // three weekdays while answering "four days a week" produces a
      // three-day programme, and `deriveProgrammeProgress` counts completions
      // against this field. A four claiming a three-day schedule would report
      // progress the user can never reach.
      final dayOffsets = programmeDayOffsets(
        startedOn: startedAt,
        daysPerWeek: programmeDaysPerWeek(template.daysPerWeek, profile),
        preferredWeekdays: profile?.schedule.preferredWeekdays ?? const [],
      );

      final programme = Programme(
        id: '${startedAt.microsecondsSinceEpoch}_${template.id}',
        templateId: template.id,
        // B2a. The stored title is a FALLBACK, not what the UI shows: every
        // screen resolves the name from `templateId` through
        // `ProgrammeLabels`, so the card follows the app's language instead of
        // freezing whichever one was active at enrolment. This provider has no
        // `AppLocalizations` — it is not a widget — so it stores the id, which
        // is only ever surfaced if the template itself disappears.
        title: template.id,
        goal: template.goal,
        level: template.level,
        weeks: template.weeks,
        // Both clamped/resolved onto the ROW rather than applied inside
        // `buildProgrammeSchedule`, so the card's header and the sessions
        // actually generated cannot disagree — and so `deriveProgrammeProgress`
        // counts against the same number the schedule was built from.
        daysPerWeek: dayOffsets.length,
        muscles: programmeMuscles(template, profile),
        startedAt: startedAt,
      );

      final safeCatalogue = await ref.read(safeCatalogProvider.future);

      // F015 (G-B/B1). The whole-person gate, hoisted ABOVE the branch below.
      //
      // It used to be read inside the `spec != null` arm only, and
      // `buildProgramme` applied it there (`programme_builder.dart:319`). The
      // `else` arm applied nothing of the kind: `buildProgrammeSchedule` got
      // `availableWith(safeCatalogue, equipment)` — the injury filter plus an
      // equipment slice — so a user the safety layer refuses ALL training was
      // enrolled in a full multi-week programme, provided the template they
      // picked happened to be one of the two without a declared role
      // structure. Which of two templates a person tapped decided whether
      // their screening was honoured.
      //
      // `allowsAnyTraining` is the correct gate here — not
      // `blockedByAStatedAnswer`, which some display surfaces use. This
      // prescribes work: it is exactly the case that getter's own doc names
      // as belonging to the stricter test, because enrolling an unscreened
      // person means inventing a dose for someone nothing is known about.
      //
      // Thrown as `ProgrammeNotViable(blockedBySafety)` rather than a bare
      // error so the caller renders the stated refusal N01 built for it,
      // rather than a service-unavailable snackbar with a Retry button.
      final safety = await ref.read(safetyContextProvider.future);
      if (!safety.allowsAnyTraining) {
        throw const ProgrammeNotViable(
          [ProgrammeFinding(ProgrammeFault.blockedBySafety)],
        );
      }

      // Gate P, completed by G-E. EVERY programme is built by
      // `buildProgramme`, which fills declared MOVEMENT ROLES and validates
      // the result.
      //
      // There used to be a second arm here for templates with no spec, and it
      // was the defect rather than a migration half-done: `_fillDay` walked
      // the catalogue in alphabetical order, so a "strength base" came out as
      // 32 sessions of yoga poses and sit-ups (F021), repeating three of four
      // exercises between consecutive days (F022). G-E gave the last three
      // templates — `shred_endurance`, `shoulders_arms` and the
      // questionnaire-built `from_answers` — declared structures, so the arm
      // has no shipped caller left and is gone.
      //
      // A null spec now refuses. It is reachable only by a template id that is
      // not shipped: a stored enrolment from an older build, or a row written
      // by hand. "We cannot build this" is a true statement the user can act
      // on; a plausible alphabetical list under a strength title is not.
      final spec = programmeSpecFor(template.id,
          daysPerWeek: programme.daysPerWeek);
      if (spec == null) {
        throw const ProgrammeNotViable(
          [ProgrammeFinding(ProgrammeFault.noDeclaredStructure)],
        );
      }
      List<ScheduledSession> rows;
      {
        final focus = programme.muscles.toSet();
        final built = buildProgramme(ProgrammeBuildRequest(
          spec: spec,
          catalogue: safeCatalogue,
          safety: safety,
          weeks: programme.weeks,
          daysPerWeek: programme.daysPerWeek,
          // Personalisation, and the only door it comes through: the answer to
          // "what do you want worked on" ORDERS the candidates for each role.
          //
          // It used to select them — `programme.muscles` was the pool key — and
          // a role structure cannot work that way: a user who asks for core
          // work still needs a squat in the squat slot. Preferring rather than
          // filtering keeps their answer and keeps the programme a programme.
          rank: focus.isEmpty
              ? null
              : (role, pool) => [
                    ...pool.where((e) =>
                        e.primaryMuscles.any(focus.contains) ||
                        e.muscles.any(focus.contains)),
                    ...pool.where((e) => !(e.primaryMuscles.any(focus.contains) ||
                        e.muscles.any(focus.contains))),
                  ],
        ));
        switch (built) {
          case ProgrammeRefused(:final findings):
            // Explicit, not a fabricated plan. `enrol` reports it through the
            // action's own error state, which the card already renders.
            throw ProgrammeNotViable(findings);
          case ProgrammeBuilt(:final sessions):
            rows = scheduleFromPlan(
              programme: programme,
              plan: sessions,
              dayOffsets: dayOffsets,
            );
        }
      }

      await repo.save(user.uid, programme);
      final sessionRepo = ref.read(scheduledSessionRepositoryProvider);
      for (final row in rows) {
        await sessionRepo.save(user.uid, row);
      }

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Schedules one extra [exercise] under the active programme, at
  /// [nextProgrammeSlot]. Called by the workout player's "Add to programme"
  /// button (`workout_player_page.dart`).
  ///
  /// Throws [StateError] when nothing is active — the button only calls this
  /// after checking [activeProgrammeProvider] itself, so reaching here with
  /// none active would be this action being called from somewhere new that
  /// skipped that check, and failing loudly beats silently doing nothing.
  ///
  /// ## R-03 — why the safety check is HERE and not only at the button
  ///
  /// This is a terminal training mutation: after it, an exercise is scheduled
  /// under the user's programme. It used to carry no safety check of its own.
  ///
  /// That was not a live bypass, and this is not a bug fix. The one caller is
  /// gated: `workout_player_page.dart` renders `_AddToProgrammeButton` only
  /// under `resolution.visible`, and a withheld exercise draws an
  /// `EligibilityNotice` instead of the page body. So today no ineligible
  /// exercise reaches this method through the UI, and that was verified rather
  /// than assumed.
  ///
  /// What it depended on was there being exactly one caller, gated. A review
  /// can establish that today; it cannot establish it for the second entry
  /// point somebody adds. A terminal mutation must not rest on caller
  /// discipline, so the authority now sits where the mutation is.
  ///
  /// The check is not a second opinion: it calls the same `evaluateExercise`
  /// the UI does, with `includeWholePerson: true`, so there is one rule and
  /// this is a second place that asks it. Duplicating the reasoning here
  /// instead would be the failure mode this is meant to avoid.
  ///
  /// Fail-closed on an unresolvable safety context: "we could not tell" must
  /// never read as "go ahead" on a path that schedules training.
  Future<void> addExerciseToActiveProgramme(ExerciseItem exercise) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot schedule a session while signed out');
      }
      // `.future`, not `.valueOrNull`: the same read enrolment does. A
      // synchronous read returns null whenever the context merely has not been
      // resolved yet, which would make the gate refuse a perfectly eligible
      // user for a reason that is about provider timing rather than about
      // them. Awaiting resolves it, and a context that cannot be resolved
      // throws out of here — still fail-closed, and nothing is written.
      final resolved = await ref.read(safetyContextProvider.future);
      // Equipment removed, deliberately, and this is the correction to the
      // first version of this gate rather than a refinement of it.
      //
      // The page that offers this button shows the exercise through
      // `exerciseResolutionProvider`, which builds ITS context without
      // equipment on purpose — its own doc gives the reason: tapping a leg
      // press you do not own is an explicit statement about what you want to
      // look at, and refusing it would turn a browse into a prescription.
      //
      // Reading the equipment-carrying context here made the two disagree, and
      // the disagreement was reachable in the most ordinary case there is: a
      // home user taps a barbell exercise, the page shows it, and "add to
      // programme" refuses. Equipment is not a safety rule; this is a safety
      // gate. Found by an independent reviewer and confirmed by measurement,
      // not by re-reading the code that had just been written.
      final safety = SafetyContext(
        screening: resolved.screening,
        injuries: resolved.injuries,
        health: resolved.health,
      );
      // `isAllowed` is the hierarchy's own verdict, so this branch does not
      // enumerate the variants and cannot fall out of step with them. It is
      // false for [Blocked] only: a [Degraded] caveat about what could not be
      // checked must not refuse training, for the same reason it does not
      // empty the catalogue.
      if (!evaluateExercise(exercise, safety).isAllowed) {
        // The same refusal shape enrolment throws, so a caller CAN render the
        // stated refusal.
        //
        // Stated exactly, because the first version of this comment claimed
        // the caller already does and an independent reviewer showed it does
        // not: `workouts_page.dart` special-cases this exception and
        // `_AddToProgrammeButton` does not — it would interpolate
        // `ProgrammeNotViable([ProgrammeFinding(blockedBySafety)])` into a
        // snackbar.
        //
        // That is not worth a branch there, and the reason is the same one
        // that made the equipment read wrong: with equipment out of the
        // context, every remaining refusal here — whole-person, injury,
        // movement restriction — also makes `resolution.visible` null, so the
        // page renders an `EligibilityNotice` and this button does not exist.
        // The throw is unreachable through today's caller BY CONSTRUCTION,
        // which is what defence in depth is supposed to look like, and a
        // handler for it could not be given a failing test.
        //
        // A SECOND caller must handle it. That is what this comment is for.
        throw const ProgrammeNotViable(
          [ProgrammeFinding(ProgrammeFault.blockedBySafety)],
        );
      }
      final programme = ref.read(activeProgrammeProvider);
      if (programme == null) {
        throw StateError('No active programme to add this exercise to');
      }
      final existing =
          ref.read(scheduledSessionsProvider).valueOrNull ?? const [];
      final when = nextProgrammeSlot(programme.id, existing);

      final session = ScheduledSession(
        id: '${DateTime.now().microsecondsSinceEpoch}_${exercise.id}',
        exerciseId: exercise.id,
        exerciseTitle: exercise.title,
        scheduledFor: when,
        durationMinutes: exercise.durationMinutes,
        programmeId: programme.id,
      );
      await ref
          .read(scheduledSessionRepositoryProvider)
          .save(user.uid, session);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// How long a questionnaire-built programme runs.
///
/// **A stated default, not a derivation.** The questionnaire never asks how
/// many weeks someone wants (`step_schedule.dart` asks days per week, session
/// length and which weekdays — not duration), so there is no answer to read.
/// Eight weeks is the length of two of the six shipped templates and sits
/// inside their 4..10 range (`programme_templates.dart:57-98`). Inventing a
/// goal-dependent duration here — twelve for muscle, four for a comeback —
/// would be methodology this project has no source for, dressed up as
/// personalisation.
const int kProfileProgrammeWeeks = 8;

/// The days-per-week a questionnaire-built programme falls back to when the
/// schedule screen was skipped. Three is the shipped beginner cadence
/// (`gym_start`, `injury_comeback`).
const int kProfileProgrammeDaysPerWeek = 3;

/// A programme assembled from the questionnaire alone, expressed as a
/// [ProgrammeTemplate] so it can go through the exact same [enroll] path a
/// chosen template does.
///
/// The alternative was a second enrolment action that builds a [Programme]
/// directly. It was rejected: `enroll` is where the weekday resolution, the
/// days-per-week reconciliation, the muscle resolution, the injury-screened
/// catalogue and the abandon-the-previous-one step all live, and a parallel
/// path would have to reproduce every one of them — or quietly not, which is
/// how the two would drift.
///
/// What each field reads, and why:
///
/// * **goal** — `goals.primary`, the question that literally asks it. Falls
///   back to [ProgrammeGoal.form] (general form) when unanswered, because a
///   programme has to have one and "general" is the only honest answer to a
///   question nobody answered.
/// * **level** — `level.tier`. [FitnessTier.never] maps to `beginner` rather
///   than getting its own tier: the catalogue has three difficulties, and
///   "never trained" belongs in the gentlest of them. An unanswered tier also
///   lands on `beginner` — the safe direction, since the opposite error puts
///   someone who never said into advanced work.
/// * **daysPerWeek** — `schedule.daysPerWeek`. Passing it as the template's own
///   figure makes [programmeDaysPerWeek]'s min() a no-op rather than a special
///   case, and [programmeDayOffsets] still narrows it to the weekdays actually
///   ticked.
/// * **muscles** — deliberately left empty. That is [ProgrammeTemplate]'s
///   full-body sentinel, and it is precisely the condition under which
///   [programmeMuscles] resolves the user's focus zones. Reading `focusZones`
///   here as well would be the same derivation written twice.
///
/// [weeks] is the one field with no answer behind it — see
/// [kProfileProgrammeWeeks].
ProgrammeTemplate programmeFromProfile(UserProfile? profile) {
  final tier = profile?.level.tier;
  return ProgrammeTemplate(
    id: kProfileProgrammeId,
    goal: profile?.goals.primary ?? ProgrammeGoal.form,
    level: switch (tier) {
      FitnessTier.advanced => ExerciseDifficulty.advanced,
      FitnessTier.intermediate => ExerciseDifficulty.intermediate,
      FitnessTier.beginner ||
      FitnessTier.never ||
      null =>
        ExerciseDifficulty.beginner,
    },
    weeks: kProfileProgrammeWeeks,
    daysPerWeek: profile?.schedule.daysPerWeek ?? kProfileProgrammeDaysPerWeek,
  );
}

/// Whether the questionnaire holds enough to build a programme FROM.
///
/// The gate on the entry point, not on [programmeFromProfile] — that function
/// is total by design, every field has a documented fallback. But offering
/// "build one from my answers" to someone who answered nothing would hand them
/// a generic 8-week, 3-day, full-body programme under a label claiming it came
/// from answers they never gave. The templates are the honest path there.
///
/// Any ONE of the four inputs the builder actually reads is enough — a person
/// who only said "I train Mon/Wed/Fri" still gets a schedule that is genuinely
/// theirs.
bool canBuildProgrammeFromProfile(UserProfile? profile) {
  if (profile == null) return false;
  return profile.goals.hasAny ||
      profile.level.tier != null ||
      profile.schedule.daysPerWeek != null ||
      profile.schedule.preferredWeekdays.isNotEmpty;
}

/// How many days a week this enrolment actually schedules.
///
/// One-way: the user's answer can only ever REDUCE the template's own figure.
/// Scheduling five days for someone who told the questionnaire they have three
/// writes three sessions a week they were never going to do — and an overdue
/// count that climbs on its own is the fastest way to make a programme feel
/// like a failure. Raising it is the opposite mistake: a 3-day beginner
/// programme is 3 days by design, and someone with time for five did not ask
/// for two extra days of it. They asked for this programme.
///
/// A null answer (the schedule screen skipped) leaves the template's figure
/// alone — not answered is not "zero days".
///
/// The floor of 1 is not defensive padding: `TrainingSchedule.daysPerWeek` is
/// deliberately unvalidated at the model (`profile_models.dart:673`, "the
/// questionnaire is the only writer"), so a 0 written by hand into Firestore
/// would otherwise reach `buildProgrammeSchedule` and produce an enrolment with
/// no sessions at all, which looks exactly like a bug in the generator.
int programmeDaysPerWeek(int templateDays, UserProfile? profile) {
  final answered = profile?.schedule.daysPerWeek;
  if (answered == null) return templateDays;
  final wanted = answered < templateDays ? answered : templateDays;
  return wanted < 1 ? 1 : wanted;
}

/// The muscles this enrolment targets: the template's own, or — only when the
/// template names none — the ones the user's focus zones resolve to.
///
/// A template that names muscles wins outright. `hypertrophy` is chest, back,
/// quads and hamstrings because that is the programme the user chose; unioning
/// their focus zones into it would quietly turn it into a different programme
/// while still calling itself hypertrophy. The full-body templates
/// (`strength_base`, `gym_start`, `injury_comeback`) name nothing, and that is
/// where an answer to "what do you want worked on" has somewhere to go —
/// [FocusZone] was stored by the questionnaire and read by nothing at all until
/// here (P4).
///
/// The result is written onto the [Programme] row, not applied inside the
/// generator, because `Programme.muscles` is also what the card's subtitle
/// reads (`programme.dart`). Resolving zones only inside the schedule would
/// leave the card saying "full body" over a schedule that had quietly become
/// arms-and-core.
///
/// [FocusZone.fullBody] contributes nothing (`focusZoneMuscles` returns the
/// empty set for it), so selecting it alone leaves a full-body programme
/// full-body — which is what the user asked for.
List<String> programmeMuscles(
    ProgrammeTemplate template, UserProfile? profile) {
  if (template.muscles.isNotEmpty) return template.muscles;
  final zones = profile?.goals.focusZones ?? const <FocusZone>[];
  final out = <String>[];
  for (final zone in zones) {
    for (final muscle in focusZoneMuscles(zone)) {
      if (!out.contains(muscle)) out.add(muscle);
    }
  }
  return out;
}

/// The day after the latest pending session already scheduled under
/// [programmeId], or tomorrow when it has none yet.
///
/// Pure and exposed so the "next slot" choice is testable without a
/// repository. Only `pending` rows count — a `completed` or `cancelled` one
/// from early in the programme must not push a new addition weeks into the
/// future just because it is chronologically later in a since-abandoned
/// tail.
DateTime nextProgrammeSlot(
  String programmeId,
  Iterable<ScheduledSession> existing, {
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  DateTime? latest;
  for (final s in existing) {
    if (s.programmeId != programmeId) continue;
    if (s.status != ScheduledSessionStatus.pending) continue;
    if (latest == null || s.scheduledFor.isAfter(latest)) {
      latest = s.scheduledFor;
    }
  }
  final base = latest != null && latest.isAfter(n) ? latest : n;
  return base.add(const Duration(days: 1));
}
