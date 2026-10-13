import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/progress_photos/data/aes_photo_cipher.dart';
import 'package:fitness_app/features/progress_photos/data/photo_store.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_store.dart';

ScanRecord _rec(String id, DateTime at, {String marker = 'LM_SECRET_NOSE'}) =>
    ScanRecord(id: id, createdAt: at, shots: {
      ScanPose.front: ScanShot(photoId: 'p_${id}_f', landmarks: [
        ScanLandmark(name: marker, x: 0.123456, y: 0.654321, likelihood: 0.9),
      ]),
      ScanPose.side: ScanShot(photoId: 'p_${id}_s', landmarks: const []),
      ScanPose.back: ScanShot(photoId: 'p_${id}_b', landmarks: const []),
    });

void main() {
  late Directory dir;
  late ScanStore store;
  final key = AesPhotoCipher.newKey();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scan_store_test');
    store = ScanStore(dir: dir, cipher: AesPhotoCipher(key));
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('empty store lists nothing', () async {
    expect(await store.list(), isEmpty);
  });

  test('round trip keeps every field, newest first', () async {
    final a = _rec('a', DateTime(2026, 9, 1, 8));
    final b = _rec('b', DateTime(2026, 9, 15, 8));
    await store.save(a);
    await store.save(b);
    final back = await store.list();
    expect(back.map((r) => r.id), ['b', 'a']);
    final f = back.last.shots[ScanPose.front]!;
    expect(f.photoId, 'p_a_f');
    expect(f.landmarks.single.name, 'LM_SECRET_NOSE');
    expect(f.landmarks.single.x, 0.123456);
    expect(back.last.createdAt.isAtSameMomentAs(a.createdAt), isTrue);
    expect(back.last.shots.keys, ScanPose.values);
  });

  test('landmarks and ids are NOT present in plaintext on disk', () async {
    await store.save(_rec('a', DateTime(2026, 9, 1)));
    final files = dir.listSync(recursive: true).whereType<File>().toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      final raw = latin1.decode(f.readAsBytesSync());
      expect(raw.contains('LM_SECRET_NOSE'), isFalse);
      expect(raw.contains('0.123456'), isFalse);
      expect(raw.contains('p_a_f'), isFalse);
      expect(raw.contains('landmarks'), isFalse);
    }
    expect(File('${dir.path}/index.json').existsSync(), isFalse);
  });

  test('saving a scan does not write landmarks into the photo index',
      () async {
    final photos = PhotoStore(dir: dir, cipher: AesPhotoCipher(key));
    await photos.put(Uint8List.fromList([1, 2, 3]),
        takenAt: DateTime(2026, 9, 1), id: 'p_a_f');
    await store.save(_rec('a', DateTime(2026, 9, 1)));
    final index = File('${dir.path}/index.json').readAsStringSync();
    expect(index.contains('LM_SECRET_NOSE'), isFalse);
    expect(index.contains('landmark'), isFalse);
    expect(await photos.prune(), 0, reason: 'sidecar is not a stray blob');
    expect(await store.list(), hasLength(1));
  });

  test('delete removes the sidecar file and is idempotent', () async {
    await store.save(_rec('a', DateTime(2026, 9, 1)));
    final path = '${dir.path}/scans/a.scan';
    expect(File(path).existsSync(), isTrue);
    await store.delete('a');
    expect(File(path).existsSync(), isFalse);
    await store.delete('a');
    expect(await store.list(), isEmpty);
  });

  test('a sidecar sealed with another key, or corrupt, is skipped', () async {
    await store.save(_rec('a', DateTime(2026, 9, 1)));
    await ScanStore(dir: dir, cipher: AesPhotoCipher(AesPhotoCipher.newKey()))
        .save(_rec('other', DateTime(2026, 9, 2)));
    File('${dir.path}/scans/junk.scan').writeAsBytesSync([9, 9, 9]);
    expect((await store.list()).map((r) => r.id), ['a']);
  });

  test('unsafe ids cannot escape the scans folder', () async {
    await expectLater(
        store.save(_rec('../evil', DateTime(2026, 9, 1))), throwsArgumentError);
    await expectLater(store.delete('..\\x'), throwsArgumentError);
  });

  test('per-uid isolation: another account directory sees nothing', () async {
    final docs = await Directory.systemTemp.createTemp('scan_uid');
    addTearDown(() => docs.delete(recursive: true));
    final u1 = Directory('${docs.path}/progress_photos/u1')
      ..createSync(recursive: true);
    final u2 = Directory('${docs.path}/progress_photos/u2')
      ..createSync(recursive: true);
    final c = AesPhotoCipher(key);
    await ScanStore(dir: u1, cipher: c).save(_rec('a', DateTime(2026, 9, 1)));
    expect(await ScanStore(dir: u2, cipher: c).list(), isEmpty);
    expect(await ScanStore(dir: u1, cipher: c).list(), hasLength(1));
  });

  test('account wipe erases the sidecars and the reminder pref, only that uid',
      () async {
    final docs = await Directory.systemTemp.createTemp('scan_wipe');
    addTearDown(() => docs.delete(recursive: true));
    final u1 = Directory('${docs.path}/progress_photos/u1')
      ..createSync(recursive: true);
    final u2 = Directory('${docs.path}/progress_photos/u2')
      ..createSync(recursive: true);
    final c = AesPhotoCipher(key);
    await ScanStore(dir: u1, cipher: c).save(_rec('a', DateTime(2026, 9, 1)));
    await ScanStore(dir: u2, cipher: c).save(_rec('b', DateTime(2026, 9, 1)));
    SharedPreferences.setMockInitialValues({
      'progress_photos.scan_reminder.v1.u1': true,
      'progress_photos.scan_reminder.v1.u2': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(u1.existsSync(), isFalse);
    expect(File('${u1.path}/scans/a.scan').existsSync(), isFalse);
    expect(prefs.containsKey('progress_photos.scan_reminder.v1.u1'), isFalse);
    expect(await ScanStore(dir: u2, cipher: c).list(), hasLength(1));
    expect(prefs.getBool('progress_photos.scan_reminder.v1.u2'), isTrue);
  });

  test('LocalScanRepository: signed out lists empty and refuses writes',
      () async {
    final repo = LocalScanRepository(() async => null);
    expect(await repo.list(), isEmpty);
    await expectLater(
        repo.save(_rec('a', DateTime(2026, 9, 1))), throwsStateError);
    await expectLater(repo.delete('a'), throwsStateError);
  });

  test('LocalScanRepository round trip through the store', () async {
    final repo = LocalScanRepository(() async => store);
    await repo.save(_rec('a', DateTime(2026, 9, 1)));
    expect((await repo.list()).single.id, 'a');
    await repo.delete('a');
    expect(await repo.list(), isEmpty);
  });
}
