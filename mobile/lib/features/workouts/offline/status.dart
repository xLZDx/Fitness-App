/// Pending versus synced status derived from the queue (protocol 3.8,
/// limited to pending vs synced). "Synced" is derived only from records in
/// state SYNCED, and a record reaches SYNCED only through a server answer of
/// class C1 or C2 (4.4). Nothing here is connected to any screen yet.
library;

import 'dart:async';

import 'command_queue_store.dart';
import 'command_record.dart';

/// Counts for one session.
class SessionSyncStatus {
  const SessionSyncStatus({
    required this.sessionId,
    this.pending = 0,
    this.synced = 0,
    this.superseded = 0,
    this.couldNotSync = 0,
  });

  final String sessionId;

  /// ACCEPTED, SENDING, UNKNOWN_EFFECT, HELD: "saved on this device, waiting
  /// to sync".
  final int pending;

  /// SYNCED and not superseded: "synced".
  final int synced;

  /// SYNCED with the superseded flag: "replaced by a newer change"; never
  /// shown as plain "synced".
  final int superseded;

  /// CONFLICTED: "could not sync".
  final int couldNotSync;

  bool get hasPending => pending > 0;

  /// True only when nothing is pending or failed for this session.
  bool get isFullySynced => pending == 0 && couldNotSync == 0;
}

class SyncStatusSnapshot {
  const SyncStatusSnapshot(this.sessions, {this.unreadableRecords = 0});

  static const SyncStatusSnapshot empty = SyncStatusSnapshot(<String, SessionSyncStatus>{});

  final Map<String, SessionSyncStatus> sessions;

  /// Record files on disk that cannot be read (their session is unknown).
  /// They can never be sent, so they count as "could not sync" everywhere.
  final int unreadableRecords;

  int get pending => sessions.values.fold(0, (a, s) => a + s.pending);
  int get synced => sessions.values.fold(0, (a, s) => a + s.synced);
  int get couldNotSync =>
      sessions.values.fold(0, (a, s) => a + s.couldNotSync) + unreadableRecords;
  bool get hasPending => pending > 0;

  /// False whenever anything is pending, failed or unreadable.
  bool get isFullySynced => pending == 0 && couldNotSync == 0;

  /// The unreadable files cannot be attributed to a session, so every session
  /// reports them as "could not sync" (conservative).
  SessionSyncStatus forSession(String sessionId) {
    final s = sessions[sessionId] ?? SessionSyncStatus(sessionId: sessionId);
    if (unreadableRecords == 0) return s;
    return SessionSyncStatus(
      sessionId: sessionId,
      pending: s.pending,
      synced: s.synced,
      superseded: s.superseded,
      couldNotSync: s.couldNotSync + unreadableRecords,
    );
  }
}

/// Pure reduction of records to a snapshot (DISCARDED records are ignored).
SyncStatusSnapshot summarizeRecords(Iterable<CommandRecord> records,
    {int unreadableRecords = 0}) {
  final pending = <String, int>{};
  final synced = <String, int>{};
  final superseded = <String, int>{};
  final failed = <String, int>{};
  final ids = <String>{};
  void bump(Map<String, int> m, String k) => m[k] = (m[k] ?? 0) + 1;
  for (final r in records) {
    switch (r.state) {
      case CommandState.accepted:
      case CommandState.sending:
      case CommandState.unknownEffect:
      case CommandState.held:
        ids.add(r.sessionId);
        bump(pending, r.sessionId);
      case CommandState.synced:
        ids.add(r.sessionId);
        bump((r.ackSummary?.superseded ?? false) ? superseded : synced, r.sessionId);
      case CommandState.conflicted:
        ids.add(r.sessionId);
        bump(failed, r.sessionId);
      case CommandState.discarded:
        break;
    }
  }
  return SyncStatusSnapshot({
    for (final id in ids)
      id: SessionSyncStatus(
        sessionId: id,
        pending: pending[id] ?? 0,
        synced: synced[id] ?? 0,
        superseded: superseded[id] ?? 0,
        couldNotSync: failed[id] ?? 0,
      ),
  }, unreadableRecords: unreadableRecords);
}

/// Interface the UI will consume later.
abstract class CommandSyncStatusSource {
  Future<SyncStatusSnapshot> snapshot();

  /// Emits the current snapshot first, then one per change of the queue.
  Stream<SyncStatusSnapshot> watch();
}

class StoreSyncStatusSource implements CommandSyncStatusSource {
  StoreSyncStatusSource(this.store);

  final CommandQueueStore store;

  @override
  Future<SyncStatusSnapshot> snapshot() async {
    final s = store;
    return summarizeRecords(
      await store.listAll(),
      unreadableRecords: s is HasUnreadableRecords
          ? (s as HasUnreadableRecords).unreadableRecordCount
          : 0,
    );
  }

  @override
  Stream<SyncStatusSnapshot> watch() {
    late final StreamController<SyncStatusSnapshot> controller;
    StreamSubscription<void>? sub;
    // Snapshots are computed one after another so they are emitted in order.
    var chain = Future<void>.value();
    void emit() {
      chain = chain.then((_) async {
        if (controller.isClosed) return;
        try {
          final s = await snapshot();
          if (!controller.isClosed) controller.add(s);
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      });
    }

    controller = StreamController<SyncStatusSnapshot>(
      onListen: () {
        emit();
        sub = store.changes.listen((_) => emit());
      },
      // Cancelling returns promptly: it only cancels the change subscription.
      onCancel: () async {
        final s = sub;
        sub = null;
        await s?.cancel();
      },
    );
    return controller.stream;
  }
}
