// S02 test epic 14b: remediation H5, "account deletion in progress stops the
// sync". Oracles: docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md heading H-B
// item 1, design section 17 item 24 (b) and the promise "after the server-side
// deletion may have completed, nothing of the deleted account is written or
// pushed again", NOT the code under test. Real UidScopedActivityJournal on temp
// directories, recording backend and pusher, deterministic gates (no sleeps).
import 'dart:async';

import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';
import '../../../support/stale_view_world.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this._cb);
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

const _uidA = 'uidAlphaSecret1';

void main() {
  late ScopedJournalWorld w;
  late HookJournal journal;
  late RecBackend backend;
  late List<String> pushes;
  late List<_FakeTimer> timers;
  late ActivitySyncRepository repo;
  late List<String> logs;
  late DebugPrintCallback savedDebugPrint;
  String? deleting;
  String? authNow;
  Object? pushError;
  Gate? pushGate;

  ActivitySyncRepository make({
    bool withAuth = false,
    bool pusher = true,
  }) =>
      repo = ActivitySyncRepository(
        journal: journal,
        backend: backend,
        tombstonePusher: pusher
            ? (id, _) async {
                pushes.add(id);
                final g = pushGate;
                pushGate = null;
                if (g != null) await g.pass();
                final e = pushError;
                if (e != null) throw e;
                backend.tombs.add(id);
              }
            : null,
        clock: () => DateTime.utc(2026, 10, 16, 12),
        retryTimerFactory: (d, cb) {
          final t = _FakeTimer(cb);
          timers.add(t);
          return t;
        },
        authUid: withAuth ? () => authNow : null,
        accountBeingDeleted: () => deleting,
      );

  /// Binds [uid]; entries 1 and 4 unsynced, entries 2 and 3 deleted (owed).
  Future<void> seed(String uid) async {
    expect(await journal.bindUid(uid), isTrue);
    await journal.put(journalSession(idFor(1), seed: 1));
    await journal.put(journalSession(idFor(4), seed: 4));
    await journal.put(journalSession(idFor(2), seed: 2));
    await journal.put(journalSession(idFor(3), seed: 3));
    await journal.delete(idFor(2));
    await journal.delete(idFor(3));
    journal.mutations.clear();
  }

  setUp(() async {
    w = await ScopedJournalWorld.create();
    journal = HookJournal(w.factory);
    backend = RecBackend();
    pushes = [];
    timers = [];
    pushError = null;
    pushGate = null;
    deleting = null;
    authNow = null;
    logs = [];
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });
  tearDown(() async {
    debugPrint = savedDebugPrint;
    await repo.dispose();
    await journal.close();
    await w.tmp.delete(recursive: true);
  });

  List<String> skipped() => [for (final l in logs) if (l.contains('skipped')) l];

  void expectNoUidInLogs() {
    for (final l in logs) {
      expect(l, isNot(contains(_uidA)), reason: 'a log line must not carry a uid');
      expect(l, isNot(contains(idFor(1))));
    }
  }

  group('H5: the flag is raised while a pass is in flight', () {
    test('during listTombstoneIds: zero summary writes, zero tombstone pushes, '
        'zero journal writes afterwards; the skip is logged without a uid',
        () async {
      await seed(_uidA);
      make();
      final before = await w.snapshot(_uidA);
      final g = Gate();
      backend.listGate = g;
      final f = repo.syncAll();
      await g.entered.future;
      expect(backend.calls, ['listTombstoneIds'], reason: 'precondition');
      deleting = _uidA; // the deletion starts while the listing is in flight
      g.open();
      final out = await f;

      expect(out, isEmpty);
      expect(backend.calls, ['listTombstoneIds'],
          reason: 'no summary write, no read, nothing after the flag');
      expect(backend.writes, isEmpty);
      expect(pushes, isEmpty, reason: 'zero tombstone pusher calls');
      expect(journal.mutations, isEmpty, reason: 'zero journal writes');
      expect(await w.snapshot(_uidA), before,
          reason: 'not one byte of the account journal changed');
      expect(timers, isEmpty, reason: 'no retry is scheduled for a dying account');
      expect(skipped(), ['activity: syncAll skipped (account-deleting)']);
      expectNoUidInLogs();
    });

    test('during a tombstone push: the second owed id is not pushed and no '
        'entry is written afterwards', () async {
      await seed(_uidA);
      make();
      final g = Gate();
      pushGate = g;
      final f = repo.syncAll();
      await g.entered.future;
      expect(pushes, hasLength(1), reason: 'precondition: first push in flight');
      deleting = _uidA;
      journal.mutations.clear();
      g.open();
      final out = await f;

      expect(pushes, hasLength(1), reason: 'the in-flight push cannot be '
          'recalled, but no further tombstone may be pushed');
      expect(backend.writes, isEmpty);
      expect(out, isEmpty);
      expect(journal.mutations, isEmpty);
      expect(timers, isEmpty);
      expectNoUidInLogs();
    });

    test('during the summary write of the first entry: nothing is stored '
        'after it (no markSynced, no further entry)', () async {
      await seed(_uidA);
      make(pusher: false);
      final g = Gate();
      backend.writeGate = g;
      final f = repo.syncAll();
      await g.entered.future;
      expect(backend.writes, hasLength(1));
      final before = await w.snapshot(_uidA);
      deleting = _uidA;
      g.open();
      await f;

      expect(backend.writes, hasLength(1),
          reason: 'the second entry gets no backend call');
      expect(journal.mutations, isNot(contains('markSynced')),
          reason: 'the entry of a deleted account is not marked synced');
      expect(await w.snapshot(_uidA), before);
      expect(skipped().every((l) => l.endsWith('(account-deleting)')), isTrue);
      expectNoUidInLogs();
    });

    test('control: the same passes complete when the flag stays down',
        () async {
      await seed(_uidA);
      make();
      final out = await repo.syncAll();
      expect(out[idFor(1)], SyncOutcome.synced);
      expect(out[idFor(4)], SyncOutcome.synced);
      expect(pushes.toSet(), {idFor(2), idFor(3)});
      expect(backend.writes, hasLength(2));
      expect(skipped(), isEmpty);
    });
  });

  group('H5: the flag is up when the operation starts', () {
    test('flag equals the journal uid: syncAll does nothing, logged '
        'account-deleting', () async {
      await seed(_uidA);
      make();
      deleting = _uidA;
      expect(await repo.syncAll(), isEmpty);
      expect(backend.calls, isEmpty);
      expect(pushes, isEmpty);
      expect(journal.mutations, isEmpty);
      expect(skipped(), ['activity: syncAll skipped (account-deleting)']);
      expectNoUidInLogs();
    });

    test('flag equals the AUTH uid on a plain journal: syncAll does nothing',
        () async {
      final h = JournalHarness.memory();
      await h.open();
      addTearDown(h.journal.close);
      await h.journal.put(journalSession(idFor(1), seed: 1));
      authNow = 'plainAuth';
      deleting = 'plainAuth';
      final plain = ActivitySyncRepository(
        journal: h.journal,
        backend: backend,
        authUid: () => authNow,
        accountBeingDeleted: () => deleting,
      );
      addTearDown(plain.dispose);
      repo = make(); // for tearDown
      expect(await plain.syncAll(), isEmpty);
      expect(await plain.syncEntry(idFor(1)), SyncOutcome.pending);
      expect(backend.calls, isEmpty);
      // control: another uid in the flag does not stop it
      deleting = 'someoneElse';
      expect(await plain.syncEntry(idFor(1)), SyncOutcome.synced);
      expect(backend.writes, hasLength(1));
    });

    test('a flag naming another uid (or null) changes nothing', () async {
      await seed(_uidA);
      make(withAuth: true);
      authNow = _uidA;
      deleting = 'uidSomeoneElse';
      var out = await repo.syncAll();
      expect(out[idFor(1)], SyncOutcome.synced);
      deleting = null;
      out = await repo.syncAll();
      expect(skipped(), isEmpty);
    });

    test('syncEntry, syncBatch, resolution, explicit edit and saveSession all '
        'refuse without a backend call or a journal write', () async {
      await seed(_uidA);
      make();
      deleting = _uidA;
      expect(await repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expect(await repo.syncBatch([idFor(1)]), {idFor(1): SyncOutcome.pending});
      expect(await repo.resolveConflict(idFor(1), ConflictChoice.keepDevice),
          SyncOutcome.pending);
      expect(await repo.applyExplicitEdit(idFor(1), {'distanceM': 5000}),
          SyncOutcome.pending);
      expect(await repo.saveSession(journalSession(idFor(1), seed: 1)),
          SyncOutcome.pending);
      expect(backend.calls, isEmpty);
      expect(pushes, isEmpty);
      expect(journal.mutations, isEmpty);
      expectNoUidInLogs();
    });

    test('the scheduled tombstone retry timer does nothing once the flag is '
        'up', () async {
      await seed(_uidA);
      pushError = StateError('offline');
      make();
      await repo.syncAll();
      expect(timers.where((t) => t.isActive), hasLength(1),
          reason: 'precondition: a retry is scheduled');
      final calls = backend.calls.length;
      final pushed = pushes.length;
      journal.mutations.clear();

      deleting = _uidA;
      timers.firstWhere((t) => t.isActive).fire();
      await settle();

      expect(backend.calls.length, calls, reason: 'no listing, no write');
      expect(pushes.length, pushed, reason: 'no push from the timer');
      expect(journal.mutations, isEmpty);
    });

    test('control: the same timer runs the pass when the flag is down',
        () async {
      await seed(_uidA);
      pushError = StateError('offline');
      make();
      await repo.syncAll();
      final pushed = pushes.length;
      timers.firstWhere((t) => t.isActive).fire();
      await settle();
      expect(pushes.length, greaterThan(pushed));
    });
  });
}
