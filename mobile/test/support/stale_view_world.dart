// Test-only helpers for the stale-view and deletion-flag tests (S02 test epic
// 14b, remediation H-B): a deterministic gate, a recording backend whose reads
// and writes can be blocked, and a scoped journal that records every mutation
// and can run a hook at chosen points (so a test can switch the account at an
// exact moment without sleeps).
import 'dart:async';

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart' show ActivityJournalFactory;
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';

/// A one-shot rendezvous: the code under test calls [pass]; the test awaits
/// [entered], does something, then completes [release].
class Gate {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  Future<void> pass() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }

  void open() {
    if (!release.isCompleted) release.complete();
  }
}

/// Lets every pending microtask and zero-delay timer run.
Future<void> settle() async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A recording backend with the rev rule of the real rules and optional gates.
class RecBackend implements ActivitySummaryBackend {
  final List<String> calls = [];
  final Set<String> tombs = {};
  final Map<String, Map<String, Object?>> docs = {};

  /// Blocks the NEXT `listTombstoneIds` (after the answer was computed).
  Gate? listGate;

  /// Blocks the NEXT `readSummary` (after the answer was computed).
  Gate? readGate;

  /// Blocks the NEXT `writeSummary` (before the document is stored).
  Gate? writeGate;

  Iterable<String> get writes => calls.where((c) => c.startsWith('writeSummary'));

  @override
  Future<Set<String>> listTombstoneIds() async {
    calls.add('listTombstoneIds');
    final r = {...tombs};
    final g = listGate;
    listGate = null;
    if (g != null) await g.pass();
    return r;
  }

  @override
  Future<bool> tombstoneExists(String id) async {
    calls.add('tombstoneExists:$id');
    return tombs.contains(id);
  }

  @override
  Future<Map<String, Object?>?> readSummary(String id) async {
    calls.add('readSummary:$id');
    final d = docs[id];
    final r = d == null ? null : {...d};
    final g = readGate;
    readGate = null;
    if (g != null) await g.pass();
    return r;
  }

  @override
  Future<void> writeSummary(String id, Map<String, Object> summary,
      {required bool create}) async {
    calls.add('writeSummary:$id');
    final g = writeGate;
    writeGate = null;
    if (g != null) await g.pass();
    final stored = docs[id];
    if (create) {
      if (stored != null || summary['rev'] != 1) {
        throw const SummaryWriteDenied('create over an existing document');
      }
    } else {
      final old = stored?['rev'];
      final rev = summary['rev'];
      if (stored == null || rev is! int || old is! int || rev <= old) {
        throw const SummaryWriteDenied('rev must increase');
      }
    }
    docs[id] = {...summary};
  }
}

/// The real scoped journal plus a mutation log and hooks.
class HookJournal extends UidScopedActivityJournal {
  HookJournal(ActivityJournalFactory f) : super(factory: f);

  /// Every mutating call, by name, in order.
  final List<String> mutations = [];

  /// Blocks the NEXT `updateSyncState` before it is delegated.
  Gate? updateSyncStateGate;

  /// Blocks the NEXT `list` after its result was computed (the caller then gets
  /// the list of the account that was bound when the call started).
  Gate? listGate;

  /// Runs after every `list` result was computed, before it is returned.
  Future<void> Function()? onListed;

  /// Runs after every `read` result was computed, before it is returned; the
  /// argument is the 1-based number of the read.
  Future<void> Function(int n)? onRead;

  int reads = 0;

  @override
  Future<List<JournalEntry>> list() async {
    final r = await super.list();
    final g = listGate;
    listGate = null;
    if (g != null) await g.pass();
    await onListed?.call();
    return r;
  }

  @override
  Future<JournalEntry?> read(String id) async {
    final r = await super.read(id);
    reads++;
    await onRead?.call(reads);
    return r;
  }

  @override
  Future<JournalEntry> put(ActivitySession session,
      {JournalSyncState? syncState,
      int? baseRev,
      Map<String, Object?>? baseSummary}) {
    mutations.add('put');
    return super.put(session,
        syncState: syncState, baseRev: baseRev, baseSummary: baseSummary);
  }

  @override
  Future<void> delete(String id) {
    mutations.add('delete');
    return super.delete(id);
  }

  @override
  Future<bool> updateSyncState(String id, JournalSyncState state,
      {int? expectedGeneration,
      int? baseRev,
      Map<String, Object?>? baseSummary}) async {
    mutations.add('updateSyncState');
    final g = updateSyncStateGate;
    updateSyncStateGate = null;
    if (g != null) await g.pass();
    return super.updateSyncState(id, state,
        expectedGeneration: expectedGeneration,
        baseRev: baseRev,
        baseSummary: baseSummary);
  }

  @override
  Future<JournalEntry?> updateRecord(String id, ActivitySession session,
      {JournalSyncState? syncState,
      int? expectedGeneration,
      int? baseRev,
      Map<String, Object?>? baseSummary}) {
    mutations.add('updateRecord');
    return super.updateRecord(id, session,
        syncState: syncState,
        expectedGeneration: expectedGeneration,
        baseRev: baseRev,
        baseSummary: baseSummary);
  }

  @override
  Future<bool> markSynced(String id,
      {int? expectedGeneration,
      int? baseRev,
      Map<String, Object?>? baseSummary}) {
    mutations.add('markSynced');
    return super.markSynced(id,
        expectedGeneration: expectedGeneration,
        baseRev: baseRev,
        baseSummary: baseSummary);
  }
}
