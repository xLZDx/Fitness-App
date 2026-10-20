// S02-12 I43, I44: summary overrides converge across a restart and a second
// edit on both devices; a field the device cannot reproduce stays a
// resolvable sync_conflict (design 3.2 rules 1, 3, 4).
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
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

  bool noRollback(String id) {
    // After A's 5000 write (index of the first write with 5000) no accepted
    // write may carry 4800 again.
    final i = w.server.accepted.indexWhere((x) => x['distanceM'] == 5000);
    return w.server.accepted.skip(i).every((x) => x['distanceM'] != 4800);
  }

  group('I43 restart and a second edit on both devices', () {
    test('(1) restart: recompute still carries 5000 from record.json, zero '
        'further writes, no conflict', () async {
      final id = await w.adopted();
      final writes = w.server.accepted.length;
      await w.b.restart();
      final ov = (await w.b.overrides(id))['distanceM'] as Map; // from disk
      expect(ov.keys, containsAll(['value', 'atComputed', 'atVersions', 'atRev']));
      expect(await w.b.rawOf(id, 'distanceM'), 4800);
      expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      expect(w.server.accepted.length, writes);
      expect(await w.b.syncState(id), JournalSyncState.synced);
      expect(w.b.states.expand((s) => s.conflicts), isEmpty);
    });

    for (final aFirst in [true, false]) {
      test('(2) new edits on both devices (A avgSpeedMps, B ascentM), '
          '${aFirst ? "A first" : "B first"}: all four edits survive', () async {
        final id = await w.adopted();
        await w.b.restart();
        if (aFirst) {
          expect(await w.a.change(id, avgSpeedMps: 3.0), SyncOutcome.synced);
          expect(await w.b.change(id, ascentM: 40), SyncOutcome.synced);
        } else {
          expect(await w.b.change(id, ascentM: 40), SyncOutcome.synced);
          expect(await w.a.change(id, avgSpeedMps: 3.0), SyncOutcome.synced);
        }
        final doc = w.server.docs[id]!;
        expect(doc['distanceM'], 5000);
        expect(doc['movingTimeS'], 1800);
        expect(doc['avgSpeedMps'], 3.0);
        expect(doc['ascentM'], 40);
        // The device that merged last (the loser of the second round) holds
        // all four edits; each device holds its own edit.
        final merged = aFirst ? w.b : w.a;
        for (final e in {
          'distanceM': 5000.0,
          'movingTimeS': 1800.0,
          'avgSpeedMps': 3.0,
          'ascentM': 40.0,
        }.entries) {
          expect(await merged.effectiveOf(id, e.key), e.value, reason: e.key);
        }
        for (final d in [w.a, w.b]) {
          expect(await d.syncState(id), JournalSyncState.synced);
          expect(d.states.expand((s) => s.conflicts), isEmpty);
        }
        expect(await w.a.effectiveOf(id, 'avgSpeedMps'), 3.0);
        expect(await w.b.effectiveOf(id, 'ascentM'), 40);
        expect(noRollback(id), isTrue);
        // the loser of the second round was refused first (fake can fail)
        expect(w.server.refused.length, greaterThanOrEqualTo(2));
        // B's record.json still holds the override (value unchanged)
        expect(((await w.b.overrides(id))['distanceM'] as Map)['value'], 5000);
      });
    }

    test('(3) drop by equality: raw becomes 5000 -> override removed from '
        'disk, no write; later 5300 is written, not pinned back', () async {
      final id = await w.adopted();
      final writes = w.server.accepted.length;
      expect(await w.b.change(id, distanceM: 5000), SyncOutcome.synced);
      expect(await w.b.overrides(id), isEmpty);
      expect(w.server.accepted.length, writes);
      expect(await w.b.change(id, distanceM: 5300), SyncOutcome.synced);
      expect(w.server.docs[id]!['distanceM'], 5300);
    });

    test('(4) drop by a changed value: 5100 is a genuine local edit merged '
        'against baseSummary', () async {
      final id = await w.adopted();
      expect(await w.b.change(id, distanceM: 5100), SyncOutcome.synced);
      expect(await w.b.overrides(id), isEmpty);
      expect(w.server.docs[id]!['distanceM'], 5100);
    });

    test('(4b) the same, but A moved the server to 5200: sync_conflict, '
        'local intact, nothing written by B', () async {
      final id = await w.adopted();
      // A learns B's rev-3 write first (different field), then moves distance.
      await w.a.change(id, ascentM: 31);
      await w.a.change(id, distanceM: 5200);
      final bWrites = w.server.writesBy('B').length;
      expect(await w.b.change(id, distanceM: 5100), SyncOutcome.conflict);
      expect(w.server.writesBy('B').length, bWrites);
      expect(w.server.docs[id]!['distanceM'], 5200);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect(await w.b.rawOf(id, 'distanceM'), 5100);
    });
  });

  group('I44 a field the device cannot reproduce', () {
    ActivitySession noGps(String id) => baseSession(id).copyWith(
        summary: const ActivitySummary(
            ascentM: 30, descentM: 25, avgSpeedMps: 2.8));

    Future<String> setUp44() async {
      final id = idFor(1);
      await w.a.h.journal.put(baseSession(id, distanceM: 5000));
      await w.a.repo.syncEntry(id);
      await w.b.h.journal.put(noGps(id)); // B lacks the stream: no distance
      return id;
    }

    test('sync_conflict, not synced, B unchanged, no override, server '
        'untouched; retried once after a restart only', () async {
      final id = await setUp44();
      final before = await w.b.session(id);
      expect(await w.b.repo.syncEntry(id), SyncOutcome.conflict);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect((await w.b.entry(id)).state.synced, isFalse);
      expect(await w.b.overrides(id), isEmpty);
      expect(w.server.writesBy('B'), isEmpty);
      expect(w.server.docs[id]!['distanceM'], 5000);
      expect((await w.b.session(id)).summary.distanceM, before.summary.distanceM);
      final c = (await w.b.repo.refreshState()).conflicts.single;
      expect(c.fields.single.field, 'distanceM');
      expect(c.fields.single.deviceValue, isNull);
      expect(c.fields.single.cloudValue, 5000);
      await w.b.restart();
      final r0 = w.b.backend.count('readSummary');
      for (var i = 0; i < 12; i++) {
        w.b.h.clock.advance(const Duration(minutes: 5));
        await w.b.repo.syncAll(retryConflicts: true);
      }
      expect(w.b.backend.count('writeSummary'), 0);
      expect(w.b.backend.count('readSummary') - r0, lessThanOrEqualTo(2));
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
    });

    test('keep cloud stores the server value with an override, ends synced, '
        'and after a restart the value is unchanged with zero writes', () async {
      final id = await setUp44();
      await w.b.repo.syncEntry(id);
      expect(await w.b.repo.resolveConflict(id, ConflictChoice.keepCloud),
          SyncOutcome.synced);
      expect(w.server.writesBy('B'), isEmpty);
      final ov = (await w.b.overrides(id))['distanceM'] as Map;
      expect(ov['value'], 5000);
      await w.b.restart();
      expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      expect(w.server.writesBy('B'), isEmpty);
      expect(await w.b.syncState(id), JournalSyncState.synced);
    });

    test('keep this device writes the local value with the next rev and ends '
        'synced', () async {
      final id = await setUp44();
      await w.b.repo.syncEntry(id);
      expect(await w.b.repo.resolveConflict(id, ConflictChoice.keepDevice),
          SyncOutcome.synced);
      expect(w.server.docs[id]!.containsKey('distanceM'), isFalse);
      expect(w.server.docs[id]!['rev'], 2);
      expect(await w.b.syncState(id), JournalSyncState.synced);
    });

    test('control: a device that HAS the value adopts a server-only change '
        'without a conflict', () async {
      final id = await w.adopted();
      expect(await w.b.syncState(id), JournalSyncState.synced);
      expect((await w.b.overrides(id)).containsKey('distanceM'), isTrue);
    });
  });
}
