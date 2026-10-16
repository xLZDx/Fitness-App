// S02-12 I31, I32, I33, I38, I39: two devices, one fake server that enforces the
// rules `rev` rule. Final VALUES are asserted on the server document and on
// both journals, never only `rev`; the loser of every race is shown to be
// REFUSED first (control) so convergence cannot pass trivially.
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/two_device_world.dart';

void main() {
  late World w;
  setUp(() async => w = await World.open());
  tearDown(() async => w.dispose());

  Future<void> bothDocsEqual(String id, String field, num v) async {
    expect((w.server.docs[id]![field] as num).toDouble(), v.toDouble());
  }

  group('I31 different fields converge, both orders', () {
    for (final aFirst in [true, false]) {
      test(aFirst ? 'A (distanceM) first, then B (movingTimeS)'
          : 'B (movingTimeS) first, then A (distanceM)', () async {
        final id = await w.bothSynced();
        if (aFirst) {
          expect(await w.a.change(id, distanceM: 5000), SyncOutcome.synced);
          expect(await w.b.change(id, movingTimeS: 1800), SyncOutcome.synced);
        } else {
          expect(await w.b.change(id, movingTimeS: 1800), SyncOutcome.synced);
          expect(await w.a.change(id, distanceM: 5000), SyncOutcome.synced);
        }
        // Control: the loser WAS refused by the rules gate.
        expect(w.server.refused.where((r) => r.reason == 'rev must increase'), hasLength(1));
        final loser = aFirst ? 'B' : 'A';
        expect(w.server.refused.single.device, loser);
        // Neither edit is lost (a last-writer-wins client fails here).
        await bothDocsEqual(id, 'distanceM', 5000);
        await bothDocsEqual(id, 'movingTimeS', 1800);
        expect(w.server.docs[id]!['rev'], 3);
        expect(w.server.docs.length, 1);
        final loserDev = aFirst ? w.b : w.a;
        final winnerDev = aFirst ? w.a : w.b;
        expect(await loserDev.syncState(id), JournalSyncState.synced);
        expect(await winnerDev.syncState(id), JournalSyncState.synced);
        final base = (await loserDev.baseSummary(id))!;
        expect(base['distanceM'], 5000);
        expect(base['movingTimeS'], 1800);
        expect(await loserDev.baseRev(id), 3);
        expect(await loserDev.effectiveOf(id, 'distanceM'), 5000);
        expect(await loserDev.effectiveOf(id, 'movingTimeS'), 1800);
      });
    }

    test('control: a single device edit writes N+1 with no read', () async {
      final id = await w.bothSynced();
      final reads = w.a.backend.count('readSummary');
      await w.a.change(id, distanceM: 5000);
      expect(w.a.backend.count('readSummary'), reads);
      expect(w.server.docs[id]!['rev'], 2);
      expect(w.server.refused, isEmpty);
    });

    test('adopted value is an override in record.json, survives restart, no '
        'further write, no conflict', () async {
      final id = await w.adopted();
      final ov = (await w.b.overrides(id))['distanceM'] as Map;
      expect(ov['value'], 5000);
      expect(ov['atComputed'], 4800);
      expect(ov['atRev'], 2);
      expect((ov['atVersions'] as Map)['formulaVersion'], 'f1');
      final writes = w.server.accepted.length;
      await w.b.restart();
      expect(await w.b.rawOf(id, 'distanceM'), 4800);
      expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      expect(w.server.accepted.length, writes);
      expect(await w.b.syncState(id), JournalSyncState.synced);
      expect(w.b.states.any((s) => s.conflicts.isNotEmpty), isFalse);
    });

    test('retries are capped: a second refusal in the same pass leaves '
        'sync_conflict, never synced', () async {
      final id = await w.bothSynced();
      // A writes between B's read and B's retried write.
      w.b.backend.afterNextRead = () async {
        await w.a.change(id, distanceM: 5000);
        await w.a.change(id, avgSpeedMps: 3.0);
      };
      await w.a.change(id, ascentM: 31); // server rev 2 so B's first write is refused
      final out = await w.b.change(id, movingTimeS: 1800);
      expect(out, SyncOutcome.conflict);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect(w.b.backend.count('writeSummary'), 2, reason: 'one retry only');
    });
  });

  group('I32 lost acknowledgement', () {
    test('the same rev is resent: refused, read, equal -> synced with no '
        'second accepted write', () async {
      final id = await w.bothSynced();
      w.a.backend.dropNextAck = true;
      expect(await w.a.change(id, distanceM: 5000), SyncOutcome.unavailable);
      expect(w.server.docs[id]!['distanceM'], 5000);
      final accepted = w.server.accepted.length;
      expect(await w.a.repo.syncEntry(id), SyncOutcome.synced);
      expect(w.server.accepted.length, accepted, reason: 'at most the one write');
      expect(w.server.refused.single.reason, 'rev must increase');
      expect(w.server.docs.length, 1);
      expect(await w.a.syncState(id), JournalSyncState.synced);
      expect((await w.a.baseSummary(id))!['distanceM'], 5000);
    });

    test('another device changed a different field in between: both values '
        'kept, replay after a restart behaves the same', () async {
      final id = await w.bothSynced();
      w.a.backend.dropNextAck = true;
      await w.a.change(id, distanceM: 5000);
      expect(await w.b.change(id, ascentM: 40), SyncOutcome.synced);
      await w.a.restart();
      expect(await w.a.repo.syncEntry(id), SyncOutcome.synced);
      await bothDocsEqual(id, 'distanceM', 5000);
      await bothDocsEqual(id, 'ascentM', 40);
      expect(await w.a.syncState(id), JournalSyncState.synced);
      expect(w.server.accepted.where((x) => x['distanceM'] == 4800 && x.rev > 1), isEmpty);
    });
  });

  group('I33 fresh device over an existing id', () {
    test('reads first and sends an UPDATE at max(1, 3) + 1 = 4', () async {
      final id = idFor(1);
      await w.a.h.journal.put(baseSession(id));
      await w.a.repo.syncEntry(id);
      await w.a.h.journal.put((await w.a.session(id)).copyWith(mergeNotes: ['a']));
      await w.a.repo.syncEntry(id);
      await w.a.h.journal.put((await w.a.session(id)).copyWith(mergeNotes: ['a', 'b']));
      await w.a.repo.syncEntry(id);
      expect(w.server.docs[id]!['rev'], 3);
      final start = w.server.docs[id]!['startUtc'];

      await w.b.h.journal.put(baseSession(id)); // same import, fresh journal
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      expect(w.server.createOverExisting, 0);
      expect(w.server.refused, isEmpty);
      expect(w.server.docs[id]!['rev'], 4);
      expect(w.server.docs[id]!['startUtc'], start);
      expect(w.server.docs[id]!['sport'], 'running');
      expect(w.server.accepted.last.create, isFalse);
      expect(await w.b.syncState(id), JournalSyncState.synced);
    });

    test('control: no server summary -> create with rev 1', () async {
      final id = idFor(2);
      await w.b.h.journal.put(baseSession(id));
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      expect(w.server.accepted.single.create, isTrue);
      expect(w.server.accepted.single.rev, 1);
    });
  });

  group('I38 same field changed differently stays sync_conflict', () {
    for (final aFirst in [true, false]) {
      test(aFirst ? 'A 5000 first, B 5200 second' : 'B 5200 first, A 5000 second',
          () async {
        final id = await w.bothSynced();
        final first = aFirst ? w.a : w.b;
        final second = aFirst ? w.b : w.a;
        await first.change(id, distanceM: aFirst ? 5000 : 5200);
        final writesBefore = w.server.accepted.length;
        final out = await second.change(id, distanceM: aFirst ? 5200 : 5000);
        expect(out, SyncOutcome.conflict);
        // Control: the loser was refused, and nothing of it was accepted.
        expect(w.server.refused.single.device, second.name);
        expect(w.server.accepted.length, writesBefore);
        expect(w.server.docs[id]!['distanceM'], aFirst ? 5000 : 5200);
        // Local data untouched, marker absent in the record and the entry.
        expect(await second.rawOf(id, 'distanceM'), aFirst ? 5200 : 5000);
        final rec = await second.record(id);
        expect((rec['state'] as Map)['synced'], false);
        expect((rec['state'] as Map)['syncState'], 'sync_conflict');
        expect((await second.entry(id)).state.synced, isFalse);
        expect(await second.overrides(id), isEmpty);
        // The state stream surfaces both values.
        await second.repo.refreshState();
        final c = (await second.repo.refreshState()).conflicts.single;
        expect(c.id, id);
        final f = c.fields.single;
        expect(f.field, 'distanceM');
        expect(f.deviceValue, aFirst ? 5200 : 5000);
        expect(f.cloudValue, aFirst ? 5000 : 5200);
      });
    }

    test('restart retries ONCE and still ends sync_conflict; no hot loop over '
        '1 hour of fake time', () async {
      final id = await w.bothSynced();
      await w.a.change(id, distanceM: 5000);
      await w.b.change(id, distanceM: 5200);
      await w.b.restart();
      final w0 = w.b.backend.count('writeSummary');
      await w.b.repo.syncAll(retryConflicts: true); // the one retry
      final r1 = w.b.backend.count('readSummary');
      for (var i = 0; i < 12; i++) {
        w.b.h.clock.advance(const Duration(minutes: 5));
        await w.b.repo.syncAll(retryConflicts: true);
      }
      expect(w.b.backend.count('readSummary'), r1, reason: 'no hot loop');
      expect(w.b.backend.count('writeSummary'), w0);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect(await w.b.rawOf(id, 'distanceM'), 5200);
    });

    test('control: a second field changed on one side only merges', () async {
      final id = await w.bothSynced();
      await w.a.change(id, distanceM: 5000);
      expect(await w.b.change(id, ascentM: 44), SyncOutcome.synced);
      await bothDocsEqual(id, 'distanceM', 5000);
      await bothDocsEqual(id, 'ascentM', 44);
    });
  });

  group('I39 the user choice converges', () {
    Future<String> conflict() async {
      final id = await w.bothSynced();
      await w.a.change(id, distanceM: 5000);
      await w.b.change(id, distanceM: 5200);
      return id;
    }

    test('keep this device: server, B and (after its next sync) A hold 5200',
        () async {
      final id = await conflict();
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect(await w.b.repo.resolveConflict(id, ConflictChoice.keepDevice),
          SyncOutcome.synced);
      await bothDocsEqual(id, 'distanceM', 5200);
      expect(w.server.docs[id]!['rev'], 3);
      expect(await w.b.syncState(id), JournalSyncState.synced);
      expect(await w.b.overrides(id), isEmpty);
      expect((await w.b.baseSummary(id))!['distanceM'], 5200);
      // A changes another field: takes the server-only 5200.
      expect(await w.a.change(id, ascentM: 41), SyncOutcome.synced);
      expect(await w.a.effectiveOf(id, 'distanceM'), 5200);
      await bothDocsEqual(id, 'distanceM', 5200);
      expect((await w.a.baseSummary(id))!['distanceM'], 5200);
      // Repeated choice is idempotent: nothing more is written.
      final n = w.server.accepted.length;
      expect(await w.b.repo.resolveConflict(id, ConflictChoice.keepDevice),
          SyncOutcome.alreadyResolved);
      expect(w.server.accepted.length, n);
    });

    test('keep cloud: B takes 5000 through an override, writes nothing, ends '
        'synced; restart keeps it with zero writes', () async {
      final id = await conflict();
      final streamsBefore = streamsOf(await w.b.session(id));
      final writes = w.server.accepted.length;
      expect(await w.b.repo.resolveConflict(id, ConflictChoice.keepCloud),
          SyncOutcome.synced);
      expect(w.server.accepted.length, writes, reason: 'no spurious rev bump');
      expect(w.server.docs[id]!['rev'], 2);
      final ov = (await w.b.overrides(id))['distanceM'] as Map;
      expect(ov['value'], 5000);
      expect(ov['atComputed'], 5200);
      expect(await w.b.syncState(id), JournalSyncState.synced);
      expect(streamsOf(await w.b.session(id)), streamsBefore);
      await w.b.restart();
      expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
      expect(await w.b.rawOf(id, 'distanceM'), 5200);
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      expect(w.server.accepted.length, writes);
      expect(w.b.states.last.conflicts, isEmpty);
    });

    test('nothing is synced before the choice is stored: offline choice '
        'leaves sync_conflict with data intact, the retry succeeds', () async {
      final id = await conflict();
      w.b.backend.offline = true;
      expect(await w.b.repo.resolveConflict(id, ConflictChoice.keepDevice),
          SyncOutcome.unavailable);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect(await w.b.rawOf(id, 'distanceM'), 5200);
      await w.b.restart();
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      w.b.backend.offline = false;
      expect(await w.b.repo.resolveConflict(id, ConflictChoice.keepDevice),
          SyncOutcome.synced);
      await bothDocsEqual(id, 'distanceM', 5200);
    });
  });
}
