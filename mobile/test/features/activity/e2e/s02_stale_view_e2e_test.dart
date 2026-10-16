// S02 test epic 14b: the user promise behind remediation H6/H7. "After I switch
// accounts I never see or act on the previous account's conflicts": not in the
// first frame of the new account, not in its later states, and not through a tap
// I made just before the switch. End to end over the REAL FileActivityJournal on
// a temp directory (UidScopedActivityJournal, per-account scopes), the real
// ActivitySyncRepository and the real presenter in a ProviderContainer. Both
// accounts hold an activity with the SAME id (ids are deterministic). Oracles
// are the promise and S02_REMEDIATION_H_TEST_NOTES.md H-B, not the code.
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';
import '../../../support/stale_view_world.dart';

final _uidState = StateProvider<String?>((_) => null);

Future<void> until(bool Function() cond) async {
  for (var i = 0; i < 600; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition not reached');
}

void main() {
  late ScopedJournalWorld w;
  late HookJournal journal;
  late RecBackend backend;
  late ActivitySyncRepository repo;
  late ProviderContainer c;
  late List<SyncConflictViewState> states;
  String? cur;
  final id = idFor(1);

  setUp(() async {
    w = await ScopedJournalWorld.create();
    journal = HookJournal(w.factory);
    backend = RecBackend();
    repo = ActivitySyncRepository(
      journal: journal,
      backend: backend,
      clock: () => DateTime.utc(2026, 10, 16, 12),
      authUid: () => cur,
    );
    states = [];
  });
  tearDown(() async {
    c.dispose();
    await repo.dispose();
    await journal.close();
    await w.tmp.delete(recursive: true);
  });

  /// The app moves to [uid]: auth flips first, then the journal rebinds, then
  /// the repository is told (the order of the production wiring).
  Future<void> switchTo(String uid) async {
    cur = uid;
    c.read(_uidState.notifier).state = uid;
    await journal.bindUid(uid);
    repo.onAccountChanged();
  }

  test('A to B with the same activity id: B never sees or acts on A\'s '
      'conflict; A\'s data survives and returns on the way back', () async {
    // B owns the same id in a conflict WITHOUT any cloud summary and with other
    // values.
    expect(await journal.bindUid('B'), isTrue);
    await journal.put(journalSession(id, seed: 1, distanceM: 6000));
    await journal.updateSyncState(id, JournalSyncState.syncConflict);
    // A owns it in a real conflict with a cloud summary (device 5200, cloud 5000).
    expect(await journal.bindUid('A'), isTrue);
    cur = 'A';
    await journal.put(journalSession(id, seed: 1));
    expect(await repo.syncEntry(id), SyncOutcome.synced);
    backend.docs[id] = {...backend.docs[id]!, 'distanceM': 5000, 'rev': 2};
    expect(await repo.applyExplicitEdit(id, {'distanceM': 5200}),
        SyncOutcome.conflict);
    final aDoc = {...backend.docs[id]!};

    c = ProviderContainer(overrides: [
      activitySyncRepositoryProvider.overrideWithValue(repo),
      syncConflictUidProvider.overrideWith((ref) => ref.watch(_uidState)),
    ]);
    c.read(_uidState.notifier).state = 'A';
    c.listen(syncConflictPresenterProvider, (_, n) => states.add(n));
    await until(() => c.read(syncConflictPresenterProvider).loaded);
    final a = c.read(syncConflictPresenterProvider).conflicts.single;
    expect(a.id, id);
    expect([a.fields.single.deviceValue, a.fields.single.cloudValue],
        [5200, 5000], reason: 'precondition: A sees its own values');

    // A taps "keep this device" while a pass is blocked: the tap queues.
    final g = Gate();
    backend.listGate = g;
    final blocked = repo.syncAll();
    await g.entered.future;
    final tap =
        c.read(syncConflictPresenterProvider.notifier).keepDevice(id);
    expect(c.read(syncConflictPresenterProvider).busy,
        {SyncConflictPresenter.conflictKey(id)});

    // The user switches to B.
    states.clear();
    backend.docs.remove(id); // B's cloud holds nothing for this id
    await switchTo('B');
    await until(() => states.isNotEmpty);

    // The first frame of B.
    final first = states.first;
    expect(first.loaded, isFalse);
    expect(first.sync.conflicts, isEmpty);
    expect(first.sync.candidates, isEmpty);
    expect(first.busy, isEmpty);
    expect(first.lastFailed, isFalse);

    // B's loaded state shows B's own conflict, with nothing of A.
    await until(() => c.read(syncConflictPresenterProvider).loaded);
    final b = c.read(syncConflictPresenterProvider).conflicts.single;
    expect(b.cloudKnown, isFalse);
    expect(b.fields, isEmpty, reason: "A's field values must never show for B");
    for (final s in states) {
      for (final x in s.conflicts) {
        expect(x.fields, isEmpty);
      }
    }

    // The queued tap and the blocked pass run to the end under B.
    final bBefore = await w.snapshot('B');
    backend.calls.clear();
    g.open();
    await blocked;
    await tap;
    await settle();
    expect(await w.snapshot('B'), bBefore,
        reason: "A's tap did not resolve or touch B's entry");
    expect(backend.writes, isEmpty, reason: "nothing of A's tap reached any cloud");
    expect(backend.docs, isEmpty);
    final now = c.read(syncConflictPresenterProvider);
    expect(now.busy, isEmpty);
    expect(now.lastFailed, isFalse);
    expect(now.conflicts.single.id, id, reason: "B's conflict is still open");
    expect((await journal.read(id))!.state.syncState,
        JournalSyncState.syncConflict);

    // Back to A: nothing of A was destroyed or resolved by the detour.
    backend.docs[id] = aDoc;
    await switchTo('A');
    await until(() {
      final v = c.read(syncConflictPresenterProvider);
      return v.loaded && v.conflicts.isNotEmpty && v.conflicts.single.cloudKnown;
    });
    final back = c.read(syncConflictPresenterProvider).conflicts.single;
    expect([back.fields.single.deviceValue, back.fields.single.cloudValue],
        [5200, 5000]);
  });
}
