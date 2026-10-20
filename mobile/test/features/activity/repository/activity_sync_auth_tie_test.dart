// S02 test epic 13a: remediation G1 (journal uid tied to auth uid) and G5
// (skipped passes are logged with a reason word and never a uid). Oracles:
// docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md headings G1 and G5 and the
// promise "nothing of account A reaches account B's cloud", NOT the code under
// test. Real UidScopedActivityJournal over temp directories; recording backend
// and pusher.
import 'dart:async';

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';

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
  void Function()? afterList;
  _Gate? writeGate;

  @override
  Future<Set<String>> listTombstoneIds() async {
    calls.add('listTombstoneIds');
    final r = {...tombs};
    afterList?.call();
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
    return d == null ? null : {...d};
  }

  @override
  Future<void> writeSummary(String id, Map<String, Object> summary,
      {required bool create}) async {
    calls.add('writeSummary:$id');
    final g = writeGate;
    writeGate = null;
    if (g != null) await g.pass();
    docs[id] = {...summary};
  }
}

/// Counts and optionally gates `put`.
class _CountingJournal extends UidScopedActivityJournal {
  _CountingJournal(ActivityJournalFactory f, Future<String> Function() root)
      : super(factory: f, scopesRoot: root);
  int puts = 0;
  _Gate? putGate;

  @override
  Future<JournalEntry> put(ActivitySession session,
      {JournalSyncState? syncState,
      int? baseRev,
      Map<String, Object?>? baseSummary}) async {
    puts++;
    final g = putGate;
    putGate = null;
    if (g != null) await g.pass();
    return super.put(session,
        syncState: syncState, baseRev: baseRev, baseSummary: baseSummary);
  }
}

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

Future<void> settle() async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _uidA = 'uidAlphaSecret1';
const _uidB = 'uidBravoSecret2';

