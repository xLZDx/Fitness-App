import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/progress_photos/data/aes_photo_cipher.dart';
import 'package:fitness_app/features/progress_photos/data/photo_store.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';

/// Real AES against a real temp directory. A mock filesystem cannot reproduce
/// the two failures this store actually has to survive — a blob deleted out
/// from under the index, and a key that no longer matches — so it is not used.
void main() {
  late Directory dir;
  late PhotoStore store;
  final key = AesPhotoCipher.newKey();

  final pixels = Uint8List.fromList(List<int>.generate(4096, (i) => i % 256));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photo_store_test');
    store = PhotoStore(dir: dir, cipher: AesPhotoCipher(key));
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('empty store reads as an empty index, not a crash', () async {
    expect(await store.index(), isEmpty);
  });

  test('put then read round-trips the exact bytes', () async {
    final photo = await store.put(pixels, takenAt: DateTime(2026, 5, 1));
    final back = await store.read(photo);
    expect(back, equals(pixels));
  });

  test('the blob on disk is not the plaintext', () async {
    final photo = await store.put(pixels, takenAt: DateTime(2026, 5, 1));
    final raw = await File(photo.storagePath).readAsBytes();
    expect(raw, isNot(equals(pixels)));
    // And it must not merely be a re-ordering: no long run of the plaintext
    // may survive. Checking a prefix is enough to catch "forgot to encrypt".
    expect(raw.sublist(0, 32), isNot(equals(pixels.sublist(0, 32))));
  });

  test('index survives a new store instance over the same directory', () async {
    await store.put(pixels, takenAt: DateTime(2026, 5, 1));
    await store.put(pixels, takenAt: DateTime(2026, 6, 1));
    final reopened = PhotoStore(dir: dir, cipher: AesPhotoCipher(key));
    final index = await reopened.index();
    expect(index.length, 2);
    expect(await reopened.read(index.first), equals(pixels));
  });

  test('index is oldest first even when written out of order', () async {
    await store.put(pixels, takenAt: DateTime(2026, 6, 1), id: 'later');
    await store.put(pixels, takenAt: DateTime(2026, 1, 1), id: 'earlier');
    expect((await store.index()).map((p) => p.id), ['earlier', 'later']);
  });

  test('metadata round-trips through the index', () async {
    await store.put(
      pixels,
      takenAt: DateTime(2026, 5, 1),
      angle: ProgressPhotoAngle.side,
      weightKg: 81.5,
      note: 'after the cut',
    );
    final p = (await store.index()).single;
    expect(p.angle, ProgressPhotoAngle.side);
    expect(p.weightKg, 81.5);
    expect(p.note, 'after the cut');
  });

  test('read of a wrong-key photo names the key, not a decode error', () async {
    final photo = await store.put(pixels, takenAt: DateTime(2026, 5, 1));
    final other = PhotoStore(dir: dir, cipher: AesPhotoCipher(AesPhotoCipher.newKey()));
    expect(
      () => other.read(photo),
      throwsA(isA<StateError>().having(
        (e) => e.message, 'message', contains('this device holds'))),
    );
  });

  test('read of a missing blob says the blob is missing', () async {
    final photo = await store.put(pixels, takenAt: DateTime(2026, 5, 1));
    await File(photo.storagePath).delete();
    expect(
      () => store.read(photo),
      throwsA(isA<StateError>().having(
        (e) => e.message, 'message', contains('blob missing'))),
    );
  });

  test('remove drops both the row and the file', () async {
    final photo = await store.put(pixels, takenAt: DateTime(2026, 5, 1));
    await store.remove(photo.id);
    expect(await store.index(), isEmpty);
    expect(await File(photo.storagePath).exists(), isFalse);
  });

  test('remove on a folder that does not exist creates neither folder nor index',
      () async {
    // The cleanup of an aborted scan save runs after the account's local wipe;
    // it must not resurrect the wiped folder by writing an empty index.
    expect(await dir.exists(), isTrue, reason: 'setUp made it');
    await dir.delete(recursive: true);
    await store.remove('p_gone');
    expect(await dir.exists(), isFalse, reason: 'folder must not be recreated');
    expect(await File('${dir.path}/index.json').exists(), isFalse);
  });

  test('remove on an existing folder without an index writes no index',
      () async {
    await File('${dir.path}/p_orphan.bin').writeAsBytes([1, 2, 3]);
    await store.remove('p_orphan');
    expect(await File('${dir.path}/p_orphan.bin').exists(), isFalse,
        reason: 'the blob is still deleted');
    expect(await File('${dir.path}/index.json').exists(), isFalse,
        reason: 'no index existed, so none is created');
  });

  test('remove of one photo rewrites the index without it and keeps the rest',
      () async {
    final a =
        await store.put(pixels, takenAt: DateTime(2026, 5, 1), id: 'keep');
    final b =
        await store.put(pixels, takenAt: DateTime(2026, 6, 1), id: 'drop');
    await store.remove(b.id);
    expect((await store.index()).map((p) => p.id), ['keep']);
    expect(await File(b.storagePath).exists(), isFalse);
    expect(await File(a.storagePath).exists(), isTrue);
    final onDisk = File('${dir.path}/index.json').readAsStringSync();
    expect(onDisk.contains('drop'), isFalse, reason: 'the row is gone on disk');
    expect(onDisk.contains('keep'), isTrue);
  });

  test('prune deletes orphan blobs and keeps referenced ones', () async {
    final kept = await store.put(pixels, takenAt: DateTime(2026, 5, 1));
    // Simulate the crash window: a blob written, the index update lost.
    await File('${dir.path}/p_orphan.bin').writeAsBytes([1, 2, 3]);
    expect(await store.prune(), 1);
    expect(await File(kept.storagePath).exists(), isTrue);
    expect(await File('${dir.path}/p_orphan.bin').exists(), isFalse);
  });

  test('a corrupt index throws, so the page can say so', () async {
    // Deliberately not swallowed into an empty list. The photos are still on
    // disk; rendering "no photos yet" over a readable directory would look
    // like data loss and invite the user to re-shoot everything. The page has
    // an error branch (progressphotosCouldNotLoadPhotos) and this is what
    // feeds it.
    await dir.create(recursive: true);
    await File('${dir.path}/index.json').writeAsString('{not json');
    expect(() => store.index(), throwsA(isA<FormatException>()));
  });

  test('an empty index file is not corruption', () async {
    await dir.create(recursive: true);
    await File('${dir.path}/index.json').writeAsString('   ');
    expect(await store.index(), isEmpty);
  });
}
