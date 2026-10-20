// S02-06a I26, I37, I13: permission-denied is never deletion; only a server
// tombstone deletes (delete wins); sync_conflict is retried at the next start
// only; the tombstone push survives a restart.
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/two_device_world.dart';

void main() {
  late World w;
  setUp(() async => w = await World.open());
  tearDown(() async => w.dispose());

  Future<Map<String, String>> files(Device d) => d.h.snapshot();

  group('I26 answers of the backend to a summary write', () {
    test('(1) denied AND tombstone present: delete wins, local data removed',
        () async {
      final id = await w.bothSynced();
      w.server.tombstones.add(id);
      expect(await w.b.change(id, movingTimeS: 1800), SyncOutcome.deletedLocal);
      expect(await w.b.h.journal.read(id), isNull);
      expect(await w.b.h.listIds(), isEmpty);
      expect((await w.b.h.journal.listTombstones()).map((e) => e.id), [id]);
      expect(w.b.backend.count('tombstoneExists'), 1,
          reason: 'the tombstone was read before choosing');
      final gens = await w.b.h.generations(id);
      expect(await w.b.h.exists(w.b.h.gen(id, gens.last, 'streams.bin')), isTrue);
      // a tombstone holds no streams
      final streams = await w.b.h.bytes(w.b.h.gen(id, gens.last, 'streams.bin'));
      expect(streams!.length, 0);
      // A re-import of the same id is refused with a typed reason, a NATIVE
      // recording with a new id is unaffected.
      await expectLater(w.b.repo.saveSession(baseSession(id)),
          throwsA(isA<JournalTombstonedException>()));
      expect(await w.b.repo.saveSession(baseSession(idFor(9))), SyncOutcome.synced);
    });

    test('(2) denied, no tombstone, same-field rev conflict: local data intact, '
        'sync_conflict, nothing deleted', () async {
      final id = await w.bothSynced();
      await w.a.change(id, distanceM: 5000);
      final before = await files(w.b);
      expect(await w.b.change(id, distanceM: 5200), SyncOutcome.conflict);
      expect(w.b.backend.count('tombstoneExists'), 1);
      expect(w.b.backend.count('readSummary'), greaterThanOrEqualTo(1));
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect(await w.b.h.listIds(), [id]);
      expect(await w.b.h.journal.listTombstones(), isEmpty);
      expect(before, isNotEmpty);
      expect((await w.b.session(id)).streams, isNotEmpty);
      expect((await w.b.entry(id)).streamLost, isFalse);
    });

    test('(3) startUtc clamp rejection: local data intact, sync_conflict', () async {
      final id = idFor(3);
      final far = ActivitySession(
        id: id,
        sport: SportType.running,
        startUtc: DateTime.utc(2200, 1, 1),
        endUtc: DateTime.utc(2200, 1, 1, 1),
        movingTimeS: 3000,
        summary: const ActivitySummary(distanceM: 9000),
      );
      expect(await w.b.repo.saveSession(far), SyncOutcome.conflict);
      expect(w.server.refused.single.reason, 'shape: clamp');
      expect(w.server.docs, isEmpty);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect((await w.b.session(id)).summary.distanceM, 9000);
      expect(await w.b.h.journal.listTombstones(), isEmpty);
    });

    test('(4) oversize batch of 9 is refused whole before any call; nothing '
        'is deleted or marked as conflict', () async {
      final ids = [for (var i = 1; i <= 9; i++) idFor(i)];
      for (final id in ids) {
        await w.b.h.journal.put(baseSession(id));
      }
      await expectLater(
          w.b.repo.syncBatch(ids), throwsA(isA<SummaryBatchTooLarge>()));
      expect(w.b.backend.calls, isEmpty);
      expect(w.server.accepted, isEmpty);
      for (final id in ids) {
        expect(await w.b.syncState(id), JournalSyncState.pending);
      }
      expect(await w.b.h.journal.listTombstones(), isEmpty);
      // the limit itself (8) is accepted
      final ok = await w.b.repo.syncBatch(ids.take(8).toList());
      expect(ok.values, everyElement(SyncOutcome.synced));
    });

    test('(5) an id in the owner-readable tombstone list is deleted on sync '
        'without any write attempt', () async {
      final id = await w.bothSynced();
      w.server.tombstones.add(id);
      final out = await w.b.repo.syncAll();
      expect(out[id], SyncOutcome.deletedLocal);
      expect(w.b.backend.count('writeSummary'), 0);
      expect(await w.b.h.listIds(), isEmpty);
    });

    test('an unreadable tombstone list never deletes', () async {
      final id = await w.bothSynced();
      w.server.tombstones.add(id);
      w.b.backend.offline = true;
      await w.b.repo.syncAll();
      expect(await w.b.h.listIds(), [id]);
    });
  });

  group('I37 sync_conflict is retried, never deleted', () {
    test('a failed single retry leaves sync_conflict with a surfaced state '
        'and intact files; the next start retries once and succeeds', () async {
      final id = await w.bothSynced();
      await w.a.change(id, ascentM: 31);
      w.b.backend.afterNextRead = () async {
        await w.a.change(id, distanceM: 5000);
        await w.a.change(id, avgSpeedMps: 3.0);
      };
      expect(await w.b.change(id, movingTimeS: 1800), SyncOutcome.conflict);
      expect(w.b.backend.count('writeSummary'), 2);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect((await w.b.session(id)).movingTimeS, 1800);
      expect((await w.b.session(id)).streams, isNotEmpty);
      expect((await w.b.repo.refreshState()).conflicts.map((c) => c.id), [id]);

      // no hot loop within the run: syncAll without retryConflicts is a no-op
      final w0 = w.b.backend.count('writeSummary');
      for (var i = 0; i < 12; i++) {
        w.b.h.clock.advance(const Duration(minutes: 5));
        await w.b.repo.syncAll();
      }
      expect(w.b.backend.count('writeSummary'), w0);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);

      await w.b.restart();
      final r0 = w.b.backend.count('readSummary');
      var out = await w.b.repo.syncAll(retryConflicts: true);
      expect(out[id], SyncOutcome.synced);
      expect(w.b.backend.count('readSummary'), greaterThan(r0));
      expect(w.server.docs[id]!['movingTimeS'], 1800);
      expect(w.server.docs[id]!['distanceM'], 5000);
    });

    test('a retry that finds a tombstone now deletes (case 1)', () async {
      final id = await w.bothSynced();
      await w.a.change(id, distanceM: 5000);
      await w.b.change(id, distanceM: 5200);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      w.server.tombstones.add(id);
      await w.b.restart();
      final out = await w.b.repo.syncAll(retryConflicts: true);
      expect(out[id], SyncOutcome.deletedLocal);
      expect(await w.b.h.listIds(), isEmpty);
    });

    test('a conflict retry happens once per process even with many passes',
        () async {
      final id = await w.bothSynced();
      await w.a.change(id, distanceM: 5000);
      await w.b.change(id, distanceM: 5200);
      await w.b.restart();
      await w.b.repo.syncAll(retryConflicts: true);
      final r = w.b.backend.count('readSummary');
      for (var i = 0; i < 10; i++) {
        w.b.h.clock.advance(const Duration(minutes: 6));
        await w.b.repo.syncAll(retryConflicts: true);
      }
      expect(w.b.backend.count('readSummary'), r);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
    });
  });

  group('I13 offline delete push survives a restart', () {
    test('a failed push keeps the local tombstone; a new repository on the '
        'same directory retries once and then stops', () async {
      final id = await w.bothSynced();
      final pushed = <String>[];
      var online = false;
      Future<void> push(String x, String? expectedUid) async {
        pushed.add(x);
        if (!online) throw const SummaryBackendUnavailable('offline');
        w.server.tombstones.add(x);
      }

      w.b.pusher = push;
      await w.b.restart();
      await w.b.h.journal.delete(id);
      expect(await w.b.h.listIds(), isEmpty, reason: 'not listed after delete');
      await w.b.repo.syncAll();
      expect(pushed, [id]);
      expect(w.server.tombstones, isEmpty);

      await w.b.restart(); // the queued delete is on disk, not in memory
      expect((await w.b.h.journal.listTombstones()).map((e) => e.id), [id]);
      online = true;
      await w.b.repo.syncAll();
      expect(pushed, [id, id]);
      expect(w.server.tombstones, {id});
      await w.b.repo.syncAll();
      expect(pushed, [id, id], reason: 'a tombstoned id is not pushed again');
      // the other device removes its copy
      expect((await w.a.repo.syncAll())[id], SyncOutcome.deletedLocal);
    });
  });
}
