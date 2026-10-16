// S02-02 I07 (084: no plaintext coordinates at rest) and I24 (design 3.5 key
// loss).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';

bool containsSeq(List<int> hay, List<int> needle) {
  if (needle.isEmpty || hay.length < needle.length) return false;
  for (var i = 0; i <= hay.length - needle.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

List<int> f64(double v, Endian e) =>
    (ByteData(8)..setFloat64(0, v, e)).buffer.asUint8List().toList();

void main() {
  group('I07 no plaintext coordinates at rest', () {
    late Directory tmp;
    late JournalHarness h;
    final id = idFor(1);

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('s02_i07_');
      h = JournalHarness.onDisk(tmp);
      await h.open();
    });

    tearDown(() async {
      await h.dispose();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('streams.bin holds neither the 7351 tail, the latitude text, nor its '
        'float64 bytes; a positive control proves the grep can find them',
        () async {
      final s = journalSession(id, seed: 4, samples: 60);
      await h.journal.put(s);
      final bytes = (await h.bytes(h.gen(id, 1, 'streams.bin')))!;
      final lats = s.streams.values.firstWhere((x) => x.lats.isNotEmpty).lats;
      final hr = s.streams.values.firstWhere((x) => x.values.isNotEmpty).values;

      // Positive control: the unencrypted document contains every pattern.
      final plain = utf8.encode(jsonEncode({
        'streams': [for (final x in s.streams.values) x.toJson()],
      }));
      expect(containsSeq(plain, ascii.encode('7351')), isTrue);
      expect(containsSeq(plain, ascii.encode(lats.first.toString())), isTrue);
      final raw = BytesBuilder();
      for (final v in lats) {
        raw.add(f64(v, Endian.little));
      }
      expect(containsSeq(raw.toBytes(), f64(lats[3], Endian.little)), isTrue);

      expect(containsSeq(bytes, ascii.encode('7351')), isFalse,
          reason: 'the ASCII tail of the sentinel latitude');
      for (final v in lats) {
        expect(containsSeq(bytes, ascii.encode(v.toString())), isFalse);
        expect(containsSeq(bytes, f64(v, Endian.little)), isFalse);
        expect(containsSeq(bytes, f64(v, Endian.big)), isFalse);
      }
      for (final v in hr.take(10)) {
        expect(containsSeq(bytes, ascii.encode(v.toString())), isFalse);
        expect(containsSeq(bytes, f64(v, Endian.little)), isFalse);
      }
      expect(containsSeq(bytes, ascii.encode('"lats"')), isFalse);
      expect(containsSeq(bytes, const [0x1F, 0x8B]), isFalse,
          reason: 'not even a gzip header is visible');
      expect(bytes.sublist(0, 4), AesGcmJournalCipher.magic);
    });

    test('no other journal file carries a coordinate or heart-rate sample '
        '(record.json, COMMIT, CURRENT, index)', () async {
      final s = journalSession(id, seed: 4, samples: 60);
      await h.journal.put(s);
      for (final f in ['record.json', 'COMMIT']) {
        final text = utf8.decode((await h.bytes(h.gen(id, 1, f)))!)
            .replaceAll(RegExp(r'[0-9a-f]{64}'), '');
        expect(text.contains('7351'), isFalse, reason: f);
        expect(text.contains('"lats"'), isFalse, reason: f);
        expect(text.contains('"offsetsMs"'), isFalse, reason: f);
      }
      for (final f in ['journal/$id/CURRENT', 'journal/index.jsonl']) {
        expect(utf8.decode((await h.bytes(f))!).contains('7351'), isFalse, reason: f);
      }
    });

    test('a wrong key does not open the file; one flipped ciphertext byte is '
        'detected by the GCM tag', () async {
      await h.journal.put(journalSession(id, seed: 4, samples: 60));
      final bytes = (await h.bytes(h.gen(id, 1, 'streams.bin')))!;
      expect(() => AesGcmJournalCipher(fixedJournalKey()).open(bytes), returnsNormally);
      expect(() => AesGcmJournalCipher(fixedJournalKey(77)).open(bytes),
          throwsA(isA<JournalDecryptFailure>()));
      for (final off in [4, 20, bytes.length ~/ 2, bytes.length - 1]) {
        final bad = Uint8List.fromList(bytes)..[off] ^= 0x01;
        expect(() => AesGcmJournalCipher(fixedJournalKey()).open(bad),
            throwsA(isA<JournalDecryptFailure>()),
            reason: 'flip at $off');
      }
    });

    test('two seals of the same plaintext differ (fresh IV)', () {
      final c = AesGcmJournalCipher(fixedJournalKey());
      final p = Uint8List.fromList(List<int>.filled(64, 7));
      expect(c.seal(p), isNot(c.seal(p)));
    });
  });

  group('I24 key loss', () {
    late FakeJournalSecureStorage storage;
    late JournalHarness h;
    final a = idFor(1), b = idFor(2);

    setUp(() async {
      storage = FakeJournalSecureStorage();
      h = JournalHarness.memory(
          keys: SecureStorageJournalKeyProvider(storage: storage));
      await h.open();
      await h.journal.put(journalSession(a, seed: 1));
      await h.journal.put(journalSession(b, seed: 2));
      expect(storage.values, contains(SecureStorageJournalKeyProvider.keyName));
    });

    tearDown(() => h.dispose());

    test('the key is gone: no throw, nothing wiped, every record readable '
        'without streams, streamLost persisted in a NEW generation, counter '
        'incremented, stream-unavailable state surfaced', () async {
      storage.values.clear();
      h.keys = SecureStorageJournalKeyProvider(storage: storage);
      final filesBefore = (await h.snapshot()).length;
      await h.restart();

      expect(await h.listIds(), [a, b]);
      final e = (await h.journal.read(a))!;
      expect(e.streamLost, isTrue);
      expect(e.streamsLoaded, isFalse);
      expect(e.session.summary.distanceM, 4800);
      expect(e.session.provenance, isNotEmpty);
      expect(e.session.streams, isEmpty);
      expect(h.journal.streamLostCount, 1, reason: 'counter incremented');

      final gens = await h.generations(a);
      expect(gens.last, greaterThan(1), reason: 'a NEW generation was written');
      final rec = await h.recordJson(a, gens.last);
      expect((rec['state'] as Map)['streamLost'], isTrue);
      expect((await h.snapshot()).length, greaterThanOrEqualTo(filesBefore),
          reason: 'nothing was wiped');

      // The other record fails the same way but loses nothing.
      final eb = (await h.journal.read(b))!;
      expect(eb.streamLost, isTrue);
      expect(eb.session.summary.distanceM, 4800);
      expect(h.journal.streamLostCount, 2);

      // The flag survives a restart (it lives in record.json).
      await h.restart();
      expect(h.journal.streamLostCount, 2);
      expect((await h.journal.list()).length, 2);
      expect((await h.journal.read(a))!.streamLost, isTrue);
    });

    test('a streams.bin that cannot be decrypted marks only that record; '
        'the other keeps its streams', () async {
      final other = AesGcmJournalCipher(fixedJournalKey(99));
      final fake = other.seal(Uint8List.fromList(gzip.encode(utf8.encode('{"streams":[]}'))));
      final sha = sha256.convert(fake).toString();
      await h.writeRaw(h.gen(a, 1, 'streams.bin'), fake);
      final rec = jsonDecode(utf8.decode((await h.bytes(h.gen(a, 1, 'record.json')))!))
          as Map<String, dynamic>;
      rec['streamHash'] = sha;
      final recBytes = utf8.encode(jsonEncode(rec));
      await h.writeRaw(h.gen(a, 1, 'record.json'), recBytes);
      final c = (await h.commitJson(a, 1))!
        ..['record'] = sha256.convert(recBytes).toString()
        ..['streams'] = sha;
      await h.writeText(h.gen(a, 1, 'COMMIT'), jsonEncode(c));
      await h.restart();

      expect(h.report.streamLost, isEmpty, reason: 'checksums are consistent');
      final ea = (await h.journal.read(a))!;
      expect(ea.streamLost, isTrue);
      expect(ea.session.summary.distanceM, 4800);
      final eb = (await h.journal.read(b))!;
      expect(eb.streamLost, isFalse);
      expect(streamsOf(eb.session), streamsOf(journalSession(b, seed: 2)));
      expect(h.journal.streamLostCount, 1);
      final rec2 = await h.recordJson(a, (await h.generations(a)).last);
      expect((rec2['state'] as Map)['streamLost'], isTrue);
    });

    test('a transient secure-storage failure never mints a new key and marks '
        'nothing as persistently lost', () async {
      storage.failReads = true;
      h.keys = SecureStorageJournalKeyProvider(storage: storage);
      await h.restart();
      final writesBefore = storage.writes;
      final e = (await h.journal.read(a))!;
      expect(e.streamLost, isTrue, reason: 'unavailable right now');
      await expectLater(h.journal.put(journalSession(idFor(9), seed: 9)),
          throwsA(isA<JournalKeyUnavailable>()));
      expect(storage.writes, writesBefore, reason: 'no key was minted');
      expect(storage.values.length, 1);
      expect(await h.generations(a), [1], reason: 'no streamLost generation');

      storage.failReads = false;
      h.keys = SecureStorageJournalKeyProvider(storage: storage);
      await h.restart();
      final back = (await h.journal.read(a))!;
      expect(back.streamLost, isFalse);
      expect(streamsOf(back.session), streamsOf(journalSession(a, seed: 1)));
    });

    test('a COMMITTED generation with a missing streams.bin starts as '
        'streamLost, not dropped; an uncommitted one is absent instead',
        () async {
      await h.deleteRawFile(h.gen(a, 1, 'streams.bin'));
      await h.restart();
      expect(h.report.streamLost, {a});
      expect(h.report.absent, isEmpty);
      expect(await h.listIds(), [a, b]);
      expect(h.journal.streamLostCount, 1);
      final e = (await h.journal.read(a))!;
      expect(e.streamLost, isTrue);
      expect(e.session.summary.distanceM, 4800);
    });

    test('no re-download and no hydrate: with a cloud copy available a sync '
        'pass calls only the summary operations and streamLost stays set',
        () async {
      await h.deleteRawFile(h.gen(a, 1, 'streams.bin'));
      await h.restart();
      final backend = FakeSummaryBackend();
      final repo = ActivitySyncRepository(
          journal: h.journal, backend: backend, clock: h.clock.call);
      final out = await repo.syncAll();
      await repo.dispose();
      expect(out[a], isNot(SyncOutcome.notFound));
      expect(backend.calls.toSet().difference({
        'readSummary',
        'writeSummary',
        'tombstoneExists',
        'listTombstoneIds',
      }), isEmpty, reason: 'the backend seam has no download surface');
      final e = (await h.journal.read(a))!;
      expect(e.streamLost, isTrue);
      expect(e.streamsLoaded, isFalse);
      await h.restart();
      expect(h.journal.streamLostCount, greaterThanOrEqualTo(1));
      expect((await h.journal.read(a))!.streamLost, isTrue);
    });
  });
}
