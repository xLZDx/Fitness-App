// S02 test epic 13a: the user promise behind remediation G1. "In the gap where
// FirebaseAuth already says B but the journal still holds A's entries, nothing
// of A reaches B's cloud and B's local data is untouched." End to end over the
// REAL FileActivityJournal on a temp directory (per-account scopes through
// UidScopedActivityJournal, in-memory key providers) and the real
// ActivitySyncRepository. The cloud is a recording fake keyed by the signed-in
// uid AT THE TIME OF EACH CALL. Oracles are the promise and
// docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md heading G1, not the code.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';

class _Cloud implements ActivitySummaryBackend {
  _Cloud(this.auth);
  final String? Function() auth;
  final List<String> calls = [];
  final Map<String, Map<String, Object?>> docsOfB = {};

  void _rec(String m, [String id = '']) => calls.add('${auth()}:$m:$id');

  @override
  Future<Set<String>> listTombstoneIds() async {
    _rec('listTombstoneIds');
    return {};
  }

  @override
  Future<bool> tombstoneExists(String id) async {
    _rec('tombstoneExists', id);
    return false;
  }

  @override
  Future<Map<String, Object?>?> readSummary(String id) async {
    _rec('readSummary', id);
    return null;
  }

  @override
  Future<void> writeSummary(String id, Map<String, Object> summary,
      {required bool create}) async {
    _rec('writeSummary', id);
    if (auth() == 'B') docsOfB[id] = {...summary};
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

Future<Map<String, String>> _hashTree(Directory d) async {
  final out = <String, String>{};
  await for (final e in d.list(recursive: true, followLinks: false)) {
    if (e is File) {
      out[e.path.replaceAll('\\', '/')] =
          sha256.convert(await e.readAsBytes()).toString();
    }
  }
  return out;
}

void main() {
  late Directory tmp;
  late UidScopedActivityJournal journal;
  late _Cloud cloud;
  late ActivitySyncRepository repo;
  late List<String> pushes;
  String? signedIn;
  void Function()? retryCallback;
  final keys = <String, JournalKeyProvider>{};

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('s02_auth_flip_');
    keys.clear();
    pushes = [];
    retryCallback = null;
    journal = UidScopedActivityJournal(
        scopesRoot: () async => '${tmp.path.replaceAll(r'\', '/')}/activity_journal',
        factory: (scope) async {
      return FileActivityJournal(
        rootPath: '${tmp.path.replaceAll('\\', '/')}/activity_journal/$scope',
        keyProvider: keys.putIfAbsent(scope,
            () => InMemoryJournalKeyProvider(fixedJournalKey(scope.hashCode))),
      );
    });
    cloud = _Cloud(() => signedIn);
    repo = ActivitySyncRepository(
      journal: journal,
      backend: cloud,
      tombstonePusher: (id, _) async {
        pushes.add('$signedIn:$id');
        throw StateError('offline'); // keeps a retry timer scheduled
      },
      authUid: () => signedIn,
      clock: () => DateTime.utc(2026, 10, 16, 12),
      retryTimerFactory: (d, cb) {
        retryCallback = cb;
        return _NeverTimer();
      },
    );
    // A: entry 1 unsynced, entry 2 deleted (owed tombstone). B: entry 3.
    expect(await journal.bindUid('A'), isTrue);
    await journal.put(journalSession(idFor(1), seed: 1));
    await journal.put(journalSession(idFor(2), seed: 2));
    await journal.delete(idFor(2));
    expect(await journal.bindUid('B'), isTrue);
    await journal.put(journalSession(idFor(3), seed: 3));
    expect(await journal.bindUid('A'), isTrue);
  });

  tearDown(() async {
    await repo.dispose();
    try {
      await journal.close();
    } catch (_) {}
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('auth flips to B while the journal still holds A: nothing of A reaches '
      'B\'s cloud, no local byte changes, then B\'s own pass syncs only B',
      () async {
    final before = await _hashTree(tmp);
    expect(before, isNotEmpty);

    signedIn = 'B'; // FirebaseAuth moved on; the journal is still A's
    expect(journal.boundUid, 'A');

    expect(await repo.syncAll(), isEmpty);
    expect(await repo.syncEntry(idFor(1)), SyncOutcome.pending);
    expect(await repo.syncBatch([idFor(1)]), {idFor(1): SyncOutcome.pending});
    expect(await repo.resolveConflict(idFor(1), ConflictChoice.keepCloud),
        SyncOutcome.pending);
    expect(await repo.applyExplicitEdit(idFor(1), {'distanceM': 9999}),
        SyncOutcome.pending);
    expect(cloud.calls, isEmpty, reason: 'nothing of A reaches any cloud');
    expect(pushes, isEmpty, reason: 'no tombstone of A is pushed');
    expect(await _hashTree(tmp), before,
        reason: 'neither A\'s nor B\'s local files changed');

    // The rebind arrives and the repository is told: B syncs ONLY its own data.
    expect(await journal.bindUid('B'), isTrue);
    repo.onAccountChanged();
    final out = await repo.syncAll();
    expect(out.keys, [idFor(3)]);
    expect(out[idFor(3)], SyncOutcome.synced);
    final writes = cloud.calls.where((c) => c.contains('writeSummary'));
    expect(writes, ['B:writeSummary:${idFor(3)}']);
    expect(cloud.calls.any((c) => c.contains(idFor(1)) || c.contains(idFor(2))),
        isFalse,
        reason: 'A\'s ids never appear under B');
    expect(pushes, isEmpty, reason: 'B owes no tombstone');
    expect(cloud.docsOfB.keys, [idFor(3)]);

    // A's own data is still intact and unsynced.
    expect(await journal.bindUid('A'), isTrue);
    expect((await journal.read(idFor(1)))!.state.syncState.name,
        isNot('synced'));
    expect(await journal.listTombstones(), hasLength(1));
  });

  test('a retry timer of A that fires after the flip does nothing; the same '
      'timer under matching uids does run (control)', () async {
    signedIn = 'A';
    await repo.syncAll(); // push of the owed tombstone fails -> timer
    expect(retryCallback, isNotNull);
    final calls = cloud.calls.length;
    final pushed = pushes.length;
    expect(pushed, 1);

    signedIn = 'B'; // no onAccountChanged yet
    retryCallback!();
    await pumpEventQueue();
    expect(cloud.calls.length, calls, reason: 'no backend call after the flip');
    expect(pushes.length, pushed, reason: 'no push for B');

    signedIn = 'A';
    retryCallback!();
    await pumpEventQueue();
    expect(pushes.length, greaterThan(pushed), reason: 'control: A retries');
  });
}
