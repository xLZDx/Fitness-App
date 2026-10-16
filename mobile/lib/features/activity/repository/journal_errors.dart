/// Typed errors of the local activity journal (S02 design 10, 3.5).
///
/// Every failure of a mutation leaves the previous durable state intact; the
/// caller can retry with the same input. [JournalWriteFailure.pending] carries
/// the session that could not be stored so a recording is kept in memory.
library;

import '../data/activity_session.dart';

/// Base class of every journal error.
abstract class JournalException implements Exception {
  const JournalException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A mutation could not be stored. The previous committed state is untouched.
class JournalWriteFailure extends JournalException {
  const JournalWriteFailure(super.message, {this.cause, this.pending});

  final Object? cause;

  /// The session the caller tried to store, kept for a later retry.
  final ActivitySession? pending;
}

/// The device storage is full (design 10: typed "storage full" error).
class JournalStorageFullException extends JournalWriteFailure {
  const JournalStorageFullException(super.message, {super.cause, super.pending});
}

/// Any other I/O failure during a mutation.
class JournalIoException extends JournalWriteFailure {
  const JournalIoException(super.message, {super.cause, super.pending});
}

/// The encryption key could not be read (a transient secure-storage failure).
/// No key is ever minted in this state: a new key would orphan every stream.
class JournalKeyUnavailable extends JournalWriteFailure {
  const JournalKeyUnavailable(super.message, {super.cause, super.pending});
}

/// The id was deleted (tombstone) and a put for it was refused: delete wins
/// (design 6.2).
class JournalTombstonedException extends JournalException {
  const JournalTombstonedException(String id)
      : super('activity $id has a tombstone; put refused');
}

/// A record written by a newer app must never be rewritten by this build.
class JournalReadOnlyException extends JournalException {
  const JournalReadOnlyException(String id)
      : super('activity $id has a newer schema and is read-only');
}

/// The activity id is not a safe single path segment.
class JournalInvalidIdException extends JournalException {
  const JournalInvalidIdException(String id)
      : super('invalid activity id: ${id.length > 80 ? id.substring(0, 80) : id}');
}

/// A second journal instance was opened on a directory that is already owned
/// by a live instance (cross-process and multi-instance writers are not
/// supported, design 10 single writer).
class JournalAlreadyOpenException extends JournalException {
  const JournalAlreadyOpenException(String root)
      : super('journal directory is already open: $root');
}

/// The journal was used before `start()` or after `close()`.
class JournalNotStartedException extends JournalException {
  const JournalNotStartedException()
      : super('journal is not started (call start() first, not after close())');
}
