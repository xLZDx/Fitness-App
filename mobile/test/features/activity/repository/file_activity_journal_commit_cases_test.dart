// S02-02 I46-I49: the four named crash cases A-D of design 10 under the COMMIT
// marker rule. Fixture and mutation table: test/support/journal_crash_matrix.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_crash_matrix.dart';
import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart';

/// Operation index of the first op of [kind] whose path ends with [suffix].
int at(Baseline b, FsOpKind kind, String suffix) =>
    b.log.firstWhere((o) => o.kind == kind && o.path.endsWith(suffix)).index;

Future<void> restartTwiceStable(JournalHarness h) async {
  final snap = await h.snapshot();
  await h.restart();
  expect(h.report.currentRepaired, isEmpty,
      reason: 'a second restart finds a valid manifest');
  expect(await h.snapshot(), snap, reason: 'a second restart changes nothing');
}

void main() {
  const modes = [FaultMode.crashAfter, FaultMode.failAt];
  final muts = Mut.values;

  group('I46 case A: crash before COMMIT, CURRENT intact', () {
    for (final m in muts) {
      test('mutation ${m.name}', () async {
        final b = await baselineFor(m);
        final g = 'g3';
        final points = <String, int>{
          'after the read-back': b.log
              .lastWhere((o) =>
                  o.kind == FsOpKind.readBytes && o.index < b.commitIndex)
              .index,
          'COMMIT temp written': at(b, FsOpKind.write, '$g/COMMIT.tmp'),
          'COMMIT temp fsynced and closed': at(b, FsOpKind.close, '$g/COMMIT.tmp'),
          'the COMMIT rename itself failed': b.commitIndex,
        };
        for (final mode in modes) {
          for (final p in points.entries) {
            // failAt of an op BEFORE the rename aborts; at the rename it is
            // not performed: both mean "no COMMIT".
            final plan = mode == FaultMode.failAt && p.key != 'the COMMIT rename itself failed'
                ? FaultPlan(p.value, FaultMode.failAt)
                : mode == FaultMode.crashAfter && p.key == 'the COMMIT rename itself failed'
                    ? FaultPlan(p.value - 1, FaultMode.crashAfter)
                    : FaultPlan(p.value, mode);
            final r = await runWithFault(m, plan);
            final why = '${m.name} ${p.key} $plan';
            try {
              expect(newExpected(plan, b), isFalse, reason: why);
              expect(r.completed, isFalse, reason: '$why: no acknowledgement');
              expect(r.h.acks, isEmpty, reason: why);
              expect((await r.h.currentJson(kTarget))!['seq'], r.base,
                  reason: '$why: CURRENT still names generation 1');
              await r.h.restart();
              await expectRecovered(r.h, m, isNew: false, base: r.base, why: why);
              final state = (await r.h.journal.read(kTarget))!.state;
              expect(state.synced, isTrue, reason: '$why synced marker PRESENT');
              expect(state.tombstone, isFalse, reason: '$why tombstone ABSENT');
            } finally {
              await r.h.dispose();
            }
          }
        }
      });
    }
  });

  group('I47 case B: crash before COMMIT, CURRENT missing or damaged, newer '
      'generation complete and intact', () {
    final damages = <String, Future<void> Function(JournalHarness, int)>{
      'missing': (h, _) => h.deleteRawFile('journal/$kTarget/CURRENT'),
      'zero-length': (h, _) => h.writeRaw('journal/$kTarget/CURRENT', const <int>[]),
      'garbage': (h, _) => h.writeText('journal/$kTarget/CURRENT', '\u0000\u0001}{'),
      'names the uncommitted generation': (h, base) => h.writeText(
          'journal/$kTarget/CURRENT',
          jsonEncode({'gen': 'g${base + 1}', 'seq': base + 1})),
    };
    for (final m in muts) {
      for (final d in damages.entries) {
        test('mutation ${m.name}, CURRENT ${d.key}', () async {
          final b = await baselineFor(m);
          // Dies after the COMMIT temp file is fully written, before its rename.
          final plan = FaultPlan(at(b, FsOpKind.close, 'g3/COMMIT.tmp'), FaultMode.crashAfter);
          final r = await runWithFault(m, plan);
          final h = r.h;
          try {
            final newDir = h.gen(kTarget, r.base + 1);
            expect(await h.exists('$newDir/record.json'), isTrue,
                reason: 'the newer generation is complete');
            expect(await h.exists('$newDir/streams.bin'), isTrue);
            expect(await h.exists('$newDir/COMMIT'), isFalse);
            await d.value(h, r.base);
            await h.restart();
            await expectRecovered(h, m, isNew: false, base: r.base, why: d.key);
            expect(
                h.recoveryLog.any((o) =>
                    o.kind == FsOpKind.readBytes &&
                    o.path.contains('/g${r.base + 1}/') &&
                    (o.path.endsWith('record.json') || o.path.endsWith('streams.bin'))),
                isFalse,
                reason: 'the uncommitted generation is never read as a session');
            expect(h.report.deletedGenerations, contains('$kTarget/g${r.base + 1}'));
            await restartTwiceStable(h);
          } finally {
            await h.dispose();
          }
        });
      }
    }
  });

  group('I48 case C: crash after COMMIT, before the CURRENT update', () {
    for (final m in muts) {
      test('mutation ${m.name}: new generation recovered; retry is a single '
          'application', () async {
        final b = await baselineFor(m);
        final variants = <String, (FaultPlan, Future<void> Function(JournalHarness, int))>{
          'CURRENT untouched': (FaultPlan(b.commitIndex, FaultMode.crashAfter), (_, __) async {}),
          'CURRENT temp written, not renamed': (
            FaultPlan(at(b, FsOpKind.close, '/CURRENT.tmp'), FaultMode.crashAfter),
            (_, __) async {}
          ),
          'CURRENT missing': (
            FaultPlan(b.commitIndex, FaultMode.crashAfter),
            (h, _) => h.deleteRawFile('journal/$kTarget/CURRENT')
          ),
        };
        for (final v in variants.entries) {
          final r = await runWithFault(m, v.value.$1);
          final h = r.h;
          final why = '${m.name} ${v.key}';
          try {
            expect(r.completed, isFalse, reason: '$why: not acknowledged');
            expect(h.acks, isEmpty, reason: why);
            await v.value.$2(h, r.base);
            await h.restart();
            await expectRecovered(h, m, isNew: true, base: r.base, why: why);
            expect(h.report.currentRepaired, contains(kTarget), reason: why);
            final entries = await h.journal.list();
            switch (m) {
              case Mut.reedit:
                expect(entries.where((e) => e.id == kTarget), hasLength(1));
                expect((await h.journal.read(kTarget))!.state.synced, isFalse,
                    reason: '$why: re-queued for upload exactly once');
              case Mut.delete:
                expect((await h.journal.listTombstones()).map((e) => e.id), [kTarget]);
              case Mut.synced:
                expect((await h.journal.read(kTarget))!.state.synced, isTrue);
            }
            expect(await h.generations(kTarget), [r.base + 1],
                reason: '$why: old generation gone after the verified read');

            // (i) the acknowledgement was never sent: the caller retries the
            // SAME mutation; the result equals a single application.
            final before = await h.generations(kTarget);
            await applyMutation(h, m);
            expect(await h.generations(kTarget), before,
                reason: '$why: the retry creates no divergent third state');
            final lines = [
              for (final l in await h.indexLines())
                if (l.contains(kTarget)) l,
            ];
            expect(lines, hasLength(1), reason: '$why: one index line, no duplicate');
            if (m == Mut.delete) {
              expect(lines.single, contains('"op":"delete"'));
            }
          } finally {
            await h.dispose();
          }
        }
      });

      test('mutation ${m.name}: acknowledgement sent before the crash, no '
          'retry, same selected generation', () async {
        final b = await baselineFor(m);
        if (m == Mut.delete) return; // no read phase after a delete
        final plan = FaultPlan(b.mutationOps, FaultMode.crashAfter); // in the read
        final r = await runWithFault(m, plan);
        try {
          expect(r.completed, isTrue);
          expect(r.h.acks, [(kTarget, r.base + 1)]);
          await r.h.restart();
          await expectRecovered(r.h, m, isNew: true, base: r.base);
        } finally {
          await r.h.dispose();
        }
      });
    }
  });

  group('I49 case D: CURRENT damaged after a normal commit', () {
    Future<void> leftover(JournalHarness h, int newSeq) async {
      final src = h.gen(kTarget, newSeq);
      final dst = h.gen(kTarget, newSeq + 1);
      await h.writeRaw('$dst/record.json', (await h.bytes('$src/record.json'))!);
      await h.writeRaw('$dst/streams.bin', (await h.bytes('$src/streams.bin'))!);
      await h.writeText('journal/$kTarget/CURRENT',
          jsonEncode({'gen': 'g${newSeq + 1}', 'seq': newSeq + 1}));
    }

    final damages = <String, Future<void> Function(JournalHarness, int)>{
      'deleted': (h, _) => h.deleteRawFile('journal/$kTarget/CURRENT'),
      'zero-length': (h, _) => h.writeRaw('journal/$kTarget/CURRENT', const <int>[]),
      'garbage': (h, _) => h.writeRaw(
          'journal/$kTarget/CURRENT', Uint8List.fromList(List.filled(20, 0xFF))),
      'names a missing directory': (h, _) => h.writeText(
          'journal/$kTarget/CURRENT', jsonEncode({'gen': 'g99', 'seq': 99})),
      'names the older committed generation': (h, newSeq) => h.writeText(
          'journal/$kTarget/CURRENT',
          jsonEncode({'gen': 'g${newSeq - 1}', 'seq': newSeq - 1})),
      'names an uncommitted leftover': leftover,
    };

    for (final m in muts) {
      for (final d in damages.entries) {
        test('mutation ${m.name}, CURRENT ${d.key}', () async {
          final h = JournalHarness.memory();
          try {
            final base = await setupFixture(h);
            await applyMutation(h, m); // normal commit, no read afterwards
            final newSeq = base + 1;
            expect((await h.currentJson(kTarget))!['seq'], newSeq);
            final selectedFiles = {
              for (final f in ['record.json', 'streams.bin', 'COMMIT'])
                f: await h.bytes(h.gen(kTarget, newSeq, f)),
            };
            final otherBefore = await h.snapshot('journal/$kOther');
            await d.value(h, newSeq);
            await h.restart();

            await expectRecovered(h, m, isNew: true, base: base, why: d.key);
            for (final f in selectedFiles.entries) {
              expect(await h.bytes(h.gen(kTarget, newSeq, f.key)), f.value,
                  reason: '${d.key}: ${f.key} unchanged (no data change)');
            }
            expect(await h.snapshot('journal/$kOther'), otherBefore);
            final gens = await h.generations(kTarget);
            expect(gens.every((g) => g <= newSeq), isTrue,
                reason: 'no new generation was created: $gens');
            expect(h.acks.where((a) => a.$2 > newSeq), isEmpty);
            if (m == Mut.synced || m == Mut.reedit) {
              final st = (await h.journal.read(kTarget))!.state;
              expect(st.synced, m == Mut.synced,
                  reason: 'a synced entry is not re-queued; a cleared one stays queued');
            }
            if (m == Mut.delete) {
              expect(await h.listIds(), [kOther], reason: 'a deleted id stays deleted');
            }
            await restartTwiceStable(h);
          } finally {
            await h.dispose();
          }
        });
      }
    }
  });
}
