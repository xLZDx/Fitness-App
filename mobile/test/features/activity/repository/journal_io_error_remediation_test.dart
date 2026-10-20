// S02 remediation B1 (epic 9a): an I/O error is never evidence of "uncommitted",
// "stream lost" or "entry gone". Oracles: docs/phase2/s02/S02_REMEDIATION_B_TEST_NOTES.md
// (B1) and S02_DESIGN.md sections 7 and 17.
//
//  - SF1: recovery keeps committed generations when COMMIT / record.json cannot
//    be read (diagnostic `unreadable:<id>`), and still deletes a genuinely
//    missing or invalid COMMIT.
//  - SF2: a transient key-store or streams.bin failure is never persisted as
//    streamLost; real key loss, a missing streams.bin and a checksum mismatch
//    still are.
//  - SF3: read() keeps the cache entry on an I/O error (JournalIoException) and
//    drops it only on a verified mismatch.
import 'dart:typed_data';

import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';

/// A key provider whose `loadKey` can throw (a key store that does not answer).
class FlakyKeyProvider implements JournalKeyProvider {
  FlakyKeyProvider(this.inner);

  final InMemoryJournalKeyProvider inner;
  bool failLoad = false;

  @override
  Future<Uint8List?> loadKey() async {
    if (failLoad) throw StateError('key store unavailable');
    return inner.loadKey();
  }

  @override
  Future<Uint8List> loadOrCreateKey() => inner.loadOrCreateKey();

  @override
  Future<void> forget() => inner.forget();
}

bool Function(String) onPath(String id, String file) =>
    (p) => p.contains('/$id/') && p.endsWith(file);

