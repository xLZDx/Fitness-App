// C24 meal_thumbnail_store_test (PRIV-19 / FOOD-27 delete half): the optional
// meal thumbnail is encrypted with the existing progress-photo cipher, lives
// at `<dir>/<entryId>.bin`, refuses unsafe ids, is pruned when orphaned and is
// deleted together with its diary entry through `FoodDiaryActions.deleteEntry`.
import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/food_diary/state/meal_thumbnail_store.dart';
import 'package:fitness_app/features/progress_photos/data/aes_photo_cipher.dart';
import 'package:fitness_app/features/progress_photos/data/photo_encryption.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../food_diary_fixtures.dart';

/// Recognisable plaintext: if it appears in the file, encryption did not run.
final Uint8List _plain = Uint8List.fromList(
    [for (var i = 0; i < 200; i++) 0xAA, ...'PLAINTEXT-THUMB'.codeUnits]);

bool _contains(Uint8List hay, List<int> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
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

late Directory _root;
late Directory _meals;

MealThumbnailStore _store({Uint8List? key}) => MealThumbnailStore(
    dir: _meals, cipher: AesPhotoCipher(key ?? _keyA));

final Uint8List _keyA = Uint8List.fromList(List<int>.generate(32, (i) => i));
final Uint8List _keyB =
    Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  setUp(() {
    _root = Directory.systemTemp.createTempSync('c24_thumb_');
    _meals = Directory('${_root.path}/meals');
  });
  tearDown(() {
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  });

  group('MealThumbnailStore', () {
    test('put then read returns the exact bytes', () async {
      final s = _store();
      expect(await s.put('e1', _plain), isTrue);
      expect(await s.read('e1'), _plain);
      expect(await s.exists('e1'), isTrue);
    });

    test('the file is <dir>/<entryId>.bin, created on demand', () async {
      expect(_meals.existsSync(), isFalse);
      await _store().put('entry-1_a', _plain);
      expect(File('${_meals.path}/entry-1_a.bin').existsSync(), isTrue);
    });

    test('what is on disk is encrypted, not the plaintext', () async {
      await _store().put('e1', _plain);
      final raw = File('${_meals.path}/e1.bin').readAsBytesSync();
      expect(_contains(raw, 'PLAINTEXT-THUMB'.codeUnits), isFalse);
      expect(raw[0], 1, reason: 'PhotoEnvelope version byte');
      // It is a real PhotoEnvelope that the existing cipher opens.
      final opened = AesPhotoCipher(_keyA).decrypt(PhotoEnvelope.fromBytes(raw));
      expect(opened, _plain);
    });

    test('a different key cannot read it (null, no throw)', () async {
      await _store().put('e1', _plain);
      expect(await _store(key: _keyB).read('e1'), isNull);
    });

    test('a corrupted file reads as null, no throw', () async {
      await _store().put('e1', _plain);
      final f = File('${_meals.path}/e1.bin');
      final b = f.readAsBytesSync();
      b[b.length - 1] ^= 0xFF;
      f.writeAsBytesSync(b);
      expect(await _store().read('e1'), isNull);
    });

    test('an absent entry reads null and does not exist', () async {
      final s = _store();
      expect(await s.read('nope'), isNull);
      expect(await s.exists('nope'), isFalse);
    });

    test('put overwrites the earlier thumbnail of the same entry', () async {
      final s = _store();
      await s.put('e1', Uint8List.fromList([1, 2, 3]));
      await s.put('e1', Uint8List.fromList([9, 8]));
      expect(await s.read('e1'), [9, 8]);
    });

    for (final bad in [
      '',
      '../escape',
      'a/b',
      r'a\b',
      'has space',
      'x.bin',
      'é',
      'a' * 65,
    ]) {
      test('unsafe id "$bad" is refused and nothing is written', () async {
        final s = _store();
        expect(await s.put(bad, _plain), isFalse);
        expect(await s.read(bad), isNull);
        expect(await s.exists(bad), isFalse);
        await s.delete(bad); // must not throw
        final written = _root.listSync(recursive: true).whereType<File>();
        expect(written, isEmpty);
      });
    }

    test('a 64-character id is the longest accepted', () async {
      expect(await _store().put('a' * 64, _plain), isTrue);
    });

    test('delete removes the file; deleting again is fine', () async {
      final s = _store();
      await s.put('e1', _plain);
      await s.delete('e1');
      expect(File('${_meals.path}/e1.bin').existsSync(), isFalse);
      expect(await s.exists('e1'), isFalse);
      await s.delete('e1');
    });

    test('delete touches only its own entry', () async {
      final s = _store();
      await s.put('e1', _plain);
      await s.put('e2', _plain);
      await s.delete('e1');
      expect(await s.exists('e2'), isTrue);
    });

    test('pruneExcept removes orphans, keeps the listed ids, returns the count',
        () async {
      final s = _store();
      for (final id in ['keep1', 'keep2', 'orphan1', 'orphan2', 'orphan3']) {
        await s.put(id, _plain);
      }
      final removed = await s.pruneExcept({'keep1', 'keep2'});
      expect(removed, 3);
      expect(await s.exists('keep1'), isTrue);
      expect(await s.exists('keep2'), isTrue);
      expect(await s.exists('orphan1'), isFalse);
      expect(await s.exists('orphan3'), isFalse);
    });

    test('pruneExcept with an empty keep set removes everything', () async {
      final s = _store();
      await s.put('a', _plain);
      await s.put('b', _plain);
      expect(await s.pruneExcept({}), 2);
    });

    test('pruneExcept leaves non-.bin files alone', () async {
      final s = _store();
      await s.put('a', _plain);
      File('${_meals.path}/notes.txt').writeAsStringSync('hi');
      expect(await s.pruneExcept({}), 1);
      expect(File('${_meals.path}/notes.txt').existsSync(), isTrue);
    });

    test('pruneExcept with no directory is 0', () async {
      expect(await _store().pruneExcept({'x'}), 0);
    });
  });

  group('mealThumbnailDeleterProvider (best effort)', () {
    test('deletes through the store of the account', () async {
      final s = _store();
      await s.put('e1', _plain);
      final c = ProviderContainer(overrides: [
        mealThumbnailStoreProvider.overrideWith((ref) async => s),
      ]);
      addTearDown(c.dispose);
      await c.read(mealThumbnailDeleterProvider)('e1');
      expect(await s.exists('e1'), isFalse);
    });

    test('signed out (null store) does nothing and does not throw', () async {
      final c = ProviderContainer(overrides: [
        mealThumbnailStoreProvider.overrideWith((ref) async => null),
      ]);
      addTearDown(c.dispose);
      await c.read(mealThumbnailDeleterProvider)('e1');
    });

    test('a failing store provider does not throw', () async {
      final c = ProviderContainer(overrides: [
        mealThumbnailStoreProvider
            .overrideWith((ref) async => throw StateError('no key')),
      ]);
      addTearDown(c.dispose);
      await c.read(mealThumbnailDeleterProvider)('e1');
    });
  });

  group('deleted with the entry (FoodDiaryActions.deleteEntry hook)', () {
    ProviderContainer container(MealThumbnailStore store) {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith(
            (ref) => Stream.value(AuthUser(uid: kDiaryUid, displayName: 'T'))),
        mealThumbnailStoreProvider.overrideWith((ref) async => store),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('deleting the entry deletes its thumbnail and only its own', () async {
      final store = _store();
      await store.put('e1', _plain);
      await store.put('e2', _plain);
      final c = container(store);
      await c.read(authUserProvider.future);
      final a = c.read(foodDiaryActionsProvider);
      expect(await a.saveEntry(quickEntry(id: 'e1')), DiaryWriteStatus.saved);

      expect(await a.deleteEntry('e1'), DiaryWriteStatus.saved);
      expect(await store.exists('e1'), isFalse);
      expect(await store.exists('e2'), isTrue);
    });

    test('when the repository delete fails the thumbnail is kept', () async {
      final store = _store();
      await store.put('e1', _plain);
      final c = container(store);
      await c.read(authUserProvider.future);
      final a = c.read(foodDiaryActionsProvider);
      await a.saveEntry(quickEntry(id: 'e1'));
      (c.read(diaryRepositoryProvider) as InMemoryDiaryRepository).offline = true;

      expect(await a.deleteEntry('e1'), DiaryWriteStatus.failed);
      expect(await store.exists('e1'), isTrue);
    });

    test('signed out: nothing is deleted', () async {
      final store = _store();
      await store.put('e1', _plain);
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        mealThumbnailStoreProvider.overrideWith((ref) async => store),
      ]);
      addTearDown(c.dispose);
      await c.read(authUserProvider.future);
      expect(await c.read(foodDiaryActionsProvider).deleteEntry('e1'),
          DiaryWriteStatus.unavailable);
      expect(await store.exists('e1'), isTrue);
    });

    test('a thumbnail store that throws does not fail the entry delete',
        () async {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith(
            (ref) => Stream.value(AuthUser(uid: kDiaryUid, displayName: 'T'))),
        mealThumbnailStoreProvider
            .overrideWith((ref) async => throw StateError('keystore')),
      ]);
      addTearDown(c.dispose);
      await c.read(authUserProvider.future);
      final a = c.read(foodDiaryActionsProvider);
      await a.saveEntry(quickEntry(id: 'e1'));
      expect(await a.deleteEntry('e1'), DiaryWriteStatus.saved);
    });
  });
}
