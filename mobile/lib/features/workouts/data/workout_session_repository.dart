import 'workout_log_totals.dart';
import 'workout_session.dart';

/// Same window rationale as [kWorkoutHistoryWindow] in
/// `workout_log_repository.dart` -- copied rather than shared so F3.3's
/// merge step controls both windows independently while both collections
/// exist. Kept equal to the log window; nothing requires them to diverge.
const int kWorkoutSessionHistoryWindow = 200;

/// Persistence interface for [WorkoutSession]s. Mirrors
/// [WorkoutLogRepository]'s shape deliberately -- see
/// `core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md` F3.1. `clear` and
/// `exportAll` are present from the start rather than added once someone
/// notices GDPR reset/export don't cover sessions.
abstract class WorkoutSessionRepository {
  /// Streams the user's most recent [kWorkoutSessionHistoryWindow] sessions,
  /// newest first. Emits an empty list when there are none.
  Stream<List<WorkoutSession>> watch(String uid);

  /// All-time count and streak record. See [WorkoutLogTotals] for why these
  /// are not derived from the windowed [watch] stream.
  Future<WorkoutLogTotals> totals(String uid);

  /// Raises the stored streak record to [days] if it beats what is there.
  /// Never lowers it.
  Future<void> recordStreak(String uid, int days);

  /// Synchronous read of the most recent [watch] emission.
  List<WorkoutSession> cached(String uid);

  /// Persists [session]. Idempotent on [WorkoutSession.id].
  Future<void> save(String uid, WorkoutSession session);

  /// Removes a single session by id.
  Future<void> delete(String uid, String sessionId);

  /// Wipes the user's entire session history. Used for "reset progress"
  /// flows.
  Future<void> clear(String uid);

  /// Every session, unwindowed. For data export only -- same rationale as
  /// `WorkoutLogRepository.exportAll` (`workout_log_repository.dart`): an
  /// export that quietly caps at the history window gives false confidence
  /// that "I have my data" when part of it is missing.
  Future<List<WorkoutSession>> exportAll(String uid);
}
