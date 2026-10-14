import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/progress_photos/data/photo_directory.dart';

/// Wraps real prefs; `remove` of chosen keys returns false (or throws), the way
/// a failed platform write does.
class _FlakyPrefs implements SharedPreferences {
  _FlakyPrefs(this._real, {required this.failing, this.throwInstead = false});
  final SharedPreferences _real;
  final Set<String> failing;
  final bool throwInstead;

  @override
  Set<String> getKeys() => _real.getKeys();
  @override
  String? getString(String key) => _real.getString(key);
  @override
  Future<bool> remove(String key) async {
    if (failing.contains(key)) {
      if (throwInstead) throw StateError('platform failure');
      return false;
    }
    return _real.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

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

  test('a failing photo-key forget still runs the remaining steps and is reported',
      () async {
    final prefs = await prefsWith({
      trainingContextKeyFor('u1'): 'yoga',
      'settings.tier_override': 'pro',
    });
    final rec = Directory('${docs.path}/coach_recordings/u1')
      ..createSync(recursive: true);
    File('${rec.path}/a.json').writeAsStringSync('{}');
    final wipe = DeviceLocalDataWipe(
      prefs: prefs,
      documentsDir: docs,
      forgetPhotoKey: (_) async => throw StateError('keystore'),
    );
    await expectLater(
      wipe.wipe('u1'),
      throwsA(isA<LocalWipeIncomplete>()
          .having((e) => e.remaining, 'remaining', contains('photo_key'))),
    );
    expect(prefs.getString(trainingContextKeyFor('u1')), isNull);
    expect(prefs.getString('settings.tier_override'), isNull);
    expect(rec.existsSync(), isFalse);
  });

  test('one key that fails to erase does not stop the others, and the caller is told',
      () async {
    final real = await prefsWith({
      'profile.sensitive.u1': '{"injuries":["knee"]}',
      'moment.streak': '3',
      'settings.tier_override': 'pro',
    });
    final flaky = _FlakyPrefs(real, failing: {'profile.sensitive.u1'});
    final photos = Directory('${docs.path}/progress_photos/u1')
      ..createSync(recursive: true);
    File('${photos.path}/p1.bin').writeAsBytesSync([1, 2, 3]);

    await expectLater(
      DeviceLocalDataWipe(prefs: flaky, documentsDir: docs).wipe('u1'),
      throwsA(isA<LocalWipeIncomplete>().having(
          (e) => e.remaining, 'remaining', ['profile.sensitive.<uid>'])),
    );

    expect(real.getString('moment.streak'), isNull,
        reason: 'keys after the failing one are still erased');
    expect(real.getString('settings.tier_override'), isNull);
    expect(photos.existsSync(), isFalse,
        reason: 'the larger leak (photos) is not skipped by a prefs failure');
  });

  test('a remove that throws is reported the same way, without aborting', () async {
    final real = await prefsWith({
      'profile.sensitive.u1': '{}',
      'moment.streak': '3',
    });
    final flaky =
        _FlakyPrefs(real, failing: {'profile.sensitive.u1'}, throwInstead: true);

    await expectLater(
      DeviceLocalDataWipe(prefs: flaky, documentsDir: docs).wipe('u1'),
      throwsA(isA<LocalWipeIncomplete>()),
    );
    expect(real.getString('moment.streak'), isNull);
  });

  test('removes this account\'s photo-consent record and keeps another\'s', () async {
    final prefs = await prefsWith({
      'progress_photos.consent.v1.u1': 'granted',
      'progress_photos.consent.v1.u2': 'granted',
    });

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(prefs.getString('progress_photos.consent.v1.u1'), isNull);
    expect(prefs.getString('progress_photos.consent.v1.u2'), isNotNull);
  });

  test('removes the health blob belonging to the deleted uid', () async {
    final prefs = await prefsWith({
      'profile.sensitive.u1': '{"injuries":["knee"]}',
    });

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(prefs.getString('profile.sensitive.u1'), isNull);
  });

  test('removes the quarantined copy of an unreadable health blob too', () async {
    // CR-07 keeps the first unreadable blob under a separate key. It is raw
    // health text, so erasure that leaves it behind is not erasure.
    final prefs = await prefsWith({
      'profile.sensitive.u1': '{"health": []}',
      'profile.sensitive.corrupt.u1': '{"health": []}',
      'profile.sensitive.corrupt.u2': '{"health": "other"}',
    });

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(prefs.getString('profile.sensitive.corrupt.u1'), isNull);
    expect(prefs.getString('profile.sensitive.corrupt.u2'), isNotNull);
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

  test(
      'two accounts on one phone: wiping A removes every item of A '
      '(scans, scan reminder, training context, consent, coach recordings) and none of B',
      () async {
    final seeded = <String, Object>{};
    for (final uid in ['A', 'B']) {
      seeded['profile.sensitive.$uid'] = '{"blob":"$uid"}';
      seeded[trainingContextKeyFor(uid)] = 'home';
      seeded['progress_photos.scan_reminder.v1.$uid'] = true;
      seeded['progress_photos.consent.v1.$uid'] = true;
    }
    final prefs = await prefsWith(seeded);
    for (final uid in ['A', 'B']) {
      final scans = Directory('${docs.path}/progress_photos/$uid/scans')
        ..createSync(recursive: true);
      File('${scans.path}/scan1.bin').writeAsBytesSync([1, 2, 3]);
      File('${scans.path}/scan1.json').writeAsStringSync('{}');
      final rec = Directory('${docs.path}/coach_recordings/$uid')
        ..createSync(recursive: true);
      File('${rec.path}/set1.json').writeAsStringSync('{}');
    }
    final forgotten = <String>[];
    final wipe = DeviceLocalDataWipe(
      prefs: prefs,
      documentsDir: docs,
      forgetPhotoKey: (uid) async => forgotten.add(uid),
    );

    await wipe.wipe('A');

    for (final key in [
      'profile.sensitive.A',
      trainingContextKeyFor('A'),
      'progress_photos.scan_reminder.v1.A',
      'progress_photos.consent.v1.A',
    ]) {
      expect(prefs.containsKey(key), isFalse, reason: '$key must be gone');
    }
    expect(Directory('${docs.path}/progress_photos/A').existsSync(), isFalse);
    expect(Directory('${docs.path}/coach_recordings/A').existsSync(), isFalse);
    expect(forgotten, ['A']);

    // B is untouched, byte for byte.
    expect(prefs.getString('profile.sensitive.B'), '{"blob":"B"}');
    expect(prefs.getString(trainingContextKeyFor('B')), 'home');
    expect(prefs.getBool('progress_photos.scan_reminder.v1.B'), isTrue);
    expect(prefs.getBool('progress_photos.consent.v1.B'), isTrue);
    expect(
        File('${docs.path}/progress_photos/B/scans/scan1.bin').readAsBytesSync(),
        [1, 2, 3]);
    expect(File('${docs.path}/progress_photos/B/scans/scan1.json').existsSync(),
        isTrue);
    expect(File('${docs.path}/coach_recordings/B/set1.json').existsSync(), isTrue);
  });
}
