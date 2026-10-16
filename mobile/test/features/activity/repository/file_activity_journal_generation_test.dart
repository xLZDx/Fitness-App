// S02-02 I40, I41: generation write with the COMMIT marker (crash after every
// named step) and recovery of the highest COMMITTED generation whatever
// CURRENT says.
import 'dart:convert';

import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_crash_matrix.dart';
import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart';

/// Index in the baseline log of the first operation matching [kind] on a path
/// ending with [suffix].
int stepIndex(Baseline b, FsOpKind kind, String suffix) => b.log
    .firstWhere((o) => o.kind == kind && o.path.endsWith(suffix)).index;

void main() {
  group('I40 crash after every named step of the generation write', () {
    test('the 12 named kill points exist in the log and each recovers exactly '
        'generation 1 before the COMMIT rename and generation 2 at or after '
        'it, as kill and as thrown error', () async {
      final b = await baselineFor(Mut.reedit);
      final g = 'g3'; // other = g1, target base = g2, mutation = g3
      final named = <String, int>{
        'g2 directory created': stepIndex(b, FsOpKind.createDir, '/$g'),
        'streams.bin temp written': stepIndex(b, FsOpKind.write, '$g/streams.bin.tmp'),
        'streams.bin renamed': stepIndex(b, FsOpKind.rename, '$g/streams.bin.tmp'),
        'record.json temp written': stepIndex(b, FsOpKind.write, '$g/record.json.tmp'),
        'record.json renamed': stepIndex(b, FsOpKind.rename, '$g/record.json.tmp'),
        'read-back verified': stepIndex(b, FsOpKind.readBytes, '$g/record.json'),
        'COMMIT temp written and fsynced': stepIndex(b, FsOpKind.fsync, '$g/COMMIT.tmp'),
        'COMMIT renamed': stepIndex(b, FsOpKind.rename, '$g/COMMIT.tmp'),
        'CURRENT temp written and fsynced': stepIndex(b, FsOpKind.fsync, '/CURRENT.tmp'),
        'CURRENT renamed': stepIndex(b, FsOpKind.rename, '/CURRENT.tmp'),
        'index appended': stepIndex(b, FsOpKind.fsync, '/index.jsonl'),
        'old g2 delete started': stepIndex(b, FsOpKind.deleteDir, '/g2'),
      };
      expect(named['COMMIT renamed'], b.commitIndex);
      expect(named.values.toSet(), hasLength(12), reason: 'twelve distinct steps');

      for (final mut in [Mut.reedit, Mut.delete, Mut.synced]) {
        final bm = mut == Mut.reedit ? b : await baselineFor(mut);
        for (final mode in [FaultMode.crashAfter, FaultMode.failAt]) {
          for (final e in named.entries) {
            if (mut != Mut.reedit &&
                (e.key.startsWith('old') || e.key.contains('read-back'))) {
              continue; // a delete has no read after it / no stream read-back
            }
            final idx = mut == Mut.reedit ? e.value : _remap(b, bm, e.value);
            if (idx == null) continue;
            final plan = FaultPlan(idx, mode);
            final why = '${mut.name} ${e.key} $plan';
            final r = await runWithFault(mut, plan);
            try {
              expect(r.h.fs.fired, isTrue, reason: why);
              final isNew = newExpected(plan, bm);
              if (mode == FaultMode.crashAfter && idx < bm.mutationOps) {
                expect(r.completed, isFalse, reason: '$why: never completes');
                expect(r.h.acks, isEmpty, reason: why);
              }
              final before = isNew
                  ? null
                  : {
                      'record': await r.h.bytes(r.h.gen(kTarget, r.base, 'record.json')),
                      'streams': await r.h.bytes(r.h.gen(kTarget, r.base, 'streams.bin')),
                    };
              await r.h.restart();
              await expectRecovered(r.h, mut,
                  isNew: isNew, base: r.base, why: why);

              // State recorded in the selected record.json itself.
              final sel = r.h.report.selectedGenerations[kTarget]!;
              final rec = await r.h.recordJson(kTarget, sel);
              final state = rec['state'] as Map<String, dynamic>;
              if (!isNew) {
                expect(state['synced'], isTrue, reason: why);
                expect(state['tombstone'], isFalse, reason: why);
                expect(await r.h.bytes(r.h.gen(kTarget, sel, 'record.json')),
                    before!['record'], reason: '$why record bytes equal before');
                expect(await r.h.bytes(r.h.gen(kTarget, sel, 'streams.bin')),
                    before['streams'], reason: '$why streams bytes equal before');
              } else if (mut == Mut.delete) {
                expect(state['tombstone'], isTrue, reason: why);
              } else if (mut == Mut.reedit) {
                expect(state['synced'], isFalse, reason: why);
              }
            } finally {
              await r.h.dispose();
            }
          }
        }
      }
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('a failed read-back never writes COMMIT and never switches CURRENT; '
        'the put surfaces a typed error with generation 1 intact', () async {
      for (final victim in ['streams.bin', 'record.json']) {
        final h = JournalHarness.memory();
        try {
          final base = await setupFixture(h);
          h.fs.onRead = (path, bytes) {
            if (path.endsWith('/g${base + 1}/$victim')) {
              bytes[bytes.length ~/ 2] ^= 0x55;
              if (victim == 'record.json') bytes.fillRange(0, bytes.length, 0x7B);
            }
            return bytes;
          };
          h.fs.clearLog();
          await expectLater(h.journal.put(r2()), throwsA(isA<JournalIoException>()),
              reason: victim);
          expect(await h.exists(h.gen(kTarget, base + 1)), isFalse,
              reason: '$victim: the failed generation is removed');
          expect(
              h.fs.log.any((o) =>
                  o.kind == FsOpKind.rename && (o.to ?? '').endsWith('/COMMIT')),
              isFalse,
              reason: '$victim: no COMMIT rename was attempted');
          expect((await h.currentJson(kTarget))!['seq'], base, reason: victim);
          expect(h.acks, isEmpty);
          h.fs.onRead = null;
          await h.restart();
          await expectRecovered(h, Mut.reedit,
              isNew: false, base: base, why: victim);
        } finally {
          await h.dispose();
        }
      }
    });
  });

  group('I41 recovery picks the highest COMMITTED generation, CURRENT is a cache',
      () {
    late JournalHarness h;
    final id = kTarget;

    // g1 synced + O1(5000), g2 pending + O2(5100), g3 synced + O3(5200).
    setUp(() async {
      h = JournalHarness.memory();
      await h.open();
      await h.journal.put(journalSession(kOther, seed: 9)); // g1 of other
      await h.journal.put(withOverride(journalSession(id, seed: 1), 5000),
          syncState: JournalSyncState.synced, baseRev: 8); // g2
      await h.journal.put(withOverride(journalSession(id, seed: 2), 5100, rev: 9)); // g3
      await h.journal.put(withOverride(journalSession(id, seed: 3), 5200, rev: 10),
          syncState: JournalSyncState.synced, baseRev: 10); // g4
    });

    tearDown(() => h.dispose());

    // Generations of the target are 2, 3, 4.
    Future<void> expectSelected(int sel, {bool deletedG4 = false}) async {
      await h.restart();
      expect(h.report.selectedGenerations[id], sel, reason: 'strictly selected');
      expect((await h.currentJson(id))!['seq'], sel, reason: 'CURRENT repaired');
      if (deletedG4) {
        expect(await h.exists(h.gen(id, 4)), isFalse,
            reason: 'the uncommitted or invalid highest generation is deleted at once');
      }
      expect(h.report.streamLost, isEmpty);
      final snap = await h.snapshot();
      final e = (await h.journal.read(id))!;
      expect(e.generation, sel);
      expect(e.streamLost, isFalse);
      final ov = e.session.summaryOverrides['distanceM']!.value;
      if (sel == 4) {
        expect([e.state.synced, e.state.baseRev, ov], [true, 10, 5200]);
        expect(streamsOf(e.session), streamsOf(journalSession(id, seed: 3)));
      } else {
        expect([e.state.synced, e.state.baseRev, ov], [false, 8, 5100],
            reason: 'g3 state, never a mix with g2 or g4');
        expect(streamsOf(e.session), streamsOf(journalSession(id, seed: 2)));
      }
      expect((await h.journal.read(kOther))!.streamLost, isFalse);

      // A second start changes nothing.
      await h.restart();
      expect(h.report.currentRepaired, isEmpty);
      expect(h.report.selectedGenerations[id], sel);
      expect(await h.snapshot(), snap);
    }

    test('(a) CURRENT deleted, newest committed', () async {
      await h.deleteRawFile('journal/$id/CURRENT');
      await expectSelected(4);
    });

    test('(b) CURRENT zero-length or garbage, newest committed', () async {
      await h.writeRaw('journal/$id/CURRENT', const <int>[]);
      await expectSelected(4);
      await h.writeText('journal/$id/CURRENT', '\u0000{{garbage');
      await expectSelected(4);
    });

    test('(c) CURRENT names a missing directory, newest committed', () async {
      await h.writeText('journal/$id/CURRENT', jsonEncode({'gen': 'g9', 'seq': 9}));
      await expectSelected(4);
    });

    test('(d) CURRENT names the newest generation which has NO COMMIT '
        '(complete and read back): generation 3 is selected', () async {
      await h.deleteRawFile(h.gen(id, 4, 'COMMIT'));
      await h.writeText('journal/$id/CURRENT',
          jsonEncode({'gen': 'g4', 'seq': 4, 'streamHash': 'x'}));
      await expectSelected(3, deletedG4: true);
    });

    for (final variant in ['unparsable', 'wrong seq', 'wrong record checksum']) {
      test('(e) invalid COMMIT of the newest generation: $variant', () async {
        final cur = (await h.commitJson(id, 4))!;
        final text = switch (variant) {
          'unparsable' => 'not json at all',
          'wrong seq' => jsonEncode({...cur, 'seq': 7}),
          _ => jsonEncode({...cur, 'record': '0' * 64}),
        };
        await h.writeText(h.gen(id, 4, 'COMMIT'), text);
        await h.writeText('journal/$id/CURRENT', jsonEncode({'gen': 'g4', 'seq': 4}));
        await expectSelected(3, deletedG4: true);
      });
    }

    test('(f) the newest generation has no record.json', () async {
      await h.deleteRawFile(h.gen(id, 4, 'record.json'));
      await expectSelected(3, deletedG4: true);
    });

    test('(g) CURRENT names the OLDEST generation while two newer ones are '
        'committed: the highest committed is selected', () async {
      await h.writeText('journal/$id/CURRENT', jsonEncode({'gen': 'g2', 'seq': 2}));
      await expectSelected(4);
    });

    test('a COMMIT is never trusted for a generation that is not the highest '
        'valid one: a higher seq without COMMIT loses even when CURRENT names it',
        () async {
      await h.deleteRawFile(h.gen(id, 4, 'COMMIT'));
      await h.deleteRawFile(h.gen(id, 3, 'COMMIT'));
      await h.writeText('journal/$id/CURRENT', jsonEncode({'gen': 'g4', 'seq': 4}));
      await h.restart();
      expect(h.report.selectedGenerations[id], 2);
      final e = (await h.journal.read(id))!;
      expect([e.state.synced, e.state.baseRev], [true, 8]);
      expect(e.session.summaryOverrides['distanceM']!.value, 5000);
    });
  });
}

/// Maps a step index of the `reedit` baseline to the same step in another
/// mutation's baseline (matched by operation path suffix and kind).
int? _remap(Baseline from, Baseline to, int idx) {
  final op = from.log.firstWhere((o) => o.index == idx);
  final suffix = op.path.substring(op.path.indexOf('/journal/'));
  for (final o in to.log) {
    if (o.kind == op.kind &&
        o.path.endsWith(suffix) &&
        o.index >= 0) {
      return o.index;
    }
  }
  return null;
}
