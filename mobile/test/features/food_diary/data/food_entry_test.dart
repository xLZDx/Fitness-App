// T96 food_entry_test (FOOD-23 entry model limits, serialisation, tolerant
// read). Limits mirror the firestore.rules foodEntryOk() function.
import 'dart:math' as math;

import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _p = Per100g(kcal: 200, proteinG: 10, carbsG: 20, fatG: 5);

FoodItem _item([String name = 'Rice', FoodSource s = FoodSource.usda]) =>
    FoodItem(
      foodRef: 'gen:1',
      name: name,
      grams: MacroRange(80, 100, 150),
      per100g: _p,
      matchQuality: MatchQuality.close,
      source: s,
    );

FoodEntry _entry({
  String day = '2026-10-15',
  String name = 'Lunch',
  List<FoodItem>? items,
  List<CheckItem> checks = const [],
  ModelRef? model,
}) =>
    FoodEntry(
      id: 'entry-uuid-1',
      day: day,
      slot: MealSlot.lunch,
      loggedAt: DateTime.utc(2026, 10, 15, 12, 30),
      name: name,
      source: EntrySource.photo,
      confidence: EntryConfidence.medium,
      items: items ?? [_item()],
      totals: MacroTotals(
        kcal: MacroRange(160, 200, 300),
        proteinG: MacroRange(8, 10, 15),
        carbsG: MacroRange(16, 20, 30),
        fatG: MacroRange(4, 5, 7.5),
      ),
      checkThese: checks,
      model: model,
    );

Map<String, dynamic> _validJson() => _entry(
      checks: CheckThese.fromCodes([CheckCode.portionUnclear]),
      model: const ModelRef(id: 'gemini', version: '2'),
    ).toJson();

