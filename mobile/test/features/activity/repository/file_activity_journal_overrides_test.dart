// S02-02 I45: summaryOverrides, explicitValues, the edit ring, the counter and
// candidates live in record.json of the committed generation and survive a
// restart and an index rebuild.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/activity_versions.dart';
import 'package:fitness_app/features/activity/data/summary_overrides.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';

const kV1 = CalcVersions(
    formulaVersion: 'f1', metricDefinitionVersion: 'm1', thresholdPolicyVersion: 't1');
const kV2 = CalcVersions(
    formulaVersion: 'f2', metricDefinitionVersion: 'm1', thresholdPolicyVersion: 't1');

SummaryOverride ov(double value, double atComputed, CalcVersions v, int rev) =>
    SummaryOverride(value: value, atComputed: atComputed, atVersions: v, atRev: rev);

String stateJson(ActivitySession s) => jsonEncode({
      'ex': encodeSorted<ExplicitValue>(s.explicitValues, (e) => e.toJson()),
      'ov': encodeSorted<SummaryOverride>(s.summaryOverrides, (e) => e.toJson()),
      'ring': [for (final e in s.editHistory) e.toJson()],
      'count': s.userEditCount,
    });

void main() {
  late JournalHarness h;
  final id = idFor(1);

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
  });

  tearDown(() => h.dispose());

  Future<Map<String, dynamic>> sessionOnDisk(int seq) async =>
      (await h.recordJson(id, seq))['session'] as Map<String, dynamic>;

  Future<ActivitySession> reload() async {
    await h.restart();
    return (await h.journal.read(id))!.session;
  }

  Future<ActivitySession> afterIndexRebuild() async {
    await h.deleteRawFile('journal/index.jsonl');
    await h.restart();
    return (await h.journal.read(id))!.session;
  }

  test('two overrides are in the record.json of the COMMITTED generation with '
      'value, atComputed, atVersions (3 strings) and atRev; a new repository '
      'and an index rebuild return them deep-equal', () async {
    final s = journalSession(id).copyWith(summaryOverrides: {
      'distanceM': ov(5000, 4800, kV1, 8),
      'movingTimeS': ov(1800, 1700, kV1, 8),
    });
    final e = await h.journal.put(s);
    expect(await h.exists(h.gen(id, e.generation, 'COMMIT')), isTrue);
    final raw = (await sessionOnDisk(e.generation))['summaryOverrides'] as Map;
    expect(raw.keys.toSet(), {'distanceM', 'movingTimeS'});
    expect(raw['distanceM'], {
      'value': 5000,
      'atComputed': 4800,
      'atVersions': {
        'formulaVersion': 'f1',
        'metricDefinitionVersion': 'm1',
        'thresholdPolicyVersion': 't1',
      },
      'atRev': 8,
    });
    expect(stateJson(await reload()), stateJson(s));
    expect(stateJson(await afterIndexRebuild()), stateJson(s),
        reason: 'overrides are not stored in the index or in memory only');
  });

  test('every later mutation carries the overrides of the mutated record; a '
      'crash before COMMIT shows the previous generation overrides', () async {
    final s = journalSession(id).copyWith(summaryOverrides: {
      'distanceM': ov(5000, 4800, kV1, 8),
    });
    await h.journal.put(s);
    await h.journal.markSynced(id, baseRev: 8);
    await h.journal.updateSyncState(id, JournalSyncState.pending);
    final e = (await h.journal.read(id))!;
    expect(e.generation, 3);
    expect(stateJson(e.session), stateJson(s));
    expect(((await sessionOnDisk(3))['summaryOverrides'] as Map).keys, ['distanceM']);
  });

  test('a corrupt override entry is dropped by the tolerant reader while the '
      'rest of the record loads', () async {
    final s = journalSession(id).copyWith(summaryOverrides: {
      'distanceM': ov(5000, 4800, kV1, 8),
      'movingTimeS': ov(1800, 1700, kV1, 8),
    });
    final e = await h.journal.put(s);
    final recPath = h.gen(id, e.generation, 'record.json');
    final rec = jsonDecode(utf8.decode((await h.bytes(recPath))!)) as Map<String, dynamic>;
    ((rec['session'] as Map)['summaryOverrides'] as Map)['movingTimeS'] = {'value': 'x'};
    final bytes = utf8.encode(jsonEncode(rec));
    await h.writeRaw(recPath, bytes);
    final c = (await h.commitJson(id, e.generation))!
      ..['record'] = sha256.convert(bytes).toString();
    await h.writeText(h.gen(id, e.generation, 'COMMIT'), jsonEncode(c));
    final back = await reload();
    expect(back.summaryOverrides.keys, ['distanceM']);
    expect(back.summary.distanceM, 4800);
  });

  test('(a) an explicit edit is stored as explicitValues in the same '
      'generation that dropped the override; a second edit REPLACES the entry '
      'while the ring keeps both operations', () async {
    var s = journalSession(id).copyWith(summaryOverrides: {
      'distanceM': ov(5100, 4800, kV1, 8),
    });
    await h.journal.put(s);
    s = SummaryProjection.applyExplicitEdit(s, {'distanceM': 5000});
    final e1 = (await h.journal.updateRecord(id, s))!;
    final disk1 = await sessionOnDisk(e1.generation);
    expect((disk1['explicitValues'] as Map)['distanceM'],
        {'value': 5000, 'atDerived': 4800, 'seq': 1});
    expect(disk1.containsKey('summaryOverrides'), isFalse,
        reason: 'no override of distanceM remains in that file');

    s = SummaryProjection.applyExplicitEdit(s, {'distanceM': 5200});
    final e2 = (await h.journal.updateRecord(id, s))!;
    final disk2 = await sessionOnDisk(e2.generation);
    expect((disk2['explicitValues'] as Map).length, 1, reason: 'one entry per field');
    expect((disk2['explicitValues'] as Map)['distanceM']['seq'], 2);
    expect((disk2['explicitValues'] as Map)['distanceM']['value'], 5200);
    expect((disk2['editHistory'] as List).length, 2);

    for (final back in [await reload(), await afterIndexRebuild()]) {
      expect(stateJson(back), stateJson(s));
      expect(SummaryProjection.effective(back)['distanceM'], 5200);
      expect(SummaryProjection.derive(back)['distanceM'], 4800);
      expect(back.userEditCount, 2);
    }
  });

  test('(a2) after 100 sequential edits the file holds exactly 64 ring '
      'entries (the newest, operation 37 first), a stored counter of 64 and '
      'one explicit entry per distinct field; growth is bounded; a replay of '
      'the last edit adds nothing', () async {
    var s = journalSession(id);
    await h.journal.put(s);
    int? size64;
    JournalEntryHolder? last;
    for (var i = 1; i <= 100; i++) {
      s = SummaryProjection.applyExplicitEdit(
          s, i.isOdd ? {'distanceM': 1000.0 + i} : {'movingTimeS': 1000.0 + i});
      last = JournalEntryHolder((await h.journal.updateRecord(id, s))!.generation);
      if (i == 64) {
        size64 = (await h.bytes(h.gen(id, last.gen, 'record.json')))!.length;
      }
    }
    final disk = await sessionOnDisk(last!.gen);
    final ring = disk['editHistory'] as List;
    expect(ring.length, 64);
    expect(ring.first['seq'], 37);
    expect(ring.last['seq'], 100);
    expect(disk['userEditCount'], 64);
    expect((disk['explicitValues'] as Map).keys.toSet(), {'distanceM', 'movingTimeS'});
    final size100 = (await h.bytes(h.gen(id, last.gen, 'record.json')))!.length;
    expect(size100, lessThanOrEqualTo(size64! + 512),
        reason: 'the stored record does not grow with the edit count');

    // Lost-acknowledgement replay: committed, not acknowledged, retried.
    final replay = (await h.journal.updateRecord(id, s))!;
    expect(replay.generation, last.gen, reason: 'no 101st operation, one generation');
    final before = await h.bytes(h.gen(id, last.gen, 'record.json'));

    for (final back in [await reload(), await afterIndexRebuild()]) {
      expect(stateJson(back), stateJson(s));
      expect(back.editHistory.length, 64);
      expect(back.userEditCount, 64);
    }
    expect(await h.bytes(h.gen(id, last.gen, 'record.json')), before);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('(a2) the counter is stored, not derived from the ring length: a hand '
      'built record with ring 5 and counter 64 reloads as 64', () async {
    final s = journalSession(id).copyWith(
      userEditCount: 64,
      editHistory: [
        for (var i = 1; i <= 5; i++)
          EditHistoryEntry(field: 'distanceM', value: 1000.0 + i, seq: i),
      ],
    );
    await h.journal.put(s);
    final back = await reload();
    expect(back.userEditCount, 64);
    expect(back.editHistory.length, 5);
  });

  test('(a3) a source candidate and the moved atDerived persist; the next '
      'recompute with the same inputs does not record it again', () async {
    var s = SummaryProjection.applyExplicitEdit(journalSession(id), {'distanceM': 5000});
    await h.journal.put(s);
    // New GPS-derived distance: the raw derivation moved under the explicit value.
    s = s.copyWith(summary: ActivitySummary(distanceM: 4950));
    s = SummaryProjection.reconcile(s);
    final ex = s.explicitValues['distanceM']!;
    expect([ex.value, ex.atDerived, ex.sourceCandidate], [5000, 4950, 4950]);
    final e = (await h.journal.updateRecord(id, s))!;
    final disk = (await sessionOnDisk(e.generation))['explicitValues'] as Map;
    expect(disk['distanceM']['atDerived'], 4950);
    expect(disk['distanceM']['sourceCandidate'], 4950);

    for (final back in [await reload(), await afterIndexRebuild()]) {
      expect(stateJson(back), stateJson(s));
      final again = SummaryProjection.reconcile(back);
      expect(stateJson(again), stateJson(back),
          reason: 'same inputs: nothing new is recorded');
      expect(again.explicitValues['distanceM']!.value, 5000,
          reason: 'the candidate value is never written');
    }
  });

  test('(b) a version reconciliation with an unchanged value is a new '
      'committed generation holding atVersions V2; it survives a restart and '
      'a replay creates no further generation', () async {
    var s = journalSession(id).copyWith(summaryOverrides: {
      'distanceM': ov(5000, 4800, kV1, 8),
    });
    final e0 = await h.journal.put(s);
    s = SummaryProjection.reconcile(s, inForce: kV2);
    final o = s.summaryOverrides['distanceM']!;
    expect([o.atComputed, o.atVersions, o.recalcCandidate], [4800, kV2, null]);
    final e1 = (await h.journal.updateRecord(id, s))!;
    expect(e1.generation, greaterThan(e0.generation));
    final disk = ((await sessionOnDisk(e1.generation))['summaryOverrides'] as Map)['distanceM']
        as Map;
    expect(disk['atVersions']['formulaVersion'], 'f2');

    final replay = (await h.journal.updateRecord(id, s))!;
    expect(replay.generation, e1.generation, reason: 'lost-acknowledgement retry');
    final back = await reload();
    expect(back.summaryOverrides['distanceM']!.atVersions, kV2,
        reason: 'not back at V1 after the restart');
    expect(stateJson(await afterIndexRebuild()), stateJson(s));
  });

  test('(b) a version change with a moved raw value records the recalculation '
      'candidate once, persistently', () async {
    var s = journalSession(id, distanceM: 4900).copyWith(summaryOverrides: {
      'distanceM': ov(5000, 4800, kV1, 8),
    });
    await h.journal.put(s);
    s = SummaryProjection.reconcile(s, inForce: kV2);
    final o = s.summaryOverrides['distanceM']!;
    expect([o.atComputed, o.atVersions, o.recalcCandidate], [4900, kV2, 4900]);
    final e = (await h.journal.updateRecord(id, s))!;
    final disk = ((await sessionOnDisk(e.generation))['summaryOverrides'] as Map)['distanceM']
        as Map;
    expect(disk['recalcCandidate'], 4900);
    expect(disk['atComputed'], 4900);
    final back = await reload();
    expect(stateJson(SummaryProjection.reconcile(back, inForce: kV2)), stateJson(back));
    expect(back.summaryOverrides['distanceM']!.recalcCandidate, 4900);
  });
}

class JournalEntryHolder {
  JournalEntryHolder(this.gen);

  final int gen;
}
