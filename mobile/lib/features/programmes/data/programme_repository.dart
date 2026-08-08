import 'programme.dart';

/// Persistence interface for a user's programme enrolments. Mirrors
/// `ScheduledSessionRepository`'s shape deliberately — same watch/cached/save
/// contract, same reason: the default in-memory implementation is
/// `MockProgrammeRepository`; production uses `FirestoreProgrammeRepository`
/// writing to `users/{uid}/programmes/{id}`.
abstract class ProgrammeRepository {
  /// Streams every programme the user has enrolled in, newest [Programme.startedAt]
  /// first. Unlike scheduled sessions this is not windowed — a user
  /// accumulates a handful of programmes over years, not tens of thousands of
  /// rows, so there is no unbounded-growth problem to cap.
  Stream<List<Programme>> watch(String uid);

  /// Synchronous read of the most recent stream emission.
  List<Programme> cached(String uid);

  /// Inserts or updates [programme]. Idempotent on [Programme.id].
  Future<void> save(String uid, Programme programme);

  /// Removes a single programme by id. Does NOT touch the
  /// `ScheduledSession` rows it generated — those are owned by
  /// `ScheduledSessionRepository` and outlive the programme that scheduled
  /// them, same as a deleted workout log entry does not retroactively unwind
  /// history.
  Future<void> delete(String uid, String programmeId);

  /// Every programme, for data export (L0c).
  Future<List<Programme>> exportAll(String uid);
}
