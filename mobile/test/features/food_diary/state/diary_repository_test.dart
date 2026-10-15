// C23 diary_repository_test (FOOD-23 storage half, PRIV-14 fake semantics):
// the in-memory fakes behave like the Firestore ports they stand in for:
// day filtering, oldest first, per-account isolation, idempotent put, the same
// refusals as the rules, the 500-food cap, offline failure.
import 'dart:async';

import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../food_diary_fixtures.dart';

const _per = Per100g(kcal: 100, proteinG: 5, carbsG: 10, fatG: 2);

void main() {
  group('InMemoryDiaryRepository', () {
    late InMemoryDiaryRepository repo;
    setUp(() => repo = InMemoryDiaryRepository());
    tearDown(() => repo.dispose());

    Future<List<String>> ids(String uid, String day) async =>
        [for (final e in await repo.watchDay(uid, day).first) e.id];

    test('an empty day replays an empty list', () async {
      expect(await repo.watchDay('u1', kToday).first, isEmpty);
    });

    test('returns only the asked day, oldest first', () async {
      await repo.put('u1', quickEntry(id: 'c', at: DateTime(2026, 10, 15, 19)));
      await repo.put('u1', quickEntry(id: 'a', at: DateTime(2026, 10, 15, 8)));
      await repo.put('u1', quickEntry(id: 'b', at: DateTime(2026, 10, 15, 12)));
      await repo.put('u1', quickEntry(id: 'x', day: '2026-10-14'));
      expect(await ids('u1', kToday), ['a', 'b', 'c']);
      expect(await ids('u1', '2026-10-14'), ['x']);
    });

    test('accounts are isolated', () async {
      await repo.put('u1', quickEntry(id: 'mine'));
      await repo.put('u2', quickEntry(id: 'theirs'));
      expect(await ids('u1', kToday), ['mine']);
      expect(await ids('u2', kToday), ['theirs']);
      expect(await ids('u3', kToday), isEmpty);
    });

    test('put is create-or-replace under the entry id', () async {
      await repo.put('u1', quickEntry(kcal: 100));
      await repo.put('u1', quickEntry(kcal: 200));
      final list = await repo.watchDay('u1', kToday).first;
      expect(list, hasLength(1));
      expect(list.single.totals.kcal.mid, 200);
      expect(repo.writes, 2, reason: 'both writes were sent');
    });

    test('an entry the rules would refuse throws FormatException, not stored',
        () async {
      final bad = quickEntry().copyWith(items: const []);
      await expectLater(repo.put('u1', bad), throwsFormatException);
      await expectLater(
          repo.put('u1', quickEntry(day: 'today')), throwsFormatException);
      expect(repo.writes, 0);
      expect(await ids('u1', kToday), isEmpty);
    });

    test('delete removes; deleting a missing id is harmless', () async {
      await repo.put('u1', quickEntry(id: 'a'));
      await repo.delete('u1', 'a');
      await repo.delete('u1', 'a');
      await repo.delete('nobody', 'a');
      expect(await ids('u1', kToday), isEmpty);
    });

    test('a live subscription sees later puts and deletes', () async {
      final seen = <List<String>>[];
      final sub = repo.watchDay('u1', kToday).listen(
          (l) => seen.add([for (final e in l) e.id]));
      await pumpEventQueue();
      await repo.put('u1', quickEntry(id: 'a'));
      await pumpEventQueue();
      await repo.put('u1', quickEntry(id: 'b', at: DateTime(2026, 10, 15, 10)));
      await pumpEventQueue();
      await repo.delete('u1', 'a');
      await pumpEventQueue();
      // Not awaited: cancelling an async* stream suspended in `await for` only
      // completes at the next event (the repository's dispose ends it).
      unawaited(sub.cancel());
      expect(seen.first, isEmpty);
      expect(seen.last, ['b']);
      expect(seen.any((l) => l.length == 2), isTrue);
    });

    test('offline: put and delete throw StateError and change nothing',
        () async {
      await repo.put('u1', quickEntry(id: 'a'));
      repo.offline = true;
      await expectLater(repo.put('u1', quickEntry(id: 'b')), throwsStateError);
      await expectLater(repo.delete('u1', 'a'), throwsStateError);
      repo.offline = false;
      expect(await ids('u1', kToday), ['a']);
      expect(repo.writes, 1);
    });
  });

  group('InMemorySavedFoodsRepository', () {
    late InMemorySavedFoodsRepository repo;
    setUp(() => repo = InMemorySavedFoodsRepository());
    tearDown(() => repo.dispose());

    Future<List<String>> names(String uid) async =>
        [for (final f in await repo.watchAll(uid).first) f.name];

    test('sorted by name ignoring case', () async {
      await repo.put('u1', const SavedFood(id: '1', name: 'banana', per100g: _per));
      await repo.put('u1', const SavedFood(id: '2', name: 'Apple', per100g: _per));
      await repo.put('u1', const SavedFood(id: '3', name: 'cherry', per100g: _per));
      expect(await names('u1'), ['Apple', 'banana', 'cherry']);
    });

    test('accounts are isolated and delete works', () async {
      await repo.put('u1', const SavedFood(id: '1', name: 'A', per100g: _per));
      await repo.put('u2', const SavedFood(id: '1', name: 'B', per100g: _per));
      expect(await names('u1'), ['A']);
      await repo.delete('u1', '1');
      await repo.delete('u1', 'missing');
      expect(await names('u1'), isEmpty);
      expect(await names('u2'), ['B']);
    });

    test('an invalid food throws FormatException', () async {
      await expectLater(
          repo.put('u1', const SavedFood(id: '1', name: '', per100g: _per)),
          throwsFormatException);
      expect(await names('u1'), isEmpty);
    });

    test('the 500th is accepted, the 501st new one is a StateError, a replace '
        'at the cap is fine', () async {
      for (var i = 0; i < SavedFood.maxCount; i++) {
        await repo.put('u1', SavedFood(id: 'f$i', name: 'f$i', per100g: _per));
      }
      await expectLater(
          repo.put('u1', const SavedFood(id: 'new', name: 'n', per100g: _per)),
          throwsStateError);
      await repo.put('u1', const SavedFood(id: 'f0', name: 'renamed', per100g: _per));
      expect((await repo.watchAll('u1').first), hasLength(500));
      // Another account has its own quota.
      await repo.put('u2', const SavedFood(id: 'new', name: 'n', per100g: _per));
    });
  });

  group('SavedFood', () {
    SavedFood food({
      String name = 'x',
      Per100g per = _per,
      double? serving,
      String? barcode,
    }) =>
        SavedFood(id: 'i', name: name, per100g: per, servingG: serving, barcode: barcode);

    test('name: 80 characters accepted, 81 and blank refused', () {
      expect(food(name: 'a' * 80).validate(), isEmpty);
      expect(food(name: 'a' * 81).validate(), isNotEmpty);
      expect(food(name: '   ').validate(), isNotEmpty);
    });

    test('per100g bounds 0..1000 inclusive', () {
      const at = Per100g(kcal: 1000, proteinG: 1000, carbsG: 0, fatG: 0);
      const over = Per100g(kcal: 1000.1, proteinG: 0, carbsG: 0, fatG: 0);
      expect(food(per: at).validate(), isEmpty);
      expect(food(per: over).validate(), isNotEmpty);
    });

    test('serving: positive up to 100000; zero, negative, NaN refused', () {
      expect(food(serving: 100000).validate(), isEmpty);
      expect(food(serving: 100000.5).validate(), isNotEmpty);
      expect(food(serving: 0).validate(), isNotEmpty);
      expect(food(serving: -1).validate(), isNotEmpty);
      expect(food(serving: double.nan).validate(), isNotEmpty);
    });

    test('barcode: 32 characters accepted, 33 refused', () {
      expect(food(barcode: 'b' * 32).validate(), isEmpty);
      expect(food(barcode: 'b' * 33).validate(), isNotEmpty);
    });

    test('toJson omits null optionals and refuses invalid foods', () {
      expect(food().toJson().keys, containsAll(['schema', 'name', 'per100g']));
      expect(food().toJson().containsKey('servingG'), isFalse);
      expect(food().toJson().containsKey('barcode'), isFalse);
      expect(food(serving: 30, barcode: '123').toJson()['servingG'], 30);
      expect(() => food(name: '').toJson(), throwsFormatException);
    });

    test('tryFromJson: tolerant read, null for unusable documents', () {
      final f = SavedFood.tryFromJson('i', {
        'name': 'Oats',
        'per100g': {'kcal': 70, 'proteinG': 2, 'carbsG': 12, 'fatG': 1},
        'servingG': -5,
        'barcode': 7,
      })!;
      expect(f.name, 'Oats');
      expect(f.per100g.kcal, 70);
      expect(f.servingG, isNull, reason: 'invalid serving dropped');
      expect(f.barcode, isNull, reason: 'non-string barcode dropped');
      expect(SavedFood.tryFromJson('i', {'per100g': {}}), isNull);
      expect(SavedFood.tryFromJson('i', {'name': 'x'}), isNull);
    });
  });
}
