import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../data/mock_workout_session_repository.dart';
import '../data/workout_log_totals.dart';
import '../data/workout_session.dart';
import '../data/workout_session_repository.dart';

/// F3.2 -- infrastructure only. Nothing reads these yet; the write path
/// (F3.4) and the read-side convergence (F3.3) are separate, later gates.
/// See `core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md`.
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

/// All-time count and streak record for sessions. Independent of
/// `workoutTotalsProvider` (logs) until F3.3b decides how the two converge.
final workoutSessionTotalsProvider =
    FutureProvider<WorkoutLogTotals>((ref) async {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return WorkoutLogTotals.zero;
  return ref.watch(workoutSessionRepositoryProvider).totals(user.uid);
});
