// S02 test epic 12a: remediation F1 (pass identity, caches, unbound visibility,
// tombstone retry). Oracles: docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md
// heading F1, S02_DESIGN.md section 17 item 23 and the promise "a sync of
// account A that is still running never touches account B's data", NOT the
// code under test.
//
// The journal is a REAL `UidScopedActivityJournal` over real temp directories
// (ScopedJournalWorld, fake secure store); a spy subclass records every write
// together with the uid that was bound at that moment and can gate reads. The
// backend records every call and can block one call on a completer.
import 'dart:async';

import 'package:fitness_app/features/activity/data/activity_cloud_summary.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/summary_codec.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';

/// One-shot block: [pass] signals [entered] and waits for [release].
class _Gate {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  Future<void> pass() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }
}

class _Backend implements ActivitySummaryBackend {
  final List<String> calls = [];
  final Set<String> tombs = {};
  final Map<String, Map<String, Object?>> docs = {};
  _Gate? listGate;
  _Gate? readGate;
  _Gate? writeGate;
  Object? listError;
  int listEnters = 0;
  int inList = 0;
  int maxInList = 0;

  int count(String m) => calls.where((c) => c.startsWith('$m:')).length;

  Future<void> _wait(_Gate? g) async {
    if (g != null) await g.pass();
  }

  @override
  Future<Set<String>> listTombstoneIds() async {
    calls.add('listTombstoneIds:');
    listEnters++;
    inList++;
    if (inList > maxInList) maxInList = inList;
    try {
      final g = listGate;
      listGate = null;
      await _wait(g);
      final e = listError;
      if (e != null) throw e;
      return {...tombs};
    } finally {
      inList--;
    }
  }

  @override
  Future<bool> tombstoneExists(String id) async {
    calls.add('tombstoneExists:$id');
    return tombs.contains(id);
  }

  @override
  Future<Map<String, Object?>?> readSummary(String id) async {
    calls.add('readSummary:$id');
    final g = readGate;
    readGate = null;
    await _wait(g);
    final d = docs[id];
    return d == null ? null : {...d};
  }

  @override
  Future<void> writeSummary(String id, Map<String, Object> summary,
      {required bool create}) async {
    calls.add('writeSummary:$id');
    final g = writeGate;
    writeGate = null;
    await _wait(g);
    docs[id] = {...summary};
  }
}

/// The real scoped journal plus a write log (with the uid bound at the time of
/// the write) and gates on `read`, `list` and the n-th `listTombstones`.
class _SpyJournal extends UidScopedActivityJournal {
  _SpyJournal(ActivityJournalFactory f, Future<String> Function() root)
      : super(factory: f, scopesRoot: root);

  final List<String> writes = [];
  _Gate? readGate;
  _Gate? listGate;
  int listTombCalls = 0;
  int? gateListTombOn;
  _Gate? listTombGate;
  Object? Function(int n)? listTombError;

  @override
  Future<JournalEntry?> read(String id) async {
    final r = await super.read(id);
    final g = readGate;
    readGate = null;
    if (g != null) await g.pass();
    return r;
  }

  @override
  Future<List<JournalEntry>> list() async {
    final r = await super.list();
    final g = listGate;
    listGate = null;
    if (g != null) await g.pass();
    return r;
  }

  @override
  Future<List<JournalEntry>> listTombstones() async {
    final n = ++listTombCalls;
    final err = listTombError?.call(n);
    if (err != null) throw err;
    final r = await super.listTombstones();
    if (gateListTombOn == n) {
      final g = listTombGate!;
      await g.pass();
    }
    return r;
  }

  @override
  Future<void> delete(String id) {
    writes.add('delete:$id@$boundUid');
    return super.delete(id);
  }

  @override
  Future<bool> markSynced(String id,
      {int? expectedGeneration, int? baseRev, Map<String, Object?>? baseSummary}) {
    writes.add('markSynced:$id@$boundUid');
    return super.markSynced(id,
        expectedGeneration: expectedGeneration,
        baseRev: baseRev,
        baseSummary: baseSummary);
  }

  @override
  Future<JournalEntry?> updateRecord(String id, session,
      {JournalSyncState? syncState,
      int? expectedGeneration,
      int? baseRev,
      Map<String, Object?>? baseSummary}) {
    writes.add('updateRecord:$id@$boundUid');
    return super.updateRecord(id, session,
        syncState: syncState,
        expectedGeneration: expectedGeneration,
        baseRev: baseRev,
        baseSummary: baseSummary);
  }

