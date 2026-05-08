import 'workout_log.dart';

/// Persistence interface for completed-workout logs. The default
/// implementation is in-memory ([MockWorkoutLogRepository]); production
/// uses [FirestoreWorkoutLogRepository] writing under
/// `users/{uid}/workout_logs/{id}`.
abstract class WorkoutLogRepository {
  /// Streams the user's full workout history, newest first. Emits an empty
  /// list when there are no logs.
  Stream<List<WorkoutLogEntry>> watch(String uid);

  /// Synchronous read of the most recent watch() emission. Returns the
  /// empty list if the user's history hasn't been observed yet.
  List<WorkoutLogEntry> cached(String uid);

  /// Persists [entry]. Idempotent on [WorkoutLogEntry.id].
  Future<void> save(String uid, WorkoutLogEntry entry);

  /// Removes a single entry by id.
  Future<void> delete(String uid, String entryId);

  /// Wipes the user's entire history. Used for "reset progress" flows
  /// (Phase 5 GDPR work).
  Future<void> clear(String uid);
}
