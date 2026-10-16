// S02-12 I57: automatic recalculation (`recalcCandidate`), explicit-value
// source candidates (`sourceCandidate`) and the ATOMIC resolution beneath a
// cloud override (rows G14, G17, G24-G29, G33-G46 of plan 1.16).
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

  /// B holds the override of I50 and upgrades to V2 with the recompute moving
  /// 4800 -> [raw] in the same mutation (kind R).
  Future<String> upgraded(double raw) async {
    final id = await w.adopted();
    w.b.versions = kV2;
    expect(await w.b.change(id, distanceM: raw), SyncOutcome.synced);
    return id;
  }

  group('recalcCandidate on the override path', () {
    test('(1) G14: override KEPT, atComputed/atVersions moved, candidate 4830, '
        '5000 stays written, no conflict', () async {
      final id = await upgraded(4830);
      final o = (await ov(w.b, id))!;
      expect(o['value'], 5000);
      expect(o['atComputed'], 4830);
      expect((o['atVersions'] as Map)['formulaVersion'], 'f2');
      expect(o['recalcCandidate'], 4830);
      expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
      expect(w.server.docs[id]!['distanceM'], 5000);
      expect(w.server.writesWith('distanceM', 4830), isEmpty);
      expect(w.server.writesWith('distanceM', 4800).where((x) => x.rev > 1), isEmpty);
      expect(await w.b.syncState(id), JournalSyncState.synced);
    });

    test('(2) G24: restart and a sync on both devices: zero writes, still ONE '
        'candidate, moved fields durable', () async {
      final id = await upgraded(4830);
      final writes = w.server.accepted.length;
      await w.b.restart();
      await w.b.repo.syncEntry(id);
      await w.a.repo.syncEntry(id);
      expect(w.server.accepted.length, writes);
      final o = (await ov(w.b, id))!;
      expect([o['atComputed'], o['recalcCandidate']], [4830, 4830]);
      final cands = (await w.b.repo.refreshState()).candidates;
      expect(cands, hasLength(1));
      expect(cands.single.reason, CandidateReason.recalculation);
      expect(cands.single.computedValue, 4830);
      expect(cands.single.cloudValue, 5000);
      expect(cands.single.choices,
          {CandidateChoice.useComputed, CandidateChoice.useCloud});
    });

    test('(3) G25/G26: a second upgrade and a downgrade only REFRESH the single '
        'candidate; 5000 is never overwritten', () async {
      final id = await upgraded(4830);
      final writes = w.server.writesWith('distanceM', 5000).length;
      w.b.versions = kV3;
      await w.b.change(id, distanceM: 4860);
      var o = (await ov(w.b, id))!;
      expect([o['recalcCandidate'], o['atComputed']], [4860, 4860]);
      expect((o['atVersions'] as Map)['formulaVersion'], 'f3');
      w.b.versions = kV1;
      await w.b.change(id, distanceM: 4800);
      o = (await ov(w.b, id))!;
      expect([o['recalcCandidate'], o['atComputed']], [4800, 4800]);
      expect((await w.b.repo.refreshState()).candidates, hasLength(1));
      expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
      expect(w.server.docs[id]!['distanceM'], 5000);
      expect(w.server.writesWith('distanceM', 5000).length, greaterThanOrEqualTo(writes));
      expect(w.server.accepted.where((x) => x.device == 'B' && x.rev > 3 && x['distanceM'] != 5000),
          isEmpty);
    });

    test('(4) G27: version AND input change in ONE mutation (raw 5100) is a '
        'recalculation: kept, candidate 5100, 5000 written', () async {
      final id = await upgraded(5100);
      final o = (await ov(w.b, id))!;
      expect([o['value'], o['atComputed'], o['recalcCandidate']], [5000, 5100, 5100]);
      expect(w.server.docs[id]!['distanceM'], 5000);
    });

    test('(5) G17: the server also changed to 5400: adopted through a NEW '
        'override, no conflict, candidate 4830 stays', () async {
      final id = await w.adopted();
      await w.a.change(id, ascentM: 31);
      await w.a.change(id, distanceM: 5400);
      w.b.versions = kV2;
      expect(await w.b.change(id, distanceM: 4830), SyncOutcome.synced);
      final o = (await ov(w.b, id))!;
      expect([o['value'], o['atComputed'], o['recalcCandidate']], [5400, 4830, 4830]);
      expect(w.server.docs[id]!['distanceM'], 5400);
      expect(w.b.states.expand((s) => s.conflicts), isEmpty);
    });

    test('(6) G28 use recalculated value: cleared + dropped in one generation, '
        '4830 written once, A converges; durable', () async {
      final id = await upgraded(4830);
      final gen = await w.b.generation(id);
      final out = await w.b.repo
          .resolveCandidate(id, 'distanceM', CandidateChoice.useComputed);
      expect(out, SyncOutcome.synced);
      expect(await ov(w.b, id), isNull);
      expect(w.server.docs[id]!['distanceM'], 4830);
      expect(w.server.writesWith('distanceM', 4830), hasLength(1));
      expect(await w.b.generation(id), greaterThan(gen));
      await w.b.restart();
      expect((await w.b.repo.refreshState()).candidates, isEmpty);
      expect(await w.b.effectiveOf(id, 'distanceM'), 4830);
      expect(await w.a.change(id, ascentM: 36), SyncOutcome.synced);
      expect(await w.a.effectiveOf(id, 'distanceM'), 4830);
      // idempotent: the same call again changes nothing
      final n = w.server.accepted.length;
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useComputed),
          SyncOutcome.alreadyResolved);
      expect(w.server.accepted.length, n);
    });

    test('(6b) A meanwhile moved the server to 5200: sync_conflict naming '
        'distanceM, nothing written, candidate already cleared', () async {
      final id = await upgraded(4830);
      await w.a.change(id, ascentM: 31);
      await w.a.change(id, distanceM: 5200);
      final bw = w.server.writesBy('B').length;
      final out = await w.b.repo
          .resolveCandidate(id, 'distanceM', CandidateChoice.useComputed);
      expect(out, SyncOutcome.conflict);
      expect(w.server.writesBy('B').length, bw);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect((await w.b.repo.refreshState()).candidates, isEmpty);
      expect((await w.b.repo.refreshState()).conflicts.single.fields.single.field,
          'distanceM');
    });

    test('(7) G29 keep cloud value: candidate cleared, override kept, zero '
        'writes; a LATER upgrade records a NEW candidate', () async {
      final id = await upgraded(4830);
      final n = w.server.accepted.length;
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useCloud),
          SyncOutcome.synced);
      expect(w.server.accepted.length, n);
      expect((await ov(w.b, id))!.containsKey('recalcCandidate'), isFalse);
      await w.b.restart();
      expect((await w.b.repo.refreshState()).candidates, isEmpty);
      expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
      w.b.versions = kV3;
      await w.b.change(id, distanceM: 4860);
      expect((await ov(w.b, id))!['recalcCandidate'], 4860);
    });

    test('a choice that is not offered is refused and changes nothing',
        () async {
      final id = await upgraded(4830);
      final gen = await w.b.generation(id);
      await expectLater(
          w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.keepMine),
          throwsArgumentError);
      expect(await w.b.generation(id), gen);
    });

    test('(13) an explicit edit of a field with a candidate drops the override '
        'AND clears the candidate', () async {
      final id = await upgraded(4830);
      await w.b.repo.applyExplicitEdit(id, {'distanceM': 4900});
      expect(await ov(w.b, id), isNull);
      expect((await w.b.repo.refreshState()).candidates, isEmpty);
      expect(await w.b.rawOf(id, 'distanceM'), 4830);
      expect(await w.b.effectiveOf(id, 'distanceM'), 4900);
      expect(w.server.docs[id]!['distanceM'], 4900);
    });
  });

  group('sourceCandidate under an explicit value', () {
    /// B explicit 4800 (server 4800, synced), restart, newer data raw 5100.
    Future<String> s33() async {
      final id = await w.bothSynced();
      await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
      await w.b.restart();
      expect(await w.b.change(id, distanceM: 5100, replaceStreams: true),
          SyncOutcome.synced);
      return id;
    }

    test('(14) G33 one candidate, nothing written, survives restart and syncs',
        () async {
      final id = await s33();
      final n = w.server.accepted.length;
      await w.b.restart();
      await w.b.repo.syncEntry(id);
      await w.a.repo.syncEntry(id);
      expect(w.server.accepted.length, n);
      final e = (await ex(w.b, id))!;
      expect([e['value'], e['atDerived'], e['sourceCandidate']], [4800, 5100, 5100]);
      final c = (await w.b.repo.refreshState()).candidates.single;
      expect(c.reason, CandidateReason.source);
      expect([c.explicitValue, c.computedValue, c.cloudValue], [4800, 5100, null]);
      expect(c.choices, {CandidateChoice.useComputed, CandidateChoice.keepMine});
    });

    test('(16) G35 use the new computed value: entry removed, 5100 merged and '
        'written once; A converges', () async {
      final id = await s33();
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useComputed),
          SyncOutcome.synced);
      expect(await ex(w.b, id), isNull);
      expect(w.server.docs[id]!['distanceM'], 5100);
      expect(w.server.writesWith('distanceM', 5100), hasLength(1));
      await w.b.restart();
      expect((await w.b.repo.refreshState()).candidates, isEmpty);
      expect(await w.a.change(id, ascentM: 36), SyncOutcome.synced);
      expect(await w.a.effectiveOf(id, 'distanceM'), 5100);
    });

    test('(16b) A moved the server to 5200 first: sync_conflict, nothing '
        'written', () async {
      final id = await s33();
      await w.a.change(id, distanceM: 5200);
      final bw = w.server.writesBy('B').length;
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useComputed),
          SyncOutcome.conflict);
      expect(w.server.writesBy('B').length, bw);
      expect(w.server.docs[id]!['distanceM'], 5200);
    });

    test('(17) G36 keep my value: candidate cleared, entry kept, zero writes; '
        'a LATER raw change records a NEW candidate', () async {
      final id = await s33();
      final n = w.server.accepted.length;
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.keepMine),
          SyncOutcome.synced);
      expect(w.server.accepted.length, n);
      final e = (await ex(w.b, id))!;
      expect([e['value'], e['atDerived']], [4800, 5100]);
      expect(e.containsKey('sourceCandidate'), isFalse);
      await w.b.restart();
      expect((await w.b.repo.refreshState()).candidates, isEmpty);
      await w.b.change(id, distanceM: 5300);
      expect(((await ex(w.b, id))!)['sourceCandidate'], 5300);
    });

    test('(18) G37 a calculation upgrade changing the raw value under an '
        'explicit value takes the same path (reason source)', () async {
      final id = await w.bothSynced();
      await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
      w.b.versions = kV2;
      await w.b.change(id, distanceM: 4830);
      final e = (await ex(w.b, id))!;
      expect([e['value'], e['atDerived'], e['sourceCandidate']], [4800, 4830, 4830]);
      expect(w.server.writesWith('distanceM', 4830), isEmpty);
    });

    test('(19) G38 explicit edit of a field with a candidate clears it and '
        'replaces the entry', () async {
      final id = await s33();
      await w.b.repo.applyExplicitEdit(id, {'distanceM': 4900});
      final e = (await ex(w.b, id))!;
      expect([e['value'], e['atDerived']], [4900, 5100]);
      expect(e.containsKey('sourceCandidate'), isFalse);
      expect(w.server.docs[id]!['distanceM'], 4900);
    });
  });

  group('(16a) G41-G46 atomic resolution beneath a cloud override', () {
    /// STATE S34: explicit 4800 (server 4800), restart, raw 5100 (candidate),
    /// A writes 5400, B adopts it through an override above the entry.
    Future<String> s34() async {
      final id = await w.bothSynced();
      await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
      await w.b.restart();
      await w.b.change(id, distanceM: 5100, replaceStreams: true);
      await w.a.change(id, distanceM: 5400);
      expect(await w.b.change(id, ascentM: 33), SyncOutcome.synced);
      final o = (await ov(w.b, id))!;
      expect([o['value'], o['atComputed'], o['atRev']], [5400, 4800, 3]);
      final e = (await ex(w.b, id))!;
      expect([e['value'], e['atDerived'], e['sourceCandidate']], [4800, 5100, 5100]);
      expect((await w.b.baseSummary(id))!['distanceM'], 5400);
      expect(await w.b.effectiveOf(id, 'distanceM'), 5400);
      final c = (await w.b.repo.refreshState()).candidates.single;
      expect(c.choices, {
        CandidateChoice.useComputed,
        CandidateChoice.keepMine,
        CandidateChoice.useCloud
      });
      return id;
    }

    test('(1) G41 use the new computed value: ONE generation removes entry, '
        'override and candidate; the write is 5100 against base 5400', () async {
      final id = await s34();
      final before = w.server.accepted.length;
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useComputed),
          SyncOutcome.synced);
      expect(await ex(w.b, id), isNull);
      expect(await ov(w.b, id), isNull);
      expect(w.server.accepted.length, before + 1);
      expect(w.server.accepted.last['distanceM'], 5100);
      expect(w.server.accepted.last.device, 'B');
      final i = w.server.accepted.indexWhere((x) => x['distanceM'] == 5400);
      expect(w.server.accepted.skip(i + 1).where((x) => x['distanceM'] == 4800), isEmpty);
      expect(await w.b.syncState(id), JournalSyncState.synced);
      expect((await w.b.baseSummary(id))!['distanceM'], 5100);
      // idempotent late delivery of the same resolution
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useComputed),
          SyncOutcome.alreadyResolved);
      expect(w.server.accepted.length, before + 1);
      await w.b.restart();
      expect(await ov(w.b, id), isNull, reason: 'a removed override never returns');
      expect(await w.a.change(id, avgSpeedMps: 3.5), SyncOutcome.synced);
      expect(await w.a.effectiveOf(id, 'distanceM'), 5100);
    });

    test('(2) G42 keep my value: entry kept, override removed, 4800 written '
        'once, 5400 is not restored', () async {
      final id = await s34();
      final before = w.server.accepted.length;
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.keepMine),
          SyncOutcome.synced);
      final e = (await ex(w.b, id))!;
      expect([e['value'], e['atDerived']], [4800, 5100]);
      expect(e.containsKey('sourceCandidate'), isFalse);
      expect(await ov(w.b, id), isNull);
      expect(w.server.accepted.length, before + 1);
      expect(w.server.accepted.last['distanceM'], 4800);
      await w.b.restart();
      expect(await w.b.effectiveOf(id, 'distanceM'), 4800);
      expect(await ov(w.b, id), isNull);
    });

    test('(3) G43 use the cloud value: entry removed, override kept with '
        'atComputed moved to the raw 5100, ZERO writes, survives restart',
        () async {
      final id = await s34();
      final before = w.server.accepted.length;
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useCloud),
          SyncOutcome.synced);
      expect(w.server.accepted.length, before);
      expect(await ex(w.b, id), isNull);
      final o = (await ov(w.b, id))!;
      expect([o['value'], o['atComputed']], [5400, 5100]);
      expect(o.containsKey('recalcCandidate'), isFalse);
      await w.b.restart();
      expect(await w.b.effectiveOf(id, 'distanceM'), 5400);
      expect(await ov(w.b, id), isNotNull);
      expect((await w.b.repo.refreshState()).candidates, isEmpty);
      expect(w.server.accepted.length, before);
    });

    test('(21) G44 the server changed AGAIN (5600): choices (1) and (2) '
        'preserve the local value in sync_conflict, write nothing; (3) adopts',
        () async {
      for (final choice in [CandidateChoice.useComputed, CandidateChoice.keepMine]) {
        final id = await s34();
        await w.a.change(id, avgSpeedMps: 3.4);
        await w.a.change(id, distanceM: 5600);
        expect(w.server.docs[id]!['distanceM'], 5600);
        final bw = w.server.writesBy('B').length;
        final out = await w.b.repo.resolveCandidate(id, 'distanceM', choice);
        expect(out, SyncOutcome.conflict, reason: '$choice');
        expect(w.server.writesBy('B').length, bw);
        expect(w.server.docs[id]!['distanceM'], 5600);
        expect(await ov(w.b, id), isNull, reason: 'the old 5400 override is not restored');
        expect(await w.b.syncState(id), JournalSyncState.syncConflict);
        expect((await w.b.baseSummary(id))!['distanceM'], 5400);
        expect(await w.b.rawOf(id, 'distanceM'), 5100);
        expect(await w.b.effectiveOf(id, 'distanceM'),
            choice == CandidateChoice.useComputed ? 5100 : 4800);
        await w.dispose();
        w = await World.open();
      }
    });

    test('(22) G45 order independence: resolve FIRST from the no-override '
        'state, then A writes 5400: ordinary three-way merge, no revived '
        'override', () async {
      final id = await w.bothSynced();
      await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
      await w.b.restart();
      await w.b.change(id, distanceM: 5100, replaceStreams: true);
      w.b.backend.offline = true; // resolve offline
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useComputed),
          SyncOutcome.unavailable);
      w.b.backend.offline = false;
      await w.a.change(id, distanceM: 5400);
      expect(await w.b.repo.syncEntry(id), SyncOutcome.conflict);
      expect(await ov(w.b, id), isNull);
      expect(await w.b.rawOf(id, 'distanceM'), 5100);
      expect(w.server.docs[id]!['distanceM'], 5400);
      expect(w.server.writesWith('distanceM', 5100), isEmpty);
    });

    test('(23)/(24) G46 restart after the resolution commit, and a dropped '
        'acknowledgement: exactly ONE B write of the chosen value', () async {
      final id = await s34();
      w.b.backend.dropNextAck = true;
      final before = w.server.accepted.length;
      expect(await w.b.repo.resolveCandidate(id, 'distanceM', CandidateChoice.useComputed),
          SyncOutcome.unavailable);
      expect(w.server.accepted.length, before + 1);
      // from record.json alone: the resolution is durable
      await w.b.restart();
      expect(await ex(w.b, id), isNull);
      expect(await ov(w.b, id), isNull);
      expect(await w.b.syncState(id), isNot(JournalSyncState.synced));
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      expect(w.server.accepted.length, before + 1, reason: 'exactly one B write');
      expect(w.server.docs[id]!['distanceM'], 5100);
      expect((await w.b.baseSummary(id))!['distanceM'], 5100);
      expect(await ov(w.b, id), isNull);
      // (25) a later independent edit carries the chosen value
      await w.b.repo.applyExplicitEdit(id, {'ascentM': 50});
      expect(w.server.docs[id]!['distanceM'], 5100);
      expect(w.server.docs[id]!['ascentM'], 50);
    });
  });
}
