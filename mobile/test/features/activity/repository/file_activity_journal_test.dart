// S02-02 I01, I06, I18, I23: the file journal against the real `dart:io` file
// system (I01, I06) and the in-memory seam (I18, I23).
import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_app/features/activity/data/native_session_id.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/synthetic_activity_corpus.dart';

void main() {
  group('I01 round trip of the 100 corpus sessions on real files', () {
    late Directory tmp;
    late JournalHarness h;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('s02_i01_');
      h = JournalHarness.onDisk(tmp);
      await h.open();
    });

    tearDown(() async {
      await h.dispose();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('every session reads back identical, list() counts 100, a restart '
        'changes nothing', () async {
      final corpus = SyntheticCorpus.build().valid;
      expect(corpus.map((s) => s.id).toSet(), hasLength(100),
          reason: 'the corpus itself must hold 100 distinct ids');

      for (final s in corpus) {
        final e = await h.journal.put(s);
        expect(e.streamsLoaded, isTrue);
      }
      expect((await h.journal.list()).length, 100);

      Future<void> verify(String when) async {
        final listed = await h.journal.list();
        expect(listed.length, 100, reason: when);
        expect([for (final e in listed) e.id], [for (final s in corpus) s.id],
            reason: '$when: list() is in mutation (sequence) order');
        for (final s in corpus) {
          final back = await h.journal.read(s.id);
          expect(back, isNotNull, reason: '$when ${s.id}');
          expect(back!.streamLost, isFalse, reason: '$when ${s.id}');
          expect(back.streamsLoaded, isTrue, reason: '$when ${s.id}');
          expect(sessionJson(back.session), sessionJson(s),
              reason: '$when ${s.id}: stored JSON differs');
          expect(streamsOf(back.session), streamsOf(s),
              reason: '$when ${s.id}: streams differ sample by sample');
          expect(back.session.laps.length, s.laps.length, reason: '$when ${s.id}');
          expect(back.session.provenance.length, s.provenance.length,
              reason: '$when ${s.id}');
        }
      }

      await verify('before restart');
      await h.restart();
      await verify('after restart');
    }, timeout: const Timeout(Duration(minutes: 8)));

    test('the list is WITHOUT streams while read() carries them', () async {
      final s = SyntheticCorpus.build().valid.firstWhere((x) => x.streams.isNotEmpty);
      await h.journal.put(s);
      final listed = (await h.journal.list()).single;
      expect(listed.streamsLoaded, isFalse);
      expect(listed.session.streams, isEmpty);
      final full = (await h.journal.read(s.id))!;
      expect(full.session.streams, isNotEmpty);
    });
  });

  group('I06 replay of the same recording is one session', () {
    late Directory tmp;
    late JournalHarness h;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('s02_i06_');
      h = JournalHarness.onDisk(tmp);
      await h.open();
    });

    tearDown(() async {
      await h.dispose();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('two imports of one recording uuid produce one directory, one live '
        'entry and no new generation', () async {
      const uuid = '3f2b8c1e-5d4a-4e0b-9a77-0c1d2e3f4a5b';
      final id1 = nativeActivityId(uuid);
      final id2 = nativeActivityId(uuid);
      expect(id1, id2, reason: 'the id rule must be deterministic');

      final first = await h.journal.put(journalSession(id1));
      // The replay builds a NEW, equal object (a re-import, not the same instance).
      final replay = await h.journal.put(journalSession(id2));

      expect(replay.generation, first.generation,
          reason: 'an identical replay must not create a generation');
      expect(await h.generations(id1), [first.generation]);
      final dirs = (await h.names('journal'))
          .where((n) => n != 'index.jsonl')
          .toList();
      expect(dirs, [id1], reason: 'one activity directory only');
      expect(await h.listIds(), [id1]);
      final putLines = [
        for (final l in await h.indexLines())
          if (l.contains(id1)) l,
      ];
      expect(putLines, hasLength(1),
          reason: 'the replay must not append a second index line');
      expect(h.acks, hasLength(1), reason: 'no second acknowledged mutation');
    });

    test('a replay after a restart is still one session; a changed '
        'recording is a new generation of the SAME directory', () async {
      final id = nativeActivityId('uuid-restart-1');
      await h.journal.put(journalSession(id));
      await h.restart();
      final replay = await h.journal.put(journalSession(id));
      expect(await h.listIds(), [id]);
      expect(await h.generations(id), [replay.generation]);

      final changed = await h.journal.put(journalSession(id, seed: 3));
      expect(changed.generation, greaterThan(replay.generation));
      expect(await h.listIds(), [id]);
      final dirs = (await h.names('journal'))
          .where((n) => n != 'index.jsonl')
          .toList();
      expect(dirs, [id]);
    });

    test('a different recording uuid is a different session', () async {
      await h.journal.put(journalSession(nativeActivityId('uuid-a')));
      await h.journal.put(journalSession(nativeActivityId('uuid-b')));
      expect((await h.listIds()).length, 2);
    });
  });

  group('I18 corrupt local files are tolerated', () {
    late JournalHarness h;
    final a = idFor(1), b = idFor(2), c = idFor(3);

    setUp(() async {
      h = JournalHarness.memory();
      await h.open();
      await h.journal.put(journalSession(a, seed: 1));
      await h.journal.put(journalSession(b, seed: 2));
      await h.journal.put(journalSession(c, seed: 3));
    });

    tearDown(() => h.dispose());

    Future<void> expectOthersIntact(JournalHarness h, List<String> ids) async {
      for (final id in ids) {
        final e = await h.journal.read(id);
        expect(e, isNotNull, reason: id);
        expect(e!.streamLost, isFalse, reason: id);
        expect(streamsOf(e.session), isNotEmpty, reason: id);
      }
    }

    final recordDamages = <String, List<int> Function(Uint8List)>{
      'zero-length record.json': (_) => <int>[],
      'garbage record.json': (_) => List<int>.generate(64, (i) => (i * 37 + 11) & 0xFF),
      'truncated record.json': (b) => b.sublist(0, b.length ~/ 2),
    };

    for (final entry in recordDamages.entries) {
      test('${entry.key}: other sessions stay listed, the damaged one is '
          'skipped with a diagnostic, nothing throws (restart)', () async {
        final rel = h.gen(b, 2, 'record.json');
        final orig = (await h.bytes(rel))!;
        await h.writeRaw(rel, entry.value(orig));
        final report = await h.restart();

        expect(await h.listIds(), [a, c]);
        expect(report.absent, {b}, reason: 'the damaged session is reported');
        await expectOthersIntact(h, [a, c]);
        expect(await h.journal.read(b), isNull);
      });

      test('${entry.key} appearing while the app runs: list() and read() '
          'do not throw and other sessions are readable', () async {
        final rel = h.gen(b, 2, 'record.json');
        final orig = (await h.bytes(rel))!;
        await h.writeRaw(rel, entry.value(orig));

        expect((await h.journal.list()).length, 3,
            reason: 'list() serves the in-memory index and must not crash');
        expect(await h.journal.read(b), isNull,
            reason: 'a record failing its COMMIT checksum is not served');
        await expectOthersIntact(h, [a, c]);
        // The damaged entry left the live set; the others remain.
        expect(await h.listIds(), [a, c]);
      });
    }

    for (final damage in ['flip', 'truncate', 'empty']) {
      test('corrupt streams.bin ($damage): the session is listed as stream '
          'unavailable with summary intact; others untouched', () async {
        final rel = h.gen(b, 2, 'streams.bin');
        final orig = (await h.bytes(rel))!;
        switch (damage) {
          case 'flip':
            await h.flipBit(rel, orig.length ~/ 2);
          case 'truncate':
            await h.writeRaw(rel, orig.sublist(0, orig.length ~/ 2));
          default:
            await h.writeRaw(rel, const <int>[]);
        }
        final report = await h.restart();

        expect(report.streamLost, {b});
        expect(await h.listIds(), [a, b, c]);
        final lost = (await h.journal.read(b))!;
        expect(lost.streamLost, isTrue);
        expect(lost.streamsLoaded, isFalse);
        expect(lost.session.summary.distanceM, 4800,
            reason: 'summary metadata stays readable');
        expect(lost.session.provenance, isNotEmpty);
        expect(h.journal.streamLostCount, 1);
        await expectOthersIntact(h, [a, c]);
      });
    }

    test('a damaged index does not hide any session', () async {
      await h.writeText('journal/index.jsonl', '\u0000\u0001 not json\n{"half"');
      await h.restart();
      expect(await h.listIds(), [a, b, c]);
    });
  });

  group('I23 monotonic ordering independent of the clock', () {
    late JournalHarness h;

    setUp(() async {
      h = JournalHarness.memory();
      await h.open();
    });

    tearDown(() => h.dispose());

    test('moving the clock back a day and forward ten years does not '
        'reorder mutations; start times in reverse do not either', () async {
      final ids = [idFor(1), idFor(2), idFor(3)];
      // Later mutations carry EARLIER start times: ordering by session time
      // would reverse the list.
      final e1 = await h.journal.put(journalSession(ids[0], seed: 5));
      h.clock.advance(const Duration(days: -1));
      final e2 = await h.journal.put(journalSession(ids[1], seed: 3));
      h.clock.advance(const Duration(days: 3650 + 1));
      final e3 = await h.journal.put(journalSession(ids[2], seed: 1));

      expect(await h.listIds(), ids);
      expect(e2.generation, greaterThan(e1.generation));
      expect(e3.generation, greaterThan(e2.generation));

      // A later mutation of the FIRST activity moves it to the end, whatever
      // the clock says.
      h.clock.set(DateTime.utc(1999, 1, 1));
      final e1b = await h.journal.put(journalSession(ids[0], seed: 6));
      expect(e1b.generation, greaterThan(e3.generation));
      expect(await h.listIds(), [ids[1], ids[2], ids[0]]);

      final seqs = [
        for (final line in await h.indexLines()) _seqOf(line),
      ];
      expect(seqs, orderedEquals([...seqs]..sort()));
      expect(seqs.toSet().length, seqs.length, reason: 'sequence numbers are unique');
    });

    test('sequence numbers keep increasing across a restart even when the '
        'clock is far in the past', () async {
      final e1 = await h.journal.put(journalSession(idFor(1)));
      final e2 = await h.journal.put(journalSession(idFor(2), seed: 1));
      h.clock.set(DateTime.utc(1990, 1, 1));
      await h.restart();
      final e3 = await h.journal.put(journalSession(idFor(3), seed: 2));
      expect(e3.generation, greaterThan(e2.generation));
      expect(e2.generation, greaterThan(e1.generation));
      await h.restart();
      expect(await h.listIds(), [idFor(1), idFor(2), idFor(3)]);
    });

    test('the highest sequence survives a restart even when its activity '
        'was deleted (tombstone), so a number is never reused', () async {
      await h.journal.put(journalSession(idFor(1)));
      await h.journal.put(journalSession(idFor(2), seed: 1));
      await h.journal.delete(idFor(2));
      final tomb = (await h.journal.listTombstones()).single;
      await h.restart();
      final e = await h.journal.put(journalSession(idFor(3), seed: 2));
      expect(e.generation, greaterThan(tomb.generation));
    });
  });
}

int _seqOf(String line) {
  final m = RegExp(r'"seq":(\d+)').firstMatch(line)!;
  return int.parse(m.group(1)!);
}
