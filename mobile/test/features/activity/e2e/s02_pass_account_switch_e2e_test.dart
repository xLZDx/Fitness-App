// S02 test epic 12a: the user promise behind remediation F1. "A sync of account
// A that is still running never touches account B's data", including the cloud
// side. End to end over the REAL FileActivityJournal on a temp directory
// (per-account scopes through UidScopedActivityJournal, in-memory key
// providers) and the real ActivitySyncRepository. The cloud is a recording
// fake keyed by the signed-in uid AT THE TIME OF EACH CALL, so a call that
// carries A's data under B's account is visible. Oracles are the promise and
// docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md heading F1, not the code.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';

const double _distA = 4800;
const double _distB = 5100;

class _Gate {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  Future<void> pass() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }
}

class _Call {
  _Call(this.uid, this.method, this.id, [this.distance]);
  final String? uid;
  final String method;
  final String id;
  final Object? distance;

  @override
  String toString() => '$uid:$method:$id:$distance';
}

/// The cloud: one document and tombstone space per account.
class _Cloud implements ActivitySummaryBackend {
  _Cloud(this.auth);

  final String? Function() auth;
  final Map<String, Map<String, Map<String, Object?>>> docs = {};
  final Map<String, Set<String>> tombs = {};
  final List<_Call> calls = [];
  _Gate? writeGate;
  _Gate? listGate;

  List<_Call> by(String uid, [String? method]) => [
        for (final c in calls)
          if (c.uid == uid && (method == null || c.method == method)) c
      ];

  @override
  Future<Set<String>> listTombstoneIds() async {
    final uid = auth();
    calls.add(_Call(uid, 'listTombstoneIds', ''));
    final g = listGate;
    listGate = null;
    if (g != null) await g.pass();
    return {...?tombs[uid]};
  }

  @override
  Future<bool> tombstoneExists(String id) async {
    final uid = auth();
    calls.add(_Call(uid, 'tombstoneExists', id));
    return tombs[uid]?.contains(id) ?? false;
  }

  @override
  Future<Map<String, Object?>?> readSummary(String id) async {
    final uid = auth();
    calls.add(_Call(uid, 'readSummary', id));
    final d = docs[uid]?[id];
    return d == null ? null : {...d};
  }

  @override
  Future<void> writeSummary(String id, Map<String, Object> summary,
      {required bool create}) async {
    final uid = auth();
    calls.add(_Call(uid, 'writeSummary', id, summary['distanceM']));
    final g = writeGate;
    writeGate = null;
    if (g != null) await g.pass();
    (docs[uid ?? '?'] ??= {})[id] = {...summary};
  }
}

class _World {
  late Directory tmp;
  final Map<String, JournalKeyProvider> _keys = {};
  late UidScopedActivityJournal journal;
  String? signedIn;
  late _Cloud cloud;
  late ActivitySyncRepository repo;
  final pushes = <(String?, String)>[];
  Future<void> Function(String id)? pushGate;

  Future<void> open() async {
    tmp = await Directory.systemTemp.createTemp('s02_pass_switch_');
    journal = UidScopedActivityJournal(
        scopesRoot: () async => '${tmp.path.replaceAll(r'\', '/')}/activity_journal',
        factory: (scope) async {
      return FileActivityJournal(
        rootPath: '${tmp.path.replaceAll('\\', '/')}/activity_journal/$scope',
        keyProvider: _keys.putIfAbsent(
            scope, () => InMemoryJournalKeyProvider(fixedJournalKey(scope.hashCode))),
      );
    });
    cloud = _Cloud(() => signedIn);
    repo = ActivitySyncRepository(
      journal: journal,
      backend: cloud,
      tombstonePusher: (id, _) async {
        pushes.add((signedIn, id));
        await pushGate?.call(id);
      },
      authUid: () => signedIn,
      clock: () => DateTime.utc(2026, 10, 16, 12),
      // Never fires on its own: the test drives passes explicitly.
      retryTimerFactory: (d, cb) => _NeverTimer(),
    );
  }

  /// The order the app uses: the auth session moves first, then the journal
  /// is rebound, then the repository is told.
  Future<void> signIn(String uid) async {
    signedIn = uid;
    expect(await journal.bindUid(uid), isTrue);
    repo.onAccountChanged();
  }

  Future<void> put(String uid, int n, double dist) async {
    expect(await journal.bindUid(uid), isTrue);
    await journal.put(journalSession(idFor(n), seed: n, distanceM: dist));
  }

  Future<void> dispose() async {
    await repo.dispose();
    try {
      await journal.close();
    } catch (_) {}
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}

class _NeverTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => true;

  @override
  int get tick => 0;
}

String _fingerprint(JournalEntry e) =>
    '${sessionJson(e.session)}|${e.state.syncState.wire}|${e.state.baseRev}|'
    '${jsonEncode(e.state.baseSummary)}|g${e.generation}';

