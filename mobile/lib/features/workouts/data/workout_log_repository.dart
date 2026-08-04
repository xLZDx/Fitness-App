import 'workout_log.dart';
import 'workout_log_totals.dart';

/// How many of the newest entries the history listener carries.
///
/// Four sessions a week for a year is about 200, and every consumer of the
/// stream wants far less than that: the progress chart shows 8 weeks, the
/// personalisation model looks at 7 days, and Home renders the most recent
/// few. The number is generous on purpose — the point is to stop the cost of
/// a cold start scaling with account age, not to trim it to the minimum.
///
/// The two figures a window genuinely cannot serve live in [WorkoutLogTotals].
const int kWorkoutHistoryWindow = 200;

/// Persistence interface for completed-workout logs. The default
/// implementation is in-memory ([MockWorkoutLogRepository]); production
/// uses [FirestoreWorkoutLogRepository] writing under
/// `users/{uid}/workout_logs/{id}`.
abstract class WorkoutLogRepository {
  /// Streams the user's most recent [kWorkoutHistoryWindow] workouts, newest
  /// first. Emits an empty list when there are no logs.
  ///
  /// Windowed rather than complete: this listener attaches on the landing
  /// screen, so an unbounded version re-downloaded the user's entire history
  /// on every cold start. For anything all-time, see [totals].
  Stream<List<WorkoutLogEntry>> watch(String uid);

  /// The all-time count and streak record — the numbers [watch] cannot answer
  /// once it is windowed. See [WorkoutLogTotals] for why they are separate.
  Future<WorkoutLogTotals> totals(String uid);

  /// Raises the stored streak record to [days] if it beats what is there.
  ///
  /// Never lowers it. The record is set while the days that make it are still
  /// inside the window, and once written it outlives them.
  Future<void> recordStreak(String uid, int days);

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

  /// Every logged workout, unwindowed. For data export (L0c) only.
  ///
  /// [watch] caps at [kWorkoutHistoryWindow] on purpose — that is the fix N2
  /// shipped for cold-start cost, and reusing it here would silently cap a
  /// user's own export at 200 entries with no indication anything was left
  /// out. An export that quietly drops rows is worse than no export: it
  /// gives false confidence that "I have my data" when part of it is
  /// missing.
  Future<List<WorkoutLogEntry>> exportAll(String uid);
}
