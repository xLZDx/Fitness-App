// S02-12 I56: the explicit user edit (kind X) names its target fields, drops
// the override of those fields in the SAME generation and is reproduced from
// `explicitValues` alone after restart, replay and later edits (rows G20-G23,
// G22b, G39, G40 of plan 1.16).
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/two_device_world.dart';

void main() {
  late World w;
  setUp(() async => w = await World.open());
  tearDown(() async => w.dispose());

  Future<Map?> ov(Device d, String id) async =>
      (await d.overrides(id))['distanceM'] as Map?;
  Future<Map?> ex(Device d, String id) async =>
      (await d.explicit(id))['distanceM'] as Map?;

  test('an edit without target fields is rejected and changes nothing',
      () async {
    final id = await w.adopted();
    final gen = await w.b.generation(id);
    await expectLater(w.b.repo.applyExplicitEdit(id, {}), throwsArgumentError);
    await expectLater(
        w.b.repo.applyExplicitEdit(id, {'distanceM': -1}), throwsArgumentError);
    await expectLater(
        w.b.repo.applyExplicitEdit(id, {'sport': 1}), throwsArgumentError);
    expect(await w.b.generation(id), gen);
    expect(await ov(w.b, id), isNotNull);
  });

  test('(1) G20 edit to 4800 (= atComputed): override gone, entry stored, '
      'written once; A adopts; durable across restart and replay', () async {
    final id = await w.adopted();
    expect(await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800}),
        SyncOutcome.synced);
    expect(await ov(w.b, id), isNull);
    final e = (await ex(w.b, id))!;
    expect([e['value'], e['atDerived']], [4800, 4800]);
    expect(await w.b.rawOf(id, 'distanceM'), 4800);
    expect(w.server.docs[id]!['distanceM'], 4800);
    expect(((await w.b.sessionMap(id))['editHistory'] as List).single['field'],
        'distanceM');
    expect((await w.b.sessionMap(id))['userEditCount'], 1);
    expect(w.server.docs[id]!['userEditCount'], 1);
    // A adopts 4800 through its own override
    expect(await w.a.change(id, ascentM: 36), SyncOutcome.synced);
    expect(await w.a.effectiveOf(id, 'distanceM'), 4800);
    // restart: still 4800, no override reappears, zero writes
    final n = w.server.accepted.length;
    await w.b.restart();
    expect(await w.b.effectiveOf(id, 'distanceM'), 4800);
    expect(await ov(w.b, id), isNull);
    await w.b.repo.syncEntry(id);
    expect(w.server.accepted.length, n);
  });

  test('(1) lost-acknowledgement replay: the server holds 4800 and 5000 is '
      'never written after B\'s write', () async {
    final id = await w.adopted();
    w.b.backend.dropNextAck = true;
    expect(await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800}),
        SyncOutcome.unavailable);
    await w.b.restart();
    expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
    expect(w.server.docs[id]!['distanceM'], 4800);
    final i = w.server.accepted.lastIndexWhere((x) => x['distanceM'] == 4800);
    expect(w.server.accepted.skip(i).where((x) => x['distanceM'] == 5000), isEmpty);
    expect((await w.b.sessionMap(id))['userEditCount'], 1,
        reason: 'the replay does not count the edit twice');
  });

  test('(1 variant) A moved the server to 5200 meanwhile: sync_conflict naming '
      'distanceM, local 4800 intact, nothing written', () async {
    final id = await w.adopted();
    await w.a.change(id, ascentM: 31);
    await w.a.change(id, distanceM: 5200);
    final bw = w.server.writesBy('B').length;
    expect(await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800}),
        SyncOutcome.conflict);
    expect(w.server.writesBy('B').length, bw);
    expect(await w.b.effectiveOf(id, 'distanceM'), 4800);
    expect(await w.b.syncState(id), JournalSyncState.syncConflict);
    expect((await w.b.repo.refreshState()).conflicts.single.fields.single.field,
        'distanceM');
  });

  test('(2) G21 edit to 5000 (= value): override dropped, no write needed, '
      'converged; raw stays 4800 and the effective 5000 survives restart, '
      'replay and an independent edit', () async {
    final id = await w.adopted();
    final n = w.server.accepted.length;
    expect(await w.b.repo.applyExplicitEdit(id, {'distanceM': 5000}),
        SyncOutcome.synced);
    expect(w.server.accepted.length, n + 0 + (w.server.docs[id]!['userEditCount'] == 1 ? 1 : 0));
    expect(await ov(w.b, id), isNull);
    final e = (await ex(w.b, id))!;
    expect([e['value'], e['atDerived']], [5000, 4800]);
    expect(await w.b.rawOf(id, 'distanceM'), 4800);
    expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
    await w.b.restart();
    expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
    expect(await w.b.rawOf(id, 'distanceM'), 4800);
    expect(await w.b.repo.applyExplicitEdit(id, {'ascentM': 35}), SyncOutcome.synced);
    expect(await ov(w.b, id), isNull, reason: 'no cloud override is recreated');
    expect(w.server.docs[id]!['distanceM'], 5000);
    expect(w.server.writesWith('distanceM', 4800).where((x) => x.rev > 1), isEmpty);
  });

  group('(3) edit then revert before any sync', () {
    for (final c in [(4800.0, 5000.0), (5100.0, 4800.0)]) {
      test('${c.$1} then ${c.$2}', () async {
        final id = await w.adopted();
        w.b.backend.offline = true;
        await w.b.repo.applyExplicitEdit(id, {'distanceM': c.$1});
        expect(await ov(w.b, id), isNull, reason: 'gone after edit 1');
        await w.b.repo.applyExplicitEdit(id, {'distanceM': c.$2});
        expect(await ov(w.b, id), isNull, reason: 'not resurrected by edit 2');
        final sm = await w.b.sessionMap(id);
        final ring = (sm['editHistory'] as List).cast<Map>();
        expect([for (final r in ring) r['value']], [c.$1, c.$2]);
        expect(sm['userEditCount'], 2);
        final e = (await ex(w.b, id))!;
        expect([e['value'], e['seq']], [c.$2, 2]);
        expect((await w.b.explicit(id)).length, 1);
        await w.b.restart();
        expect(await w.b.effectiveOf(id, 'distanceM'), c.$2);
        w.b.backend.offline = false;
        expect(await w.b.repo.syncEntry(id), SyncOutcome.synced);
        expect(w.server.docs[id]!['distanceM'], c.$2,
            reason: 'the cloud value 5000 is not silently restored');
        await w.b.restart();
        expect(await w.b.effectiveOf(id, 'distanceM'), c.$2);
      });
    }
  });

  test('(4) G23 an edit of a DIFFERENT field keeps the distanceM override; the '
      'write carries 5000 and 1900, never 4800', () async {
    final id = await w.adopted();
    expect(await w.b.repo.applyExplicitEdit(id, {'movingTimeS': 1900}),
        SyncOutcome.synced);
    expect(await ov(w.b, id), isNotNull);
    expect(w.server.docs[id]!['movingTimeS'], 1900);
    expect(w.server.docs[id]!['distanceM'], 5000);
    expect(w.server.writesWith('distanceM', 4800).where((x) => x.rev > 1), isEmpty);
  });

  test('(5) an edit of two fields drops exactly those two overrides',
      () async {
    final id = await w.bothSynced();
    await w.a.change(id, distanceM: 5000);
    await w.a.change(id, ascentM: 31);
    await w.a.change(id, avgSpeedMps: 3.0);
    expect(await w.b.change(id, movingTimeS: 1800), SyncOutcome.synced);
    expect((await w.b.overrides(id)).keys,
        containsAll(['distanceM', 'ascentM', 'avgSpeedMps']));
    await w.b.repo.applyExplicitEdit(id, {'distanceM': 5050, 'ascentM': 32});
    expect((await w.b.overrides(id)).keys.toList()..sort(), ['avgSpeedMps']);
    expect(w.server.docs[id]!['distanceM'], 5050);
    expect(w.server.docs[id]!['ascentM'], 32);
    expect(w.server.docs[id]!['avgSpeedMps'], 3.0);
    expect((await w.b.sessionMap(id))['userEditCount'], 1,
        reason: 'one operation, one count');
  });

  group('(9) bounded history (G39, G40)', () {
    for (final n in [63, 64, 65, 100]) {
      for (final shape in ['same field', 'cycle']) {
        test('$n operations, $shape: counter and ring bounded, every summary '
            'accepted by the rules shape check, last value survives', () async {
          final id = await w.bothSynced();
          final fields = shape == 'same field'
              ? ['distanceM']
              : ['distanceM', 'movingTimeS', 'ascentM'];
          final last = <String, double>{};
          for (var i = 1; i <= n; i++) {
            final f = fields[i % fields.length];
            final v = 1000.0 + i; // every operation changes a value
            last[f] = v;
            final out = await w.b.repo.applyExplicitEdit(id, {f: v});
            expect(out, SyncOutcome.synced, reason: 'operation $i');
            if (i == 10 || i == 64 || i == 65) await w.b.restart();
          }
          expect(w.server.refused, isEmpty, reason: 'no summary was ever refused');
          final doc = w.server.docs[id]!;
          expect(doc['userEditCount'], n < 64 ? n : 64);
          for (final e in last.entries) {
            expect(doc[e.key], e.value, reason: e.key);
          }
          final sm = await w.b.sessionMap(id);
          expect(sm['userEditCount'], n < 64 ? n : 64);
          final ring = (sm['editHistory'] as List);
          expect(ring.length, n < 64 ? n : 64);
          if (n == 100) expect((ring.first as Map)['seq'], 37);
          expect((await w.b.explicit(id)).length, fields.length);
          await w.b.restart();
          for (final e in last.entries) {
            expect(await w.b.effectiveOf(id, e.key), e.value, reason: e.key);
          }
          expect(await w.b.syncState(id), JournalSyncState.synced);
          // the ring is device-only: A adopts every field through overrides
          expect(await w.a.change(id, avgSpeedMps: 3.3), SyncOutcome.synced);
          for (final e in last.entries) {
            expect(await w.a.effectiveOf(id, e.key), e.value, reason: 'A ${e.key}');
          }
        });
      }
    }
  });
}