  @override
  Future<bool> updateSyncState(String id, JournalSyncState state,
      {int? expectedGeneration, int? baseRev, Map<String, Object?>? baseSummary}) {
    writes.add('updateSyncState:$id@$boundUid');
    return super.updateSyncState(id, state,
        expectedGeneration: expectedGeneration,
        baseRev: baseRev,
        baseSummary: baseSummary);
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this._cb);

  final Duration delay;
  final void Function() _cb;
  bool cancelled = false;
  bool fired = false;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => 0;

  @override
  void cancel() => cancelled = true;

  void fire() {
    fired = true;
    _cb();
  }
}

class _Timers {
  final List<_FakeTimer> list = [];
  int overlaps = 0;

  Timer create(Duration d, void Function() cb) {
    if (list.any((t) => t.isActive)) overlaps++;
    final t = _FakeTimer(d, cb);
    list.add(t);
    return t;
  }

  List<_FakeTimer> get active => [for (final t in list) if (t.isActive) t];
}

class _CodeError implements Exception {
  _CodeError(this.code);
  final String code;
}

Future<void> until(bool Function() done, [String why = '']) async {
  for (var i = 0; i < 50000 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'condition not reached $why');
}

/// Lets queued microtasks and timers-of-zero run.
Future<void> settle() async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final DateTime _t0 = DateTime.utc(2026, 10, 16, 12);

class _Rig {
  late ScopedJournalWorld w;
  late _SpyJournal journal;
  final backend = _Backend();
  final timers = _Timers();
  final pushes = <String>[];
  Object? Function(String id)? pushFailure;
  Future<void> Function(String id)? pushGate;
  late ActivitySyncRepository repo;

  Future<void> open() async {
    w = await ScopedJournalWorld.create();
    journal = _SpyJournal(w.factory, () async => '${w.base}/activity_journal');
  }

  Future<void> push(String id, String? expectedUid) async {
    pushes.add(id);
    await pushGate?.call(id);
    final e = pushFailure?.call(id);
    if (e != null) throw e;
    backend.tombs.add(id);
  }

  ActivitySyncRepository make({
    bool pusher = false,
    String? Function()? authUid,
  }) =>
      repo = ActivitySyncRepository(
        journal: journal,
        backend: backend,
        tombstonePusher: pusher ? push : null,
        clock: () => _t0,
        retryTimerFactory: timers.create,
        authUid: authUid,
      );

  /// Binds [uid] and stores unsynced entries with the given numeric ids.
  Future<void> seed(String uid, List<int> ids) async {
    expect(await journal.bindUid(uid), isTrue);
    for (final n in ids) {
      await journal.put(journalSession(idFor(n), seed: n));
    }
  }

  /// Binds [uid] and stores entry [n] as a sync_conflict against a base with a
  /// different distance (both sides changed it).
  Future<void> seedConflict(String uid, int n) async {
    expect(await journal.bindUid(uid), isTrue);
    final id = idFor(n);
    final base = ActivityCloudSummary.fromSession(
        journalSession(id, seed: n, distanceM: 4000),
        updatedAt: _t0)
      ..['rev'] = 1;
    await journal.put(journalSession(id, seed: n, distanceM: 4800),
        syncState: JournalSyncState.syncConflict,
        baseRev: 1,
        baseSummary: encodeSummary(base));
  }

  Map<String, Object?> serverDoc(int n, double distance, int rev) => {
        ...ActivityCloudSummary.fromSession(
            journalSession(idFor(n), seed: n, distanceM: distance),
            updatedAt: _t0),
        'rev': rev,
      };

  Future<void> switchTo(String? uid, {bool notify = true}) async {
    await journal.bindUid(uid);
    if (notify) repo.onAccountChanged();
  }

  Future<void> deleteOwned(String uid, List<int> ids) async {
    expect(await journal.bindUid(uid), isTrue);
    for (final n in ids) {
      await journal.delete(idFor(n));
    }
  }

  Future<JournalSyncState?> stateOf(String uid, int n) async {
    await journal.bindUid(uid);
    return (await journal.read(idFor(n)))?.state.syncState;
  }

  Future<void> dispose() async {
    await repo.dispose();
    await w.dispose();
  }
}

