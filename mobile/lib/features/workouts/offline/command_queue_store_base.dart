/// Shared logic of the queue stores: unique indexes, cap, seq allocation,
/// transitions, pruning and an in-process critical section. Subclasses supply
/// only the durable writes ([persistRecord], [persistMetadata],
/// [removeRecordFromDisk]).
///
/// Ordering rule for every mutation: durable write first, in-memory view
/// second. A failed write therefore leaves the visible state unchanged.
library;

import 'dart:async';

import 'canonical.dart';
import 'command_queue_store.dart';
import 'command_record.dart';

abstract class BaseCommandQueueStore implements CommandQueueStore {
  BaseCommandQueueStore({required this.uid, int Function()? nowMs})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  @override
  final String uid;

  final int Function() _nowMs;
  final Map<String, CommandRecord> _records = <String, CommandRecord>{};

  /// `nextSeq` per `(sessionId, originDeviceInstallId)`. Never derived from
  /// remaining records and never pruned (section 2.1).
  final Map<String, int> _nextSeq = <String, int>{};

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  static String seqKey(String sessionId, String origin) =>
      '${sessionId.length}:$sessionId|$origin';

  // ---- hooks for subclasses -------------------------------------------

  /// Durably writes [record] (replacing any previous version of it).
  Future<void> persistRecord(CommandRecord record);

  /// Durably removes the record.
  Future<void> removeRecordFromDisk(String operationId);

  /// Durably writes the complete metadata (seq counters and logical-set
  /// markers) as ONE unit. A throw means nothing was changed on disk.
  Future<void> persistMetadata(
      Map<String, int> counters, Map<String, LogicalSetMarker> markers);

  /// Copy of the seq counters (for subclasses and tests).
  Map<String, int> get seqCountersView => Map<String, int>.of(_nextSeq);

  /// Logical-set identity markers; never pruned (see [LogicalSetMarker]).
  final Map<String, LogicalSetMarker> _markers = <String, LogicalSetMarker>{};

  /// True when [seed] had to add a marker that was missing on disk (crash
  /// between the record write and the marker write); the subclass persists the
  /// table then.
  bool markersNeedPersist = false;

  /// Non-null when the persisted metadata (seq counters or logical-set
  /// markers) could not be completely recovered. While set, [accept] and
  /// [prune] refuse to run (fail closed). Set by the subclass during load.
  String? recoveryRequiredReason;

  /// True while the store fails closed (see [recoveryRequiredReason]).
  bool get recoveryRequired => recoveryRequiredReason != null;

  /// Copy of the marker table (for subclasses and tests).
  Map<String, LogicalSetMarker> get markersView =>
      Map<String, LogicalSetMarker>.of(_markers);

  /// Loads state read from disk into memory. Call once, before first use.
  void seed(Iterable<CommandRecord> records, Map<String, int> counters,
      [Iterable<LogicalSetMarker> markers = const <LogicalSetMarker>[]]) {
    for (final m in markers) {
      _markers[m.logicalSetId] = m;
    }
    for (final r in records) {
      if (r.uid != uid) continue; // another uid is never visible
      _records[r.operationId] = r;
      final set = r.logicalSetId;
      if (set != null && !_markers.containsKey(set)) {
        _markers[set] = LogicalSetMarker(
            logicalSetId: set,
            operationId: r.operationId,
            acceptedAtLocalWallMs: r.acceptedAtLocalWallMs);
        markersNeedPersist = true;
      }
    }
    _nextSeq
      ..clear()
      ..addAll(counters);
    // A counter must never be behind a record that exists.
    for (final r in _records.values) {
      final key = seqKey(r.sessionId, r.originDeviceInstallId);
      final next = _nextSeq[key] ?? 1;
      if (next <= r.seq) _nextSeq[key] = r.seq + 1;
    }
  }

  /// Crash recovery (T10): a record left in SENDING by a dead process returns
  /// to the unknown-effect state (it may or may not have reached the server);
  /// `maybeSent` stays true. Returns the number of recovered records.
  Future<int> recoverInterrupted() => _locked(() async {
        var n = 0;
        for (final r in _records.values.toList()) {
          if (r.state != CommandState.sending) continue;
          final next = r.copyWith(state: CommandState.unknownEffect);
          await persistRecord(next);
          _records[r.operationId] = next;
          n++;
        }
        if (n > 0) _notify();
        return n;
      });

