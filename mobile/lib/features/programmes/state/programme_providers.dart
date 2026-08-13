import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
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

      final programme = Programme(
        id: '${DateTime.now().microsecondsSinceEpoch}_${template.id}',
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
        daysPerWeek: template.daysPerWeek,
        muscles: template.muscles,
        startedAt: DateTime.now(),
      );

      final catalogue = await ref.read(safeCatalogProvider.future);
      final rows = buildProgrammeSchedule(
        programme: programme,
        catalogue: catalogue,
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
