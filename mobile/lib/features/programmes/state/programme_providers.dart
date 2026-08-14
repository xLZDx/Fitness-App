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
import '../data/programme_schedule.dart';
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
final programmesProvider = StreamProvider<List<Programme>>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <Programme>[]);
  final repo = ref.watch(programmeRepositoryProvider);
  return repo.watch(user.uid);
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
  final scheduled = ref.watch(scheduledSessionsProvider).valueOrNull ?? const [];
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
        await repo.save(user.uid, current.copyWith(
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

      final catalogue = availableWith(
        await ref.read(safeCatalogProvider.future),
        profile?.equipment ?? EquipmentAccess.empty,
      );
      final rows = buildProgrammeSchedule(
        programme: programme,
        catalogue: catalogue,
        sessionMinutes: profile?.schedule.sessionMinutes,
        preferredWeekdays: profile?.schedule.preferredWeekdays ?? const [],
      );

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
  /// [nextProgrammeSlot]. Used by the Equipment exercise page's "Add to
  /// programme" button (`exercise_reference.dart`).
  ///
  /// Throws [StateError] when nothing is active — the button only calls this
  /// after checking [activeProgrammeProvider] itself, so reaching here with
  /// none active would be this action being called from somewhere new that
  /// skipped that check, and failing loudly beats silently doing nothing.
  Future<void> addExerciseToActiveProgramme(ExerciseItem exercise) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot schedule a session while signed out');
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
      await ref.read(scheduledSessionRepositoryProvider).save(user.uid, session);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
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
List<String> programmeMuscles(ProgrammeTemplate template, UserProfile? profile) {
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
    if (latest == null || s.scheduledFor.isAfter(latest)) latest = s.scheduledFor;
  }
  final base = latest != null && latest.isAfter(n) ? latest : n;
  return base.add(const Duration(days: 1));
}
