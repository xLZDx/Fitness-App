import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/progress_photos/data/photo_directory.dart';

/// A1 — the on-device half of account deletion.
///
/// Every case here is a real leak the audit of 2026-08-11 named, expressed as
/// the state of the device AFTER a successful server-side deletion. None of
/// them is a string match on the implementation: each seeds a store, runs the
/// wipe, and reads the store back.
void main() {
  late Directory docs;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('wipe_test');
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('removes the health blob belonging to the deleted uid', () async {
    final prefs = await prefsWith({
      'profile.sensitive.u1': '{"injuries":["knee"]}',
    });

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(prefs.getString('profile.sensitive.u1'), isNull);
  });

  test('keeps another account\'s health blob on a shared phone', () async {
    // Deleting your account must not delete a family member's health data as
    // a side effect. Their own deletion is what removes theirs.
    final prefs = await prefsWith({
      'profile.sensitive.u1': '{"injuries":["knee"]}',
      'profile.sensitive.u2': '{"injuries":["shoulder"]}',
    });

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(prefs.getString('profile.sensitive.u1'), isNull);
    expect(prefs.getString('profile.sensitive.u2'), isNotNull);
  });

  test('drops the photo key, so leftover ciphertext is unreadable', () async {
    final prefs = await prefsWith({
      'progress_photos.key.v1': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    });

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(prefs.getString('progress_photos.key.v1'), isNull);
  });

  test('deletes this account\'s photo directory, not just its indexed files',
      () async {
    // Directory-level on purpose: an index-driven wipe silently misses
    // anything the index did not list, including a half-written blob.
    final mine = Directory('${docs.path}/progress_photos/u1')
      ..createSync(recursive: true);
    File('${mine.path}/index.json').writeAsStringSync('[{"id":"p1"}]');
    File('${mine.path}/p1.bin').writeAsBytesSync([1, 2, 3]);
    File('${mine.path}/orphan.bin').writeAsBytesSync([4, 5, 6]);

    final prefs = await prefsWith({});
    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(mine.existsSync(), isFalse);
  });

  test('leaves another account\'s photos alone', () async {
    // The mirror of the health-blob case, and the reason A2-sec's per-uid
    // layout had to reach this class: deleting the whole tree would erase a
    // family member's photos as a side effect of deleting your account.
    final mine = Directory('${docs.path}/progress_photos/u1')
      ..createSync(recursive: true);
    File('${mine.path}/p1.bin').writeAsBytesSync([1]);
    final theirs = Directory('${docs.path}/progress_photos/u2')
      ..createSync(recursive: true);
    File('${theirs.path}/p9.bin').writeAsBytesSync([9]);

    final prefs = await prefsWith({});
    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(mine.existsSync(), isFalse);
    expect(File('${theirs.path}/p9.bin').existsSync(), isTrue);
  });

  test('sweeps pre-A2-sec files still loose at the photo root', () async {
    // An install that upgraded but never re-opened the Photos tab still has
    // its photos directly under progress_photos/, adopted by nobody. They are
    // this user's by every available signal.
    final root = Directory('${docs.path}/progress_photos')
      ..createSync(recursive: true);
    File('${root.path}/index.json').writeAsStringSync('[{"id":"p1"}]');
    File('${root.path}/p1.bin').writeAsBytesSync([1, 2, 3]);

    final prefs = await prefsWith({});
    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(File('${root.path}/index.json').existsSync(), isFalse);
    expect(File('${root.path}/p1.bin').existsSync(), isFalse);
  });

  test('leaves un-migrated legacy data alone when it belongs to someone else',
      () async {
    // The Act gate's second blocker. The marker names A, so the loose root
    // files and the v1 key are demonstrably A's -- B deleting their own
    // account must not take A's photos with it.
    final root = Directory('${docs.path}/progress_photos')
      ..createSync(recursive: true);
    File('${root.path}/index.json').writeAsStringSync('[{"id":"p1"}]');
    File('${root.path}/p1.bin').writeAsBytesSync([1, 2, 3]);

    final prefs = await prefsWith({
      kLegacyPhotoMigrationMarker: 'A',
      'progress_photos.key.v1': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    });
    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('B');

    expect(File('${root.path}/p1.bin').existsSync(), isTrue);
    expect(File('${root.path}/index.json').existsSync(), isTrue);
    expect(prefs.getString('progress_photos.key.v1'), isNotNull);
    expect(prefs.getString(kLegacyPhotoMigrationMarker), 'A');
  });

  test('the key and the blobs it opens are always erased together', () async {
    // Never one without the other: a plaintext key left beside deleted
    // ciphertext is a dangling secret, and ciphertext left beside a deleted
    // key is junk nobody can ever open.
    final root = Directory('${docs.path}/progress_photos')
      ..createSync(recursive: true);
    File('${root.path}/p1.bin').writeAsBytesSync([1]);

    final prefs = await prefsWith({
      'progress_photos.key.v1': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    });
    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    // Unclaimed legacy data, so it is this user's to erase -- both halves.
    expect(File('${root.path}/p1.bin').existsSync(), isFalse);
    expect(prefs.getString('progress_photos.key.v1'), isNull);
  });

  test('forgets the legacy-migration marker only when it names this user',
      () async {
    final prefs = await prefsWith({kLegacyPhotoMigrationMarker: 'u1'});
    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');
    expect(prefs.getString(kLegacyPhotoMigrationMarker), isNull);

    final other = await prefsWith({kLegacyPhotoMigrationMarker: 'u2'});
    await DeviceLocalDataWipe(prefs: other, documentsDir: docs).wipe('u1');
    expect(other.getString(kLegacyPhotoMigrationMarker), 'u2');
  });

  test('a missing photo directory is not an error', () async {
    // The account IS deleted by the time this runs. Throwing here would
    // surface as "your account was not deleted", which would be untrue.
    final prefs = await prefsWith({});

    await expectLater(
      DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1'),
      completes,
    );
  });

  test('clears moment counters and the debug tier override', () async {
    final prefs = await prefsWith({
      'moment.launch_count': 12,
      'moment.injury_filter_uses': 3,
      'moment.shown.firstWorkout': true,
      'settings.tier_override': 'pro',
    });

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(prefs.getKeys().where((k) => k.startsWith('moment.')), isEmpty);
    expect(prefs.getString('settings.tier_override'), isNull);
  });

  test('keeps device preferences that describe the phone, not the person',
      () async {
    // Wiping these would drop a Russian user onto an English login screen as
    // a side effect of deleting their account, and would desynchronise the
    // notification toggle from an OS permission that deletion does not revoke.
    final prefs = await prefsWith({
      'settings.language': 'ru',
      'settings.theme_mode': 'dark',
      'settings.notifications_enabled': true,
    });

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(prefs.getString('settings.language'), 'ru');
    expect(prefs.getString('settings.theme_mode'), 'dark');
    expect(prefs.getBool('settings.notifications_enabled'), isTrue);
    expect(DeviceLocalDataWipe.kept, contains('settings.language'));
  });
}
