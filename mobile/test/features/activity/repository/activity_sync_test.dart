// S02-02 I05: the `synced` marker is written only after the server accepted the
// write, and a replay after a crash converges to ONE server row. (The stream
// commit callable and its `already_stored` answer belong to S02-04; here the
// summary write plays that role. See the findings document.)
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart';

void main() {
  late JournalHarness h;
  late FakeSummaryBackend backend;
  late ActivitySyncRepository repo;
  final id = idFor(1);

  ActivitySyncRepository newRepo() => ActivitySyncRepository(
      journal: h.journal, backend: backend, clock: h.clock.call);

  setUp(() async {
    h = JournalHarness.memory();
    backend = FakeSummaryBackend();
    await h.open();
    repo = newRepo();
    await h.journal.put(journalSession(id));
  });

  tearDown(() async {
    await repo.dispose();
    await h.dispose();
  });

  Future<List<bool>> syncedFlagsOnDisk() async {
    final out = <bool>[];
    for (final g in await h.generations(id)) {
      final rec = await h.recordJson(id, g);
      out.add((rec['state'] as Map)['synced'] == true);
    }
    return out;
  }

  test('a failing server write never produces a synced marker, in any '
      'generation on disk', () async {
    backend.failWrites = true;
    final out = await repo.syncEntry(id);
    expect(out, SyncOutcome.unavailable);
    expect(backend.applied, 0);
    expect((await h.journal.read(id))!.state.syncState, JournalSyncState.uploadFailed);
    expect(await syncedFlagsOnDisk(), everyElement(isFalse));
    expect((await h.journal.assessSignOut()).unsyncedCount, 1);
  });

  test('success writes exactly one server row and then the marker', () async {
    final out = await repo.syncEntry(id);
    expect(out, SyncOutcome.synced);
    expect(backend.applied, 1);
    expect(backend.docs, hasLength(1));
    final e = (await h.journal.read(id))!;
    expect(e.state.synced, isTrue);
    expect(e.state.baseRev, 1);
  });

  test('a repeated sync of a synced entry writes nothing', () async {
    await repo.syncEntry(id);
    final gen = (await h.journal.read(id))!.generation;
    expect(await repo.syncEntry(id), SyncOutcome.synced);
    expect(await repo.syncEntry(id), SyncOutcome.synced);
    expect(backend.applied, 1);
    expect((await h.journal.read(id))!.generation, gen, reason: 'no new generation');
  });

  test('a lost answer (server applied, client saw an error) followed by a '
      'second sync creates NO second server row and ends synced', () async {
    backend.loseNextAnswer = true;
    expect(await repo.syncEntry(id), SyncOutcome.unavailable);
    expect(backend.applied, 1, reason: 'the server did apply the first write');
    expect(await syncedFlagsOnDisk(), everyElement(isFalse));

    expect(await repo.syncEntry(id), SyncOutcome.synced);
    expect(backend.applied, 1, reason: 'still exactly one server row');
    expect(backend.docs, hasLength(1));
    expect((await h.journal.read(id))!.state.synced, isTrue);
  });

  test('kill after the upload and before the marker, then a restart and a '
      'second sync: one server row, marker written, no conflict', () async {
    // The process dies on the first file operation after the server applied.
    backend.afterApply = () => h.fs.arm(const FaultPlan(0, FaultMode.crashAfter));
    await expectLater(repo.syncEntry(id), throwsA(isA<SimulatedCrash>()));
    expect(backend.applied, 1);
    expect(await syncedFlagsOnDisk(), everyElement(isFalse),
        reason: 'the marker is not on disk');
    backend.afterApply = null;

    await repo.dispose();
    await h.restart();
    repo = newRepo();

    final out = await repo.syncEntry(id);
    expect(out, SyncOutcome.synced,
        reason: 'the replay must converge (not sync_conflict)');
    expect(backend.applied, 1, reason: 'a second server row/object would be a duplicate');
    expect(backend.docs, hasLength(1));
    final e = (await h.journal.read(id))!;
    expect(e.state.synced, isTrue);
    expect(e.state.syncState, isNot(JournalSyncState.syncConflict));
  });
}