void main() {
  late _World w;
  setUp(() async {
    w = _World();
    await w.open();
  });
  tearDown(() => w.dispose());

  test('A\'s pass blocked in a cloud write while the user signs in as B: no '
      'cloud call carries A\'s data under B, B\'s entry is untouched, and both '
      'accounts still sync correctly afterwards', () async {
    await w.put('A', 1, _distA);
    await w.put('A', 2, _distA);
    await w.put('B', 1, _distB); // SAME id as A's first activity
    final bBefore = _fingerprint((await w.journal.read(idFor(1)))!);
    await w.signIn('A');

    final gate = _Gate();
    w.cloud.writeGate = gate;
    final stale = w.repo.syncAll();
    await gate.entered.future; // A's pass is inside its first cloud write
    expect(w.cloud.by('A', 'writeSummary'), hasLength(1));

    await w.signIn('B');
    final callsAtSwitch = w.cloud.calls.length;
    gate.release.complete();
    final out = await stale;

    // The promise: the stale pass touches nothing of B, in the cloud or locally.
    expect(w.cloud.calls.length, callsAtSwitch,
        reason: 'the stale pass makes no further cloud call');
    expect(w.cloud.by('B'), isEmpty,
        reason: 'no call under B\'s account at all');
    expect(w.cloud.docs['B'], isNull, reason: 'B has nothing in the cloud yet');
    expect(out.values, isNot(contains(SyncOutcome.synced)),
        reason: 'a pass that lost its account reports nothing as synced');
    expect(_fingerprint((await w.journal.read(idFor(1)))!), bBefore,
        reason: 'B\'s entry (same id) is byte-identical, still pending');

    // B syncs its own data.
    final bOut = await w.repo.syncAll();
    expect(bOut[idFor(1)], SyncOutcome.synced);
    expect(w.cloud.docs['B']![idFor(1)]!['distanceM'], _distB);
    expect(w.cloud.by('B', 'writeSummary').map((c) => c.distance),
        everyElement(_distB),
        reason: 'only B\'s own value is ever written under B');
    expect(w.cloud.docs['B']!.keys, [idFor(1)],
        reason: 'A\'s second activity never reaches B\'s cloud space');

    // A signs in again: its data is intact and its own pass completes.
    await w.signIn('A');
    final aEntry = (await w.journal.read(idFor(1)))!;
    expect(aEntry.session.summary.distanceM, _distA);
    expect(aEntry.state.syncState, JournalSyncState.pending,
        reason: 'A\'s entry was not marked synced by the stale pass');
    final aOut = await w.repo.syncAll();
    expect(aOut[idFor(1)], SyncOutcome.synced);
    expect(aOut[idFor(2)], SyncOutcome.synced);
    expect(w.cloud.docs['A']!.keys.toSet(), {idFor(1), idFor(2)});
    expect(w.cloud.docs['A']![idFor(1)]!['distanceM'], _distA);
    expect(w.cloud.docs['B']![idFor(1)]!['distanceM'], _distB,
        reason: 'B\'s cloud document is still B\'s');
  });

  test('A\'s server tombstone for an id B also holds never deletes B\'s '
      'entry; A\'s own delete still works', () async {
    await w.put('A', 1, _distA);
    await w.put('A', 2, _distA);
    await w.put('B', 1, _distB);
    w.cloud.tombs['A'] = {idFor(1)}; // A deleted activity 1 on another device
    await w.signIn('A');

    final gate = _Gate();
    w.cloud.listGate = gate;
    final stale = w.repo.syncAll();
    await gate.entered.future;
    await w.signIn('B');
    gate.release.complete();
    final out = await stale;

    expect(out.values, isNot(contains(SyncOutcome.deletedLocal)));
    final b = await w.journal.read(idFor(1));
    expect(b, isNotNull, reason: 'B\'s activity survives A\'s tombstone');
    expect(b!.session.summary.distanceM, _distB);
    expect(await w.journal.listTombstones(), isEmpty,
        reason: 'B has no local tombstone');
    expect(w.cloud.by('B'), isEmpty);

    // B\'s own pass keeps and syncs it.
    final bOut = await w.repo.syncAll();
    expect(bOut[idFor(1)], SyncOutcome.synced);
    expect(await w.journal.read(idFor(1)), isNotNull);

    // A\'s own pass still honours A\'s tombstone (delete wins for A).
    await w.signIn('A');
    final aOut = await w.repo.syncAll();
    expect(aOut[idFor(1)], SyncOutcome.deletedLocal);
    expect(await w.journal.read(idFor(1)), isNull);
    expect(aOut[idFor(2)], SyncOutcome.synced);
  });

  test('A\'s owed deletions: a push blocked during the switch is the last '
      'call for A, and B pushes its own deletions under its own account',
      () async {
    for (final u in ['A', 'B']) {
      await w.put(u, 1, 4000);
      await w.put(u, 2, 4000);
      expect(await w.journal.bindUid(u), isTrue);
      await w.journal.delete(idFor(1));
      await w.journal.delete(idFor(2));
    }
    await w.signIn('A');
    final gate = _Gate();
    w.pushGate = (id) async {
      if (w.pushes.length == 1) await gate.pass();
    };
    final stale = w.repo.syncAll();
    await gate.entered.future;
    await w.signIn('B');
    gate.release.complete();
    await stale;

    expect(w.pushes.where((p) => p.$1 == 'A'), hasLength(1),
        reason: 'A pushed only the call that was already in flight');
    expect(w.pushes.where((p) => p.$1 == 'B'), isEmpty,
        reason: 'the stale pass pushed nothing under B');

    await w.repo.syncAll();
    expect({for (final p in w.pushes.where((p) => p.$1 == 'B')) p.$2},
        {idFor(1), idFor(2)},
        reason: 'B owed both ids and its confirmed set was not polluted');
  });
}