void main() {
  late ScopedJournalWorld w;
  late _CountingJournal journal;
  late _Backend backend;
  late List<String> pushes;
  late List<_FakeTimer> timers;
  late ActivitySyncRepository repo;
  late List<String> logs;
  late DebugPrintCallback savedDebugPrint;
  Object? pushError;

  ActivitySyncRepository make({String? Function()? authUid, bool pusher = true}) =>
      repo = ActivitySyncRepository(
        journal: journal,
        backend: backend,
        tombstonePusher: pusher
            ? (id, _) async {
                pushes.add(id);
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
        authUid: authUid,
      );

  /// Binds [uid]; entry 1 unsynced, entry 2 deleted (a local tombstone).
  Future<void> seed(String uid) async {
    expect(await journal.bindUid(uid), isTrue);
    await journal.put(journalSession(idFor(1), seed: 1));
    await journal.put(journalSession(idFor(2), seed: 2));
    await journal.delete(idFor(2));
  }

  setUp(() async {
    w = await ScopedJournalWorld.create();
    journal = _CountingJournal(w.factory, () async => '${w.base}/activity_journal');
    backend = _Backend();
    pushes = [];
    timers = [];
    pushError = null;
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

  void expectNoCalls() {
    expect(backend.calls, isEmpty, reason: 'zero backend calls');
    expect(pushes, isEmpty, reason: 'zero pusher calls');
  }

  group('G1: journal bound to A, authUid returns B', () {
    test('every operation returns pending/empty with zero calls', () async {
      await seed('A');
      make(authUid: () => 'B');
      final putsBefore = journal.puts;

      expect(await repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expect(await repo.syncAll(), isEmpty);
      expect(await repo.syncBatch([idFor(1)]),
          {idFor(1): SyncOutcome.pending});
      expect(await repo.resolveConflict(idFor(1), ConflictChoice.keepCloud),
          SyncOutcome.pending);
      expect(
          await repo.resolveCandidate(
              idFor(1), 'distanceM', CandidateChoice.useComputed),
          SyncOutcome.pending);
      expect(await repo.applyExplicitEdit(idFor(1), {'distanceM': 5000}),
          SyncOutcome.pending);
      expect(await repo.saveSession(journalSession(idFor(1), seed: 1)),
          SyncOutcome.pending);

      expect(journal.puts, putsBefore, reason: 'saveSession put nothing');
      expectNoCalls();
      expect(timers, isEmpty);
    });

    test('case sensitive: bound Abc, authUid abc -> zero calls', () async {
      await seed('Abc');
      make(authUid: () => 'abc');
      expect(await repo.syncAll(), isEmpty);
      expect(await repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expectNoCalls();
    });

    test('retry timer scheduled under A does nothing once auth is B',
        () async {
      await seed('A');
      String? cur = 'A';
      pushError = StateError('offline');
      make(authUid: () => cur);
      await repo.syncAll();
      expect(timers.where((t) => t.isActive), hasLength(1));
      final calls = backend.calls.length;
      final pushed = pushes.length;
      expect(pushed, 1, reason: 'A tried once');

      cur = 'B'; // no onAccountChanged
      timers.firstWhere((t) => t.isActive).fire();
      await settle();
      expect(backend.calls.length, calls);
      expect(pushes.length, pushed);
    });

    test('control: the same timer under matching uids does run the pass',
        () async {
      await seed('A');
      pushError = StateError('offline');
      make(authUid: () => 'A');
      await repo.syncAll();
      final pushed = pushes.length;
      timers.firstWhere((t) => t.isActive).fire();
      await settle();
      expect(pushes.length, greaterThan(pushed));
    });

    test('auth flips between listTombstoneIds and the pusher: not pushed',
        () async {
      await seed('A');
      String? cur = 'A';
      make(authUid: () => cur);
      backend.afterList = () => cur = 'B';
      final out = await repo.syncAll();
      expect(pushes, isEmpty, reason: 'the pusher must not be called for B');
      expect(out.values, isNot(contains(SyncOutcome.deletedLocal)));
      expect(backend.calls, ['listTombstoneIds']);
    });

    test('auth flips while the first of two writes is blocked: the second '
        'entry gets no backend call', () async {
      expect(await journal.bindUid('A'), isTrue);
      await journal.put(journalSession(idFor(1), seed: 1));
      await journal.put(journalSession(idFor(2), seed: 2));
      String? cur = 'A';
      make(authUid: () => cur);
      final g = _Gate();
      backend.writeGate = g;
      final f = repo.syncAll();
      await g.entered.future;
      final at = backend.calls.length;
      cur = 'B';
      g.release.complete();
      await f;
      expect(backend.calls.length, at, reason: 'nothing after the flip');
      expect(backend.calls.where((c) => c.startsWith('writeSummary')),
          hasLength(1));
    });

    test('authUid null at the start with a bound scoped journal: zero calls',
        () async {
      await seed('A');
      make(authUid: () => null);
      expect(await repo.syncAll(), isEmpty);
      expect(await repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expectNoCalls();
    });

    test('unbound scoped journal: syncAll empty, syncEntry pending, '
        'resolutions unavailable', () async {
      make(authUid: () => 'A');
      expect(await repo.syncAll(), isEmpty);
      expect(await repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expect(await repo.resolveConflict(idFor(1), ConflictChoice.keepCloud),
          SyncOutcome.unavailable);
      expect(await repo.applyExplicitEdit(idFor(1), {'distanceM': 1}),
          SyncOutcome.unavailable);
      expectNoCalls();
    });

    test('positive control: agreeing uids sync entries and push tombstones',
        () async {
      await seed('A');
      make(authUid: () => 'A');
      final out = await repo.syncAll();
      expect(out[idFor(1)], SyncOutcome.synced);
      expect(backend.docs.keys, contains(idFor(1)));
      expect(pushes, [idFor(2)]);
    });

    test('scoped journal with a null supplier: behaviour unchanged', () async {
      await seed('A');
      make();
      final out = await repo.syncAll();
      expect(out[idFor(1)], SyncOutcome.synced);
      expect(pushes, [idFor(2)]);
    });

    test('plain (non-scoped) journal ignores the tie: any authUid syncs',
        () async {
      final h = JournalHarness.memory();
      await h.open();
      addTearDown(h.journal.close);
      await h.journal.put(journalSession(idFor(1), seed: 1));
      final plain = ActivitySyncRepository(
          journal: h.journal, backend: backend, authUid: () => 'whoever');
      addTearDown(plain.dispose);
      repo = make(); // for tearDown
      expect(await plain.syncEntry(idFor(1)), SyncOutcome.synced);
      expect(backend.docs.keys, [idFor(1)]);
    });
  });

  group('G5: skipped passes are logged with a reason and no uid', () {
    List<String> skipped() => [for (final l in logs) if (l.contains('skipped')) l];

    void expectClean() {
      for (final l in logs) {
        expect(l, isNot(contains(_uidA)));
        expect(l, isNot(contains(_uidB)));
        expect(l, isNot(contains(idFor(1))));
      }
    }

    test('journal-unbound for syncAll and syncEntry', () async {
      make(authUid: () => _uidA);
      expect(await repo.syncAll(), isEmpty);
      expect(await repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expect(skipped(), [
        'activity: syncAll skipped (journal-unbound)',
        'activity: syncEntry skipped (journal-unbound)',
      ]);
      expectClean();
    });

    test('journal-auth-mismatch', () async {
      await seed(_uidA);
      make(authUid: () => _uidB);
      expect(await repo.syncAll(), isEmpty);
      expect(await repo.syncEntry(idFor(1)), SyncOutcome.pending);
      expect(skipped(), [
        'activity: syncAll skipped (journal-auth-mismatch)',
        'activity: syncEntry skipped (journal-auth-mismatch)',
      ]);
      expectClean();
    });

    test('auth-null', () async {
      await seed(_uidA);
      make(authUid: () => null);
      expect(await repo.syncAll(), isEmpty);
      expect(skipped(), ['activity: syncAll skipped (auth-null)']);
      expectClean();
    });

    test('auth-changed: the supplier answers differently after the start',
        () async {
      await seed(_uidA);
      var n = 0;
      make(authUid: () => ++n == 1 ? _uidA : _uidB);
      expect(await repo.syncAll(), isEmpty);
      expect(skipped(), ['activity: syncAll skipped (auth-changed)']);
      expect(backend.calls, isEmpty);
      expectClean();
    });

    test('pass-identity: onAccountChanged while saveSession put is blocked',
        () async {
      expect(await journal.bindUid(_uidA), isTrue);
      make();
      final g = _Gate();
      journal.putGate = g;
      final f = repo.saveSession(journalSession(idFor(1), seed: 1));
      await g.entered.future;
      repo.onAccountChanged();
      g.release.complete();
      expect(await f, SyncOutcome.pending);
      expect(skipped(), ['activity: syncEntry skipped (pass-identity)']);
      expect(backend.calls, isEmpty);
      expectClean();
    });

    test('a normal successful pass logs no skipped line', () async {
      await seed(_uidA);
      make(authUid: () => _uidA);
      final out = await repo.syncAll();
      expect(out[idFor(1)], SyncOutcome.synced);
      expect(skipped(), isEmpty);
    });
  });
}
