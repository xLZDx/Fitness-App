// S02 remediation C (test epic 10a): FL1 conflict view error handling and the
// presenter side of FL2 (loading / failed / retry). Oracles:
// docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md items FL1 and FL2, not the
// code under test.
//
// Real repository over the in-memory journal harness; only the failing
// collaborator (backend readSummary, journal list) is scripted.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';
import '../../../support/two_device_world.dart' show baseSession;

/// Throws [readError] from readSummary while it is set; a SummaryCorrupt while
/// [corruptOnce] is set (used only to create the conflict).
class _ScriptedBackend extends FakeSummaryBackend {
  Object? readError;
  bool corrupt = false;

  @override
  Future<Map<String, Object?>?> readSummary(String id) async {
    if (corrupt) throw const SummaryCorrupt('TypeError');
    final e = readError;
    if (e != null) {
      calls.add('readSummary');
      throw e;
    }
    return super.readSummary(id);
  }
}

/// Delegates to a real journal; `list()` can be made to throw.
class _FlakyJournal implements ActivityJournal {
  _FlakyJournal(this.inner);
  final ActivityJournal inner;
  Object? listError;
  int listCalls = 0;

  @override
  Future<List<JournalEntry>> list() async {
    listCalls++;
    final e = listError;
    if (e != null) throw e;
    return inner.list();
  }

  /// `refreshState()` also counts the unconfirmed local tombstones (E2).
  @override
  Future<List<JournalEntry>> listTombstones() => inner.listTombstones();

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

const _id = 'act_00000000000000000000000000000000000000c1';

Future<void> until(bool Function() cond, {int ms = 4000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('condition not reached in ${ms}ms');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late JournalHarness h;
  late _ScriptedBackend backend;
  late _FlakyJournal journal;
  late ActivitySyncRepository repo;

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
    backend = _ScriptedBackend();
    journal = _FlakyJournal(h.journal);
    repo = ActivitySyncRepository(
        journal: journal, backend: backend, clock: h.clock.call);
    addTearDown(repo.dispose);
    addTearDown(h.dispose);
    // One entry in sync_conflict (the cloud copy is unreadable at first sync).
    // The sync runs on a repository over the real journal; the repository
    // under test wraps it in the flaky journal.
    final seeder = ActivitySyncRepository(
        journal: h.journal, backend: backend, clock: h.clock.call);
    addTearDown(seeder.dispose);
    backend.corrupt = true;
    await h.journal.put(baseSession(_id));
    expect(await seeder.syncEntry(_id), SyncOutcome.conflict);
    backend.corrupt = false;
  });

  group('FL1 watch(): a failing backend read', () {
    test('permission-denied from readSummary: the state still carries the '
        'conflict with cloudKnown false and no fields; no zone error',
        () async {
      backend.readError =
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      final zoneErrors = <Object>[];
      final states = <ActivitySyncState>[];
      final streamErrors = <Object>[];
      await runZonedGuarded(() async {
        final sub = repo.watch().listen(states.add, onError: streamErrors.add);
        await until(() => states.isNotEmpty || streamErrors.isNotEmpty);
        await sub.cancel();
      }, (e, _) => zoneErrors.add(e));

      expect(zoneErrors, isEmpty);
      expect(streamErrors, isEmpty, reason: 'a backend failure is not a load failure');
      expect(states, hasLength(1));
      final c = states.single.conflicts.single;
      expect(c.id, _id);
      expect(c.cloudKnown, isFalse);
      expect(c.fields, isEmpty);
    });

    test('the failed read is not cached: when the backend recovers the next '
        'state knows the cloud again', () async {
      backend.readError =
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      expect((await repo.refreshState()).conflicts.single.cloudKnown, isFalse);
      backend.readError = null;
      backend.docs[_id] = {'rev': 1, 'distanceM': 5000};
      expect((await repo.refreshState()).conflicts.single.cloudKnown, isTrue);
    });

    test('journal list() throws: watch() delivers a stream error, no zone '
        'error, no silent empty state', () async {
      journal.listError = const FileSystemLikeError('disk gone');
      final zoneErrors = <Object>[];
      final states = <ActivitySyncState>[];
      final streamErrors = <Object>[];
      await runZonedGuarded(() async {
        final sub = repo.watch().listen(states.add, onError: streamErrors.add);
        await until(() => streamErrors.isNotEmpty);
        // Give a wrongly emitted empty state a chance to appear.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
      }, (e, _) => zoneErrors.add(e));

      expect(zoneErrors, isEmpty);
      expect(streamErrors, hasLength(1));
      expect(streamErrors.single, isA<FileSystemLikeError>());
      expect(states, isEmpty);
    });
  });

