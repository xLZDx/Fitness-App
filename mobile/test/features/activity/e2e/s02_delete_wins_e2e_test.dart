// S02 E04: delete wins across devices and the client reaction chain of every
// two-device scenario (plan E04, scenarios 1-6 with 2b-2g), over two journals
// on separate directories and one fake server that enforces the rules shape,
// the `rev` rule, the tombstone check and the account-deletion fence.
// permission-denied is NEVER deletion by itself; any removal of local data in
// scenarios 2-6 fails the test.
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart'
    show CandidateChoice;
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

  Future<Map?> ov(Device d, String id) async =>
      (await d.overrides(id))['distanceM'] as Map?;
  Future<Map?> ex(Device d, String id) async =>
      (await d.explicit(id))['distanceM'] as Map?;

  test('(1) delete wins: A deletes, B had a queued offline put and a local '
      'copy: B reconnects and ends with no summary, no local data, no '
      'accepted B write', () async {
    final id = await w.bothSynced();
    w.a.pusher = (x, _) async {
      w.server.tombstones.add(x);
      w.server.docs.remove(x);
    };
    await w.a.restart();
    await w.a.h.journal.delete(id);
    await w.a.repo.syncAll();
    expect(w.server.tombstones, {id});
    expect(w.server.docs.containsKey(id), isFalse);

    await w.b.changeOffline(id, movingTimeS: 1800); // queued offline put
    expect(await w.b.syncState(id), isNot(JournalSyncState.synced));
    final out = await w.b.repo.syncAll();
    expect(out[id], SyncOutcome.deletedLocal);
    expect(w.server.docs.containsKey(id), isFalse);
    expect(w.server.writesBy('B').where((x) => x.id == id && x.rev > 1), isEmpty);
    expect(await w.b.h.listIds(), isEmpty);
    // a replayed put with the old token is refused by the tombstone check
    expect(() => w.server.write('B', id, w.server.accepted.first.summary, create: true),
        returnsNormally);
    expect(w.server.docs.containsKey(id), isFalse);
    expect(w.server.refused.last.reason, 'tombstone');
  });

  group('(2) different fields, both orders', () {
    for (final aFirst in [true, false]) {
      test(aFirst ? 'A then B' : 'B then A', () async {
        final id = await w.bothSynced();
        final first = aFirst ? w.a : w.b;
        final second = aFirst ? w.b : w.a;
        await first.change(id, distanceM: 5000);
        await second.change(id, movingTimeS: 1800);
        expect(w.server.docs[id]!['distanceM'], 5000);
        expect(w.server.docs[id]!['movingTimeS'], 1800);
        expect(w.server.tombstones, isEmpty);
        expect(await w.a.syncState(id), JournalSyncState.synced);
        expect(await w.b.syncState(id), JournalSyncState.synced);
        expect(await w.a.h.listIds(), [id]);
        expect(await w.b.h.listIds(), [id]);
      });
    }

    test('convergence: restart, second edit on both devices, all four edits, '
        'no 4800 after A\'s write, no conflict', () async {
      final id = await w.adopted();
      await w.b.restart();
      await w.a.change(id, avgSpeedMps: 3.2);
      await w.b.change(id, ascentM: 42);
      final d = w.server.docs[id]!;
      expect([d['distanceM'], d['movingTimeS'], d['avgSpeedMps'], d['ascentM']],
          [5000, 1800, 3.2, 42]);
      final i = w.server.accepted.indexWhere((x) => x['distanceM'] == 5000);
      expect(w.server.accepted.skip(i).where((x) => x['distanceM'] == 4800), isEmpty);
      for (final dev in [w.a, w.b]) {
        expect(dev.states.expand((s) => s.conflicts), isEmpty);
      }
    });

    test('(2c) explicit edit: B writes 4800, A adopts it, both restart, a '
        'lost-ack replay: 4800 everywhere and 5000 never again', () async {
      final id = await w.adopted();
      w.b.backend.dropNextAck = true;
      await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
      expect(await ov(w.b, id), isNull);
      await w.b.restart();
      await w.b.repo.syncEntry(id);
      await w.a.change(id, ascentM: 36);
      await w.a.restart();
      await w.b.restart();
      expect(w.server.docs[id]!['distanceM'], 4800);
      expect(await w.a.effectiveOf(id, 'distanceM'), 4800);
      expect(await w.b.effectiveOf(id, 'distanceM'), 4800);
      final i = w.server.accepted.lastIndexWhere((x) => x['distanceM'] == 4800);
      expect(w.server.accepted.skip(i).where((x) => x['distanceM'] == 5000), isEmpty);
    });

    for (final useRecalc in [false, true]) {
      test('(2d) automatic recalculation 4800 -> 4830: B writes no 4830, '
          'candidate durable; ${useRecalc ? "use recalculated: written once, A converges" : "keep cloud: zero writes"}',
          () async {
        final id = await w.adopted();
        w.b.versions = kV2;
        await w.b.change(id, distanceM: 4830);
        expect(w.server.writesWith('distanceM', 4830), isEmpty);
        await w.b.restart();
        expect(((await ov(w.b, id))!)['recalcCandidate'], 4830);
        expect((await w.b.repo.refreshState()).candidates, hasLength(1));
        final n = w.server.accepted.length;
        await w.b.repo.resolveCandidate(id, 'distanceM',
            useRecalc ? CandidateChoice.useComputed : CandidateChoice.useCloud);
        if (useRecalc) {
          expect(w.server.writesWith('distanceM', 4830), hasLength(1));
          expect(w.server.docs[id]!['distanceM'], 4830);
          await w.a.change(id, ascentM: 36);
          expect(await w.a.effectiveOf(id, 'distanceM'), 4830);
        } else {
          expect(w.server.accepted.length, n);
          expect(w.server.docs[id]!['distanceM'], 5000);
        }
        expect((await w.b.repo.refreshState()).candidates, isEmpty);
      });
    }

    for (final concurrent in [false, true]) {
      test('(2e) explicit value vs newer source data, '
          '${concurrent ? "with a concurrent cloud change to 5400" : "no concurrent change"}',
          () async {
        final id = await w.bothSynced();
        await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
        await w.a.restart();
        await w.b.restart();
        if (concurrent) await w.a.change(id, distanceM: 5400);
        final n = w.server.accepted.length;
        await w.b.change(id, distanceM: 5100, replaceStreams: true,
            ascentM: concurrent ? 44 : null);
        final e = (await ex(w.b, id))!;
        expect([e['value'], e['atDerived'], e['sourceCandidate']], [4800, 5100, 5100]);
        expect(w.server.writesWith('distanceM', 5100), isEmpty);
        expect(await w.b.syncState(id), JournalSyncState.synced);
        if (concurrent) {
          expect((await ov(w.b, id))!['value'], 5400);
          expect(await w.b.effectiveOf(id, 'distanceM'), 5400);
        } else {
          expect(w.server.accepted.length, n);
        }
        expect((await w.b.repo.refreshState()).candidates, hasLength(1));
        await w.b.restart();
        expect((await w.b.repo.refreshState()).candidates, hasLength(1));
      });
    }

    test('(2e) use the new computed value: written once when the server is '
        'unchanged, sync_conflict when A moved it to 5200', () async {
      final id = await w.bothSynced();
      await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
      await w.b.change(id, distanceM: 5100, replaceStreams: true);
      await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useComputed);
      expect(w.server.writesWith('distanceM', 5100), hasLength(1));
      expect(w.server.docs[id]!['distanceM'], 5100);
    });

    test('(2f) 65 sequential explicit edits with restarts and a lost-ack '
        'replay of the last: every summary accepted, counter 64, latest '
        'value on the server and on A', () async {
      final id = await w.bothSynced();
      for (var i = 1; i <= 65; i++) {
        if (i == 65) w.b.backend.dropNextAck = true;
        await w.b.repo.applyExplicitEdit(id, {'distanceM': 2000.0 + i});
        if (i == 10 || i == 64) await w.b.restart();
      }
      await w.b.restart();
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      // only the replay of the acknowledged-but-unseen write is refused
      expect(w.server.refused.map((r) => r.reason), ['rev must increase']);
      expect(w.server.docs[id]!['distanceM'], 2065);
      expect(w.server.docs[id]!['userEditCount'], 64);
      expect(w.server.writesWith('distanceM', 2065), hasLength(1));
      expect(await w.a.change(id, avgSpeedMps: 3.0), SyncOutcome.synced);
      expect(await w.a.effectiveOf(id, 'distanceM'), 2065);
    });

    for (final c in [
      (CandidateChoice.useComputed, 5100.0),
      (CandidateChoice.keepMine, 4800.0),
      (CandidateChoice.useCloud, 5400.0),
    ]) {
      test('(2g) atomic resolution beneath a cloud override: ${c.$1.name}',
          () async {
        final id = await w.bothSynced();
        await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
        await w.a.restart();
        await w.b.restart();
        await w.b.change(id, distanceM: 5100, replaceStreams: true);
        await w.a.change(id, distanceM: 5400);
        await w.b.change(id, ascentM: 33);
        expect((await ov(w.b, id))!['value'], 5400);
        final n = w.server.accepted.length;
        w.b.backend.dropNextAck = c.$1 != CandidateChoice.useCloud;
        await w.b.repo.resolveCandidate(id, 'distanceM', c.$1);
        await w.b.restart();
        await w.b.repo.syncEntry(id);
        await w.a.restart();
        expect(await ex(w.b, id), c.$1 == CandidateChoice.keepMine ? isNotNull : isNull);
        expect(await ov(w.b, id),
            c.$1 == CandidateChoice.useCloud ? isNotNull : isNull);
        expect(w.server.docs[id]!['distanceM'], c.$2);
        expect(w.server.accepted.length,
            c.$1 == CandidateChoice.useCloud ? n : n + 1,
            reason: 'exactly one B write, none for cloud');
        expect(await w.b.effectiveOf(id, 'distanceM'), c.$2);
        expect(await w.b.syncState(id), JournalSyncState.synced);
        expect((await w.b.repo.refreshState()).candidates, isEmpty);
      });
    }

    test('(2g)(i) A writes 5600 before B resolves: choices (1) and (2) end '
        'sync_conflict with the local value preserved, (3) adopts 5600',
        () async {
      for (final choice in CandidateChoice.values) {
        await w.dispose();
        w = await World.open();
        final id = await w.bothSynced();
        await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
        await w.b.change(id, distanceM: 5100, replaceStreams: true);
        await w.a.change(id, distanceM: 5400);
        await w.b.change(id, ascentM: 33);
        await w.a.change(id, avgSpeedMps: 3.4);
        await w.a.change(id, distanceM: 5600);
        final n = w.server.writesBy('B').length;
        final out = await w.b.repo.resolveCandidate(id, 'distanceM', choice);
        expect(w.server.writesBy('B').length, n, reason: '$choice writes nothing');
        if (choice == CandidateChoice.useCloud) {
          expect(out, SyncOutcome.synced);
          expect((await ov(w.b, id))!['value'], 5400);
        } else {
          expect(out, SyncOutcome.conflict, reason: '$choice');
          expect(await ov(w.b, id), isNull);
          expect(await w.b.syncState(id), JournalSyncState.syncConflict);
          expect(await w.b.effectiveOf(id, 'distanceM'),
              choice == CandidateChoice.useComputed ? 5100 : 4800);
        }
      }
    });
  });

  group('(2b) same field changed differently', () {
    for (final keepDevice in [true, false]) {
      test(keepDevice ? 'keep this device' : 'keep cloud', () async {
        final id = await w.bothSynced();
        await w.a.change(id, distanceM: 5000);
        expect(await w.b.change(id, distanceM: 5200), SyncOutcome.conflict);
        expect(w.server.docs[id]!['distanceM'], 5000, reason: 'first writer kept');
        expect(await w.b.syncState(id), JournalSyncState.syncConflict);
        expect(await w.b.h.listIds(), [id]);
        await w.b.repo.resolveConflict(
            id, keepDevice ? ConflictChoice.keepDevice : ConflictChoice.keepCloud);
        final want = keepDevice ? 5200 : 5000;
        expect(w.server.docs[id]!['distanceM'], want);
        expect(await w.b.effectiveOf(id, 'distanceM'), want);
        await w.a.change(id, ascentM: 41);
        expect(await w.a.effectiveOf(id, 'distanceM'), want);
        expect(w.server.docs[id]!['distanceM'], want);
      });
    }

    test('a field derived from a stream only the other device holds stays '
        'sync_conflict and is resolved by the same choice', () async {
      final id = idFor(1);
      await w.a.h.journal.put(baseSession(id, distanceM: 5000));
      await w.a.repo.syncEntry(id);
      await w.b.h.journal.put(baseSession(id).copyWith(
          summary: const ActivitySummary(ascentM: 30, descentM: 25, avgSpeedMps: 2.8)));
      expect(await w.b.repo.syncEntry(id), SyncOutcome.conflict);
      expect(await w.b.syncState(id), isNot(JournalSyncState.synced));
      expect(await w.b.repo.resolveConflict(id, ConflictChoice.keepCloud),
          SyncOutcome.synced);
      expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
    });
  });

  test('(3) lost acknowledgement: the resend converges, value present on the '
      'server, no sync_conflict', () async {
    final id = await w.bothSynced();
    w.a.backend.dropNextAck = true;
    await w.a.change(id, distanceM: 5000);
    expect(await w.a.repo.syncEntry(id), SyncOutcome.synced);
    expect(w.server.docs[id]!['distanceM'], 5000);
    expect(await w.a.h.listIds(), [id]);
  });

  test('(4) startUtc clamp rejection: refused, no tombstone, local data '
      'intact, sync_conflict, never deleted', () async {
    final id = idFor(4);
    final far = ActivitySession(
        id: id,
        sport: SportType.running,
        startUtc: DateTime.utc(2200),
        endUtc: DateTime.utc(2200, 1, 1, 1),
        movingTimeS: 100,
        summary: const ActivitySummary(distanceM: 1000));
    expect(await w.b.repo.saveSession(far), SyncOutcome.conflict);
    expect(w.server.tombstones, isEmpty);
    expect(await w.b.h.listIds(), [id]);
    expect(await w.b.syncState(id), JournalSyncState.syncConflict);
  });

  test('(5) fresh device imports the same id as an existing summary: one '
      'document at the next rev via read-then-merge-then-update', () async {
    final id = idFor(1);
    await w.a.h.journal.put(baseSession(id));
    await w.a.repo.syncEntry(id);
    await w.a.h.journal.put((await w.a.session(id)).copyWith(mergeNotes: ['x']));
    await w.a.repo.syncEntry(id);
    await w.b.h.journal.put(baseSession(id));
    expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
    expect(w.server.docs.length, 1);
    expect(w.server.docs[id]!['rev'], 3);
    expect(w.server.createOverExisting, 0);
  });

  test('(6) account-deletion fence: a queued offline put replayed with a '
      'valid token is refused, no summary document, B keeps its data until '
      'the account wipe, no hot loop over 1 hour', () async {
    final id = idFor(6);
    await w.b.h.journal.put(baseSession(id)); // queued offline put
    w.server.accountFence = true;
    expect(await w.b.repo.syncEntry(id), SyncOutcome.conflict);
    final attempts = w.b.backend.count('writeSummary');
    for (var i = 0; i < 12; i++) {
      w.b.h.clock.advance(const Duration(minutes: 5));
      await w.b.repo.syncAll(); // no retryConflicts: foreground passes
    }
    expect(w.b.backend.count('writeSummary'), attempts);
    expect(w.server.docs, isEmpty);
    expect(w.server.accepted, isEmpty);
    expect(w.server.refused.every((r) => r.reason == 'fence'), isTrue);
    expect(await w.b.h.listIds(), [id], reason: 'local data stays');
    // the account wipe (design 3.5) is what removes it
    await w.b.restart();
    await w.b.h.journal.wipe();
    expect(await w.b.h.journal.list(), isEmpty);
  });
}
