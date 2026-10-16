// S02-02 I02, I03, I04, I22, I35, I36: crash between temp write and rename,
// torn / missing index, index as a rebuildable cache, pair verification and
// orphan generation recovery.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_crash_matrix.dart';
import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart';

Future<JournalHarness> threeEntries() async {
  final h = JournalHarness.memory();
  await h.open();
  await h.journal.put(journalSession(idFor(1), seed: 1));
  await h.journal.put(journalSession(idFor(2), seed: 2));
  await h.journal.put(journalSession(idFor(3), seed: 3));
  return h;
}

int idx(Baseline b, FsOpKind k, String suffix) =>
    b.log.firstWhere((o) => o.kind == k && o.path.endsWith(suffix)).index;

void main() {
  group('I02 crash between temp write and rename', () {
    test('the previously committed version survives, no .tmp survives the next '
        'start, the new version is not visible without the rename', () async {
      final b = await baselineFor(Mut.reedit);
      final points = <String, FaultPlan>{
        'streams temp written': FaultPlan(idx(b, FsOpKind.write, 'g3/streams.bin.tmp'), FaultMode.crashAfter),
        'streams temp TORN (half the bytes)': FaultPlan(
            idx(b, FsOpKind.write, 'g3/streams.bin.tmp'), FaultMode.crashAfter,
            partialWrite: true),
        'streams temp closed, not renamed': FaultPlan(idx(b, FsOpKind.close, 'g3/streams.bin.tmp'), FaultMode.crashAfter),
        'record temp written': FaultPlan(idx(b, FsOpKind.write, 'g3/record.json.tmp'), FaultMode.crashAfter),
        'record temp TORN': FaultPlan(
            idx(b, FsOpKind.write, 'g3/record.json.tmp'), FaultMode.crashAfter,
            partialWrite: true),
        'record temp closed, not renamed': FaultPlan(idx(b, FsOpKind.close, 'g3/record.json.tmp'), FaultMode.crashAfter),
      };
      for (final p in points.entries) {
        final r = await runWithFault(Mut.reedit, p.value);
        try {
          expect(r.completed, isFalse, reason: p.key);
          expect(await r.h.exists('journal/$kTarget/g3'), isTrue,
              reason: '${p.key}: the crash left debris');
          final tree = await r.h.snapshot();
          expect(tree.keys.any((k) => k.endsWith('.tmp')), isTrue,
              reason: '${p.key}: precondition, a temp file exists');
          await r.h.restart();
          expect(r.h.report.tempFilesRemoved, greaterThan(0), reason: p.key);
          await expectRecovered(r.h, Mut.reedit,
              isNew: false, base: r.base, why: p.key);
        } finally {
          await r.h.dispose();
        }
      }
    });

    test('the same crash for the very first write of an activity leaves no '
        'trace of it and no temp file', () async {
      final h = JournalHarness.memory();
      try {
        await h.open();
        h.fs.arm(const FaultPlan(2, FaultMode.crashAfter, partialWrite: true));
        await expectLater(h.journal.put(journalSession(idFor(1))), throwsA(isA<SimulatedCrash>()));
        await h.restart();
        expect(await h.listIds(), isEmpty);
        expect((await h.snapshot()).keys.where((k) => k.contains(idFor(1))), isEmpty);
      } finally {
        await h.dispose();
      }
    });
  });

  group('I03 torn index at every byte offset of the last line', () {
    test('no committed session disappears and start never throws', () async {
      final h = await threeEntries();
      try {
        final full = (await h.bytes('journal/index.jsonl'))!;
        final lastStart = full.sublist(0, full.length - 1).lastIndexOf(0x0A) + 1;
        expect(lastStart, greaterThan(0));
        final ids = [idFor(1), idFor(2), idFor(3)];
        final gensBefore = {for (final i in ids) i: await h.generations(i)};
        for (var t = lastStart; t <= full.length; t++) {
          await h.writeRaw('journal/index.jsonl', full.sublist(0, t));
          await h.restart();
          expect(await h.listIds(), ids, reason: 'truncated at $t of ${full.length}');
          for (final i in ids) {
            expect(await h.generations(i), gensBefore[i], reason: 'offset $t');
          }
          // The index is healed: every line parses and covers every id.
          final lines = await h.indexLines();
          for (final l in lines) {
            expect(() => jsonDecode(l), returnsNormally, reason: 'offset $t: $l');
          }
          expect(lines.where((l) => l.contains(ids.last)), hasLength(1),
              reason: 'offset $t');
        }
      } finally {
        await h.dispose();
      }
    });
  });

  group('I04 / I22 the index is a rebuildable cache', () {
    Future<JournalHarness> mixed() async {
      final h = JournalHarness.memory();
      await h.open();
      await h.journal.put(journalSession(idFor(1), seed: 1),
          syncState: JournalSyncState.synced, baseRev: 4); // synced
      await h.journal.put(journalSession(idFor(2), seed: 2)); // deleted below
      await h.journal.put(journalSession(idFor(3), seed: 3)); // pending
      await h.journal.delete(idFor(2));
      await h.journal.put(journalSession(idFor(4), seed: 4),
          syncState: JournalSyncState.uploadFailed);
      return h;
    }

    final damages = <String, Future<void> Function(JournalHarness)>{
      'deleted': (h) => h.deleteRawFile('journal/index.jsonl'),
      'garbage': (h) => h.writeText('journal/index.jsonl', '\u0000\u0001garbage\n'),
      'zero-length': (h) => h.writeRaw('journal/index.jsonl', const <int>[]),
      'stale lines resurrecting a deleted id': (h) => h.writeText(
          'journal/index.jsonl',
          '{"seq":1,"op":"put","id":"${idFor(2)}"}\n{"seq":2,"op":"put","id":"${idFor(1)}"}\n'),
    };

    for (final d in damages.entries) {
      test('index ${d.key}: the rebuilt set equals the set before, tombstones '
          'and synced markers are kept, order is the sequence order', () async {
        final h = await mixed();
        try {
          final idsBefore = await h.listIds();
          final tombsBefore = [for (final e in await h.journal.listTombstones()) e.id];
          final genBefore = [for (final e in await h.journal.list()) e.generation];
          expect(idsBefore, [idFor(1), idFor(3), idFor(4)]);
          expect(tombsBefore, [idFor(2)]);

          await d.value(h);
          final report = await h.restart();

          expect(report.indexRebuilt, isTrue);
          expect(await h.listIds(), idsBefore);
          expect([for (final e in await h.journal.list()) e.generation], genBefore,
              reason: 'order = sequence order');
          expect([for (final e in await h.journal.listTombstones()) e.id], tombsBefore,
              reason: 'a deleted id does not reappear');
          expect(await h.journal.read(idFor(2)), isNull);
          // The "upload queue" is the set of entries that are not synced.
          final states = {
            for (final e in await h.journal.list()) e.id: e.state.syncState,
          };
          expect(states, {
            idFor(1): JournalSyncState.synced,
            idFor(3): JournalSyncState.pending,
            idFor(4): JournalSyncState.uploadFailed,
          }, reason: 'a synced entry is not re-queued');
          final lines = await h.indexLines();
          expect(lines.where((l) => l.contains(idFor(2))).single, contains('"op":"delete"'));
          for (final i in [idFor(1), idFor(3), idFor(4)]) {
            expect(lines.where((l) => l.contains(i)), hasLength(1));
          }
          final seqs = [for (final l in lines) (jsonDecode(l) as Map)['seq'] as int];
          expect(seqs, orderedEquals([...seqs]..sort()));
        } finally {
          await h.dispose();
        }
      });
    }

    test('baseRev and the synced marker come from record.json, not from the '
        'index', () async {
      final h = await mixed();
      try {
        await h.deleteRawFile('journal/index.jsonl');
        await h.restart();
        final e = (await h.journal.read(idFor(1)))!;
        expect(e.state.synced, isTrue);
        expect(e.state.baseRev, 4);
      } finally {
        await h.dispose();
      }
    });
  });

  group('I35 pair verification', () {
    late JournalHarness h;
    final id = kTarget;

    setUp(() async {
      h = JournalHarness.memory();
    });

    tearDown(() => h.dispose());

    test('a kill between the streams.bin rename and the record.json rename '
        'leaves the new generation without COMMIT: the previous pair, strictly '
        'that generation, never streamLost', () async {
      final b = await baselineFor(Mut.reedit);
      final r = await runWithFault(Mut.reedit,
          FaultPlan(idx(b, FsOpKind.rename, 'g3/streams.bin.tmp'), FaultMode.crashAfter),
          harness: h);
      expect(await h.exists('journal/$id/g3/streams.bin'), isTrue);
      expect(await h.exists('journal/$id/g3/record.json'), isFalse);
      await h.restart();
      await expectRecovered(h, Mut.reedit, isNew: false, base: r.base);
    });

    test('a generation whose streams do not match record.streamHash never '
        'receives a COMMIT marker', () async {
      await setupFixture(h);
      h.fs.onRead = (p, bytes) {
        if (p.endsWith('/g3/streams.bin')) bytes[bytes.length ~/ 3] ^= 0x01;
        return bytes;
      };
      h.fs.clearLog();
      await expectLater(h.journal.put(r2()), throwsA(isA<JournalIoException>()));
      expect(await h.exists('journal/$id/g3/COMMIT'), isFalse);
      expect(h.fs.log.any((o) => (o.to ?? '').endsWith('COMMIT')), isFalse);
    });

    test('a valid COMMIT whose record.streamHash differs from the marker '
        'stream checksum is not read as a valid stream: streamLost, record kept',
        () async {
      final base = await setupFixture(h);
      final recPath = h.gen(id, base, 'record.json');
      final rec = jsonDecode(utf8.decode((await h.bytes(recPath))!)) as Map<String, dynamic>;
      rec['streamHash'] = 'f' * 64;
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(rec)));
      await h.writeRaw(recPath, bytes);
      final commit = (await h.commitJson(id, base))!;
      commit['record'] = sha256.convert(bytes).toString();
      await h.writeText(h.gen(id, base, 'COMMIT'), jsonEncode(commit));
      await h.restart();
      expect(h.report.selectedGenerations[id], base);
      expect(h.report.streamLost, {id});
      final e = (await h.journal.read(id))!;
      expect(e.streamLost, isTrue);
      expect(e.session.summary.distanceM, 4800);
    });

    test('control: a matching pair is untouched and not marked lost', () async {
      final base = await setupFixture(h);
      final snap = await h.snapshot('journal/$id/g$base');
      await h.restart();
      expect(h.report.streamLost, isEmpty);
      expect(await h.snapshot('journal/$id/g$base'), snap);
      expect((await h.journal.read(id))!.streamLost, isFalse);
    });
  });

  group('I36 orphan generation and directory recovery', () {
    test('uncommitted generations (complete and newer, no record.json, no '
        'streams.bin, empty) are deleted at once and never listed', () async {
      final h = JournalHarness.memory();
      try {
        final base = await setupFixture(h);
        final sibSnap = await h.snapshot('journal/$kOther');
        final src = h.gen(kTarget, base);
        final rec = (await h.bytes('$src/record.json'))!;
        final str = (await h.bytes('$src/streams.bin'))!;
        await h.writeRaw(h.gen(kTarget, 20, 'record.json'), rec);
        await h.writeRaw(h.gen(kTarget, 20, 'streams.bin'), str); // complete, newer
        await h.writeRaw(h.gen(kTarget, 21, 'streams.bin'), str); // no record
        await h.writeRaw(h.gen(kTarget, 22, 'record.json'), rec); // no streams
        await h.writeRaw(h.gen(kTarget, 23, 'x.tmp'), const [1]); // junk only
        await h.writeText('journal/$kTarget/g24/record.json.tmp', 'orphan temp');

        await h.restart(); // the clock did not move: no age elapsed

        expect(await h.generations(kTarget), [base]);
        for (final g in [20, 21, 22, 23]) {
          expect(h.report.deletedGenerations, contains('$kTarget/g$g'));
        }
        expect(h.report.tempFilesRemoved, greaterThanOrEqualTo(2));
        expect(h.report.selectedGenerations[kTarget], base);
        expect(await h.listIds(), [kOther, kTarget]);
        expect(await h.snapshot('journal/$kOther'), sibSnap);
      } finally {
        await h.dispose();
      }
    });

    test('a directory without any record.json is never listed or read as a '
        'session', () async {
      final h = JournalHarness.memory();
      try {
        await setupFixture(h);
        await h.writeRaw('journal/${idFor(7)}/g1/streams.bin', const [1, 2, 3]);
        await h.writeRaw('journal/${idFor(8)}/stray.txt', const [1]);
        await h.restart();
        expect(await h.listIds(), [kOther, kTarget]);
        expect(await h.exists('journal/${idFor(7)}'), isFalse);
        expect(h.report.absent, contains(idFor(7)));
      } finally {
        await h.dispose();
      }
    });

    test('an older COMMITTED orphan (kept because the selected generation is '
        'stream-lost) survives before the bounded age and goes through '
        'quarantine after it; the selected generation is never removed', () async {
      final h = JournalHarness.memory();
      try {
        await h.open();
        await h.journal.put(journalSession(kTarget, seed: 1)); // g1
        await h.journal.put(journalSession(kTarget, seed: 2)); // g2
        await h.flipBit(h.gen(kTarget, 2, 'streams.bin'), 30);

        h.clock.advance(const Duration(days: 1));
        await h.restart();
        expect(await h.generations(kTarget), [1, 2], reason: 'before the age');
        expect(await h.names('quarantine'), isEmpty);

        h.clock.advance(const Duration(days: 8));
        await h.restart();
        expect(await h.generations(kTarget), [2], reason: 'after the age');
        expect(h.report.selectedGenerations[kTarget], 2);
        expect(await h.names('quarantine'), ['$kTarget-g1.json'],
            reason: 'a readable record.json goes through quarantine first');
        expect((await h.journal.read(kTarget))!.streamLost, isTrue);
      } finally {
        await h.dispose();
      }
    });

    test('the quarantine count bound drops the oldest, never the newest session',
        () async {
      final h = JournalHarness.memory(quarantineMaxCount: 2);
      try {
        await h.open();
        for (var i = 1; i <= 4; i++) {
          await h.journal.put(journalSession(idFor(i), seed: i)); // g(2i-1)
          await h.journal.put(journalSession(idFor(i), seed: i + 10)); // g(2i)
          await h.flipBit(h.gen(idFor(i), 2 * i, 'streams.bin'), 30);
        }
        h.clock.advance(const Duration(days: 8));
        await h.restart();
        expect(await h.names('quarantine'), [
          '${idFor(3)}-g5.json',
          '${idFor(4)}-g7.json',
        ]);
        expect(h.report.streamLost, {for (var i = 1; i <= 4; i++) idFor(i)});
      } finally {
        await h.dispose();
      }
    });

    test('the old generation of a successful put is deleted only after the next '
        'verified read; a failed delete leaves an orphan that the pass removes',
        () async {
      final b = await baselineFor(Mut.reedit);
      final del = b.log.firstWhere((o) => o.kind == FsOpKind.deleteDir).index;
      final r = await runWithFault(Mut.reedit, FaultPlan(del, FaultMode.failAt));
      try {
        expect(r.completed, isTrue);
        expect(r.h.fs.fired, isTrue);
        expect(await r.h.generations(kTarget), [r.base, r.base + 1],
            reason: 'the failed delete left an orphan');
        await r.h.restart();
        expect(await r.h.generations(kTarget), [r.base + 1],
            reason: 'the recovery pass removed it');
        await expectRecovered(r.h, Mut.reedit, isNew: true, base: r.base);
      } finally {
        await r.h.dispose();
      }
    });
  });
}
