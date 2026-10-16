// S02 remediation B1 (epic 9a, coordinator addition): after SF3, journal.read()
// can throw JournalIoException on a local I/O error. Every caller must treat
// that as retryable for THAT entry only: no crash, no aborted pass, and no
// state change to synced / lost / conflict.
//
// Callers covered: ActivitySyncRepository (syncAll, syncEntry, saveSession),
// the resolution API (resolveConflict, resolveCandidate, applyExplicitEdit),
// ActivityStreamUploader (uploadEntry, runPending) and JournalActivityLocalExport.
import 'package:fitness_app/features/activity/data/summary_projection.dart';
import 'package:fitness_app/features/activity/repository/activity_local_export.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/stream_upload_world.dart';

bool Function(String) recordOf(String id) =>
    (p) => p.contains('/$id/') && p.endsWith('/record.json');

void main() {
  late StreamUploadWorld w;
  late ActivitySyncRepository repo;
  final a = idFor(1), b = idFor(2), c = idFor(3);

  setUp(() async {
    w = await StreamUploadWorld.open();
    repo = ActivitySyncRepository(
        journal: w.h.journal, backend: w.backend, clock: w.h.clock.call);
  });

  tearDown(() async {
    await repo.dispose();
    await w.dispose();
  });

  Future<void> putAll() async {
    await w.h.journal.put(journalSession(a, seed: 1));
    await w.h.journal.put(journalSession(b, seed: 2));
    await w.h.journal.put(journalSession(c, seed: 3));
  }

  void failRead(String id) => w.h.fs.failReadWhen = recordOf(id);
  void healRead() => w.h.fs.failReadWhen = null;

  group('sync pass', () {
    test('syncAll keeps going; the unreadable entry is retryable, not lost',
        () async {
      await putAll();
      failRead(b);
      final out = await repo.syncAll();
      expect(out[a], SyncOutcome.synced);
      expect(out[c], SyncOutcome.synced);
      expect(out[b], SyncOutcome.pending,
          reason: 'not synced, not conflict, not notFound');
      expect(w.backend.applied, 2, reason: 'only the readable entries uploaded');

      healRead();
      final e = (await w.h.journal.read(b))!;
      expect(e.state.syncState, JournalSyncState.pending,
          reason: 'state untouched by the failed read');
      expect(e.state.streamLost, isFalse);
      expect(await w.h.journal.list(), hasLength(3), reason: 'entry not dropped');

      final again = await repo.syncAll();
      expect(again[b], SyncOutcome.synced, reason: 'the next pass retries it');
      expect(w.backend.applied, 3);
    });

    test('syncEntry returns pending instead of throwing', () async {
      await putAll();
      failRead(a);
      expect(await repo.syncEntry(a), SyncOutcome.pending);
      expect(w.backend.applied, 0);
      healRead();
      expect(await repo.syncEntry(a), SyncOutcome.synced);
    });

    test('saveSession does not overwrite an unreadable entry', () async {
      await putAll();
      healRead();
      final before = (await w.h.journal.read(a))!.generation;
      failRead(a);
      expect(await repo.saveSession(journalSession(a, seed: 9)),
          SyncOutcome.pending);
      healRead();
      final e = (await w.h.journal.read(a))!;
      expect(e.generation, before, reason: 'nothing was written');
      expect(e.session.startUtc, journalSession(a, seed: 1).startUtc);
    });
  });

  group('resolution', () {
    test('resolveConflict / resolveCandidate / applyExplicitEdit are retryable',
        () async {
      await putAll();
      final before = (await w.h.journal.read(a))!.generation;
      failRead(a);
      expect(await repo.resolveConflict(a, ConflictChoice.keepCloud),
          SyncOutcome.pending);
      expect(await repo.resolveCandidate(a, 'distanceM', CandidateChoice.keepMine),
          SyncOutcome.pending);
      expect(await repo.applyExplicitEdit(a, {'distanceM': 5000.0}),
          SyncOutcome.pending);
      healRead();
      final e = (await w.h.journal.read(a))!;
      expect(e.generation, before, reason: 'no generation written');
      expect(e.state.syncState, JournalSyncState.pending);
    });
  });

  group('stream uploader', () {
    Future<void> seedSynced(String id, int seed) async {
      await w.h.journal.put(journalSession(id, seed: seed));
      await w.summarySync();
    }

    test('uploadEntry fails retryably; runPending completes; entry stays pending',
        () async {
      await seedSynced(a, 1);
      await seedSynced(b, 2);
      expect((await w.h.journal.read(a))!.state.streamUploadPending, isTrue);
      failRead(a);
      expect(await w.uploader.uploadEntry(a), StreamUploadOutcome.failed);
      expect(w.cloud.creates, isEmpty, reason: 'no network step for it');
      await w.uploader.runPending(); // must not throw; b still uploads
      expect(w.cloud.stored.keys, contains(b));
      expect(w.cloud.stored.keys, isNot(contains(a)));

      healRead();
      expect((await w.h.journal.read(a))!.state.streamUploadPending, isTrue,
          reason: 'still pending for retry');
      expect(await w.uploader.uploadEntry(a), StreamUploadOutcome.uploaded);
    });
  });

  group('local export', () {
    test('exportActivity returns a typed result; exportAll keeps the others',
        () async {
      await putAll();
      failRead(b);
      final export = JournalActivityLocalExport(w.h.journal);
      final one = await export.exportActivity(b, ActivityExportFormat.json);
      expect(one, isA<ActivityExportUnavailable>());
      expect(one.activityId, b);

      final all = await export.exportAll(ActivityExportFormat.json);
      expect(all, hasLength(3));
      expect(all.whereType<ActivityExportFile>(), hasLength(2));
      expect(all.whereType<ActivityExportUnavailable>().single.activityId, b);

      healRead();
      expect(await export.exportActivity(b, ActivityExportFormat.json),
          isA<ActivityExportFile>());
    });
  });
}
