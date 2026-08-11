import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/progress_photos/data/photo_directory.dart';

/// A2-sec — the photo folder is per-account, and the one install-wide folder
/// that existed before it is moved rather than stranded or deleted.
void main() {
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('photo_dir_test');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  Directory root() => Directory('${documents.path}/progress_photos');

  Future<void> seedLegacy({int blobs = 2}) async {
    await root().create(recursive: true);
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < blobs; i++) {
      final id = 'p_$i';
      await File('${root().path}/$id.bin').writeAsBytes([1, 2, 3, i]);
      rows.add({
        'id': id,
        'takenAt': '2026-08-0${i + 1}T10:00:00.000',
        'storagePath': '${root().path}/$id.bin',
        'keyFingerprint': 'fp',
        'angle': 'front',
      });
    }
    await File('${root().path}/index.json').writeAsString(jsonEncode(rows));
  }

  test('each account gets its own directory', () async {
    final a = await resolvePhotoDir(documents: documents, uid: 'alice');
    final b = await resolvePhotoDir(documents: documents, uid: 'bob');

    // Built with a literal '/', so this holds on Windows too.
    expect(a.path, endsWith('progress_photos/alice'));
    expect(a.path, isNot(b.path));
    expect(await a.exists(), isTrue);
    expect(await b.exists(), isTrue);
  });

  test('the legacy folder is absorbed by the first account, blobs and all',
      () async {
    await seedLegacy(blobs: 3);

    final dir = await resolvePhotoDir(documents: documents, uid: 'alice');

    expect(await File('${dir.path}/index.json').exists(), isTrue);
    for (var i = 0; i < 3; i++) {
      expect(await File('${dir.path}/p_$i.bin').exists(), isTrue,
          reason: 'blob p_$i should have moved');
    }
    // Nothing left loose at the root, which is the state the next account
    // must find.
    expect(await File('${root().path}/index.json').exists(), isFalse);
    expect(await File('${root().path}/p_0.bin').exists(), isFalse);
  });

  test('the second account inherits nothing', () async {
    // The bug A2-sec closes: sign out, sign in as someone else, see their
    // photos. After the first account absorbs the legacy folder, the second
    // must start empty.
    await seedLegacy();
    await resolvePhotoDir(documents: documents, uid: 'alice');

    final bob = await resolvePhotoDir(documents: documents, uid: 'bob');

    expect(await File('${bob.path}/index.json').exists(), isFalse);
    expect(bob.listSync(), isEmpty);
  });

  test('migration runs once, recorded by uid', () async {
    await seedLegacy();
    await resolvePhotoDir(documents: documents, uid: 'alice');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kLegacyPhotoMigrationMarker), 'alice');
  });

  test('a marker with no legacy folder is not an error', () async {
    SharedPreferences.setMockInitialValues(
        {kLegacyPhotoMigrationMarker: 'someone'});

    final dir = await resolvePhotoDir(documents: documents, uid: 'alice');

    expect(await dir.exists(), isTrue);
  });

  test('storagePath in the moved index points at where the file now is',
      () async {
    // Nothing opens a blob through this field, but the GDPR export prints it,
    // and an export naming a path that does not exist is a lie in a document
    // whose only job is being accurate.
    await seedLegacy(blobs: 1);

    final dir = await resolvePhotoDir(documents: documents, uid: 'alice');
    final rows = jsonDecode(
      await File('${dir.path}/index.json').readAsString(),
    ) as List;

    expect(rows.single['storagePath'], '${dir.path}/p_0.bin');
    expect(await File(rows.single['storagePath'] as String).exists(), isTrue);
  });

  test('an empty legacy index migrates to an empty account folder', () async {
    await root().create(recursive: true);
    await File('${root().path}/index.json').writeAsString('');

    final dir = await resolvePhotoDir(documents: documents, uid: 'alice');

    expect(await File('${dir.path}/index.json').readAsString(), '[]');
  });
}
