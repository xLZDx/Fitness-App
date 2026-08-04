import 'scheduled_session.dart';

/// Persistence interface for upcoming/past scheduled workouts. The default
/// in-memory implementation is `MockScheduledSessionRepository`; production
/// uses `FirestoreScheduledSessionRepository` writing to
/// `users/{uid}/scheduled_sessions/{id}`.
/// How many of the latest-dated sessions the listener carries.
///
/// Everything reading this stream looks forward -- `filterUpcoming` at 14
/// days, the offline prefetch at 7 -- and completed sessions are never
/// deleted, so the collection grows in the direction nobody reads. 50 is far
/// more than any of those windows need.
const int kScheduledSessionWindow = 50;

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