void main() {
  group('MacroRange', () {
    test('sorts and sanitises on construction', () {
      expect(MacroRange(10, 5, 7), MacroRange(5, 7, 10));
      final r = MacroRange(double.nan, -3, double.infinity);
      expect(r, MacroRange(0, 0, 0));
      expect(MacroRange(double.negativeInfinity, 4, 9), MacroRange(0, 4, 9));
    });

    test('exact and zero', () {
      expect(MacroRange.exact(7), MacroRange(7, 7, 7));
      expect(MacroRange.zero, MacroRange(0, 0, 0));
      expect(MacroRange.exact(-7), MacroRange.zero);
    });

    test('scaled multiplies all bounds; bad factors give zero', () {
      expect(MacroRange(2, 4, 8).scaled(0.5), MacroRange(1, 2, 4));
      expect(MacroRange(2, 4, 8).scaled(0), MacroRange.zero);
      expect(MacroRange(2, 4, 8).scaled(-2), MacroRange.zero);
      expect(MacroRange(2, 4, 8).scaled(double.nan), MacroRange.zero);
      expect(MacroRange(2, 4, 8).scaled(double.infinity), MacroRange.zero);
    });

    test('plain + adds bound-wise', () {
      expect(MacroRange(1, 2, 3) + MacroRange(10, 20, 30),
          MacroRange(11, 22, 33));
    });

    test('combine: mids add, spreads are root-sum-square', () {
      final c = MacroRange.combine(
          [MacroRange(900, 1000, 1000), MacroRange(900, 1000, 1000)]);
      expect(c.mid, 2000);
      expect(c.low, closeTo(2000 - 100 * math.sqrt2, 1e-9));
      expect(c.high, 2000);
    });

    test('combine of nothing is zero', () {
      expect(MacroRange.combine(const []), MacroRange.zero);
    });

    test('combine low bound never goes negative', () {
      final c = MacroRange.combine([MacroRange(0, 10, 10), MacroRange(0, 10, 10)]);
      expect(c.mid, 20);
      expect(c.low, closeTo(20 - 10 * math.sqrt2, 1e-9));
      final tight = MacroRange.combine([MacroRange(0, 1, 1), MacroRange(0, 100, 100)]);
      expect(tight.low >= 0, isTrue);
    });

    test('toJson/fromJson round trip and tolerant read', () {
      final r = MacroRange(1.5, 2.5, 3.5);
      expect(r.toJson(), {'low': 1.5, 'mid': 2.5, 'high': 3.5});
      expect(MacroRange.fromJson(r.toJson()), r);
      expect(MacroRange.fromJson(null), MacroRange.zero);
      expect(MacroRange.fromJson('x'), MacroRange.zero);
      expect(MacroRange.fromJson({'low': 'a', 'mid': 5, 'high': -1}),
          MacroRange(0, 0, 5));
      expect(MacroRange.fromJson({'low': 9, 'mid': 2, 'high': 5}),
          MacroRange(2, 5, 9));
    });

    test('equality and hashCode', () {
      expect(MacroRange(1, 2, 3) == MacroRange(1, 2, 3), isTrue);
      expect(MacroRange(1, 2, 3) == MacroRange(1, 2, 4), isFalse);
      expect(MacroRange(1, 2, 3).hashCode, MacroRange(1, 2, 3).hashCode);
    });
  });

  group('Per100g / MacroTotals', () {
    test('Per100g json round trip and tolerant read', () {
      expect(Per100g.fromJson(_p.toJson()), _p);
      expect(_p.toJson(),
          {'kcal': 200.0, 'proteinG': 10.0, 'carbsG': 20.0, 'fatG': 5.0});
      expect(Per100g.fromJson(null),
          const Per100g(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0));
      expect(Per100g.fromJson({'kcal': -5, 'proteinG': 'x', 'carbsG': 3}),
          const Per100g(kcal: 0, proteinG: 0, carbsG: 3, fatG: 0));
    });

    test('rules bounds are inclusive 0..1000', () {
      Per100g k(double v) => Per100g(kcal: v, proteinG: 0, carbsG: 0, fatG: 0);
      expect(k(0).isWithinRulesBounds, isTrue);
      expect(k(1000).isWithinRulesBounds, isTrue);
      expect(k(1000.01).isWithinRulesBounds, isFalse);
      expect(k(-0.01).isWithinRulesBounds, isFalse);
      expect(k(double.nan).isWithinRulesBounds, isFalse);
      expect(
          const Per100g(kcal: 1, proteinG: 1001, carbsG: 0, fatG: 0)
              .isWithinRulesBounds,
          isFalse);
    });

    test('MacroTotals has exactly the four macro keys and round trips', () {
      final t = _entry().totals;
      expect(t.toJson().keys.toSet(), {'kcal', 'proteinG', 'carbsG', 'fatG'});
      expect(MacroTotals.fromJson(t.toJson()), t);
      expect(MacroTotals.fromJson(null), MacroTotals.zero);
    });

    test('MacroTotals.combine applies RSS per macro', () {
      final a = MacroTotals(
        kcal: MacroRange(90, 100, 100),
        proteinG: MacroRange(5, 10, 15),
        carbsG: MacroRange.zero,
        fatG: MacroRange.zero,
      );
      final c = MacroTotals.combine([a, a]);
      expect(c.kcal.low, closeTo(200 - 10 * math.sqrt2, 1e-9));
      expect(c.proteinG.low, closeTo(20 - 5 * math.sqrt2, 1e-9));
      expect(c.proteinG.high, closeTo(20 + 5 * math.sqrt2, 1e-9));
      expect(MacroTotals.combine(const []), MacroTotals.zero);
    });
  });

  group('enums mirror the Firestore rules allowlists', () {
    test('slot', () {
      expect(MealSlot.values.map((e) => e.name),
          ['breakfast', 'lunch', 'dinner', 'snack']);
    });
    test('source', () {
      expect(EntrySource.values.map((e) => e.name),
          ['photo', 'describe', 'search', 'barcode', 'label', 'manual']);
    });
    test('confidence', () {
      expect(EntryConfidence.values.map((e) => e.name),
          ['low', 'medium', 'high']);
    });
    test('matchQuality', () {
      expect(MatchQuality.values.map((e) => e.name),
          ['exact', 'close', 'weak', 'none']);
    });
  });

  group('toJson shape', () {
    test('minimal entry omits model and checkThese and the id', () {
      final j = _entry().toJson();
      expect(j.keys.toSet(), {
        'schema',
        'day',
        'slot',
        'loggedAt',
        'name',
        'source',
        'confidence',
        'items',
        'totals',
      });
      expect(j.containsKey('model'), isFalse);
      expect(j.containsKey('checkThese'), isFalse);
      expect(j.containsKey('id'), isFalse);
      expect(j.containsKey('degraded'), isFalse);
    });

    test('empty checkThese list is omitted (not serialised as [])', () {
      expect(_entry(checks: const []).toJson().containsKey('checkThese'),
          isFalse);
    });

    test('model and non-empty checkThese are emitted', () {
      final j = _validJson();
      expect(j['model'], {'id': 'gemini', 'version': '2'});
      expect(j['checkThese'], [
        {'code': 'portionUnclear', 'resolved': false}
      ]);
    });

    test('scalar fields', () {
      final j = _entry().toJson();
      expect(j['schema'], 1);
      expect(FoodEntry.schema, 1);
      expect(j['day'], '2026-10-15');
      expect(j['slot'], 'lunch');
      expect(j['source'], 'photo');
      expect(j['confidence'], 'medium');
      expect(j['name'], 'Lunch');
      expect(j['loggedAt'], '2026-10-15T12:30:00.000Z');
    });

    test('item json has exactly the six item keys', () {
      final item = _entry().toJson()['items'][0] as Map<String, dynamic>;
      expect(item.keys.toSet(), {
        'foodRef',
        'name',
        'grams',
        'per100g',
        'matchQuality',
        'sourceId',
      });
      expect(item['foodRef'], 'gen:1');
      expect(item['matchQuality'], 'close');
      expect(item['sourceId'], 'usda_fdc');
      expect(item['grams'], {'low': 80.0, 'mid': 100.0, 'high': 150.0});
    });

    test('totals json carries all four macro ranges', () {
      final t = _entry().toJson()['totals'] as Map<String, dynamic>;
      expect(t['kcal'], {'low': 160.0, 'mid': 200.0, 'high': 300.0});
      expect(t['fatG'], {'low': 4.0, 'mid': 5.0, 'high': 7.5});
    });
  });

  group('round trip', () {
    test('toJson -> fromJson restores every field', () {
      final src = _entry(
        checks: CheckThese.fromCodes(
            [CheckCode.hiddenIngredients, CheckCode.cookingMethod]),
        model: const ModelRef(id: 'gemini', version: '2'),
        items: [_item('Rice'), _item('Oil', FoodSource.llmEstimate)],
      );
      final back = FoodEntry.fromJson(src.id, src.toJson());
      expect(back.id, src.id);
      expect(back.day, src.day);
      expect(back.slot, src.slot);
      expect(back.loggedAt, src.loggedAt);
      expect(back.name, src.name);
      expect(back.source, src.source);
      expect(back.confidence, src.confidence);
      expect(back.items.length, 2);
      expect(back.items[1].source, FoodSource.llmEstimate);
      expect(back.items[0].grams, MacroRange(80, 100, 150));
      expect(back.items[0].per100g, _p);
      expect(back.items[0].matchQuality, MatchQuality.close);
      expect(back.totals, src.totals);
      expect(back.checkThese.map((c) => c.code).toList(),
          [CheckCode.hiddenIngredients, CheckCode.cookingMethod]);
      expect(back.model!.id, 'gemini');
      expect(back.model!.version, '2');
      expect(back.degraded, isFalse);
      expect(back.toJson(), src.toJson());
    });

    test('resolved flags survive the round trip', () {
      final src = _entry(checks: [
        const CheckItem(code: CheckCode.portionUnclear, resolved: true),
        const CheckItem(code: CheckCode.cookingMethod),
      ]);
      final back = FoodEntry.fromJson('x', src.toJson());
      expect(back.checkThese.map((c) => c.resolved).toList(), [true, false]);
    });

    test('unicode names survive', () {
      final src = _entry(name: 'Борщ с говядиной', items: [_item('Свёкла')]);
      final back = FoodEntry.fromJson('x', src.toJson());
      expect(back.name, 'Борщ с говядиной');
      expect(back.items.single.name, 'Свёкла');
    });
  });

  group('limits (refused on write)', () {
    test('30 items accepted, 31 refused', () {
      final ok = _entry(items: List.generate(30, (_) => _item()));
      expect(ok.validate(), isEmpty);
      expect(() => ok.toJson(), returnsNormally);
      expect(FoodEntry.maxItems, 30);
      final bad = _entry(items: List.generate(31, (_) => _item()));
      expect(bad.validate(), isNotEmpty);
      expect(() => bad.toJson(), throwsFormatException);
    });

    test('1 item accepted, 0 items refused', () {
      expect(_entry(items: [_item()]).validate(), isEmpty);
      final bad = _entry(items: const []);
      expect(bad.validate(), isNotEmpty);
      expect(() => bad.toJson(), throwsFormatException);
    });

    test('8 check items accepted, 9 refused', () {
      final eight = _entry(checks: CheckThese.fromCodes(CheckCode.values));
      expect(eight.checkThese.length, 8);
      expect(eight.validate(), isEmpty);
      final nine = _entry(checks: [
        for (final c in CheckCode.values.take(9)) CheckItem(code: c),
      ]);
      expect(nine.checkThese.length, 9);
      expect(nine.validate(), isNotEmpty);
      expect(() => nine.toJson(), throwsFormatException);
    });

    test('entry name 80 chars accepted, 81 refused', () {
      expect(_entry(name: 'a' * 80).validate(), isEmpty);
      final bad = _entry(name: 'a' * 81);
      expect(bad.validate(), isNotEmpty);
      expect(() => bad.toJson(), throwsFormatException);
      expect(FoodEntry.maxNameLength, 80);
    });

    test('item name 80 chars accepted, 81 refused', () {
      expect(_entry(items: [_item('b' * 80)]).validate(), isEmpty);
      final bad = _entry(items: [_item('b' * 81)]);
      expect(bad.validate(), isNotEmpty);
      expect(() => bad.toJson(), throwsFormatException);
      expect(FoodItem.maxNameLength, 80);
    });

    test('empty entry name is accepted (rules require only a string <= 80)',
        () {
      expect(_entry(name: '').validate(), isEmpty);
    });

    for (final d in <String>[
      '',
      '2026-1-5',
      '26-10-15',
      '2026/10/15',
      '2026-10-15T00:00',
      ' 2026-10-15',
      '2026-10-15 ',
      '2026-10-15\n',
      'abcd-ef-gh',
    ]) {
      test('bad day "${d.replaceAll('\n', '\\n')}" refused', () {
        final e = _entry(day: d);
        expect(e.validate(), isNotEmpty);
        expect(() => e.toJson(), throwsFormatException);
      });
    }

    test('good day accepted', () {
      expect(_entry(day: '2026-02-30').validate(), isEmpty,
          reason: 'shape only, like the rules regex');
      expect(_entry(day: '1999-12-31').validate(), isEmpty);
    });

    test('FormatException message names the problem', () {
      final e = _entry(day: 'nope');
      expect(
          () => e.toJson(),
          throwsA(isA<FormatException>()
              .having((x) => x.message, 'message', contains('yyyy-MM-dd'))));
    });

    test('several problems are all listed', () {
      final e = _entry(day: 'x', name: 'a' * 81, items: const []);
      expect(e.validate().length, 3);
    });
  });

  group('tolerant read (degrade, then refuse on write)', () {
    test('a valid document is not degraded', () {
      expect(FoodEntry.fromJson('x', _validJson()).degraded, isFalse);
    });

    void degrades(String label, void Function(Map<String, dynamic>) mutate,
        void Function(FoodEntry) check) {
      test(label, () {
        final j = _validJson();
        mutate(j);
        final e = FoodEntry.fromJson('x', j);
        expect(e.degraded, isTrue);
        check(e);
        expect(e.validate(), isNotEmpty);
        expect(() => e.toJson(), throwsFormatException);
        expect(e.copyWith(name: 'renamed').degraded, isTrue,
            reason: 'copyWith keeps the degraded flag');
      });
    }

    degrades('unknown slot -> snack', (j) => j['slot'] = 'brunch',
        (e) => expect(e.slot, MealSlot.snack));
    degrades('missing slot -> snack', (j) => j.remove('slot'),
        (e) => expect(e.slot, MealSlot.snack));
    degrades('unknown source -> manual', (j) => j['source'] = 'telepathy',
        (e) => expect(e.source, EntrySource.manual));
    degrades('unknown confidence -> low', (j) => j['confidence'] = 'certain',
        (e) => expect(e.confidence, EntryConfidence.low));
    degrades(
        'unknown item matchQuality -> none',
        (j) => (j['items'][0] as Map)['matchQuality'] = 'perfect',
        (e) => expect(e.items.single.matchQuality, MatchQuality.none));
    degrades(
        'unknown item sourceId -> user',
        (j) => (j['items'][0] as Map)['sourceId'] = 'wikipedia',
        (e) => expect(e.items.single.source, FoodSource.user));

    test('SF-F12: missing totals or loggedAt set the degraded flag', () {
      final noTotals = _validJson()..remove('totals');
      expect(FoodEntry.fromJson('x', noTotals).degraded, isTrue);
      final noTime = _validJson()..remove('loggedAt');
      expect(FoodEntry.fromJson('x', noTime).degraded, isTrue);
      final badTime = _validJson()..['loggedAt'] = 'yesterday-ish';
      expect(FoodEntry.fromJson('x', badTime).degraded, isTrue);
    });

    test('non-map item rows are dropped; the rest are kept', () {
      final j = _validJson();
      j['items'] = ['junk', null, 5, (j['items'] as List).first];
      final e = FoodEntry.fromJson('x', j);
      expect(e.items.length, 1);
    });

    test('items that is not a list gives no items (and refuses write)', () {
      final j = _validJson()..['items'] = 'nope';
      final e = FoodEntry.fromJson('x', j);
      expect(e.items, isEmpty);
      expect(() => e.toJson(), throwsFormatException);
    });

    test('unknown check codes are dropped, duplicates collapse', () {
      final j = _validJson()
        ..['checkThese'] = [
          {'code': 'madeUp', 'resolved': true},
          {'code': 'cookingMethod', 'resolved': false},
          {'code': 'cookingMethod', 'resolved': true},
        ];
      final e = FoodEntry.fromJson('x', j);
      expect(e.checkThese.length, 1);
      expect(e.checkThese.single.code, CheckCode.cookingMethod);
      expect(e.checkThese.single.resolved, isTrue);
      expect(e.degraded, isFalse);
    });

    test('more than 8 stored chips are capped at 8 on read', () {
      final j = _validJson()
        ..['checkThese'] = [
          for (final c in CheckCode.values) {'code': c.name},
        ];
      expect(FoodEntry.fromJson('x', j).checkThese.length, 8);
    });

    test('missing / invalid loggedAt -> epoch; DateTime accepted', () {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      expect(
          FoodEntry.fromJson('x', _validJson()..remove('loggedAt')).loggedAt,
          epoch);
      expect(
          FoodEntry.fromJson('x', _validJson()..['loggedAt'] = 'yesterday')
              .loggedAt,
          epoch);
      expect(FoodEntry.fromJson('x', _validJson()..['loggedAt'] = 12345).loggedAt,
          epoch);
      final at = DateTime.utc(2026, 1, 2, 3);
      expect(FoodEntry.fromJson('x', _validJson()..['loggedAt'] = at).loggedAt,
          at);
    });

    test('missing day / name / totals fall back to safe values', () {
      final j = _validJson()
        ..remove('day')
        ..remove('name')
        ..remove('totals');
      final e = FoodEntry.fromJson('x', j);
      expect(e.day, '');
      expect(e.name, '');
      expect(e.totals, MacroTotals.zero);
      expect(() => e.toJson(), throwsFormatException,
          reason: 'empty day is not yyyy-MM-dd');
    });

    test('model needs a non-empty string id, version defaults to empty', () {
      expect(FoodEntry.fromJson('x', _validJson()..['model'] = {'id': ''}).model,
          isNull);
      expect(FoodEntry.fromJson('x', _validJson()..['model'] = 'gemini').model,
          isNull);
      final m =
          FoodEntry.fromJson('x', _validJson()..['model'] = {'id': 'g'}).model;
      expect(m!.id, 'g');
      expect(m.version, '');
      expect(FoodEntry.fromJson('x', _validJson()..remove('model')).model,
          isNull);
    });

    test('item with missing fields is read with safe defaults', () {
      final j = _validJson()..['items'] = [<String, dynamic>{}];
      final e = FoodEntry.fromJson('x', j);
      final it = e.items.single;
      expect(it.foodRef, 'user:unknown');
      expect(it.name, '');
      expect(it.grams, MacroRange.zero);
      expect(it.matchQuality, MatchQuality.none);
      expect(it.source, FoodSource.user);
      expect(e.degraded, isTrue);
    });
  });

  group('copyWith', () {
    test('changes only the requested fields', () {
      final e = _entry(model: const ModelRef(id: 'g', version: '1'));
      final c = e.copyWith(slot: MealSlot.dinner, name: 'Dinner');
      expect(c.slot, MealSlot.dinner);
      expect(c.name, 'Dinner');
      expect(c.id, e.id);
      expect(c.day, e.day);
      expect(c.loggedAt, e.loggedAt);
      expect(c.source, e.source);
      expect(c.model, e.model);
      expect(c.items, e.items);
      expect(c.totals, e.totals);
      expect(e.slot, MealSlot.lunch);
    });

    test('FoodItem.copyWith keeps per100g, source and quality', () {
      final i = _item('x', FoodSource.label)
          .copyWith(grams: MacroRange.exact(5), name: 'y');
      expect(i.grams, MacroRange.exact(5));
      expect(i.name, 'y');
      expect(i.per100g, _p);
      expect(i.source, FoodSource.label);
      expect(i.matchQuality, MatchQuality.close);
      expect(i.foodRef, 'gen:1');
    });
  });
}