  group('FL1/FL2 presenter: load failure and retry', () {
    ProviderContainer containerFor() {
      final c = ProviderContainer(
          overrides: [activitySyncRepositoryProvider.overrideWithValue(repo)]);
      c.listen(syncConflictPresenterProvider, (_, __) {});
      addTearDown(c.dispose);
      return c;
    }

    test('before the first emission: loaded false, loadFailed false',
        () async {
      final gate = Completer<void>();
      journal.listError = null;
      final slow = _SlowRepo(journal, backend, gate.future, h.clock.call);
      addTearDown(slow.dispose);
      final c = ProviderContainer(
          overrides: [activitySyncRepositoryProvider.overrideWithValue(slow)]);
      addTearDown(c.dispose);
      c.listen(syncConflictPresenterProvider, (_, __) {});
      final v = c.read(syncConflictPresenterProvider);
      expect(v.loaded, isFalse);
      expect(v.loadFailed, isFalse);
      expect(v.hasItems, isFalse);
      gate.complete();
      await until(() => c.read(syncConflictPresenterProvider).loaded);
      expect(c.read(syncConflictPresenterProvider).hasItems, isTrue);
    });

    test('list() throws: loadFailed true and loaded false', () async {
      journal.listError = const FileSystemLikeError('disk gone');
      final zoneErrors = <Object>[];
      await runZonedGuarded(() async {
        final c = containerFor();
        await until(() => c.read(syncConflictPresenterProvider).loadFailed);
        final v = c.read(syncConflictPresenterProvider);
        expect(v.loaded, isFalse);
        expect(v.loadFailed, isTrue);
        expect(v.hasItems, isFalse);
      }, (e, _) => zoneErrors.add(e));
      expect(zoneErrors, isEmpty);
    });

    test('retry re-subscribes (list called again), clears the error and the '
        'next emission carries the conflict', () async {
      journal.listError = const FileSystemLikeError('disk gone');
      final c = containerFor();
      await until(() => c.read(syncConflictPresenterProvider).loadFailed);
      final callsBefore = journal.listCalls;

      journal.listError = null;
      c.read(syncConflictPresenterProvider.notifier).retry();
      // The failure flag is cleared synchronously by retry.
      expect(c.read(syncConflictPresenterProvider).loadFailed, isFalse);
      await until(() => c.read(syncConflictPresenterProvider).loaded);

      expect(journal.listCalls, greaterThan(callsBefore));
      final v = c.read(syncConflictPresenterProvider);
      expect(v.loadFailed, isFalse);
      expect(v.conflicts.single.id, _id);
    });

    test('retry that fails again returns to loadFailed true', () async {
      journal.listError = const FileSystemLikeError('disk gone');
      final c = containerFor();
      await until(() => c.read(syncConflictPresenterProvider).loadFailed);
      final before = journal.listCalls;
      c.read(syncConflictPresenterProvider.notifier).retry();
      await until(() => journal.listCalls > before);
      await until(() => c.read(syncConflictPresenterProvider).loadFailed);
      expect(c.read(syncConflictPresenterProvider).loaded, isFalse);
    });
  });
}

class FileSystemLikeError implements Exception {
  const FileSystemLikeError(this.message);
  final String message;
}

/// Repository whose first `watch()` waits for a gate before reading.
class _SlowRepo extends ActivitySyncRepository {
  _SlowRepo(ActivityJournal j, ActivitySummaryBackend b, this._gate, DateTime Function() clock)
      : super(journal: j, backend: b, clock: clock);
  final Future<void> _gate;

  @override
  Future<ActivitySyncState> refreshState() async {
    await _gate;
    return super.refreshState();
  }
}
