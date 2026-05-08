import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../data/mock_workout_log_repository.dart';
import '../data/workout_log.dart';
import '../data/workout_log_repository.dart';

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
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
