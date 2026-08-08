import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../progress/data/progress_stats.dart';
import '../data/mock_workout_session_repository.dart';
import '../data/workout_log.dart' show WorkoutLogEntry;
import '../data/workout_log_totals.dart';
import '../data/workout_session.dart';
import '../data/workout_session_repository.dart';

/// F3.3/F3.4: the read-side convergence and the write path both now use
/// these providers. See `core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md`.
final workoutSessionRepositoryProvider =
    Provider<WorkoutSessionRepository>((ref) {
  final repo = MockWorkoutSessionRepository();
  ref.onDispose(() {
    if (repo is MockWorkoutSessionRepository) repo.dispose();
  });
  return repo;
});

/// Live session history of the signed-in user, newest first. Empty when
/// signed out -- mirrors `workoutLogsProvider`'s null-safety shape.
final workoutSessionsProvider = StreamProvider<List<WorkoutSession>>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <WorkoutSession>[]);
  final repo = ref.watch(workoutSessionRepositoryProvider);
  return repo.watch(user.uid);
});

/// All-time count and streak record for sessions.
///
/// F3.3b: this is now the totals source the app reads (`progress_page.dart`,
/// `home_page.dart`) instead of the old `workoutTotalsProvider` (logs). The
/// `total` count is always correct going forward -- a server-side `count()`
/// over the now-backfilled `workout_sessions` collection. `longestStreakDays`
/// needed its own one-time backfill from `stats/workouts` into
/// `stats/workout_sessions` (the F3.3 document backfill never touched this
/// separate stats document) -- see `functions/scripts/backfill_workout_sessions.mjs`'s
/// streak-record step. Without that backfill, every existing user's streak
/// record would silently read back as 0 the first time this provider was
/// used, even though the count and history were both correct.
final workoutSessionTotalsProvider =
    FutureProvider<WorkoutLogTotals>((ref) async {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return WorkoutLogTotals.zero;
  return ref.watch(workoutSessionRepositoryProvider).totals(user.uid);
});

/// F3.3 read-convergence, extended at R11e: [workoutSessionsProvider]
/// reshaped into the [WorkoutLogEntry] view every existing consumer
/// (progress, home, suggestions, recovery, personalisation, data export)
/// already reads via [WorkoutSessionLogView.asLogEntries] -- now `expand`ed
/// rather than `map`ped, because R11e's multi-exercise sessions can produce
/// more than one row per session (see that method's own doc comment). Only
/// completed sessions are included -- a pending/abandoned session has no
/// [WorkoutSession.completedAt] and is not a past workout to show.
final workoutSessionHistoryProvider = Provider<List<WorkoutLogEntry>>((ref) {
  final sessions =
      ref.watch(workoutSessionsProvider).valueOrNull ?? const <WorkoutSession>[];
  return sessions
      .where((s) =>
          s.status == WorkoutSessionStatus.completed && s.completedAt != null)
      .expand((s) => s.asLogEntries())
      .toList(growable: false);
});

/// F3.4: imperative controller for the "Mark complete" CTA. Mirrors
/// `LogWorkoutAction` in `workout_log_providers.dart` -- same streak-write
/// timing and swallowed-streak-write-failure rationale, see that class's doc
/// comments. This is now the ONLY write path new completions use;
/// `workout_logs` stops receiving new entries from this point on (it stays
/// read-only historical data, per the plan doc's F3.3 section).
final logSessionActionProvider =
    NotifierProvider<LogSessionAction, AsyncValue<void>>(
        LogSessionAction.new);

class LogSessionAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> log(WorkoutSession session) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot log a workout while signed out');
      }
      final repo = ref.read(workoutSessionRepositoryProvider);
      await repo.save(user.uid, session);
      await _rememberStreak(repo, user.uid, session);
      ref.invalidate(workoutSessionTotalsProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Same rationale as `LogWorkoutAction._rememberStreak`: the record is
  /// stored because it cannot be recomputed once the streak days scroll past
  /// the history window. Filtered to completed sessions first -- same
  /// invariant `workoutSessionHistoryProvider` and the data-export path
  /// enforce, since `asLogEntryView()` fabricates a completion time for a
  /// session that has none.
  Future<void> _rememberStreak(
    WorkoutSessionRepository repo,
    String uid,
    WorkoutSession session,
  ) async {
    try {
      final known = repo.cached(uid);
      final sessions = [
        session,
        for (final s in known)
          if (s.id != session.id) s,
      ];
      final logs = sessions
          .where((s) =>
              s.status == WorkoutSessionStatus.completed &&
              s.completedAt != null)
          .expand((s) => s.asLogEntries())
          .toList();
      final streak = deriveProgress(logs).currentStreakDays;
      if (streak > 0) await repo.recordStreak(uid, streak);
    } catch (_) {
      // Deliberate, and narrow: see LogWorkoutAction._rememberStreak.
    }
  }
}
