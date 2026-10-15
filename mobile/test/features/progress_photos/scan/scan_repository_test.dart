// C14: LocalScanRepository resolves the signed-in account's store lazily.
// Signed out means "no scans" for reads and a loud error for writes, never a
// silent drop.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress_photos/data/aes_photo_cipher.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_store.dart';

ScanRecord _rec(String id, DateTime at) =>
    ScanRecord(id: id, createdAt: at, shots: const {});

void main() {
  late Directory dir;
  late ScanStore store;
  late int resolved;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scan_repo_test');
    store = ScanStore(dir: dir, cipher: AesPhotoCipher(AesPhotoCipher.newKey()));
    resolved = 0;
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('signed in', () {
    LocalScanRepository repo() => LocalScanRepository(() async {
          resolved++;
          return store;
        });

    test('save, list (newest first) and delete go through the store', () async {
      final r = repo();
      await r.save(_rec('old', DateTime.utc(2026, 1, 1)));
      await r.save(_rec('new', DateTime.utc(2026, 2, 1)));
      expect((await r.list()).map((e) => e.id), ['new', 'old']);
      await r.delete('old');
      expect((await r.list()).map((e) => e.id), ['new']);
      expect((await store.list()).map((e) => e.id), ['new']);
    });

    test('the store is resolved on every call, not cached', () async {
      final r = repo();
      await r.list();
      await r.list();
      expect(resolved, 2);
    });

    test('an unsafe id is refused by the store and surfaces', () async {
      await expectLater(
          repo().save(_rec('../evil', DateTime.utc(2026, 1, 1))), throwsArgumentError);
    });
  });

  group('signed out (store resolves to null)', () {
    final r = LocalScanRepository(() async => null);

    test('list is empty, never an error', () async {
      expect(await r.list(), isEmpty);
    });

    test('save and delete fail loudly with a StateError', () async {
      await expectLater(
          r.save(_rec('a', DateTime.utc(2026, 1, 1))), throwsStateError);
      await expectLater(r.delete('a'), throwsStateError);
    });
  });
}
