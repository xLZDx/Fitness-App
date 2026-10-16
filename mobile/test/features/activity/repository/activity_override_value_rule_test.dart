// S02-12 I50-I53: the VALUE-based override lifecycle (design 3.2 rule 2),
// driven by the literal rows G1-G16, G30-G33 of plan section 1.16 (the oracle
// of epic 1: test/support/golden_override_scenarios.dart is cross-checked for
// the rows it carries). Two devices, one rule-enforcing server.
import 'package:fitness_app/features/activity/data/activity_cloud_summary.dart';
import 'package:fitness_app/features/activity/data/summary_fields.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_override_scenarios.dart' as gold;
import '../../../support/journal_harness.dart';
import '../../../support/s02_fixtures.dart';
import '../../../support/two_device_world.dart';

void main() {
  late World w;
  setUp(() async => w = await World.open());
  tearDown(() async => w.dispose());

  /// The override of `distanceM` in record.json, as read from disk.
  Future<Map?> ov(Device d, String id) async =>
      (await d.overrides(id))['distanceM'] as Map?;

  Future<void> expectKept(Device d, String id, {List<String>? versions}) async {
    final o = (await ov(d, id))!;
    expect(o['value'], 5000, reason: 'value');
    expect(o['atComputed'], 4800, reason: 'atComputed');
    expect(o['atRev'], 2, reason: 'atRev');
    expect(o.containsKey('recalcCandidate'), isFalse);
    if (versions != null) {
      expect((o['atVersions'] as Map)['formulaVersion'], versions.first);
    }
    expect(await d.rawOf(id, 'distanceM'), 4800);
    expect(await d.effectiveOf(id, 'distanceM'), 5000);
  }

  /// No write after A's 5000 (rev 2) ever carries 4800.
  void noStaleWrite() {
    final i = w.server.accepted.indexWhere((x) => x['distanceM'] == 5000);
    expect(w.server.accepted.skip(i).where((x) => x['distanceM'] == 4800), isEmpty);
  }

  test('the literal oracle carries the rows this file drives', () {
    final ids = gold.kOverrideRows.map((r) => r.id).toSet();
    expect(ids, containsAll(['G1', 'G2', 'G9', 'G10', 'G11', 'G12', 'G13', 'G14', 'G17', 'G27']));
    final g10 = gold.kOverrideRows.firstWhere((r) => r.id == 'G10');
    expect([g10.kept, g10.written], [false, 5100]);
  });

  group('I50 metadata-only mutations preserve the override (G1-G6)', () {
    test('synced marker, base update, queue state, repeated synced, lost-ack '
        'replay: override unchanged on disk after every step and restart',
        () async {
      final id = await w.adopted();
      await expectKept(w.b, id, versions: gold.kV1);
      var gen = await w.b.generation(id);

      Future<void> step(String name, Future<void> Function() act) async {
        await act();
        await w.b.restart();
        final g = await w.b.generation(id);
        expect(g, greaterThan(gen), reason: '$name: the generation grew');
        gen = g;
        await expectKept(w.b, id, versions: gold.kV1);
        noStaleWrite();
      }

      await step('queue state (pending then upload_failed then retry)', () async {
        await w.b.h.journal.updateSyncState(id, JournalSyncState.uploadFailed);
        expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      });
      await step('repeated synced updates', () async {
        for (var i = 0; i < 3; i++) {
          await w.b.h.journal.updateSyncState(id, JournalSyncState.pending);
          await w.b.repo.syncEntry(id);
        }
      });
      await step('base update after a later sync of another field', () async {
        await w.a.change(id, ascentM: 31);
        expect(await w.b.change(id, avgSpeedMps: 3.1), SyncOutcome.synced);
      });
      await step('lost-acknowledgement replay', () async {
        w.b.backend.dropNextAck = true;
        expect(await w.b.change(id, ascentM: 45), SyncOutcome.unavailable);
        expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      });
      expect(w.server.docs[id]!['distanceM'], 5000);
      expect((await w.b.baseSummary(id))!['distanceM'], 5000);
    });
  });

  group('I51 passive input change under an unchanged triple (G10-G13, G15, G16)',
      () {
    test('G10: raw 4800 -> 5100: override gone on disk and after restart, '
        '5100 written, B synced', () async {
      final id = await w.adopted();
      expect(await w.b.change(id, distanceM: 5100, replaceStreams: true),
          SyncOutcome.synced);
      for (var i = 0; i < 2; i++) {
        expect(await ov(w.b, id), isNull);
        expect(await w.b.effectiveOf(id, 'distanceM'), 5100);
        await w.b.restart();
      }
      expect(w.server.docs[id]!['distanceM'], 5100);
      expect(await w.b.syncState(id), JournalSyncState.synced);
    });

    test('G11: A moved the server to 5200 -> sync_conflict, local '
        'byte-identical, no write from B', () async {
      final id = await w.adopted();
      await w.a.change(id, ascentM: 31);
      await w.a.change(id, distanceM: 5200);
      final bWrites = w.server.writesBy('B').length;
      expect(await w.b.change(id, distanceM: 5100), SyncOutcome.conflict);
      expect(w.server.writesBy('B').length, bWrites);
      expect(w.server.docs[id]!['distanceM'], 5200);
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
      expect(await ov(w.b, id), isNull);
      expect(await w.b.rawOf(id, 'distanceM'), 5100);
      final c = (await w.b.repo.refreshState()).conflicts.single;
      expect(c.fields.single.field, 'distanceM');
    });

    test('G12: A moved the server to 5100 -> no conflict, B synced', () async {
      final id = await w.adopted();
      await w.a.change(id, ascentM: 31);
      await w.a.change(id, distanceM: 5100);
      final out = await w.b.change(id, distanceM: 5100);
      expect(out, SyncOutcome.synced);
      expect(w.server.docs[id]!['distanceM'], 5100);
      expect(await w.b.syncState(id), JournalSyncState.synced);
    });

    test('G13/G15: equality drops it; re-edit back to 4800 is a local change, '
        'not pinned to 5000', () async {
      final id = await w.adopted();
      await w.b.change(id, distanceM: 5100);
      expect(await ov(w.b, id), isNull);
      expect(await w.b.change(id, distanceM: 4800), SyncOutcome.synced);
      expect(w.server.docs[id]!['distanceM'], 4800);
      expect(await ov(w.b, id), isNull);
    });

    test('G16: per-field independence: distanceM dropped, movingTimeS override '
        'kept; the write carries 5100 and 1800', () async {
      final id = await w.bothSynced();
      await w.a.change(id, distanceM: 5000);
      await w.a.change(id, movingTimeS: 1800);
      expect(await w.b.change(id, ascentM: 33), SyncOutcome.synced); // adopts both
      expect((await w.b.overrides(id)).keys, containsAll(['distanceM', 'movingTimeS']));
      expect(await w.b.change(id, distanceM: 5100), SyncOutcome.synced);
      expect(await ov(w.b, id), isNull);
      expect((await w.b.overrides(id))['movingTimeS'], isNotNull);
      expect(w.server.docs[id]!['distanceM'], 5100);
      expect(w.server.docs[id]!['movingTimeS'], 1800);
    });

    test('(g) explicit value: a passive raw change is NOT a drop and NOT '
        'written; atDerived moves and ONE sourceCandidate is recorded', () async {
      final id = await w.bothSynced();
      expect(await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800}),
          SyncOutcome.synced);
      await w.b.restart();
      final writes = w.server.accepted.length;
      expect(await w.b.change(id, distanceM: 5100, replaceStreams: true),
          SyncOutcome.synced);
      for (var i = 0; i < 2; i++) {
        final e = (await w.b.explicit(id))['distanceM'] as Map;
        expect(e['value'], 4800);
        expect(e['atDerived'], 5100);
        expect(e['sourceCandidate'], 5100);
        expect(await w.b.effectiveOf(id, 'distanceM'), 4800);
        await w.b.restart();
      }
      expect(w.server.accepted.length, writes, reason: '5100 is never written');
      expect(await w.b.syncState(id), JournalSyncState.synced);
      expect(w.b.states.expand((s) => s.conflicts), isEmpty);
    });

    test('(g2) concurrent cloud change: adopted through an override ABOVE the '
        'explicit value, candidate stays, no conflict', () async {
      final id = await w.bothSynced();
      await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
      await w.a.change(id, distanceM: 5400);
      expect(await w.b.change(id, distanceM: 5100, ascentM: 44), SyncOutcome.synced);
      final o = (await ov(w.b, id))!;
      expect(o['value'], 5400);
      expect(o['atComputed'], 4800);
      expect(((await w.b.explicit(id))['distanceM'] as Map)['sourceCandidate'], 5100);
      expect(w.server.docs[id]!['distanceM'], 5400);
      expect(w.server.writesWith('distanceM', 5100), isEmpty);
    });
  });

  group('I52 input changes that leave the value alone (G7-G9, G30-G32)', () {
    test('G7: a merge note keeps the override; mergeNoteCount is merged, '
        'no write of 4800', () async {
      final id = await w.adopted();
      expect(await w.b.change(id, mergeNotes: ['summaryDisagreement:distanceM']),
          SyncOutcome.synced);
      await w.b.restart();
      await expectKept(w.b, id);
      expect(w.server.docs[id]!['mergeNoteCount'], 1);
      expect(w.server.docs[id]!['distanceM'], 5000);
      noStaleWrite();
    });

    test('G8: provenance changed keeps it; sourceCount is merged', () async {
      final id = await w.adopted();
      final s = await w.b.session(id);
      expect(
          await w.b.repo.saveSession(s.copyWith(
              provenance: [...s.provenance, miniSource(sourceId: 'strava', externalId: 'z')])),
          SyncOutcome.synced);
      await expectKept(w.b, id);
      expect(w.server.docs[id]!['sourceCount'], 2);
      noStaleWrite();
    });

    test('G9: version bump V1 -> V2 with the value unchanged: atVersions = V2 '
        'in the committed record, no candidate, durable, idempotent', () async {
      final id = await w.adopted();
      w.b.versions = kV2;
      final gen0 = await w.b.generation(id);
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      await expectKept(w.b, id, versions: gold.kV2);
      expect(await w.b.generation(id), greaterThan(gen0));
      noStaleWrite();
      expect(w.server.docs[id]!['formulaVersion'], 'f2',
          reason: 'the version string is merged as a local change');
      await w.b.restart();
      final g1 = await w.b.generation(id);
      final writes = w.server.accepted.length;
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      expect(await w.b.generation(id), g1, reason: 'second load: no new generation');
      expect(w.server.accepted.length, writes);
      expect(((await ov(w.b, id))!['atVersions'] as Map)['formulaVersion'], 'f2');
    });

    test('G30: after the bump a PASSIVE change 5100 is kind P (override '
        'dropped, no candidate, 5100 merged), never the G27 outcome', () async {
      final id = await w.adopted();
      w.b.versions = kV2;
      await w.b.repo.syncEntry(id);
      await w.b.restart();
      expect(await w.b.change(id, distanceM: 5100, replaceStreams: true),
          SyncOutcome.synced);
      expect(await ov(w.b, id), isNull);
      expect((await w.b.explicit(id)), isEmpty);
      expect(w.server.docs[id]!['distanceM'], 5100);
    });

    test('G30 variant: A moved the server to 5200 -> sync_conflict naming '
        'distanceM, no write from B', () async {
      final id = await w.adopted();
      w.b.versions = kV2;
      await w.b.repo.syncEntry(id);
      await w.a.change(id, ascentM: 31);
      await w.a.change(id, distanceM: 5200);
      final bw = w.server.writesBy('B').length;
      expect(await w.b.change(id, distanceM: 5100), SyncOutcome.conflict);
      expect(w.server.writesBy('B').length, bw);
    });

    test('G31: lost acknowledgement of the reconciliation: after the retry the '
        'version is V2 and the outcome is unchanged', () async {
      final id = await w.adopted();
      w.b.versions = kV2;
      w.b.backend.dropNextAck = true; // the summary write carrying f2
      expect(await w.b.repo.syncEntry(id), SyncOutcome.unavailable);
      await w.b.restart();
      expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
      expect(((await ov(w.b, id))!['atVersions'] as Map)['formulaVersion'], 'f2');
      expect(w.server.docs[id]!['distanceM'], 5000);
      noStaleWrite();
    });
  });

  group('I53 after restart the recompute equals the server field by field', () {
    Future<void> equalsServer(Device d, String id) async {
      final s = await d.session(id);
      final eff = SummaryProjection.effective(s);
      final doc = w.server.docs[id]!;
      for (final k in kSummaryNumericBounds.keys) {
        final a = eff[k], b = doc[k];
        expect(a, b == null ? isNull : (b as num).toDouble(), reason: k);
      }
      final base = (await d.baseSummary(id))!;
      expect(base['rev'], doc['rev']);
      expect(ActivityCloudSummary.fromSession(s)['distanceM'], doc['distanceM']);
    }

    test('after the merge and every metadata mutation: equal, zero writes, no '
        'conflict, forced sync is a no-op', () async {
      final id = await w.adopted();
      await equalsServer(w.b, id);
      final writes = w.server.accepted.length;
      for (var i = 0; i < 3; i++) {
        await w.b.h.journal.updateSyncState(id, JournalSyncState.pending);
        await w.b.restart();
        expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
        await equalsServer(w.b, id);
      }
      expect(w.server.accepted.length, writes);
      expect(w.server.docs[id]!['rev'], 3);
      expect(w.b.states.expand((s) => s.conflicts), isEmpty);
      expect(await w.b.syncState(id), JournalSyncState.synced);
    });

    test('then new edits on both devices after the restart: everything '
        'survives, no conflict, no 4800', () async {
      final id = await w.adopted();
      await w.b.restart();
      await w.a.change(id, avgSpeedMps: 3.2);
      await w.b.change(id, ascentM: 42);
      final doc = w.server.docs[id]!;
      expect([doc['distanceM'], doc['movingTimeS'], doc['avgSpeedMps'], doc['ascentM']],
          [5000, 1800, 3.2, 42]);
      noStaleWrite();
      expect(await w.b.syncState(id), JournalSyncState.synced);
    });
  });
}