  // ---- CommandQueueStore ----------------------------------------------

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<AcceptResult> accept(AcceptRequest request) => _locked(() async {
        final recovery = recoveryRequiredReason;
        if (recovery != null) throw QueueRecoveryRequiredException(recovery);
        final byId = _records[request.operationId];
        if (byId != null) return _readopt(byId);

        for (final r in _records.values) {
          if (r.intentKey == request.intentKey) {
            return _readopt(r);
          }
        }
        // The marker outlives the pruned record stub, so this also covers a
        // set whose APPEND was synced and pruned.
        if (_markers.containsKey(request.logicalSetId)) {
          throw DuplicateLogicalSetException(request.logicalSetId);
        }
        for (final r in _records.values) {
          if (r.logicalSetId == request.logicalSetId &&
              r.operation == 'CompleteSet' &&
              r.state != CommandState.discarded) {
            throw DuplicateLogicalSetException(request.logicalSetId);
          }
        }
        final active =
            _records.values.where((r) => r.state.countsTowardCap).length;
        if (active >= kQueueRecordCap) throw QueueFullException();

        final key = seqKey(request.sessionId, request.originDeviceInstallId);
        final seq = _nextSeq[key] ?? 1;

        final record = request.build(seq);
        _validateBuilt(request, record, seq);
        await persistRecord(record);
        // Metadata (counter and marker) in ONE write after the record: a crash
        // between the two is healed by seed() (a surviving record raises its
        // counter and re-creates its marker). If the metadata write fails
        // while the process lives, nothing on disk or in memory changed in the
        // metadata and the record is rolled back, so "not saved" is true and a
        // retry of the same set works.
        final marker = LogicalSetMarker(
            logicalSetId: request.logicalSetId,
            operationId: record.operationId,
            acceptedAtLocalWallMs: record.acceptedAtLocalWallMs);
        try {
          await persistMetadata(Map<String, int>.of(_nextSeq)..[key] = seq + 1,
              Map.of(_markers)..[request.logicalSetId] = marker);
        } catch (_) {
          try {
            await removeRecordFromDisk(record.operationId);
          } catch (_) {
            // Double fault: the record file survives on disk (it is re-adopted
            // at the next open). Mirror that in memory now, so a retry of the
            // same tap finds this record instead of minting a second one. Its
            // marker stays missing; [_readopt] writes the metadata on retry.
            _records[record.operationId] = record;
            _markers[request.logicalSetId] = marker;
            _nextSeq[key] = seq + 1;
            _notify();
          }
          rethrow;
        }
        _nextSeq[key] = seq + 1;
        _records[record.operationId] = record;
        _markers[request.logicalSetId] = marker;
        _notify();
        return AcceptResult(record, created: true);
      });

  /// Returns an already accepted record for a repeated request. A record whose
  /// logical-set marker is missing (adopted after a failed metadata write and
  /// failed rollback, or loaded without its marker) gets its metadata written
  /// now, exactly like a fresh accept; a throw leaves the state unchanged.
  Future<AcceptResult> _readopt(CommandRecord r) async {
    final set = r.logicalSetId;
    if (set != null &&
        r.state != CommandState.discarded &&
        !_markers.containsKey(set)) {
      final key = seqKey(r.sessionId, r.originDeviceInstallId);
      final next = _nextSeq[key] ?? 1;
      final marker = LogicalSetMarker(
          logicalSetId: set,
          operationId: r.operationId,
          acceptedAtLocalWallMs: r.acceptedAtLocalWallMs);
      await persistMetadata(
          Map<String, int>.of(_nextSeq)..[key] = next > r.seq ? next : r.seq + 1,
          Map.of(_markers)..[set] = marker);
      _nextSeq[key] = next > r.seq ? next : r.seq + 1;
      _markers[set] = marker;
    }
    return AcceptResult(r, created: false);
  }

  void _validateBuilt(AcceptRequest req, CommandRecord r, int seq) {
    if (r.uid != uid) throw UidMismatchException();
    if (r.operationId != req.operationId ||
        r.sessionId != req.sessionId ||
        r.intentKey != req.intentKey ||
        r.logicalSetId != req.logicalSetId ||
        r.originDeviceInstallId != req.originDeviceInstallId ||
        r.seq != seq) {
      throw QueueException('built record does not match the accept request');
    }
    if (r.state != CommandState.accepted) {
      throw QueueException('V0 accepts records in state ACCEPTED only');
    }
    if (r.dependsOn.isNotEmpty) {
      throw QueueException('dependsOn is not supported in V0 (no HELD state)');
    }
    final bytes = r.canonicalBytes;
    if (bytes == null || payloadHashHex(bytes) != r.payloadHash) {
      throw QueueException('canonicalBytes missing or not matching payloadHash');
    }
  }

  @override
  Future<CommandRecord?> get(String operationId) =>
      _locked(() async => _records[operationId]);

  @override
  Future<List<CommandRecord>> listAll() => _locked(() async {
        final list = _records.values.toList()..sort(_byAcceptance);
        return list;
      });

  @override
  Future<List<CommandRecord>> listPending() => _locked(() async {
        final list = _records.values.where((r) => r.state.isSendable).toList()
          ..sort(_byAcceptance);
        return list;
      });

