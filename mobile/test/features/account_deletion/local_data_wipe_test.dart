import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';

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

  test('deletes the whole progress-photo directory, not just indexed files',
      () async {
    // Directory-level on purpose: A2 is about to move these into per-uid
    // subdirectories, and an index-driven wipe would silently miss anything
    // the index did not list -- including a half-written blob.
    final photoDir = Directory('${docs.path}/progress_photos')
      ..createSync(recursive: true);
    File('${photoDir.path}/index.json').writeAsStringSync('[{"id":"p1"}]');
    File('${photoDir.path}/p1.bin').writeAsBytesSync([1, 2, 3]);
    File('${photoDir.path}/orphan.bin').writeAsBytesSync([4, 5, 6]);

    final prefs = await prefsWith({});
    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(photoDir.existsSync(), isFalse);
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
