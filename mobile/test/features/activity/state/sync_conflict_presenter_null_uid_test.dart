// S02 test epic 16c: remediation J3 B4. A conflict-sheet tap with no signed-in
// uid does nothing: the repository is not called, no busy key is set and no
// failure flag appears. Oracle: S02_REMEDIATION_J_TEST_NOTES.md (CLIENT J3b, B4).
//
// The real repository over the shared journal harness; a counting journal and
// the fake backend observe every call the repository makes. The control rows
// (uid 'A') prove the observers see a call when one is made, so "zero" cannot
// pass because the observer is blind.
import 'package:fitness_app/features/activity/data/summary_projection.dart'
    show CandidateChoice;
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';

class _CountingJournal extends FileActivityJournal {
  _CountingJournal({
    required super.rootPath,
    required super.fileSystem,
    required super.keyProvider,
    required super.clock,
  });
  int reads = 0;

  @override
  Future<JournalEntry?> read(String id) {
    reads++;
    return super.read(id);
  }
}

void main() {
  late JournalHarness h;
  late _CountingJournal journal;
  late FakeSummaryBackend backend;
  late ActivitySyncRepository repo;

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
    await h.journal.close();
    journal = _CountingJournal(
      rootPath: h.root,
      fileSystem: h.fs,
      keyProvider: h.keys,
      clock: h.clock.call,
    );
    await journal.start();
    backend = FakeSummaryBackend();
    repo = ActivitySyncRepository(
        journal: journal, backend: backend, clock: h.clock.call);
  });

  tearDown(() async {
    await repo.dispose();
    await journal.close();
    await h.dispose();
  });

  ProviderContainer containerFor(String? uid) {
    final c = ProviderContainer(overrides: [
      activitySyncRepositoryProvider.overrideWithValue(repo),
      syncConflictUidProvider.overrideWithValue(uid),
    ]);
    c.listen(syncConflictPresenterProvider, (_, __) {});
    addTearDown(c.dispose);
    return c;
  }

  int observed() => journal.reads + backend.calls.length;

  final taps = <String, Future<void> Function(SyncConflictPresenter)>{
    'keepDevice': (p) => p.keepDevice('missing-1'),
    'keepCloud': (p) => p.keepCloud('missing-1'),
    'resolveCandidate': (p) =>
        p.resolveCandidate('missing-1', 'distanceM', CandidateChoice.useComputed),
  };

  for (final e in taps.entries) {
    test('${e.key}: uid null -> the repository is not called, nothing busy, '
        'no failure flag', () async {
      final c = containerFor(null);
      await pumpEventQueue();
      final before = observed();
      await e.value(c.read(syncConflictPresenterProvider.notifier));
      await pumpEventQueue();
      expect(observed(), before, reason: 'no journal read, no backend call');
      final v = c.read(syncConflictPresenterProvider);
      expect(v.busy, isEmpty);
      expect(v.lastFailed, isFalse);
    });

    test('${e.key} control: uid A reaches the repository (the observers see '
        'the call)', () async {
      final c = containerFor('A');
      await pumpEventQueue();
      final before = observed();
      await e.value(c.read(syncConflictPresenterProvider.notifier));
      expect(observed(), greaterThan(before),
          reason: 'a tap with a uid must call the repository');
    });
  }

  test('a null-uid tap does not make a later tap with a uid a no-op', () async {
    final c = containerFor(null);
    final p = c.read(syncConflictPresenterProvider.notifier);
    await p.keepDevice('missing-1');
    expect(c.read(syncConflictPresenterProvider).busy, isEmpty,
        reason: 'no stuck busy key after the ignored tap');
  });
}