  static int _byAcceptance(CommandRecord a, CommandRecord b) {
    final t = a.acceptedAtLocalWallMs.compareTo(b.acceptedAtLocalWallMs);
    if (t != 0) return t;
    final s = a.seq.compareTo(b.seq);
    if (s != 0) return s;
    return a.operationId.compareTo(b.operationId);
  }

  @override
  Future<CommandRecord> markSending(String operationId) => _locked(() async {
        final r = _require(operationId);
        if (!isTransitionAllowed(r.state, CommandState.sending)) {
          throw InvalidTransitionException(
              'cannot start sending from ${r.state.wire}');
        }
        if (r.canonicalBytes == null) {
          throw InvalidTransitionException('record has no payload to send');
        }
        final next = r.copyWith(
          state: CommandState.sending,
          maybeSent: true,
          attempts: r.attempts + 1,
          lastAttemptLocalMs: _nowMs(),
        );
        await persistRecord(next);
        _records[operationId] = next;
        _notify();
        return next;
      });

  @override
  Future<CommandRecord> markResult(String operationId, CommandResult result) =>
      _locked(() async {
        final r = _require(operationId);
        if (r.state == CommandState.synced &&
            result.to == CommandState.synced) {
          return r; // idempotent re-acknowledgement
        }
        if (!isTransitionAllowed(r.state, result.to)) {
          throw InvalidTransitionException(
              'transition ${r.state.wire} -> ${result.to.wire} is not allowed');
        }
        if (r.state == CommandState.unknownEffect &&
            !(result.to == CommandState.conflicted &&
                result.conflictTerminal == true)) {
          // T9 is the only transition out of UNKNOWN_EFFECT other than T6.
          throw InvalidTransitionException(
              'UNKNOWN_EFFECT may only move to terminal CONFLICTED or SENDING');
        }
        final CommandRecord next;
        switch (result.to) {
          case CommandState.synced:
            next = r
                .copyWith(
                  state: CommandState.synced,
                  lastResultCode: result.resultCode,
                  ackSummary: AckSummary(
                    revisionAfter: result.revisionAfter,
                    serverTimeMs: result.serverTimeMs,
                    detailExpired: result.detailExpired,
                    superseded: result.superseded,
                    localAckMs: _nowMs(),
                  ),
                )
                .erasePayload(); // T7 / section 3.6
          case CommandState.conflicted:
            next = r.copyWith(
              state: CommandState.conflicted,
              conflictKind: result.conflictKind ?? result.resultCode,
              conflictTerminal: result.conflictTerminal ?? true,
              lastResultCode: result.resultCode,
            );
          case CommandState.unknownEffect:
          case CommandState.accepted:
            next = r.copyWith(
              state: result.to,
              lastResultCode: result.resultCode,
            );
          case CommandState.sending:
          case CommandState.held:
          case CommandState.discarded:
            throw InvalidTransitionException(
                'target ${result.to.wire} is not a result state');
        }
        await persistRecord(next);
        _records[operationId] = next;
        _notify();
        return next;
      });

  @override
  Future<int> prune() => _locked(() async {
        // Pruning rewrites the marker table from memory; with incomplete
        // metadata that could drop information for good.
        if (recoveryRequired) return 0;
        final cutoff = _nowMs() - kStubRetention.inMilliseconds;
        var n = 0;
        for (final r in _records.values.toList()) {
          if (r.state != CommandState.synced) continue;
          final at = r.ackSummary?.localAckMs;
          if (at == null || at > cutoff) continue;
          // Make sure the identity marker is durable before its record goes.
          // Defensive: a record being pruned always leaves its marker behind.
          final set = r.logicalSetId;
          final markers = Map.of(_markers);
          if (set != null && !markers.containsKey(set)) {
            markers[set] = LogicalSetMarker(
                logicalSetId: set,
                operationId: r.operationId,
                acceptedAtLocalWallMs: r.acceptedAtLocalWallMs);
          }
          await persistMetadata(Map<String, int>.of(_nextSeq), markers);
          if (set != null) _markers.putIfAbsent(set, () => markers[set]!);
          await removeRecordFromDisk(r.operationId);
          _records.remove(r.operationId);
          n++;
        }
        if (n > 0) _notify();
        return n;
      });

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _tail;
    await _changes.close();
  }

  // ---- internals --------------------------------------------------------

  CommandRecord _require(String operationId) =>
      _records[operationId] ??
      (throw InvalidTransitionException('unknown operationId'));

  void _notify() {
    if (!_disposed && !_changes.isClosed) _changes.add(null);
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _tail;
    _tail = completer.future.then<void>((_) {}, onError: (Object _) {});
    previous.then<void>((_) async {
      try {
        completer.complete(await action());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }
}
