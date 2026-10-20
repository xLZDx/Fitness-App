// S02 test epic 14b: remediation H6 (queued tap with expectedUid) and H7
// (cache fills and state reads across an account switch). Oracles:
// S02_REMEDIATION_H_TEST_NOTES.md H-B items 4, 5 and 6, design 17 item 24 (c),
// (d) and the promise "after I switch accounts I never see or act on the
// previous account's conflicts". Real UidScopedActivityJournal on temp
// directories; deterministic gates; activity ids are the SAME in both accounts.
import 'package:fitness_app/features/activity/data/summary_projection.dart'
    show CandidateChoice;
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';
import '../../../support/stale_view_world.dart';

void main() {
  late ScopedJournalWorld w;
  late HookJournal journal;
  late RecBackend backend;
  late ActivitySyncRepository repo;
  String? cur;

  final id = idFor(1);

  setUp(() async {
    w = await ScopedJournalWorld.create();
    journal = HookJournal(w.factory,
        scopesRoot: () async => '${w.base}/activity_journal');
    backend = RecBackend();
    cur = null;
    repo = ActivitySyncRepository(
      journal: journal,
      backend: backend,
      clock: () => DateTime.utc(2026, 10, 16, 12),
      authUid: () => cur,
    );
  });
  tearDown(() async {
    await repo.dispose();
    await journal.close();
    await w.tmp.delete(recursive: true);
  });

  /// Account [uid] holds [entryId] in sync_conflict (state only, no server).
  Future<void> seedConflict(String uid, String entryId,
      {int seed = 1, double distance = 6000}) async {
    expect(await journal.bindUid(uid), isTrue);
    await journal.put(journalSession(entryId, seed: seed, distanceM: distance));
    await journal.updateSyncState(entryId, JournalSyncState.syncConflict);
  }

  /// Switches the app to [uid] the way production does: auth flips, the
  /// journal rebinds, the repository is told.
  Future<void> switchTo(String? uid) async {
    cur = uid;
    await journal.bindUid(uid);
    repo.onAccountChanged();
  }

  /// Account A (bound, auth A): entry 1 synced, then the server and the device
  /// change distanceM differently; returns the future of the explicit edit that
  /// ends in a real conflict with a cloud summary.
  Future<SyncOutcome> makeServerConflictInA() async {
    expect(await journal.bindUid('A'), isTrue);
    cur = 'A';
    await journal.put(journalSession(id, seed: 1));
    expect(await repo.syncEntry(id), SyncOutcome.synced);
    backend.docs[id] = {...backend.docs[id]!, 'distanceM': 5000, 'rev': 2};
    return repo.applyExplicitEdit(id, {'distanceM': 5200});
  }

  group('H6: a tap queued under A behind a blocked syncAll', () {
    Future<Map<String, String>> queueThenSwitch(
        Future<SyncOutcome> Function() tap) async {
      await seedConflict('B', id, distance: 6000);
      await seedConflict('A', id, seed: 1, distance: 4800);
      cur = 'A';
      final g = Gate();
      backend.listGate = g;
      final blocked = repo.syncAll();
      await g.entered.future;
      final queued = tap(); // queued behind the blocked pass
      await switchTo('B');
      final bBefore = await w.snapshot('B');
      backend.calls.clear();
      g.open();
      await blocked;
      expect(await queued, SyncOutcome.pending,
          reason: 'the tap was made under A; B must not be touched');
      return bBefore;
    }

    test('resolveConflict keep device: B entry unchanged, outcome pending, '
        'zero backend calls', () async {
      final before = await queueThenSwitch(() =>
          repo.resolveConflict(id, ConflictChoice.keepDevice, expectedUid: 'A'));
      expect(await w.snapshot('B'), before,
          reason: "B's entry, record and state are byte-identical");
      expect((await journal.read(id))!.state.syncState,
          JournalSyncState.syncConflict);
      expect(backend.calls, isEmpty, reason: 'no read, no write for B');
      expect(backend.docs, isEmpty);
    });

    test('resolveCandidate: B entry unchanged, outcome pending, zero backend '
        'calls', () async {
      final before = await queueThenSwitch(() => repo.resolveCandidate(
          id, 'distanceM', CandidateChoice.useComputed,
          expectedUid: 'A'));
      expect(await w.snapshot('B'), before);
      expect(backend.calls, isEmpty);
    });

    test('resolveConflict called directly under B with expectedUid A is '
        'refused; with expectedUid B (control) it resolves', () async {
      await seedConflict('B', id, distance: 6000);
      cur = 'B';
      final before = await w.snapshot('B');
      expect(
          await repo.resolveConflict(id, ConflictChoice.keepDevice,
              expectedUid: 'A'),
          SyncOutcome.pending);
      expect(await w.snapshot('B'), before);
      expect(backend.calls, isEmpty);

      expect(
          await repo.resolveConflict(id, ConflictChoice.keepDevice,
              expectedUid: 'B'),
          SyncOutcome.synced,
          reason: 'control: the matching uid is allowed to act');
      expect(backend.writes, hasLength(1));
    });

    test('resolveCandidate directly under B with expectedUid A is refused',
        () async {
      await seedConflict('B', id);
      cur = 'B';
      expect(
          await repo.resolveCandidate(id, 'distanceM', CandidateChoice.useComputed,
              expectedUid: 'A'),
          SyncOutcome.pending);
      expect(backend.calls, isEmpty);
    });
  });

  group('H7: _markConflict does not fill the conflict cache across a switch',
      () {
    test('control: without a switch the cache serves the cloud values',
        () async {
      expect(await makeServerConflictInA(), SyncOutcome.conflict,
          reason: 'precondition: a real conflict with a cloud summary');
      final s = await repo.refreshState();
      final c = s.conflicts.single;
      expect(c.cloudKnown, isTrue);
      expect(c.fields.single.field, 'distanceM');
      expect([c.fields.single.deviceValue, c.fields.single.cloudValue],
          [5200, 5000]);
    });

    test('switch to B while updateSyncState is blocked: B never gets A\'s '
        'cloud values', () async {
      await seedConflict('B', id, distance: 6000);
      final g = Gate();
      final f = Future(() async {
        // A's whole flow runs after B was seeded
        expect(await journal.bindUid('A'), isTrue);
        cur = 'A';
        await journal.put(journalSession(id, seed: 1));
        expect(await repo.syncEntry(id), SyncOutcome.synced);
        backend.docs[id] = {...backend.docs[id]!, 'distanceM': 5000, 'rev': 2};
        journal.updateSyncStateGate = g;
        return repo.applyExplicitEdit(id, {'distanceM': 5200});
      });
      await g.entered.future;
      await switchTo('B');
      backend.docs.remove(id); // B has no cloud document
      g.open();
      expect(await f, SyncOutcome.pending);

      final s = await repo.refreshState();
      final c = s.conflicts.single;
      expect(c.cloudKnown, isFalse,
          reason: "A's cached cloud summary must not be served to B");
      expect(c.fields, isEmpty);
    });

    test('switch to B while readSummary of _conflictView is blocked: the read '
        'is discarded, nothing is cached, B shows its own state', () async {
      await seedConflict('B', id, distance: 6000);
      expect(await makeServerConflictInA(), SyncOutcome.conflict);
      repo.onAccountChanged(); // empty the cache: the next view reads again
      final g = Gate();
      backend.readGate = g;
      final f = repo.refreshState();
      await g.entered.future;
      await switchTo('B');
      backend.docs.remove(id);
      g.open();

      final first = await f;
      expect(first.conflicts.single.cloudKnown, isFalse,
          reason: 'the result of a read made under A is discarded');
      expect(first.conflicts.single.fields, isEmpty);
      final second = await repo.refreshState();
      expect(second.conflicts.single.cloudKnown, isFalse,
          reason: 'and A\'s cloud summary was not cached for B');
    });
  });

  group('H7: refreshState discards a result assembled across a switch', () {
    test('list() answered for A after the switch to B: the result is B\'s only',
        () async {
      await seedConflict('A', idFor(1));
      await seedConflict('B', idFor(2));
      await switchTo('A');
      final g = Gate();
      journal.listGate = g;
      final f = repo.refreshState();
      await g.entered.future;
      await switchTo('B');
      g.open();
      final s = await f;
      expect([for (final c in s.conflicts) c.id], [idFor(2)],
          reason: "A's entry id must not appear in B's state");
    });

    test('switch to nobody during the read: JournalUnbound', () async {
      await seedConflict('A', idFor(1));
      await switchTo('A');
      final g = Gate();
      journal.listGate = g;
      final f = repo.refreshState();
      await g.entered.future;
      await switchTo(null);
      g.open();
      await expectLater(f, throwsA(isA<JournalUnbound>()));
    });

    test('the account changes during every attempt: three tries, then '
        'JournalUnbound', () async {
      await seedConflict('A', idFor(1));
      await seedConflict('B', idFor(2));
      await switchTo('A');
      var lists = 0;
      journal.onListed = () async {
        lists++;
        await switchTo(lists.isOdd ? 'B' : 'A');
      };
      await expectLater(repo.refreshState(), throwsA(isA<JournalUnbound>()));
      expect(lists, 3, reason: 'at most 3 attempts');

      journal.onListed = null;
      final s = await repo.refreshState();
      expect(s.conflicts, hasLength(1), reason: 'stable again: one state');
    });

    test('control: no switch returns the entries of the bound account',
        () async {
      await seedConflict('A', idFor(1));
      await switchTo('A');
      final s = await repo.refreshState();
      expect([for (final c in s.conflicts) c.id], [idFor(1)]);
    });
  });
}
