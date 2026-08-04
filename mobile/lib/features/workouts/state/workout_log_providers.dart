import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../progress/data/progress_stats.dart';
import '../data/mock_workout_log_repository.dart';
import '../data/workout_log.dart';
import '../data/workout_log_repository.dart';
import '../data/workout_log_totals.dart';

/// Persistence provider — defaults to the in-memory mock; overridden in
/// `main.dart` to use the Firestore-backed implementation.
final workoutLogRepositoryProvider = Provider<WorkoutLogRepository>((ref) {
  final repo = MockWorkoutLogRepository();
  ref.onDispose(() {
    if (repo is MockWorkoutLogRepository) repo.dispose();
  });
  return repo;
});

/// Live history of the signed-in user, newest first. Empty list when there
/// is no signed-in user — keeps the Progress tab safe to render at all
/// router states.
final workoutLogsProvider = StreamProvider<List<WorkoutLogEntry>>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <WorkoutLogEntry>[]);
  final repo = ref.watch(workoutLogRepositoryProvider);
  return repo.watch(user.uid);
});

/// All-time count and streak record for the signed-in user.
///
/// A separate read from [workoutLogsProvider] on purpose. That listener is
/// windowed to the newest [kWorkoutHistoryWindow] entries so a cold start
/// stops costing the user's whole history, and these are the two numbers a
/// window cannot answer — see [WorkoutLogTotals].
///
/// One `count()` aggregation and one small document, fetched once per session
/// rather than streamed: neither number changes without this app writing it,
/// and [logWorkoutActionProvider] refreshes them when it does.
final workoutTotalsProvider = FutureProvider<WorkoutLogTotals>((ref) async {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return WorkoutLogTotals.zero;
  return ref.watch(workoutLogRepositoryProvider).totals(user.uid);
});

/// Imperative controller for the "Mark complete" CTA. Surfaces an
/// AsyncValue so the UI can render a loading spinner / error.
final logWorkoutActionProvider =
    NotifierProvider<LogWorkoutAction, AsyncValue<void>>(LogWorkoutAction.new);

class LogWorkoutAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> log(WorkoutLogEntry entry) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot log a workout while signed out');
      }
      final repo = ref.read(workoutLogRepositoryProvider);
      await repo.save(user.uid, entry);
      await _rememberStreak(repo, user.uid, entry);
      // The count just changed, and it is not streamed. Without this the
      // workouts figure on Home and Progress stays on its previous value
      // until the next cold start, which is more obviously wrong than the
      // read cost the window saves.
      ref.invalidate(workoutTotalsProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Writes the streak down while the days that make it are still visible.
  ///
  /// This is the write half of the windowed listener. The record is stored
  /// rather than recomputed because it cannot be recomputed later: once the
  /// consecutive days scroll past [kWorkoutHistoryWindow] the app can no
  /// longer see them, and a record derived from what is visible would quietly
  /// shrink. Finishing a workout is the only moment a streak can grow, so it
  /// is the only moment worth checking.
  ///
  /// Failures are swallowed. A record that did not get written is a cosmetic
  /// loss; failing the "Mark complete" the user just tapped, after the log
  /// itself saved, would be a real one.
  Future<void> _rememberStreak(
    WorkoutLogRepository repo,
    String uid,
    WorkoutLogEntry entry,
  ) async {
    try {
      final known = repo.cached(uid);
      final logs = [
        entry,
        for (final e in known)
          if (e.id != entry.id) e,
      ];
      final streak = deriveProgress(logs).currentStreakDays;
      if (streak > 0) await repo.recordStreak(uid, streak);
    } catch (_) {
      // Deliberate, and narrow: see above.
    }
  }
}