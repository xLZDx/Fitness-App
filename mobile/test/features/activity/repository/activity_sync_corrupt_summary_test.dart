// S02 remediation B2 (test epic 9b): SF4 corrupt cloud summary and SF9
// tombstone push error code. Oracles: S02_REMEDIATION_B_TEST_NOTES.md B2
// (SF4 backend, SF4 sync, SF9) and design 6.2, not the code under test.
//
// The Firestore types are faked by implementing them (no Firestore fake is a
// dependency of this project; same approach as
// test/features/workouts/data_session_repo_save_timeout_test.dart).
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/firestore_activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';
import '../../../support/two_device_world.dart' show baseSession;

// ---- fake Firestore ---------------------------------------------------------

typedef _Fetch = Future<Object> Function(String path);

class _Snap implements DocumentSnapshot<Map<String, dynamic>> {
  _Snap({required this.exists, this.onData});
  @override
  final bool exists;
  final Map<String, dynamic>? Function()? onData;

  @override
  Map<String, dynamic>? data() => onData?.call();

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _QDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QDoc(this.id);
  @override
  final String id;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _QSnap implements QuerySnapshot<Map<String, dynamic>> {
  _QSnap(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Doc implements DocumentReference<Map<String, dynamic>> {
  _Doc(this.path, this.fetch);
  final String path;
  final _Fetch fetch;
  @override
  CollectionReference<Map<String, dynamic>> collection(String p) =>
      _Col('$path/$p', fetch);
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async =>
      (await fetch(path)) as DocumentSnapshot<Map<String, dynamic>>;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Col implements CollectionReference<Map<String, dynamic>> {
  _Col(this.path, this.fetch);
  final String path;
  final _Fetch fetch;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? p]) =>
      _Doc('$path/$p', fetch);
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async =>
      (await fetch(path)) as QuerySnapshot<Map<String, dynamic>>;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Db implements FirebaseFirestore {
  _Db(this.fetch);
  final _Fetch fetch;
  @override
  CollectionReference<Map<String, dynamic>> collection(String p) => _Col(p, fetch);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

FirestoreActivitySummaryBackend _backend(_Fetch fetch,
        {String? uid = 'u1',
        Duration timeout = const Duration(seconds: 5)}) =>
    FirestoreActivitySummaryBackend(
        firestore: _Db(fetch), currentUid: () => uid, timeout: timeout);

// ---- sync fakes -------------------------------------------------------------

class _CorruptableBackend extends FakeSummaryBackend {
  bool corrupt = false;

  @override
  Future<Map<String, Object?>?> readSummary(String id) async {
    if (corrupt) {
      calls.add('readSummary');
      throw const SummaryCorrupt('TypeError');
    }
    return super.readSummary(id);
  }
}

class _Coded implements Exception {
  _Coded(this.code);
  final String code;
}

void main() {
  group('SF4 backend: parse is outside the network catch', () {
    test('fetch succeeds but the document cannot be parsed: SummaryCorrupt, '
        'never SummaryBackendUnavailable', () async {
      final b = _backend((_) async => _Snap(
          exists: true, onData: () => throw const FormatException('bad type')));
      await expectLater(b.readSummary('a1'), throwsA(isA<SummaryCorrupt>()));
      await expectLater(
          b.readSummary('a1'), throwsA(isNot(isA<SummaryBackendUnavailable>())));
    });

    test('a fetch that throws FirebaseException is Unavailable with the code',
        () async {
      final b = _backend((_) async =>
          throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      await expectLater(
          b.readSummary('a1'),
          throwsA(isA<SummaryBackendUnavailable>()
              .having((e) => e.cause, 'cause', 'unavailable')));
      await expectLater(b.tombstoneExists('a1'),
          throwsA(isA<SummaryBackendUnavailable>()));
      await expectLater(b.listTombstoneIds(),
          throwsA(isA<SummaryBackendUnavailable>()));
    });

    test('a fetch that times out is Unavailable (TimeoutException)', () async {
      final never = Completer<Object>();
      final b = _backend((_) => never.future,
          timeout: const Duration(milliseconds: 20));
      await expectLater(
          b.readSummary('a1'),
          throwsA(isA<SummaryBackendUnavailable>()
              .having((e) => e.cause, 'cause', 'TimeoutException')));
    });

    test('a missing sign-in is Unavailable(not-signed-in) before any fetch',
        () async {
      var fetched = false;
      final b = _backend((_) async {
        fetched = true;
        return _Snap(exists: false);
      }, uid: null);
      await expectLater(
          b.readSummary('a1'),
          throwsA(isA<SummaryBackendUnavailable>()
              .having((e) => e.cause, 'cause', 'not-signed-in')));
      expect(fetched, isFalse);
    });

    test('a good document is returned, an absent one is null, tombstones list',
        () async {
      final t = Timestamp.fromDate(DateTime.utc(2026, 5, 1, 6));
      final paths = <String>[];
      final b = _backend((p) async {
        paths.add(p);
        if (p.endsWith('activity_tombstones')) {
          return _QSnap([_QDoc('x'), _QDoc('y')]);
        }
        if (p.endsWith('/missing')) return _Snap(exists: false);
        return _Snap(
            exists: true, onData: () => {'startUtc': t, 'distanceM': 5000});
      });
      final doc = await b.readSummary('a1');
      expect(doc!['startUtc'], DateTime.utc(2026, 5, 1, 6));
      expect((doc['startUtc'] as DateTime).isUtc, isTrue);
      expect(doc['distanceM'], 5000);
      expect(await b.readSummary('missing'), isNull);
      expect(await b.listTombstoneIds(), {'x', 'y'});
      expect(paths.first, 'users/u1/activities/a1');
    });
  });

  group('SF4 sync: SummaryCorrupt is a visible conflict, not offline', () {
    late JournalHarness h;
    late _CorruptableBackend backend;
    late ActivitySyncRepository repo;
    const id = 'act_00000000000000000000000000000000000000a1';

    setUp(() async {
      h = JournalHarness.memory();
      await h.open();
      backend = _CorruptableBackend();
      repo = ActivitySyncRepository(
          journal: h.journal, backend: backend, clock: h.clock.call);
      addTearDown(repo.dispose);
      addTearDown(h.dispose);
    });

    Future<JournalState> stateOf() async => (await h.journal.read(id))!.state;

    test('non-denial read (new entry): outcome conflict, entry sync_conflict, '
        'local data intact, nothing written, lastCorruptRead set', () async {
      backend.corrupt = true;
      final session = baseSession(id);
      await h.journal.put(session);
      expect(repo.lastCorruptRead, isNull);

      final out = await repo.syncEntry(id);

      expect(out, SyncOutcome.conflict);
      expect(out, isNot(SyncOutcome.unavailable));
      expect((await stateOf()).syncState, JournalSyncState.syncConflict);
      expect(backend.count('writeSummary'), 0, reason: 'nothing written');
      expect(backend.docs, isEmpty);
      final kept = (await h.journal.read(id))!;
      expect(sessionJson(kept.session), sessionJson(session),
          reason: 'local data kept');
      expect(kept.streamsLoaded, isTrue);
      expect(repo.lastCorruptRead, h.clock.now);
    });

    test('after a denial: the read of the server copy is corrupt, outcome '
        'conflict, local edit kept', () async {
      // Synced at rev 1, then the server moves on and the device edits.
      expect(await (() async {
        await h.journal.put(baseSession(id));
        return repo.syncEntry(id);
      })(), SyncOutcome.synced);
      backend.docs[id]!['rev'] = 5; // another device wrote
      final edited = baseSession(id, distanceM: 6100);
      await h.journal.put(edited);
      backend.corrupt = true;
      final writesBefore = backend.count('writeSummary');

      final out = await repo.syncEntry(id);

      expect(backend.count('writeSummary') - writesBefore, 1,
          reason: 'the optimistic write was tried and denied');
      expect(out, SyncOutcome.conflict);
      expect((await stateOf()).syncState, JournalSyncState.syncConflict);
      expect(sessionJson((await h.journal.read(id))!.session),
          sessionJson(edited),
          reason: 'local edit kept');
      expect(backend.docs[id]!['rev'], 5, reason: 'server copy untouched');
      expect(repo.lastCorruptRead, isNotNull);
    });

    test('no retry loop: syncAll skips the conflict, a retry pass reads once '
        'per process', () async {
      backend.corrupt = true;
      await h.journal.put(baseSession(id));
      await repo.syncEntry(id);
      final reads = backend.count('readSummary');

      await repo.syncAll();
      await repo.syncAll();
      expect(backend.count('readSummary'), reads,
          reason: 'a conflict is not retried without retryConflicts');

      await repo.syncAll(retryConflicts: true);
      expect(backend.count('readSummary'), reads + 1,
          reason: 'one retry per process');
      await repo.syncAll(retryConflicts: true);
      await repo.syncAll(retryConflicts: true);
      expect(backend.count('readSummary'), reads + 1, reason: 'no hot loop');
      expect((await stateOf()).syncState, JournalSyncState.syncConflict);
      expect(backend.count('writeSummary'), 0);
    });

    test('the conflict view shows cloudKnown false with no fields and does '
        'not throw', () async {
      backend.corrupt = true;
      await h.journal.put(baseSession(id));
      await repo.syncEntry(id);

      final state = await repo.refreshState();

      expect(state.conflicts, hasLength(1));
      expect(state.conflicts.single.id, id);
      expect(state.conflicts.single.cloudKnown, isFalse);
      expect(state.conflicts.single.fields, isEmpty);
    });

    test('resolveConflict returns conflict and keeps sync_conflict for both '
        'choices', () async {
      backend.corrupt = true;
      final session = baseSession(id);
      await h.journal.put(session);
      await repo.syncEntry(id);

      for (final choice in ConflictChoice.values) {
        expect(await repo.resolveConflict(id, choice), SyncOutcome.conflict,
            reason: '$choice');
        expect((await stateOf()).syncState, JournalSyncState.syncConflict,
            reason: '$choice');
      }
      expect(backend.count('writeSummary'), 0);
      expect(sessionJson((await h.journal.read(id))!.session),
          sessionJson(session));
    });

    test('once the cloud copy is readable again the conflict resolves',
        () async {
      backend.corrupt = true;
      await h.journal.put(baseSession(id));
      await repo.syncEntry(id);
      backend.corrupt = false;

      expect(await repo.resolveConflict(id, ConflictChoice.keepDevice),
          SyncOutcome.synced);
      expect((await stateOf()).syncState, JournalSyncState.synced);
      expect(backend.docs, contains(id));
    });
  });

  group('SF9: tombstone push error code', () {
    late JournalHarness h;
    late FakeSummaryBackend backend;
    const id = 'act_00000000000000000000000000000000000000b1';

    setUp(() async {
      h = JournalHarness.memory();
      await h.open();
      backend = FakeSummaryBackend();
      addTearDown(h.dispose);
    });

    ActivitySyncRepository repoWith(ActivityTombstonePusher push) {
      final r = ActivitySyncRepository(
          journal: h.journal,
          backend: backend,
          tombstonePusher: push,
          clock: h.clock.call);
      addTearDown(r.dispose);
      return r;
    }

    test('an error object with code permission-denied is kept as that code; '
        'the local tombstone stays and the next pass retries', () async {
      await h.journal.put(baseSession(id));
      await h.journal.delete(id);
      var calls = 0;
      var fail = true;
      final repo = repoWith((_, __) async {
        calls++;
        if (fail) throw _Coded('permission-denied');
      });
      expect(repo.lastTombstonePushError, isNull);

      final first = await repo.syncAll();
      expect(first, isEmpty, reason: 'syncAll still completes');
      expect(repo.lastTombstonePushError, 'permission-denied');
      expect(await h.journal.listTombstones(), hasLength(1),
          reason: 'the local tombstone stays');
      expect(calls, 1);

      await repo.syncAll();
      expect(calls, 2, reason: 'the next pass retries');

      fail = false;
      await repo.syncAll();
      expect(calls, 3);
      // Remediation F1 (design 17 item 23) supersedes the epic 9 oracle: a
      // fully clean pass clears the last error, since nothing is owed any more.
      expect(repo.lastTombstonePushError, isNull);
    });

    test('a plain StateError is kept as its type name', () async {
      await h.journal.put(baseSession(id));
      await h.journal.delete(id);
      final repo = repoWith((_, __) async => throw StateError('offline'));
      await repo.syncAll();
      expect(repo.lastTombstonePushError, 'StateError');
      expect(await h.journal.listTombstones(), hasLength(1));
    });

    test('a push that succeeds records no error', () async {
      await h.journal.put(baseSession(id));
      await h.journal.delete(id);
      final pushed = <String>[];
      final repo = repoWith((t, _) async => pushed.add(t));
      await repo.syncAll();
      expect(pushed, [id]);
      expect(repo.lastTombstonePushError, isNull);
    });
  });
}
