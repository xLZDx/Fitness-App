// S02-02 I20, I21: fault injection at EVERY operation of a mutation, and the
// single-writer rule.
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_crash_matrix.dart';
import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart';

void main() {
  group('I20 fault injection at every step', () {
    for (final m in Mut.values) {
      test('mutation ${m.name}: crash after, error after, failure instead and '
          '"no space left" at every operation', () async {
        final b = await baselineFor(m);
        if (m == Mut.reedit) {
          expect(b.mutationOps, 32,
              reason: 'the I19 log of one put has 32 operations');
        }
        if (m != Mut.delete) {
          expect(b.total, greaterThan(b.mutationOps),
              reason: 'the read after the put (old-generation delete) is part of the points');
        }
        var injected = 0;
        for (var k = 0; k < b.total; k++) {
          for (final mode in FaultMode.values) {
            final plan = FaultPlan(k, mode);
            final r = await runWithFault(m, plan);
            final why = '${m.name} $plan';
            try {
              expect(r.h.fs.fired, isTrue, reason: '$why: the injection happened');
              injected++;
              final isNew = newExpected(plan, b);
              if (k < b.mutationOps) {
                if (mode == FaultMode.crashAfter) {
                  expect(r.error, isA<SimulatedCrash>(), reason: why);
                  expect(r.completed, isFalse, reason: why);
                  expect(r.h.acks, isEmpty, reason: '$why: no acknowledgement');
                } else if (isNew) {
                  expect(r.completed, isTrue,
                      reason: '$why: committed, later failures are cache failures');
                  expect(r.h.acks, hasLength(1), reason: why);
                } else {
                  expect(r.completed, isFalse, reason: why);
                  expectTypedAbort(r, m,
                      onRead: b.log.firstWhere((o) => o.index == k).kind == FsOpKind.readBytes);
                  expect(r.h.acks, isEmpty, reason: why);
                  // The same process still sees the previous pair.
                  expect(await r.h.listIds(), contains(kTarget), reason: why);
                }
              } else {
                expect(r.completed, isTrue, reason: '$why: acknowledged earlier');
              }
              await r.h.restart();
              await expectRecovered(r.h, m,
                  isNew: isNew, base: r.base, why: why);
            } finally {
              await r.h.dispose();
            }
          }
        }
        expect(injected, b.total * FaultMode.values.length,
            reason: 'an unexercised step fails');
      }, timeout: const Timeout(Duration(minutes: 10)));
    }

    test('control: with no fault the same put succeeds and is the new pair',
        () async {
      final r = await runWithFault(Mut.reedit, const FaultPlan(100000, FaultMode.failAt));
      try {
        expect(r.h.fs.fired, isFalse);
        expect(r.completed, isTrue);
        await r.h.restart();
        await expectRecovered(r.h, Mut.reedit, isNew: true, base: r.base);
      } finally {
        await r.h.dispose();
      }
    });

    test('a failed put is retried with the same input after the disk frees up',
        () async {
      final b = await baselineFor(Mut.reedit);
      final r = await runWithFault(
          Mut.reedit, FaultPlan(b.commitIndex - 3, FaultMode.diskFullAt));
      try {
        expect(r.error, isA<JournalStorageFullException>());
        await applyMutation(r.h, Mut.reedit); // fault already fired
        final e = (await r.h.journal.read(kTarget))!;
        expect(sessionJson(e.session), sessionJson(r2()));
        expect(e.generation, greaterThan(r.base + 1),
            reason: 'the failed attempt consumed a number; numbers never repeat');
      } finally {
        await r.h.dispose();
      }
    });
  });

  group('I21 single writer', () {
    late JournalHarness h;

    setUp(() async {
      h = JournalHarness.memory();
      await h.open();
    });

    tearDown(() => h.dispose());

    test('concurrent puts of different activities never interleave their '
        'file steps', () async {
      await Future.wait([
        for (var i = 1; i <= 4; i++) h.journal.put(journalSession(idFor(i), seed: i)),
      ]);
      final segments = <Set<String>>[{}];
      for (final o in h.fs.log) {
        if (o.kind == FsOpKind.note) {
          segments.add({});
          continue;
        }
        final m = RegExp(r'/journal/([^/]+)/').firstMatch(o.path);
        if (m != null) segments.last.add(m.group(1)!);
      }
      for (final s in segments.where((s) => s.isNotEmpty)) {
        expect(s, hasLength(1), reason: 'one mutation = one activity per segment: $s');
      }
      expect(h.acks.map((a) => a.$1).toSet(), hasLength(4));
      expect((await h.listIds()).toSet(), {for (var i = 1; i <= 4; i++) idFor(i)});
    });

    test('two concurrent puts of one id end in the serial order of the calls',
        () async {
      final id = idFor(1);
      await Future.wait([
        h.journal.put(journalSession(id, seed: 1)),
        h.journal.put(journalSession(id, seed: 2)),
      ]);
      final e = (await h.journal.read(id))!;
      expect(sessionJson(e.session), sessionJson(journalSession(id, seed: 2)));
      await h.restart();
      expect(sessionJson((await h.journal.read(id))!.session),
          sessionJson(journalSession(id, seed: 2)));
    });

    test('put and delete of one id: delete first wins, put first is deleted',
        () async {
      final id = idFor(1);
      await Future.wait([
        h.journal.put(journalSession(id)),
        h.journal.delete(id),
      ]);
      expect(await h.listIds(), isEmpty);
      expect((await h.journal.listTombstones()).map((e) => e.id), [id]);

      final id2 = idFor(2);
      final put = h.journal.put(journalSession(id2));
      await h.journal.delete(id2);
      await put;
      expect(await h.listIds(), isEmpty);

      final id3 = idFor(3);
      final del = h.journal.delete(id3);
      await expectLater(h.journal.put(journalSession(id3)),
          throwsA(isA<JournalTombstonedException>()));
      await del;
    });

    test('a second instance on the same directory is refused until the first '
        'is closed (cross-process writers are unsupported)', () async {
      final second = FileActivityJournal(
          rootPath: h.root, fileSystem: h.delegate, keyProvider: h.keys);
      await expectLater(second.start(), throwsA(isA<JournalAlreadyOpenException>()));
      await h.journal.close();
      await second.start();
      await second.put(journalSession(idFor(1)));
      await second.close();
    });

    test('a journal used before start or after close refuses the call', () async {
      final j = FileActivityJournal(
          rootPath: '${h.root}x', fileSystem: h.delegate, keyProvider: h.keys);
      await expectLater(j.list(), throwsA(isA<JournalNotStartedException>()));
      await h.journal.close();
      await expectLater(
          h.journal.put(journalSession(idFor(1))), throwsA(isA<JournalNotStartedException>()));
    });
  });
}
