import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';

/// C25 (design 20.2, PRIV-11): the per-uid keys of the body-scan, nutrition and
/// diary features go with the account, and ONLY with that account.
///
/// Rule under test: a key is erased when it starts with one of
/// `data_notice.`, `body_scan.`, `nutrition.`, `food_diary.`, `weight.` AND ends
/// with `.<exact uid>`.
void main() {
  late Directory docs;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('wipe_c25_test');
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  DeviceLocalDataWipe wipeOf(SharedPreferences prefs) => DeviceLocalDataWipe(
        prefs: prefs,
        documentsDir: docs,
        forgetPhotoKey: (_) async {},
      );

  test('every prefix family is erased for the deleted uid, any notice version', () async {
    final mine = <String, Object>{
      'data_notice.v1.u1': true,
      'data_notice.v2.u1': true,
      'data_notice.v37.u1': true,
      'body_scan.settings.cache.u1': 'x',
      'nutrition.review.undo.u1': 'x',
      'nutrition.pause.u1': 'x',
      'food_diary.resume.u1': 'x',
      'weight.last_entry.u1': 'x',
    };
    final prefs = await prefsWith({...mine, 'settings.language': 'ru'});

    await wipeOf(prefs).wipe('u1');

    for (final key in mine.keys) {
      expect(prefs.containsKey(key), isFalse, reason: '$key must be erased');
    }
    // Kept by contract: how the phone looks is not the account's data.
    expect(prefs.getString('settings.language'), 'ru');
  });

  test('another account on the same phone keeps every key, including a uid that merely shares a suffix or prefix', () async {
    final others = <String, Object>{
      'data_notice.v1.u2': true,
      'body_scan.settings.cache.u2': 'x',
      'nutrition.review.undo.u2': 'x',
      'food_diary.resume.u2': 'x',
      'weight.last_entry.u2': 'x',
      // "u1" is a prefix of "u10" and a suffix of "xu1": neither is the uid.
      'data_notice.v1.u10': true,
      'weight.last_entry.u10': 'x',
      'nutrition.pause.xu1': 'x',
      'body_scan.settings.cache.u1x': 'x',
    };
    final prefs = await prefsWith({
      ...others,
      'data_notice.v1.u1': true,
      'weight.last_entry.u1': 'x',
    });

    await wipeOf(prefs).wipe('u1');

    expect(prefs.containsKey('data_notice.v1.u1'), isFalse);
    expect(prefs.containsKey('weight.last_entry.u1'), isFalse);
    for (final key in others.keys) {
      expect(prefs.containsKey(key), isTrue, reason: '$key must survive');
    }
  });

  test('a uid-suffixed key outside the five prefixes, and a prefixed key without the uid segment, are untouched', () async {
    final untouched = <String, Object>{
      'unrelated_feature.state.u1': 'x',
      'workouts.draft.u1': 'x',
      // Install-wide (not per-uid) keys under the feature prefixes.
      'nutrition.auto.kcal': 1,
      'nutrition.auto.steps': 1,
      'food_diary.meal_thumbnail.enabled': true,
      'body_scan.u1.extra': 'x', // uid is not the final segment
    };
    final prefs = await prefsWith(untouched);

    await wipeOf(prefs).wipe('u1');

    for (final key in untouched.keys) {
      expect(prefs.containsKey(key), isTrue, reason: '$key must survive');
    }
  });

  test('device photo directory of the uid goes (scans/ and meals/ inside it), another uid directory stays', () async {
    final prefs = await prefsWith({'data_notice.v1.u1': true});
    for (final uid in ['u1', 'u2']) {
      for (final sub in ['scans', 'meals']) {
        final d = Directory('${docs.path}/progress_photos/$uid/$sub')
          ..createSync(recursive: true);
        File('${d.path}/a.enc').writeAsBytesSync([1, 2, 3]);
      }
    }

    await wipeOf(prefs).wipe('u1');

    expect(Directory('${docs.path}/progress_photos/u1').existsSync(), isFalse);
    expect(
        File('${docs.path}/progress_photos/u2/scans/a.enc').existsSync(), isTrue);
    expect(
        File('${docs.path}/progress_photos/u2/meals/a.enc').existsSync(), isTrue);
  });

  test('a per-uid feature key that fails to erase is reported with the uid masked, and the other keys are still erased', () async {
    final real = await prefsWith({
      'weight.last_entry.u1': 'x',
      'food_diary.resume.u1': 'x',
    });
    final flaky = _FailingRemove(real, 'weight.last_entry.u1');

    await expectLater(
      wipeOf(flaky).wipe('u1'),
      throwsA(isA<LocalWipeIncomplete>().having(
          (e) => e.remaining, 'remaining', ['weight.last_entry.<uid>'])),
    );
    expect(real.containsKey('food_diary.resume.u1'), isFalse);
  });

  test('wiping twice is harmless', () async {
    final prefs = await prefsWith({'nutrition.pause.u1': 'x'});
    final wipe = wipeOf(prefs);
    await wipe.wipe('u1');
    await wipe.wipe('u1');
    expect(prefs.containsKey('nutrition.pause.u1'), isFalse);
  });
}

/// Real prefs whose `remove` of one key reports failure (returns false).
class _FailingRemove implements SharedPreferences {
  _FailingRemove(this._real, this._failing);
  final SharedPreferences _real;
  final String _failing;

  @override
  Set<String> getKeys() => _real.getKeys();
  @override
  String? getString(String key) => _real.getString(key);
  @override
  Future<bool> remove(String key) async =>
      key == _failing ? false : _real.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