void main() {
  late _Rig r;
  setUp(() async {
    r = _Rig();
    await r.open();
  });
  tearDown(() async => r.dispose());

  group('A: tombstone phase, switch while the listing is awaited', () {
    for (final notify in [true, false]) {
      test(
          'B keeps its entry with the SAME id as A\'s server tombstone '
          '(onAccountChanged called: $notify); nothing is deleted or written',
          () async {
        await r.seed('A', [1]);
        await r.seed('B', [1]);
        await r.journal.bindUid('A');
        r.make();
        r.backend.tombs.add(idFor(1));
        final gate = _Gate();
        r.backend.listGate = gate;
        final pass = r.repo.syncAll();
        await gate.entered.future;
        await r.switchTo('B', notify: notify);
        gate.release.complete();
        final out = await pass;

        expect(out, isEmpty, reason: 'the stale pass reports nothing');
        expect(out.values, isNot(contains(SyncOutcome.deletedLocal)));
        expect((await r.journal.read(idFor(1))), isNotNull,
            reason: 'B\'s activity survives A\'s tombstone');
        expect(await r.journal.listTombstones(), isEmpty,
            reason: 'B got no tombstone');
        expect(r.journal.writes, isEmpty,
            reason: 'no delete / markSynced / updateRecord under B');
        expect(r.backend.calls, ['listTombstoneIds:'],
            reason: 'no write or read for B with A\'s data');
        expect(await r.stateOf('B', 1), JournalSyncState.pending);
      });
    }
  });

  group('A: entry phase, switch while a backend call is blocked', () {
    test('writeSummary blocked: no markSynced under B, outcome pending',
        () async {
      await r.seed('A', [1]);
      await r.seed('B', [1]);
      await r.journal.bindUid('A');
      r.make();
      final gate = _Gate();
      r.backend.writeGate = gate;
      final f = r.repo.syncEntry(idFor(1));
      await gate.entered.future;
      await r.switchTo('B');
      gate.release.complete();
      expect(await f, SyncOutcome.pending);
      expect(r.backend.count('writeSummary'), 1,
          reason: 'only the write that started before the switch');
      expect(r.journal.writes, isEmpty,
          reason: 'no markSynced / delete / updateRecord under B');
      expect(await r.stateOf('B', 1), JournalSyncState.pending,
          reason: 'B\'s X is not synced');
    });

    test('readSummary blocked: no write at all after the answer', () async {
      await r.seed('A', [1]);
      await r.seed('B', [1]);
      await r.journal.bindUid('A');
      r.make();
      final gate = _Gate();
      r.backend.readGate = gate;
      final f = r.repo.syncEntry(idFor(1));
      await gate.entered.future;
      await r.switchTo('B');
      gate.release.complete();
      expect(await f, SyncOutcome.pending);
      expect(r.backend.count('writeSummary'), 0);
      expect(r.backend.docs, isEmpty, reason: 'nothing stored in the cloud');
      expect(r.journal.writes, isEmpty);
      expect(await r.stateOf('B', 1), JournalSyncState.pending);
    });

    test('syncAll: switch while journal.list() is awaited -> the stale list is '
        'not used, nothing is written', () async {
      await r.seed('A', [1]);
      await r.seed('B', [1]);
      await r.journal.bindUid('A');
      r.make();
      final gate = _Gate();
      r.journal.listGate = gate;
      final f = r.repo.syncAll();
      await gate.entered.future;
      await r.switchTo('B');
      gate.release.complete();
      expect(await f, isEmpty);
      expect(r.backend.count('writeSummary'), 0);
      expect(r.backend.count('readSummary'), 0);
      expect(r.journal.writes, isEmpty);
      expect(await r.stateOf('B', 1), JournalSyncState.pending);
    });

    test('syncEntry: switch while journal.read() is awaited -> no backend '
        'call, outcome pending', () async {
      await r.seed('A', [1]);
      await r.seed('B', [1]);
      await r.journal.bindUid('A');
      r.make();
      final gate = _Gate();
      r.journal.readGate = gate;
      final f = r.repo.syncEntry(idFor(1));
      await gate.entered.future;
      await r.switchTo('B');
      gate.release.complete();
      expect(await f, SyncOutcome.pending);
      expect(r.backend.calls, isEmpty);
      expect(r.journal.writes, isEmpty);
    });

    test('saveSession: switch while the previous entry is read -> A\'s '
        'session is not put into B', () async {
      await r.seed('A', [1]);
      await r.seed('B', [2]);
      await r.journal.bindUid('A');
      r.make();
      final gate = _Gate();
      r.journal.readGate = gate;
      final f = r.repo.saveSession(journalSession(idFor(1), seed: 1));
      await gate.entered.future;
      await r.switchTo('B');
      gate.release.complete();
      expect(await f, SyncOutcome.pending);
      expect(await r.journal.read(idFor(1)), isNull,
          reason: 'A\'s activity must not be created in B');
      expect(r.backend.calls, isEmpty);
    });
  });

  group('A: authUid mismatch', () {
    test('authUid changes after the pass started: no backend call after it',
        () async {
      await r.seed('A', [1]);
      String? cur = 'A';
      r.make(authUid: () => cur);
      final gate = _Gate();
      r.backend.listGate = gate;
      final f = r.repo.syncAll();
      await gate.entered.future;
      cur = 'B'; // the auth session moved on; the journal still says A
      gate.release.complete();
      expect(await f, isEmpty);
      expect(r.backend.calls, ['listTombstoneIds:'],
          reason: 'no readSummary / writeSummary / tombstoneExists');
      expect(r.journal.writes, isEmpty);
      expect(await r.stateOf('A', 1), JournalSyncState.pending);
    });

    test('authUid changes while read() is awaited: syncEntry makes no call',
        () async {
      await r.seed('A', [1]);
      String? cur = 'A';
      r.make(authUid: () => cur);
      final gate = _Gate();
      r.journal.readGate = gate;
      final f = r.repo.syncEntry(idFor(1));
      await gate.entered.future;
      cur = 'B';
      gate.release.complete();
      expect(await f, SyncOutcome.pending);
      expect(r.backend.calls, isEmpty);
    });

    test('authUid null at the start: every operation makes zero backend calls',
        () async {
      await r.seed('A', [1]);
      r.backend.tombs.add(idFor(1));
      r.make(authUid: () => null, pusher: true);
      expect(await r.repo.syncAll(), isEmpty);
      expect(await r.repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expect(await r.repo.resolveConflict(idFor(1), ConflictChoice.keepCloud),
          isNot(SyncOutcome.deletedLocal));
      expect(r.backend.calls, isEmpty);
      expect(r.pushes, isEmpty);
      expect(await r.journal.read(idFor(1)), isNotNull);
    });

    test('authUid null FUNCTION (tests): behaviour unchanged, entry syncs',
        () async {
      await r.seed('A', [1]);
      r.make();
      final out = await r.repo.syncAll();
      expect(out[idFor(1)], SyncOutcome.synced);
      expect(r.backend.docs.keys, [idFor(1)]);
    });

    test('pusher: authUid flips after the first push -> the second id is not '
        'pushed', () async {
      await r.seed('A', [1, 2]);
      await r.deleteOwned('A', [1, 2]);
      String? cur = 'A';
      r.make(pusher: true, authUid: () => cur);
      r.pushGate = (id) async => cur = 'B';
      await r.repo.syncAll();
      expect(r.pushes, hasLength(1),
          reason: 'the push for A must not start once auth moved on');
    });
  });

  group('A: tombstone push, switch while a push is blocked', () {
    test('the second owed id is not pushed for A; B\'s own pass pushes its '
        'ids and its confirmed set is not polluted', () async {
      await r.seed('A', [1, 2]);
      await r.deleteOwned('A', [1, 2]);
      await r.seed('B', [1, 2]);
      await r.deleteOwned('B', [1, 2]);
      await r.journal.bindUid('A');
      r.make(pusher: true);
      final gate = _Gate();
      r.pushGate = (id) async {
        if (r.pushes.length == 1) await gate.pass();
      };
      final f = r.repo.syncAll();
      await gate.entered.future;
      expect(r.pushes, hasLength(1));
      await r.switchTo('B');
      gate.release.complete();
      await f;
      expect(r.pushes, hasLength(1),
          reason: 'the pusher is not called for the second id of A');
      // B's own pass: both of its owed ids are pushed (the first id was NOT
      // marked as confirmed for B by the stale pass).
      r.backend.tombs.clear();
      await r.repo.syncAll();
      expect(r.pushes.skip(1).toSet(), {idFor(1), idFor(2)});
      expect(r.pushes, hasLength(3));
    });
  });

  group('A: conflict operations, switch while the cloud read is blocked', () {
    test('resolveConflict: no updateRecord on B, outcome pending', () async {
      await r.seedConflict('A', 1);
      await r.seedConflict('B', 1);
      await r.journal.bindUid('A');
      r.make();
      r.backend.docs[idFor(1)] = r.serverDoc(1, 4500, 2);
      final gate = _Gate();
      r.backend.readGate = gate;
      final f = r.repo.resolveConflict(idFor(1), ConflictChoice.keepCloud);
      await gate.entered.future;
      final before = (await (() async {
        await r.journal.bindUid('B');
        return r.journal.read(idFor(1));
      })())!;
      await r.switchTo('B');
      gate.release.complete();
      expect(await f, SyncOutcome.pending);
      expect(r.journal.writes.where((w) => w.startsWith('updateRecord')),
          isEmpty);
      expect(r.backend.count('writeSummary'), 0);
      final after = (await r.journal.read(idFor(1)))!;
      expect(after.generation, before.generation);
      expect(after.state.syncState, JournalSyncState.syncConflict);
    });

    test('resolveCandidate and applyExplicitEdit: switch while read() is '
        'awaited -> pending, B untouched', () async {
      await r.seed('A', [1]);
      await r.seed('B', [1]);
      await r.journal.bindUid('B');
      final before = (await r.journal.read(idFor(1)))!;
      await r.journal.bindUid('A');
      r.make();

      var gate = _Gate();
      r.journal.readGate = gate;
      var f = r.repo.resolveCandidate(
          idFor(1), 'distanceM', CandidateChoice.useComputed);
      await gate.entered.future;
      await r.switchTo('B');
      gate.release.complete();
      expect(await f, SyncOutcome.pending);

      await r.switchTo('A');
      gate = _Gate();
      r.journal.readGate = gate;
      f = r.repo.applyExplicitEdit(idFor(1), {'distanceM': 5000});
      await gate.entered.future;
      await r.switchTo('B');
      gate.release.complete();
      expect(await f, SyncOutcome.pending);

      expect(r.journal.writes, isEmpty);
      expect(r.backend.calls, isEmpty);
      final after = (await r.journal.read(idFor(1)))!;
      expect(after.generation, before.generation);
      expect(after.state.syncState, JournalSyncState.pending);
    });
  });

  group('B: caches', () {
    test('onAccountChanged drops the conflict cache: B re-reads the backend '
        'and shows B\'s cloud value', () async {
      await r.seedConflict('A', 1);
      await r.seedConflict('B', 1);
      await r.journal.bindUid('A');
      r.make();
      r.backend.docs[idFor(1)] = r.serverDoc(1, 4500, 2);
      var s = await r.repo.refreshState();
      expect(r.backend.count('readSummary'), 1);
      expect(s.conflicts.single.cloudKnown, isTrue);
      expect(
          s.conflicts.single.fields.map((f) => f.cloudValue), contains(4500));
      await r.repo.refreshState();
      expect(r.backend.count('readSummary'), 1, reason: 'cached for A');

      r.backend.docs[idFor(1)] = r.serverDoc(1, 4700, 2);
      await r.switchTo('B');
      s = await r.repo.refreshState();
      expect(r.backend.count('readSummary'), 2, reason: 'B reads again');
      final cloud = s.conflicts.single.fields.map((f) => f.cloudValue);
      expect(cloud, contains(4700));
      expect(cloud, isNot(contains(4500)), reason: 'A\'s value does not leak');
    });

    test('onAccountChanged clears the once-per-process conflict retry marks',
        () async {
      await r.seedConflict('A', 1);
      await r.seedConflict('B', 1);
      await r.journal.bindUid('A');
      r.make();
      r.backend.docs[idFor(1)] = r.serverDoc(1, 4500, 2);
      await r.repo.syncAll(retryConflicts: true);
      expect(r.backend.count('readSummary'), 1, reason: 'A retried once');
      await r.repo.syncAll(retryConflicts: true);
      expect(r.backend.count('readSummary'), 1,
          reason: 'second retry of the same conflict is skipped');
      await r.switchTo('B');
      await r.repo.syncAll(retryConflicts: true);
      expect(r.backend.count('readSummary'), 2,
          reason: 'B\'s conflict is retried: the marks were cleared');
    });

    test('a readSummary that completes after the switch is not cached',
        () async {
      await r.seedConflict('A', 1);
      await r.seedConflict('B', 1);
      await r.journal.bindUid('A');
      r.make();
      r.backend.docs[idFor(1)] = r.serverDoc(1, 4500, 2);
      final gate = _Gate();
      r.backend.readGate = gate;
      final f = r.repo.refreshState();
      await gate.entered.future;
      await r.switchTo('B');
      r.backend.docs[idFor(1)] = r.serverDoc(1, 4700, 2);
      gate.release.complete();
      await f;
      final s = await r.repo.refreshState();
      expect(r.backend.count('readSummary'), 2,
          reason: 'the stale answer was not cached for B');
      final cloud = s.conflicts.single.fields.map((x) => x.cloudValue);
      expect(cloud, contains(4700));
      expect(cloud, isNot(contains(4500)));
    });
  });

  group('C: unbound journal is a visible failure', () {
    test('refreshState throws JournalUnbound and watch() emits the error',
        () async {
      r.make();
      await expectLater(r.repo.refreshState(), throwsA(isA<JournalUnbound>()));
      await expectLater(
          r.repo.watch(), emitsError(isA<JournalUnbound>()));
    });

    test('a bind that failed behaves like never bound', () async {
      r.w.failOpen.add(activityJournalScopeId('A'));
      expect(await r.journal.bindUid('A'), isFalse);
      r.make();
      await expectLater(r.repo.refreshState(), throwsA(isA<JournalUnbound>()));
      expect(await r.repo.syncAll(), isEmpty);
      expect(await r.repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expect(r.backend.calls, isEmpty);
    });

    test('syncAll empty with zero backend calls; syncEntry/syncBatch pending; '
        'resolve* unavailable; saveSession throws', () async {
      r.make(pusher: true);
      r.backend.tombs.add(idFor(1));
      expect(await r.repo.syncAll(), isEmpty);
      expect(await r.repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expect(await r.repo.syncBatch([idFor(1), idFor(2)]),
          {idFor(1): SyncOutcome.pending, idFor(2): SyncOutcome.pending});
      expect(await r.repo.resolveConflict(idFor(1), ConflictChoice.keepDevice),
          SyncOutcome.unavailable);
      expect(
          await r.repo.resolveCandidate(
              idFor(1), 'distanceM', CandidateChoice.useComputed),
          SyncOutcome.unavailable);
      expect(await r.repo.applyExplicitEdit(idFor(1), {'distanceM': 1}),
          SyncOutcome.unavailable);
      await expectLater(r.repo.saveSession(journalSession(idFor(1))),
          throwsA(isA<JournalUnbound>()));
      expect(r.backend.calls, isEmpty);
      expect(r.pushes, isEmpty);
    });

    test('presenter: loadFailed (never an empty loaded state), retry, then '
        'loaded after a bind; failed actions show lastFailed', () async {
      r.make();
      // Remediation J3 B4: a tap with no signed-in uid does nothing, so the
      // failure path needs a uid (the unbound JOURNAL is what fails here).
      final c = ProviderContainer(overrides: [
        activitySyncRepositoryProvider.overrideWithValue(r.repo),
        syncConflictUidProvider.overrideWithValue('A'),
      ]);
      addTearDown(c.dispose);
      c.listen(syncConflictPresenterProvider, (_, __) {});
      await until(() => c.read(syncConflictPresenterProvider).loadFailed,
          'load failure shown');
      var v = c.read(syncConflictPresenterProvider);
      expect(v.loaded, isFalse);
      expect(v.hasItems, isFalse);

      final p = c.read(syncConflictPresenterProvider.notifier);
      await p.keepDevice(idFor(1));
      expect(c.read(syncConflictPresenterProvider).lastFailed, isTrue,
          reason: 'unavailable is a failure, never success');
      await p.resolveCandidate(idFor(1), 'distanceM', CandidateChoice.useComputed);
      expect(c.read(syncConflictPresenterProvider).lastFailed, isTrue);

      p.retry();
      await until(() => c.read(syncConflictPresenterProvider).loadFailed,
          'still failing while unbound');
      expect(c.read(syncConflictPresenterProvider).loaded, isFalse);

      expect(await r.journal.bindUid('A'), isTrue);
      p.retry();
      await until(() => c.read(syncConflictPresenterProvider).loaded,
          'loaded after bind');
      v = c.read(syncConflictPresenterProvider);
      expect(v.loadFailed, isFalse);
    });
  });

  group('D: tombstone retry', () {
    Future<void> failPass(int i) async {
      r.timers.list.last.fire();
      await until(() => r.timers.list.length == i + 1, 'timer ${i + 1}');
    }

    test('the counter is reset after a clean pass: the next failure starts at '
        '60 s again', () async {
      await r.seed('A', [1, 2, 3]);
      await r.deleteOwned('A', [1, 2, 3]);
      r.make(pusher: true);
      r.pushFailure = (_) => _CodeError('unavailable');
      await r.repo.syncAll();
      await failPass(1);
      await failPass(2);
      expect([for (final t in r.timers.list) t.delay], const [
        Duration(seconds: 60),
        Duration(minutes: 2),
        Duration(minutes: 4),
      ]);
      r.pushFailure = null; // server is back: the next timer pass is clean
      r.timers.list.last.fire();
      await settle();
      expect(r.timers.active, isEmpty, reason: 'clean pass leaves no timer');
      expect(r.timers.list, hasLength(3));
      expect((await r.repo.refreshState()).pendingTombstones, 0);

      // A new deletion fails again: the FIRST delay, not the fourth.
      await r.journal.put(journalSession(idFor(9), seed: 9));
      await r.journal.delete(idFor(9));
      r.pushFailure = (_) => _CodeError('unavailable');
      await r.repo.syncAll();
      expect(r.timers.list, hasLength(4));
      expect(r.timers.list.last.delay, const Duration(seconds: 60));
    });

    test('fallback timer after six attempts: one at a time, fires a pass, '
        'gone after a clean pass', () async {
      await r.seed('A', [1]);
      await r.deleteOwned('A', [1]);
      r.make(pusher: true);
      r.pushFailure = (_) => _CodeError('unavailable');
      await r.repo.syncAll();
      for (var i = 1; i < 6; i++) {
        await failPass(i);
      }
      expect(r.timers.list, hasLength(6));
      await failPass(6); // the sixth timer pass fails: the fallback
      expect(r.timers.list, hasLength(7));
      expect(r.timers.list.last.delay, kTombstoneFallbackDelay);
      expect(kTombstoneFallbackDelay, const Duration(minutes: 60));
      expect(r.timers.active, hasLength(1));
      // A manual failing pass while it is pending adds no second timer.
      await r.repo.syncAll();
      expect(r.timers.list, hasLength(7));

      final pushesBefore = r.pushes.length;
      r.timers.list.last.fire();
      await until(() => r.timers.list.length == 8, 'fallback fires a pass');
      expect(r.pushes.length, greaterThan(pushesBefore),
          reason: 'firing the fallback runs a pass');
      expect(r.timers.list.last.delay, kTombstoneFallbackDelay);
      expect(r.timers.overlaps, 0, reason: 'never two timers at once');

      r.pushFailure = null;
      r.timers.list.last.fire();
      await settle();
      expect(r.timers.active, isEmpty, reason: 'clean pass: no timer');
      expect(r.timers.overlaps, 0);
    });

    for (final how in ['dispose', 'cancelTombstoneRetry', 'onAccountChanged']) {
      test('$how cancels the fallback timer', () async {
        await r.seed('A', [1]);
        await r.deleteOwned('A', [1]);
        r.make(pusher: true);
        r.pushFailure = (_) => _CodeError('unavailable');
        await r.repo.syncAll();
        for (var i = 1; i <= 6; i++) {
          await failPass(i);
        }
        final fb = r.timers.list.last;
        expect(fb.delay, kTombstoneFallbackDelay);
        expect(fb.isActive, isTrue);
        switch (how) {
          case 'dispose':
            await r.repo.dispose();
          case 'cancelTombstoneRetry':
            r.repo.cancelTombstoneRetry();
          default:
            r.repo.onAccountChanged();
        }
        expect(fb.cancelled, isTrue);
        expect(r.timers.active, isEmpty);
        if (how == 'dispose') r.make(); // tearDown disposes a live instance
      });
    }

    test('listTombstones throws inside the tombstone phase: no throw, a retry '
        'is scheduled, the code is kept and the state is published', () async {
      await r.seed('A', [1]);
      await r.deleteOwned('A', [1]);
      r.make(pusher: true);
      final states = <ActivitySyncState>[];
      final sub = r.repo.watch().listen(states.add, onError: (_) {});
      addTearDown(sub.cancel);
      await until(() => states.isNotEmpty, 'first state');
      r.journal.listTombCalls = 0;
      r.journal.listTombError = (n) => n == 1
          ? const JournalIoException('disk read failed')
          : null;
      states.clear();
      final out = await r.repo.syncAll();
      expect(out, isNotNull);
      expect(r.timers.active, hasLength(1), reason: 'retry scheduled');
      expect(r.timers.list.single.delay, const Duration(seconds: 60));
      expect(r.repo.lastTombstonePushError, 'JournalIoException');
      await until(() => states.isNotEmpty, 'state published after the pass');
      expect(states.last.lastTombstonePushError, 'JournalIoException');
    });

    test('the pusher throwing a non-coded error: no throw, retry scheduled',
        () async {
      await r.seed('A', [1]);
      await r.deleteOwned('A', [1]);
      r.make(pusher: true);
      r.pushFailure = (_) => StateError('no uid');
      await r.repo.syncAll();
      expect(r.timers.active, hasLength(1));
      expect(r.repo.lastTombstonePushError, 'StateError');
    });

    test('epoch re-check after the pending-count await: no timer, counter '
        'stays 0', () async {
      await r.seed('A', [1]);
      await r.deleteOwned('A', [1]);
      await r.seed('B', [1]);
      await r.deleteOwned('B', [1]);
      await r.journal.bindUid('A');
      r.make(pusher: true);
      r.pushFailure = (_) => _CodeError('unavailable');
      final gate = _Gate();
      r.journal.listTombGate = gate;
      // call 1: the push round; call 2: the pending count in the scheduler.
      r.journal.gateListTombOn = 2;
      final f = r.repo.syncAll();
      await gate.entered.future;
      await r.switchTo('B');
      gate.release.complete();
      await f;
      expect(r.timers.list, isEmpty, reason: 'a stale pass creates no timer');

      // The attempt counter is untouched: B's first failure uses 60 s.
      r.journal.gateListTombOn = null;
      await r.repo.syncAll();
      expect(r.timers.list, hasLength(1));
      expect(r.timers.list.single.delay, const Duration(seconds: 60));
    });

    test('listTombstoneIds unavailable: code "unavailable" and a timer; a '
        'clean pass clears it', () async {
      await r.seed('A', [1]);
      await r.deleteOwned('A', [1]);
      r.make(pusher: true);
      r.backend.listError = const SummaryBackendUnavailable('offline');
      await r.repo.syncAll();
      expect(r.repo.lastTombstonePushError, 'unavailable');
      expect((await r.repo.refreshState()).lastTombstonePushError,
          'unavailable');
      expect(r.timers.active, hasLength(1));
      expect(r.pushes, isEmpty, reason: 'unknown list: nothing pushed');

      r.backend.listError = null;
      r.timers.list.last.fire();
      await settle();
      expect(r.repo.lastTombstonePushError, isNull);
      expect((await r.repo.refreshState()).lastTombstonePushError, isNull);
      expect(r.timers.active, isEmpty);
    });

    test('requestTombstoneSync never runs two passes at once and serializes '
        'with syncAll', () async {
      await r.seed('A', [1]);
      r.make();
      final gate = _Gate();
      r.backend.listGate = gate;
      final a = r.repo.requestTombstoneSync();
      final b = r.repo.requestTombstoneSync();
      final c = r.repo.syncAll();
      await gate.entered.future;
      await settle();
      expect(r.backend.listEnters, 1, reason: 'the others wait in the queue');
      gate.release.complete();
      await Future.wait([a, b, c]);
      expect(r.backend.listEnters, 3);
      expect(r.backend.maxInList, 1, reason: 'never two listings at once');
    });

    test('requestTombstoneSync swallows an unexpected backend failure, does '
        'not retry conflicts, and does nothing after dispose', () async {
      await r.seedConflict('A', 1);
      r.make();
      r.backend.docs[idFor(1)] = r.serverDoc(1, 4500, 2);
      r.backend.listError = StateError('boom');
      await r.repo.requestTombstoneSync(); // must not throw
      r.backend.listError = null;
      await r.repo.requestTombstoneSync();
      expect(r.backend.count('readSummary'), 0,
          reason: 'a conflict is never retried by this path');
      await r.repo.dispose();
      final n = r.backend.calls.length;
      await r.repo.requestTombstoneSync();
      expect(r.backend.calls.length, n, reason: 'disposed: no pass');
      r.make();
    });
  });
}