void main() {
  final id = idFor(1);

  /// Two committed generations g1, g2 of [id] (no read happened, so no prune).
  Future<JournalHarness> twoGenerations({JournalKeyProvider? keys}) async {
    final h = JournalHarness.memory(keys: keys);
    await h.open();
    await h.journal.put(journalSession(id, seed: 1));
    await h.journal.put(journalSession(id, seed: 2));
    expect(await h.generations(id), [1, 2]);
    return h;
  }

  group('SF1 recovery on a read I/O error keeps committed generations', () {
    for (final file in ['COMMIT', 'record.json']) {
      test('I/O error on $file of the highest generation', () async {
        final h = await twoGenerations();
        addTearDown(h.dispose);
        h.failReadsOnOpen = onPath(id, 'g2/$file');
        final report = await h.restart();
        expect(await h.generations(id), [1, 2],
            reason: 'no generation deleted on an I/O error');
        expect(report.absent, isNot(contains(id)));
        expect(report.diagnostics, contains('unreadable:$id'));
        expect(report.deletedGenerations, isEmpty);

        h.failReadsOnOpen = null;
        final again = await h.restart();
        expect(again.diagnostics, isNot(contains('unreadable:$id')));
        expect(again.selectedGenerations[id], 2,
            reason: 'the newest committed generation is recovered');
        final e = (await h.journal.list()).singleWhere((x) => x.session.id == id);
        expect(e.generation, 2);
      });
    }

    test('a genuinely missing COMMIT deletes only that generation', () async {
      final h = await twoGenerations();
      addTearDown(h.dispose);
      await h.deleteRawFile(h.gen(id, 2, 'COMMIT'));
      final report = await h.restart();
      expect(await h.generations(id), [1]);
      expect(report.deletedGenerations, contains('$id/g2'));
      expect(report.diagnostics, isNot(contains('unreadable:$id')));
      expect(report.selectedGenerations[id], 1);
    });

    test('an invalid COMMIT marker deletes only that generation', () async {
      final h = await twoGenerations();
      addTearDown(h.dispose);
      await h.writeText(h.gen(id, 2, 'COMMIT'), 'garbage');
      final report = await h.restart();
      expect(await h.generations(id), [1]);
      expect(report.deletedGenerations, contains('$id/g2'));
      expect(report.selectedGenerations[id], 1);
    });
  });

  group('SF2 transient failures are never persisted as streamLost', () {
    Future<JournalHarness> oneEntry(JournalKeyProvider keys) async {
      final h = JournalHarness.memory(keys: keys);
      await h.open();
      await h.journal.put(journalSession(id, seed: 1));
      await h.restart(); // a fresh instance reads what is on disk
      return h;
    }

    test('loadKey throws once: metadata edit does not persist streamLost',
        () async {
      final keys = FlakyKeyProvider(InMemoryJournalKeyProvider(fixedJournalKey()));
      final h = await oneEntry(keys);
      addTearDown(h.dispose);
      keys.failLoad = true;
      final r1 = (await h.journal.read(id))!;
      expect(r1.streamsLoaded, isFalse);
      expect(await h.journal.updateSyncState(id, JournalSyncState.synced), isTrue);
      keys.failLoad = false;
      final r2 = (await h.journal.read(id))!;
      expect(r2.streamsLoaded, isTrue);
      expect(r2.state.streamLost, isFalse);
      expect(r2.state.syncState, JournalSyncState.synced,
          reason: 'the metadata edit itself was applied');
      expect(h.journal.streamLostCount, 0);
    });

    test('real key loss (loadKey null) persists streamLost in a new generation',
        () async {
      final keys = InMemoryJournalKeyProvider(fixedJournalKey());
      final h = await oneEntry(keys);
      addTearDown(h.dispose);
      await keys.forget();
      final r = (await h.journal.read(id))!;
      expect(r.streamsLoaded, isFalse);
      expect(r.state.streamLost, isTrue);
      await h.restart();
      final e = (await h.journal.list()).singleWhere((x) => x.session.id == id);
      expect(e.state.streamLost, isTrue, reason: 'persisted across restart');
      expect(e.generation, greaterThan(1), reason: 'written as a new generation');
    });

    test('streams.bin I/O error on read: not persisted, recovers afterwards',
        () async {
      final h = await oneEntry(InMemoryJournalKeyProvider(fixedJournalKey()));
      addTearDown(h.dispose);
      h.fs.failReadWhen = onPath(id, 'streams.bin');
      final r1 = (await h.journal.read(id))!;
      expect(r1.streamsLoaded, isFalse);
      // A metadata edit while streams.bin cannot be read must abort, not
      // write a streamLost generation.
      await expectLater(
          h.journal.updateSyncState(id, JournalSyncState.synced),
          throwsA(isA<JournalIoException>()));
      expect(await h.generations(id), [1], reason: 'nothing persisted');
      h.fs.failReadWhen = null;
      final r2 = (await h.journal.read(id))!;
      expect(r2.streamsLoaded, isTrue);
      expect(r2.state.streamLost, isFalse);
      await h.restart();
      final e = (await h.journal.list()).single;
      expect(e.state.streamLost, isFalse);
    });

    test('missing streams.bin is stream-lost and persisted by the next edit',
        () async {
      final h = await oneEntry(InMemoryJournalKeyProvider(fixedJournalKey()));
      addTearDown(h.dispose);
      await h.deleteRawFile(h.gen(id, 1, 'streams.bin'));
      final r = (await h.journal.read(id))!;
      expect(r.streamsLoaded, isFalse);
      expect(r.state.streamLost, isTrue);
      await h.journal.updateSyncState(id, JournalSyncState.synced);
      await h.restart();
      final e = (await h.journal.list()).single;
      expect(e.state.streamLost, isTrue);
      expect(e.state.syncState, JournalSyncState.synced);
    });

    test('checksum mismatch is stream-lost and persisted by the next edit',
        () async {
      final h = await oneEntry(InMemoryJournalKeyProvider(fixedJournalKey()));
      addTearDown(h.dispose);
      await h.flipBit(h.gen(id, 1, 'streams.bin'));
      final r = (await h.journal.read(id))!;
      expect(r.streamsLoaded, isFalse);
      expect(r.state.streamLost, isTrue);
      await h.journal.updateSyncState(id, JournalSyncState.synced);
      await h.restart();
      final e = (await h.journal.list()).single;
      expect(e.state.streamLost, isTrue);
    });

    test('recovery: streams.bin I/O error is not stream-lost, older kept',
        () async {
      final h = await twoGenerations();
      addTearDown(h.dispose);
      h.failReadsOnOpen = onPath(id, 'g2/streams.bin');
      final report = await h.restart();
      expect(report.streamLost, isNot(contains(id)));
      expect(report.diagnostics, contains('streamsUnreadable:$id'));
      expect(report.selectedGenerations[id], 2);
      expect(await h.generations(id), [1, 2], reason: 'older generation kept');
      expect(h.journal.streamLostCount, 0);
      final e = (await h.journal.list()).single;
      expect(e.state.streamLost, isFalse);
    });

    test('recovery: checksum mismatch of streams.bin is still stream-lost',
        () async {
      final h = await twoGenerations();
      addTearDown(h.dispose);
      await h.flipBit(h.gen(id, 2, 'streams.bin'));
      final report = await h.restart();
      expect(report.streamLost, contains(id));
      expect(h.journal.streamLostCount, 1);
    });
  });

  group('SF3 read keeps the cache entry on an I/O error', () {
    Future<JournalHarness> withBase() async {
      final h = JournalHarness.memory();
      await h.open();
      await h.journal.put(journalSession(id, seed: 1),
          syncState: JournalSyncState.synced,
          baseRev: 7,
          baseSummary: {'distanceM': 4800});
      await h.restart();
      return h;
    }

    for (final file in ['record.json', 'COMMIT']) {
      test('I/O error on $file: JournalIoException, entry kept, put keeps base',
          () async {
        final h = await withBase();
        addTearDown(h.dispose);
        h.fs.failReadWhen = onPath(id, file);
        await expectLater(h.journal.read(id), throwsA(isA<JournalIoException>()));
        expect((await h.journal.list()).map((e) => e.session.id), contains(id));
        h.fs.failReadWhen = null;
        final put = await h.journal.put(journalSession(id, seed: 2));
        expect(put.state.baseRev, 7, reason: 'previous entry still known');
        expect(put.state.baseSummary, {'distanceM': 4800});
        final r = (await h.journal.read(id))!;
        expect(r.streamsLoaded, isTrue);
        expect(r.state.baseRev, 7);
      });

      test('after the $file fault is removed read succeeds with synced state',
          () async {
        final h = await withBase();
        addTearDown(h.dispose);
        h.fs.failReadWhen = onPath(id, file);
        await expectLater(h.journal.read(id), throwsA(isA<JournalIoException>()));
        h.fs.failReadWhen = null;
        final r = (await h.journal.read(id))!;
        expect(r.streamsLoaded, isTrue);
        expect(r.state.syncState, JournalSyncState.synced);
      });
    }

    for (final c in <String, Future<void> Function(JournalHarness)>{
      'deleted COMMIT': (h) => h.deleteRawFile(h.gen(id, 1, 'COMMIT')),
      'deleted record.json': (h) => h.deleteRawFile(h.gen(id, 1, 'record.json')),
      'record hash differs from the marker': (h) =>
          h.flipBit(h.gen(id, 1, 'record.json')),
    }.entries) {
      test('${c.key}: read returns null and the entry is dropped', () async {
        final h = await withBase();
        addTearDown(h.dispose);
        await c.value(h);
        expect(await h.journal.read(id), isNull);
        expect(await h.journal.list(), isEmpty);
      });
    }
  });
}
