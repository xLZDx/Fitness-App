// S02-02 I54, I55 (design 10, MAJOR-02B): a first generation without COMMIT is
// absent after restart; a committed generation with damaged streams.bin is
// streamLost with every metadata edit preserved.
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart';

void main() {
  group('I54 first generation without COMMIT is absent', () {
    final sib = idFor(1), committed = idFor(2), fresh = idFor(3);

    // Operation indexes of the I19 order of one put: 0 createDir; 1-6 streams.bin;
    // 7-12 record.json; 13-14 read-back; 15-20 COMMIT (19 = close of the temp
    // file, 20 = the COMMIT rename).
    const closeCommitTmp = 19;
    const commitIdx = 20;

    Future<JournalHarness> crashedFirstPut(FaultPlan plan) async {
      final h = JournalHarness.memory();
      await h.open();
      await h.journal.put(journalSession(sib, seed: 1));
      await h.journal.put(journalSession(committed, seed: 2));
      expect((await h.journal.list()).length, 2);
      h.acks.clear();
      h.fs.clearLog();
      h.fs.arm(plan);
      Object? err;
      try {
        await h.journal.put(journalSession(fresh, seed: 3));
      } catch (e) {
        err = e;
      }
      expect(err, isNotNull, reason: 'the put future never completed normally');
      expect(h.fs.fired, isTrue);
      expect(h.acks, isEmpty, reason: 'no acknowledgement');
      return h;
    }

    final damages = <String, Future<void> Function(JournalHarness)>{
      'intact g1, CURRENT absent': (_) async {},
      'CURRENT zero-length': (h) => h.writeRaw('journal/$fresh/CURRENT', const <int>[]),
      'CURRENT garbage': (h) => h.writeText('journal/$fresh/CURRENT', '\u0000garbage'),
      'CURRENT names g3': (h) => h.writeText(
          'journal/$fresh/CURRENT', jsonEncode({'gen': 'g3', 'seq': 3})),
      'only record.json': (h) => h.deleteRawFile('journal/$fresh/g3/streams.bin'),
      'only streams.bin': (h) => h.deleteRawFile('journal/$fresh/g3/record.json'),
    };

    for (final mode in [FaultMode.crashAfter]) {
      for (final plan in [
        ('after the read-back, before COMMIT', closeCommitTmp - 5),
        ('COMMIT temp written, not renamed', closeCommitTmp),
      ]) {
        for (final d in damages.entries) {
          test('${mode.name}: ${plan.$1}; ${d.key}', () async {
            final h = await crashedFirstPut(FaultPlan(plan.$2, mode));
            try {
              expect(await h.exists('journal/$fresh/g3/record.json'), isTrue,
                  reason: 'precondition: the uncommitted g1 is on disk');
              expect(await h.exists('journal/$fresh/g3/COMMIT'), isFalse);
              await d.value(h);
              final sibSnap = await h.snapshot('journal/$sib');
              await h.restart();

              expect(await h.listIds(), [sib, committed],
                  reason: 'absent from the active list, count unchanged');
              expect(h.report.absent, {fresh});
              expect(h.report.streamLost, isEmpty, reason: 'NOT streamLost');
              expect(h.journal.streamLostCount, 0);
              expect(await h.exists('journal/$fresh'), isFalse,
                  reason: 'activity directory and g1 deleted from disk');
              expect(await h.journal.read(fresh), isNull);
              expect(await h.journal.listTombstones(), isEmpty);
              expect((await h.indexLines()).where((l) => l.contains(fresh)), isEmpty,
                  reason: 'the index rebuilt from disk does not contain it');
              expect(await h.snapshot('journal/$sib'), sibSnap);
              expect((await h.journal.read(committed))!.streamLost, isFalse,
                  reason: 'a second activity committed before the crash survives');
            } finally {
              await h.dispose();
            }
          });
        }
      }
    }

    test('thrown error instead of the COMMIT rename: the put fails typed and '
        'the activity is absent after restart', () async {
      final h = await crashedFirstPut(FaultPlan(commitIdx, FaultMode.failAt));
      try {
        await h.restart();
        expect(await h.listIds(), [sib, committed]);
        expect(await h.exists('journal/$fresh'), isFalse);
      } finally {
        await h.dispose();
      }
    });

    test('control: the same put without a fault is listed and survives a '
        'restart', () async {
      final h = JournalHarness.memory();
      try {
        await h.open();
        await h.journal.put(journalSession(sib, seed: 1));
        await h.journal.put(journalSession(fresh, seed: 3));
        expect(await h.listIds(), [sib, fresh]);
        await h.restart();
        expect(await h.listIds(), [sib, fresh]);
        expect(h.report.absent, isEmpty);
      } finally {
        await h.dispose();
      }
    });
  });

  group('I55 committed generation with damaged streams.bin is streamLost', () {
    final id = idFor(1), other = idFor(2);

    late JournalHarness h;
    late ActivitySession finalSession;
    late int lastGen;

    // g(other)=1, then target: put (R1,S1), explicit edit, cloud override,
    // synced marker. The last committed generation carries all of them.
    setUp(() async {
      h = JournalHarness.memory();
      await h.open();
      await h.journal.put(journalSession(other, seed: 9));
      final e1 = await h.journal.put(journalSession(id, seed: 1));
      var s = SummaryProjection.applyExplicitEdit(e1.session, {'distanceM': 5000});
      final e2 = (await h.journal.updateRecord(id, s))!;
      s = SummaryProjection.adoptServerValue(e2.session, 'movingTimeS', 1800, 3)!;
      final e3 = (await h.journal.updateRecord(id, s))!;
      expect(await h.journal.markSynced(id, baseRev: 3), isTrue);
      finalSession = e3.session;
      lastGen = (await h.generations(id)).last;
      expect(lastGen, e1.generation + 3);
      expect(finalSession.explicitValues, isNotEmpty);
      expect(finalSession.summaryOverrides, isNotEmpty);
    });

    tearDown(() => h.dispose());

    String metaJson(ActivitySession s) => jsonEncode(s.toJson()..remove('streams'));

    final damages = <String, Future<void> Function(JournalHarness, String)>{
      'bit-flipped': (h, rel) => h.flipBit(rel, 40),
      'truncated': (h, rel) async =>
          h.writeRaw(rel, (await h.bytes(rel))!.sublist(0, 30)),
      'deleted': (h, rel) => h.deleteRawFile(rel),
      'zero-length': (h, rel) => h.writeRaw(rel, const <int>[]),
    };

    for (final d in damages.entries) {
      test('${d.key}: listed as streamLost on the last committed '
          'generation, every metadata edit kept, no rollback', () async {
        await d.value(h, h.gen(id, lastGen, 'streams.bin'));
        await h.restart();

        expect(h.report.selectedGenerations[id], lastGen,
            reason: 'not rolled back to an older generation');
        expect(h.report.streamLost, {id});
        expect(h.journal.streamLostCount, 1, reason: 'counter incremented once');
        expect(await h.listIds(), [other, id], reason: 'listed, not dropped');

        final e = (await h.journal.read(id))!;
        expect(e.streamLost, isTrue);
        expect(e.streamsLoaded, isFalse);
        expect(e.generation, lastGen);
        expect(metaJson(e.session), metaJson(finalSession),
            reason: 'summary, laps, provenance, explicit values, ring, counter '
                'and overrides are those of the last committed generation');
        expect(e.session.explicitValues['distanceM']!.value, 5000);
        expect(e.session.editHistory, finalSession.editHistory);
        expect(e.session.userEditCount, 1);
        expect(e.session.summaryOverrides['movingTimeS']!.value, 1800);
        expect(e.state.synced, isTrue);
        expect(e.state.baseRev, 3);
        final rec = await h.recordJson(id, lastGen);
        expect((rec['state'] as Map)['synced'], isTrue,
            reason: 'metadata edits are in the committed record.json');

        final o = (await h.journal.read(other))!;
        expect(o.streamLost, isFalse, reason: 'other sessions intact');
        expect(streamsOf(o.session), streamsOf(journalSession(other, seed: 9)));

        final snap = await h.snapshot();
        await h.restart();
        expect(h.report.selectedGenerations[id], lastGen);
        expect(h.report.streamLost, {id});
        expect(await h.snapshot(), snap, reason: 'a second restart changes nothing');
      });
    }

    test('control: with a valid streams.bin the same entry is not streamLost',
        () async {
      await h.restart();
      expect(h.report.streamLost, isEmpty);
      final e = (await h.journal.read(id))!;
      expect(e.streamLost, isFalse);
      expect(streamsOf(e.session), streamsOf(journalSession(id, seed: 1)));
    });

    test('a damaged record.json of the last generation is NOT this case: the '
        'highest generation with a valid marker is selected', () async {
      await h.flipBit(h.gen(id, lastGen, 'record.json'), 20);
      await h.restart();
      expect(h.report.selectedGenerations[id], lastGen - 1);
      expect(h.report.streamLost, isEmpty);
      expect((await h.journal.read(id))!.streamLost, isFalse);
    });

    test('a metadata change on a stream-lost entry whose streams.bin is gone '
        'still commits (the sync layer must be able to record a failure)',
        () async {
      await h.deleteRawFile(h.gen(id, lastGen, 'streams.bin'));
      await h.restart();
      expect(await h.journal.updateSyncState(id, JournalSyncState.uploadFailed), isTrue);
      await h.restart();
      final e = (await h.journal.read(id))!;
      expect(e.state.syncState, JournalSyncState.uploadFailed);
      expect(e.streamLost, isTrue, reason: 'the stream is still unavailable');
    });
  });
}
