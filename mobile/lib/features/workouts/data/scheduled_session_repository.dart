import 'scheduled_session.dart';

/// Persistence interface for upcoming/past scheduled workouts. The default
/// in-memory implementation is `MockScheduledSessionRepository`; production
/// uses `FirestoreScheduledSessionRepository` writing to
/// `users/{uid}/scheduled_sessions/{id}`.
abstract class ScheduledSessionRepository {
  /// Streams every scheduled session for the user, sorted by
  /// [ScheduledSession.scheduledFor] ascending.
  Stream<List<ScheduledSession>> watch(String uid);

  /// Synchronous read of the most recent stream emission.
  List<ScheduledSession> cached(String uid);

  /// Inserts or updates [session]. Idempotent on [ScheduledSession.id].
  Future<void> save(String uid, ScheduledSession session);

  /// Removes a single session by id.
  Future<void> delete(String uid, String sessionId);

  /// Wipes the entire schedule.
  Future<void> clear(String uid);
}
