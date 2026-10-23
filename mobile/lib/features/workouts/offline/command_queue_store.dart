/// Storage contract of the offline command queue (protocol section 3):
/// durable acceptance with unique indexes, listing, send-start and result
/// commits, and pruning. Two implementations exist: the file store and an
/// in-memory fake, both built on `BaseCommandQueueStore`.
library;

import 'command_record.dart';

/// Hard cap of records in states that count toward it (section 3.3 step 1).
const int kQueueRecordCap = 500;

/// Retention of SYNCED stubs before pruning (T16, section 3.6).
const Duration kStubRetention = Duration(days: 7);

class QueueException implements Exception {
  QueueException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The 500 record cap is reached; the caller shows "not saved".
class QueueFullException extends QueueException {
  QueueFullException() : super('queue is full ($kQueueRecordCap records)');
}

/// A second APPEND for a logical set that already has a non-discarded one
/// (local unique index of section 3.1).
class DuplicateLogicalSetException extends QueueException {
  DuplicateLogicalSetException(String logicalSetId)
      : super('logical set already has an APPEND: $logicalSetId');
}

/// The queue metadata (`seq.json` or `logical_sets.json`) could not be fully
/// recovered at open. The store fails closed: it refuses new appends (and
/// pruning) so a reused seq or a lost logical-set marker cannot occur, until
/// the metadata is recoverable again. Existing records stay readable.
class QueueRecoveryRequiredException extends QueueException {
  QueueRecoveryRequiredException(String reason)
      : super('queue metadata needs recovery: $reason');
}

/// A record or request belongs to another uid than the store.
class UidMismatchException extends QueueException {
  UidMismatchException() : super('record uid does not match the store uid');
}

/// A transition outside the implemented table or an unknown record.
class InvalidTransitionException extends QueueException {
  InvalidTransitionException(super.message);
}

/// Minimal durable identity marker of a logical set (the identity part of the
/// `effective_set` marker, spec 3.6). It holds no workout value, survives the
/// pruning of the record stub, and makes a second APPEND for the set
/// impossible. Retention and deletion (account deletion, discard refinement of
/// 3.6) are out of V0: markers are never removed in this slice.
class LogicalSetMarker {
  const LogicalSetMarker({
    required this.logicalSetId,
    required this.operationId,
    required this.acceptedAtLocalWallMs,
  });

  final String logicalSetId;
  final String operationId;
  final int acceptedAtLocalWallMs;
}

/// Everything needed to commit one command. [build] is called inside the
/// store's critical section with the freshly allocated `seq`, so the hashed
/// payload can contain it; it must be pure and return a record in state
/// ACCEPTED whose identity matches this request.
class AcceptRequest {
  const AcceptRequest({
    required this.operationId,
    required this.intentKey,
    required this.sessionId,
    required this.originDeviceInstallId,
    required this.logicalSetId,
    required this.build,
  });

  final String operationId;
  final String intentKey;
  final String sessionId;
  final String originDeviceInstallId;
  final String logicalSetId;
  final CommandRecord Function(int seq) build;
}

class AcceptResult {
  const AcceptResult(this.record, {required this.created});

  final CommandRecord record;

  /// False when the same operationId or intentKey was already committed and
  /// the stored record is returned unchanged.
  final bool created;
}

/// The sender's description of an outcome, committed by `markResult`.
class CommandResult {
  const CommandResult({
    required this.to,
    this.resultCode,
    this.conflictKind,
    this.conflictTerminal,
    this.revisionAfter,
    this.serverTimeMs,
    this.detailExpired = false,
    this.superseded = false,
  });

  /// Target state; the store validates it with `isTransitionAllowed`.
  final CommandState to;
  final String? resultCode;
  final String? conflictKind;
  final bool? conflictTerminal;
  final int? revisionAfter;
  final int? serverTimeMs;
  final bool detailExpired;
  final bool superseded;
}

/// Optional capability of a store: record files that exist but cannot be
/// read. Such records can never be sent, so status must not read as synced.
abstract class HasUnreadableRecords {
  int get unreadableRecordCount;
}

abstract class CommandQueueStore {
  /// The uid this store is scoped to. Records of another uid are never visible.
  String get uid;

  /// Fires after every committed change (accept, send start, result, prune).
  Stream<void> get changes;

  /// Durable commit (T1). Completes only after the record is durable.
  ///
  /// - same `operationId` already stored: no-op, returns the stored record;
  /// - same `intentKey` already stored: no-op, returns that record;
  /// - second APPEND for the same logical set: [DuplicateLogicalSetException];
  /// - cap reached: [QueueFullException]; wrong uid: [UidMismatchException].
  Future<AcceptResult> accept(AcceptRequest request);

  Future<CommandRecord?> get(String operationId);

  /// Every stored record of this uid, oldest first (by `seq` per session).
  Future<List<CommandRecord>> listAll();

  /// ACCEPTED and UNKNOWN_EFFECT records, ordered by acceptance time then seq.
  Future<List<CommandRecord>> listPending();

  /// T6: one commit sets SENDING, `maybeSent = true`, increments `attempts`.
  Future<CommandRecord> markSending(String operationId);

  /// Commits the outcome of a send attempt. Re-applying a result to a record
  /// already SYNCED with the same target is a no-op that returns the record.
  Future<CommandRecord> markResult(String operationId, CommandResult result);

  /// Removes SYNCED stubs older than [kStubRetention]. Never touches a record
  /// in another state, the `seq` counters or any other table. Returns the
  /// number of removed records.
  Future<int> prune();

  Future<void> dispose();
}
