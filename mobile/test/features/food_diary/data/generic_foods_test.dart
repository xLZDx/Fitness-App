// C21 generic_foods_test: parse of the REAL bundled assets, nutrient sanity,
// RU name fallback, token search ranking and synonyms.
//
// Expected values come from the change record (2,590 / 321 rows), from the
// Atwater factors (4/4/9) and from public USDA values, not from the parser.
// Assets are read through dart:io relative to the `mobile/` package root
// (the working directory of `flutter test`).
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/food_diary/data/generic_foods.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_test/flutter_test.dart';

const _foodsPath = 'assets/nutrition/generic_foods_v1.json';
const _ruPath = 'assets/nutrition/generic_foods_ru.json';

String _row(
  String name, {
  int fdc = 1,
  String category = 'Test',
  Map<String, Object?>? per,
  Object? tags,
  bool withTags = true,
  bool derived = false,
}) {
  final m = <String, Object?>{
    'id': 'gen:$fdc',
    'name': name,
    'category': category,
    'per100g': per ??
        {'kcal': 100.0, 'proteinG': 5.0, 'carbsG': 10.0, 'fatG': 4.0},
    'sourceId': 'usda_fdc',
    'fdcId': fdc,
    if (withTags)
      'tags': tags ??
          {
            'allergens': <String>[],
            'allergenCertain': true,
            'animalProduct': false,
            'pescatarianOk': true,
          },
    if (derived) 'derivedEnergy': true,
  };
  return jsonEncode(m);
}

String _doc(List<String> rows) => '{"version":1,"foods":[${rows.join(',')}]}';

String _ru(Map<String, String> names) => jsonEncode({'names': names});

void main() {
  late String foodsRaw;
  late String ruRaw;
  late Map<String, dynamic> foodsDoc;
  late Map<String, dynamic> ruDoc;
  late GenericFoodTable table;

  setUpAll(() {
    foodsRaw = File(_foodsPath).readAsStringSync();
    ruRaw = File(_ruPath).readAsStringSync();
    foodsDoc = jsonDecode(foodsRaw) as Map<String, dynamic>;
    ruDoc = jsonDecode(ruRaw) as Map<String, dynamic>;
    table = GenericFoodTable.parse(foodsRaw, ruJson: ruRaw);
  });

  group('real asset: parse and row count', () {
    test('asset files exist and are valid JSON documents', () {
      expect(foodsDoc['foods'], isA<List<dynamic>>());
      expect((ruDoc['names'] as Map).isNotEmpty, isTrue);
    });

    test('2,590 rows in the file and every one parses (none skipped)', () {
      final raw = foodsDoc['foods'] as List<dynamic>;
      expect(raw.length, 2590);
      expect(table.foods.length, 2590);
    });

    test('ids are unique, gen:<fdcId>, and fdcId is positive', () {
      final ids = <String>{};
      for (final f in table.foods) {
        expect(f.id, 'gen:${f.fdcId}', reason: f.name);
        expect(f.fdcId, greaterThan(0), reason: f.name);
        expect(ids.add(f.id), isTrue, reason: 'duplicate id ${f.id}');
      }
      expect(ids.length, 2590);
    });

    test('names are non-empty and unique (RU table is keyed by name)', () {
      final names = <String>{};
      for (final f in table.foods) {
        expect(f.name.trim(), isNotEmpty);
        expect(f.category, isNotEmpty, reason: f.name);
        names.add(f.name);
      }
      expect(names.length, 2590);
    });

    test('21 categories are present, including the ones suggestions rely on',
        () {
      final cats = table.foods.map((f) => f.category).toSet();
      expect(cats.length, 21);
      for (final c in [
        'Poultry Products',
        'Fats and Oils',
        'Spices and Herbs',
        'Sweets',
        'Beverages',
        'Finfish and Shellfish Products',
        'Dairy and Egg Products',
      ]) {
        expect(cats, contains(c));
      }
    });

    test('byId finds a real row and returns null for unknown ids', () {
      final egg = table.byId('gen:171287');
      expect(egg, isNotNull);
      expect(egg!.name, 'Egg, whole, raw, fresh');
      expect(table.byId('gen:0'), isNull);
      expect(table.byId(''), isNull);
    });

    test('anchor row Egg, whole, raw, fresh keeps its USDA values and tags',
        () {
      final egg = table.byId('gen:171287')!;
      expect(egg.per100g.kcal, 143.0);
      expect(egg.per100g.proteinG, 12.6);
      expect(egg.per100g.carbsG, 0.72);
      expect(egg.per100g.fatG, 9.51);
      expect(egg.category, 'Dairy and Egg Products');
      expect(egg.tags.allergens, {FoodAllergen.eggs});
      expect(egg.tags.allergenCertain, isTrue);
      expect(egg.tags.animalProduct, isTrue);
      expect(egg.tags.pescatarianOk, isTrue);
      expect(egg.tags.isUncertain, isFalse);
    });

    test('derivedEnergy is false on every row (no row used the 4/4/9 fallback)',
        () {
      expect(table.foods.where((f) => f.derivedEnergy), isEmpty);
    });
  });

  group('real asset: nutrient sanity per 100 g', () {
    test('no negative or non-finite values, kcal <= 900, macros <= 100.5 g',
        () {
      for (final f in table.foods) {
        final p = f.per100g;
        for (final v in [p.kcal, p.proteinG, p.carbsG, p.fatG]) {
          expect(v.isFinite && v >= 0, isTrue, reason: f.name);
        }
        expect(p.kcal, lessThanOrEqualTo(900.0), reason: f.name);
        expect(p.proteinG + p.carbsG + p.fatG, lessThanOrEqualTo(100.5),
            reason: f.name);
      }
    });

    test('energy is not above Atwater 4/4/9 + 15% + 10 kcal (non-alcohol)', () {
      // Documented exceptions: vinegars (acetic acid) and vanilla extract
      // (35% ethanol, not tagged alcohol on purpose: a flavouring).
      const exempt = {'Vinegar, cider', 'Vinegar, distilled', 'Vanilla extract'};
      final bad = <String>[];
      for (final f in table.foods) {
        if (f.tags.alcohol || exempt.contains(f.name)) continue;
        final p = f.per100g;
        final atwater = 4 * p.proteinG + 4 * p.carbsG + 9 * p.fatG;
        if (p.kcal > atwater * 1.15 + 10) bad.add('${f.name} ${p.kcal}>$atwater');
      }
      expect(bad, isEmpty);
    });

    test('energy is not below half of Atwater minus 10 kcal (fibre/polyols)',
        () {
      // Stevia extract is listed as 100 g carbohydrate with 0 kcal.
      const exempt = {'Sweetener, herbal extract powder from Stevia leaf'};
      final bad = <String>[];
      for (final f in table.foods) {
        if (f.tags.alcohol || exempt.contains(f.name)) continue;
        final p = f.per100g;
        final atwater = 4 * p.proteinG + 4 * p.carbsG + 9 * p.fatG;
        if (p.kcal < atwater * 0.5 - 10) bad.add('${f.name} ${p.kcal}<$atwater');
      }
      expect(bad, isEmpty);
    });

    test('alcohol rows carry energy beyond the macros (7 kcal/g ethanol)', () {
      final alcohol = table.foods.where((f) => f.tags.alcohol).toList();
      expect(alcohol.length, greaterThanOrEqualTo(30));
      final vodka = alcohol
          .firstWhere((f) => f.name == 'Alcoholic beverage, distilled, vodka, 80 proof');
      // 0 g of every macro yet 231 kcal: Atwater alone would be 0.
      expect(vodka.per100g.kcal, 231.0);
      expect(vodka.per100g.proteinG + vodka.per100g.carbsG + vodka.per100g.fatG,
          0.0);
    });

    test('anchor foods fall in well-known USDA ranges per 100 g', () {
      GenericFood byName(String n) => table.foods.firstWhere((f) => f.name == n);
      final salmon = byName('Fish, salmon, Atlantic, farmed, raw');
      expect(salmon.per100g.proteinG, inInclusiveRange(18, 22));
      expect(salmon.per100g.kcal, inInclusiveRange(190, 215));
      final peanuts = byName('Peanuts, raw');
      expect(peanuts.per100g.fatG, inInclusiveRange(40, 52));
      expect(peanuts.per100g.kcal, inInclusiveRange(540, 600));
      final oats = byName('Oats, whole grain, rolled, old fashioned');
      expect(oats.per100g.carbsG, inInclusiveRange(60, 72));
      final brownRice = byName('Rice, brown, long-grain, raw');
      expect(brownRice.per100g.kcal, inInclusiveRange(350, 380));
    });

    test('pure-fat rows sit between 7.4 and 9 kcal/g (lecithin is 7.6)', () {
      final oils = table.foods.where((f) => f.name.startsWith('Oil, ')).toList();
      expect(oils, isNotEmpty);
      for (final o in oils) {
        if (o.per100g.fatG < 99) continue;
        expect(o.per100g.kcal,
            inInclusiveRange(7.4 * o.per100g.fatG, 9.0 * o.per100g.fatG + 1),
            reason: o.name);
      }
    });
  });

  group('real asset: tag integrity', () {
    test('every certain-vegan row (animalProduct false) has no animal allergen',
        () {
      const animal = {
        FoodAllergen.milk,
        FoodAllergen.eggs,
        FoodAllergen.fish,
        FoodAllergen.crustaceans,
        FoodAllergen.molluscs,
      };
      for (final f in table.foods) {
        if (f.tags.animalProduct == false) {
          expect(f.tags.allergens.intersection(animal), isEmpty,
              reason: '${f.name} ${f.tags.allergens}');
        }
      }
    });

    test('regression: Eggplant is not tagged with the egg allergen', () {
      final eggplants = table.foods.where((f) => f.name.startsWith('Eggplant'));
      expect(eggplants.length, 2);
      for (final f in eggplants) {
        expect(f.tags.allergens, isNot(contains(FoodAllergen.eggs)),
            reason: f.name);
        expect(f.tags.animalProduct, isFalse);
      }
    });

    test('regression: malt liquor is tagged alcohol; every named alcohol is',
        () {
      final re = RegExp(
          r'\b(alcoholic|beer|wine|liqueur|liquor|whiskey|vodka|brandy)\b',
          caseSensitive: false);
      var seen = 0;
      for (final f in table.foods) {
        if (re.hasMatch(f.name)) {
          seen++;
          expect(f.tags.alcohol, isTrue, reason: f.name);
        }
      }
      expect(seen, greaterThanOrEqualTo(30));
      expect(table.byId('gen:171907')!.tags.alcohol, isTrue);
    });

    test('every Pork Products row and every pork-named row has the pork tag',
        () {
      for (final f in table.foods) {
        if (f.category == 'Pork Products') {
          expect(f.tags.pork, isTrue, reason: f.name);
          expect(f.tags.animalProduct, isTrue, reason: f.name);
          expect(f.tags.pescatarianOk, isFalse, reason: f.name);
        }
      }
      expect(table.foods.where((f) => f.tags.pork).length, 151);
    });

    test('meat categories are animal and not pescatarian', () {
      const meat = {
        'Beef Products',
        'Poultry Products',
        'Pork Products',
        'Lamb, Veal, and Game Products',
      };
      var n = 0;
      for (final f in table.foods) {
        if (meat.contains(f.category)) {
          n++;
          expect(f.tags.animalProduct, isTrue, reason: f.name);
          expect(f.tags.pescatarianOk, isFalse, reason: f.name);
        }
      }
      expect(n, 400);
    });

    test('fish rows: pescatarian-ok animal products with a fish-type allergen',
        () {
      var n = 0;
      for (final f in table.foods) {
        if (f.category != 'Finfish and Shellfish Products') continue;
        n++;
        expect(f.tags.animalProduct, isTrue, reason: f.name);
        expect(f.tags.pescatarianOk, isTrue, reason: f.name);
        expect(
            f.tags.allergens.intersection({
              FoodAllergen.fish,
              FoodAllergen.crustaceans,
              FoodAllergen.molluscs
            }),
            isNotEmpty,
            reason: f.name);
      }
      expect(n, 170);
    });

    test('uncertain rows exist (711 with unknown animal status) and are flagged',
        () {
      final unknown = table.foods.where((f) => f.tags.animalProduct == null);
      expect(unknown.length, 711);
      for (final f in unknown) {
        expect(f.tags.isUncertain, isTrue, reason: f.name);
        expect(f.tags.allergenCertain, isFalse, reason: f.name);
      }
    });

    test('baked products and sweets are never allergen-certain', () {
      for (final f in table.foods) {
        if (f.category == 'Baked Products' ||
            f.category == 'Soups, Sauces, and Gravies' ||
            f.category == 'Sausages and Luncheon Meats') {
          expect(f.tags.allergenCertain, isFalse, reason: f.name);
        }
      }
    });
  });

  group('real asset: RU names and fallback', () {
    test('321 RU names; every RU key is an exact English name in the table',
        () {
      final names = (ruDoc['names'] as Map).cast<String, String>();
      expect(names.length, 321);
      final byName = {for (final f in table.foods) f.name: f};
      for (final k in names.keys) {
        expect(byName.containsKey(k), isTrue, reason: 'orphan RU key $k');
      }
      expect(table.foods.where((f) => f.nameRu != null).length, 321);
    });

    test('RU value is applied to the right row (and trimmed)', () {
      expect(table.byId('gen:171287')!.nameRu, 'Яйцо куриное сырое');
      for (final f in table.foods.where((f) => f.nameRu != null)) {
        expect(f.nameRu, f.nameRu!.trim());
        expect(f.nameRu, isNotEmpty);
      }
    });

    test('RU names contain Cyrillic and no nutrition numbers are leaked', () {
      final cyr = RegExp(r'[А-Яа-яЁё]');
      for (final f in table.foods.where((f) => f.nameRu != null)) {
        expect(cyr.hasMatch(f.nameRu!), isTrue, reason: f.nameRu);
      }
    });

    test('displayName: ru and ru-RU use RU, en and others use English', () {
      final egg = table.byId('gen:171287')!;
      expect(egg.displayName('ru'), 'Яйцо куриное сырое');
      expect(egg.displayName('ru-RU'), 'Яйцо куриное сырое');
      expect(egg.displayName('RU'), 'Яйцо куриное сырое');
      expect(egg.displayName('en'), 'Egg, whole, raw, fresh');
      expect(egg.displayName('de'), 'Egg, whole, raw, fresh');
    });

    test('a food with no RU entry falls back to the English name for ru', () {
      final noRu = table.foods.firstWhere((f) => f.nameRu == null);
      expect(noRu.displayName('ru'), noRu.name);
      expect(noRu.displayName('ru-RU'), noRu.name);
      expect(table.foods.where((f) => f.nameRu == null).length, 2590 - 321);
    });

    test('without ruJson no row has a RU name and ru falls back everywhere',
        () {
      final en = GenericFoodTable.parse(foodsRaw);
      expect(en.foods.length, 2590);
      expect(en.foods.where((f) => f.nameRu != null), isEmpty);
      expect(en.byId('gen:171287')!.displayName('ru'),
          'Egg, whole, raw, fresh');
    });
  });

  group('parse: malformed input is contained', () {
    test('non-JSON, wrong shape and empty documents give an empty table', () {
      for (final bad in ['', 'not json', '[]', '{}', '{"foods":5}', 'null']) {
        final t = GenericFoodTable.parse(bad);
        expect(t.foods, isEmpty, reason: bad);
        expect(t.search('egg'), isEmpty);
      }
      expect(GenericFoodTable.empty().foods, isEmpty);
    });

    test('bad rows are skipped, good rows around them are kept', () {
      final good1 = _row('Apple, raw', fdc: 11);
      final good2 = _row('Bread, rye', fdc: 12);
      final t = GenericFoodTable.parse(_doc([
        good1,
        '"just a string"',
        '42',
        '{"id":"gen:1","name":"No per","fdcId":1}',
        '{"id":"gen:2","per100g":{"kcal":1,"proteinG":1,"carbsG":1,"fatG":1},"fdcId":2}',
        '{"name":"No id","per100g":{"kcal":1,"proteinG":1,"carbsG":1,"fatG":1},"fdcId":3}',
        '{"id":"gen:4","name":"No fdc","per100g":{"kcal":1,"proteinG":1,"carbsG":1,"fatG":1}}',
        good2,
      ]));
      expect(t.foods.map((f) => f.id), ['gen:11', 'gen:12']);
    });

    test('negative, missing and non-numeric nutrient values drop the row', () {
      Map<String, Object?> per(Object? k, Object? p, Object? c, Object? f) =>
          {'kcal': k, 'proteinG': p, 'carbsG': c, 'fatG': f};
      final t = GenericFoodTable.parse(_doc([
        _row('neg kcal', fdc: 1, per: per(-1, 1, 1, 1)),
        _row('neg protein', fdc: 2, per: per(1, -0.1, 1, 1)),
        _row('str carbs', fdc: 3, per: per(1, 1, '5', 1)),
        _row('null fat', fdc: 4, per: per(1, 1, 1, null)),
        _row('missing', fdc: 5, per: {'kcal': 1, 'proteinG': 1}),
        _row('zeros ok', fdc: 6, per: per(0, 0, 0, 0)),
        _row('ints ok', fdc: 7, per: per(52, 1, 14, 0)),
      ]));
      expect(t.foods.map((f) => f.name), ['zeros ok', 'ints ok']);
      expect(t.byId('gen:7')!.per100g.kcal, 52.0);
      expect(t.byId('gen:7')!.per100g.carbsG, 14.0);
    });

    test('fdcId given as a JSON number with fraction is truncated, string drops',
        () {
      final t = GenericFoodTable.parse(_doc([
        '{"id":"gen:9","name":"A","per100g":{"kcal":1,"proteinG":1,"carbsG":1,"fatG":1},"fdcId":9.0}',
        '{"id":"gen:10","name":"B","per100g":{"kcal":1,"proteinG":1,"carbsG":1,"fatG":1},"fdcId":"10"}',
      ]));
      expect(t.foods.map((f) => f.id), ['gen:9']);
      expect(t.foods.single.fdcId, 9);
    });

    test('missing category becomes empty string; derivedEnergy flag is read',
        () {
      final t = GenericFoodTable.parse(_doc([
        '{"id":"gen:1","name":"X","per100g":{"kcal":1,"proteinG":1,"carbsG":1,"fatG":1},"fdcId":1,"derivedEnergy":true}',
        _row('Y', fdc: 2, derived: false),
      ]));
      expect(t.byId('gen:1')!.category, '');
      expect(t.byId('gen:1')!.derivedEnergy, isTrue);
      expect(t.byId('gen:2')!.derivedEnergy, isFalse);
    });

    test('malformed or oddly typed RU document is ignored, foods still load',
        () {
      final foods = _doc([_row('Apple, raw', fdc: 1)]);
      for (final ru in [
        'garbage',
        '[]',
        '{"names":5}',
        '{"names":{"Apple, raw":7}}',
        '{"names":{"Apple, raw":"   "}}',
        '{"names":{"Pear":"Груша"}}',
      ]) {
        final t = GenericFoodTable.parse(foods, ruJson: ru);
        expect(t.foods.length, 1, reason: ru);
        expect(t.foods.single.nameRu, isNull, reason: ru);
      }
      final ok = GenericFoodTable.parse(foods,
          ruJson: _ru({'Apple, raw': '  Яблоко сырое  '}));
      expect(ok.foods.single.nameRu, 'Яблоко сырое');
    });

    test('table lists are unmodifiable', () {
      final t = GenericFoodTable.parse(_doc([_row('A', fdc: 1)]));
      expect(() => t.foods.add(t.foods.first), throwsUnsupportedError);
    });
  });

  group('tag parse is restrictive', () {
    GenericFood one(Object? tags, {bool withTags = true}) =>
        GenericFoodTable.parse(_doc([
          _row('T', fdc: 1, tags: tags, withTags: withTags),
        ])).foods.single;

    test('missing tag block: nothing certain, nothing known', () {
      final f = one(null, withTags: false);
      expect(f.tags.allergenCertain, isFalse);
      expect(f.tags.animalProduct, isNull);
      expect(f.tags.pescatarianOk, isNull);
      expect(f.tags.allergens, isEmpty);
      expect(f.tags.pork, isFalse);
      expect(f.tags.alcohol, isFalse);
      expect(f.tags.isUncertain, isTrue);
    });

    test('non-map tag block behaves like a missing one', () {
      for (final raw in ['"x"', '7', '[]']) {
        final t = GenericFoodTable.parse(_doc([
          '{"id":"gen:1","name":"T","per100g":{"kcal":1,"proteinG":1,"carbsG":1,"fatG":1},"fdcId":1,"tags":$raw}',
        ])).foods.single;
        expect(t.tags.isUncertain, isTrue, reason: raw);
        expect(t.tags.allergenCertain, isFalse, reason: raw);
      }
    });

    test('a fully specified block is read exactly', () {
      final f = one({
        'allergens': ['milk', 'treeNuts'],
        'allergenCertain': true,
        'animalProduct': true,
        'pescatarianOk': false,
        'pork': true,
        'alcohol': true,
      });
      expect(f.tags.allergens, {FoodAllergen.milk, FoodAllergen.treeNuts});
      expect(f.tags.allergenCertain, isTrue);
      expect(f.tags.animalProduct, isTrue);
      expect(f.tags.pescatarianOk, isFalse);
      expect(f.tags.pork, isTrue);
      expect(f.tags.alcohol, isTrue);
      expect(f.tags.isUncertain, isFalse);
    });

    test('unknown allergen name makes the row uncertain, known ones are kept',
        () {
      final f = one({
        'allergens': ['milk', 'kryptonite'],
        'allergenCertain': true,
        'animalProduct': true,
        'pescatarianOk': true,
      });
      expect(f.tags.allergens, {FoodAllergen.milk});
      expect(f.tags.allergenCertain, isFalse);
      expect(f.tags.isUncertain, isTrue);
    });

    test('allergens not a list makes the row uncertain', () {
      final f = one({
        'allergens': 'milk',
        'allergenCertain': true,
        'animalProduct': false,
        'pescatarianOk': true,
      });
      expect(f.tags.allergenCertain, isFalse);
      expect(f.tags.isUncertain, isTrue);
    });

    test('allergenCertain must be literally true; truthy strings do not count',
        () {
      for (final v in ['"true"', '1', 'null', 'false']) {
        final t = GenericFoodTable.parse(_doc([
          '{"id":"gen:1","name":"T","per100g":{"kcal":1,"proteinG":1,"carbsG":1,"fatG":1},"fdcId":1,"tags":{"allergens":[],"allergenCertain":$v,"animalProduct":false,"pescatarianOk":true}}',
        ])).foods.single;
        expect(t.tags.allergenCertain, isFalse, reason: v);
      }
    });

    test('animalProduct / pescatarianOk of a non-bool type become null', () {
      final f = one({
        'allergens': <String>[],
        'allergenCertain': true,
        'animalProduct': 'no',
        'pescatarianOk': 0,
      });
      expect(f.tags.animalProduct, isNull);
      expect(f.tags.pescatarianOk, isNull);
      expect(f.tags.isUncertain, isTrue);
    });

    test('each of the three unknowns alone is enough for isUncertain', () {
      const certainVegan = GenericFoodTags(
          allergenCertain: true, animalProduct: false, pescatarianOk: true);
      expect(certainVegan.isUncertain, isFalse);
      expect(
          const GenericFoodTags(
                  allergenCertain: false, animalProduct: false, pescatarianOk: true)
              .isUncertain,
          isTrue);
      expect(
          const GenericFoodTags(
                  allergenCertain: true, animalProduct: null, pescatarianOk: true)
              .isUncertain,
          isTrue);
      expect(
          const GenericFoodTags(
                  allergenCertain: true, animalProduct: false, pescatarianOk: null)
              .isUncertain,
          isTrue);
    });

    test('GenericFoodHit.showTagWarning mirrors uncertainty', () {
      final t = GenericFoodTable.parse(_doc([
        _row('Sure apple', fdc: 1),
        _row('Mystery apple', fdc: 2, withTags: false),
      ]));
      final hits = t.search('apple');
      expect(hits.length, 2);
      expect(hits.firstWhere((h) => h.food.id == 'gen:1').showTagWarning,
          isFalse);
      expect(hits.firstWhere((h) => h.food.id == 'gen:2').showTagWarning,
          isTrue);
    });
  });

  group('tokenize', () {
    test('lowercases, splits on punctuation, keeps digits and unicode', () {
      expect(tokenize('Milk, whole, 3.25% milkfat'),
          ['milk', 'whole', '3', '25', 'milkfat']);
      expect(tokenize('  Овсяные хлопья!! '), ['овсяные', 'хлопья']);
      expect(tokenize('Жёлтый'), ['желтый']);
      expect(tokenize(''), isEmpty);
      expect(tokenize(' ,.; '), isEmpty);
    });
  });

  group('search ranking (synthetic table, exact expectations)', () {
    GenericFoodTable mk(List<(String, int)> rows, {Map<String, String>? ru}) =>
        GenericFoodTable.parse(
          _doc([for (final (n, id) in rows) _row(n, fdc: id)]),
          ruJson: ru == null ? null : _ru(ru),
        );

    test('exact token beats prefix beats substring', () {
      final t = mk([
        ('Sunflower seeds', 1), // substring "flower"
        ('Flowerpot cake', 2), // prefix "flower"
        ('Flower, edible', 3), // exact "flower"
      ]);
      final hits = t.search('flower');
      expect(hits.map((h) => h.food.id), ['gen:3', 'gen:2', 'gen:1']);
      expect(hits.map((h) => h.score), [3, 2, 1]);
    });

    test('substring needs a query of 3+ letters', () {
      final t = mk([('Cheese', 1), ('Chickpeas', 2)]);
      // "ee" is inside "cheese" but only 2 chars: no substring hit.
      expect(t.search('ee'), isEmpty);
      expect(t.search('eese').map((h) => h.food.id), ['gen:1']);
      // 2-char prefix still works.
      expect(t.search('ch').map((h) => h.food.id).toSet(), {'gen:1', 'gen:2'});
    });

    test('every query token must match; scores add up', () {
      final t = mk([
        ('Rice, brown, raw', 1),
        ('Rice, white, raw', 2),
        ('Beans, brown', 3),
      ]);
      final hits = t.search('brown rice');
      expect(hits.map((h) => h.food.id), ['gen:1']);
      expect(hits.single.score, 6);
      expect(t.search('brown rice pizza'), isEmpty);
      expect(t.search('rice').length, 2);
    });

    test('ties: shorter name first, then id ascending', () {
      final t = mk([
        ('Egg, whole, boiled and shelled', 5),
        ('Egg, raw', 9),
        ('Egg, dry', 3),
      ]);
      final hits = t.search('egg');
      expect(hits.map((h) => h.score).toSet(), {3});
      // "Egg, dry" (8) and "Egg, raw" (8) tie on length: id 3 before id 9.
      expect(hits.map((h) => h.food.id), ['gen:3', 'gen:9', 'gen:5']);
    });

    test('result order is stable across calls and input order', () {
      final rows = [
        ('Egg, dry', 3),
        ('Egg, raw', 9),
        ('Egg, whole, boiled and shelled', 5),
      ];
      final a = mk(rows).search('egg').map((h) => h.food.id).toList();
      final b = mk(rows.reversed.toList())
          .search('egg')
          .map((h) => h.food.id)
          .toList();
      expect(a, b);
      expect(mk(rows).search('egg').map((h) => h.food.id).toList(), a);
    });

    test('limit truncates after sorting; limit <= 0 and blank query are empty',
        () {
      final t = mk([for (var i = 1; i <= 30; i++) ('Egg $i', i)]);
      expect(t.search('egg').length, 20);
      expect(t.search('egg', limit: 3).length, 3);
      expect(t.search('egg', limit: 100).length, 30);
      expect(t.search('egg', limit: 0), isEmpty);
      expect(t.search('egg', limit: -1), isEmpty);
      expect(t.search(''), isEmpty);
      expect(t.search('   '), isEmpty);
      expect(t.search('!!!'), isEmpty);
    });

    test('case-insensitive and ё/е-insensitive, both in query and in data',
        () {
      final t = mk([('Oats', 1)], ru: {'Oats': 'Овёс'});
      expect(t.search('OATS').length, 1);
      expect(t.search('овес').length, 1);
      expect(t.search('ОВЁС').length, 1);
    });

    test('RU names are searchable regardless of UI language', () {
      final t = mk([('Cheese, cottage, lowfat', 1)],
          ru: {'Cheese, cottage, lowfat': 'Творог 2%'});
      expect(t.search('творог').map((h) => h.food.id), ['gen:1']);
      expect(t.search('твор').map((h) => h.food.id), ['gen:1']);
      expect(t.search('cottage').map((h) => h.food.id), ['gen:1']);
    });

    test('a row is not found by a RU word when it has no RU entry', () {
      final t = mk([('Cheese, cottage, lowfat', 1)]);
      expect(t.search('творог').map((h) => h.food.id), ['gen:1'],
          reason: 'synonym творог -> cottage still finds the English row');
      expect(t.search('арахис'), isEmpty);
    });
  });

  group('search synonyms', () {
    test('synonym table covers the documented EN and RU pairs', () {
      const s = GenericFoodTable.synonyms;
      expect(s['картошка'], contains('potatoes'));
      expect(s['курица'], contains('chicken'));
      expect(s['овсянка'], contains('oats'));
      expect(s['yoghurt'], contains('yogurt'));
      expect(s['творог'], contains('cottage'));
      expect(s['eggs'], contains('egg'));
      expect(s['peanut'], contains('peanuts'));
      for (final e in s.entries) {
        expect(e.key, equals(e.key.toLowerCase()));
        expect(e.value, isNotEmpty);
        for (final v in e.value) {
          expect(v, equals(v.toLowerCase()), reason: '${e.key} -> $v');
        }
      }
    });

    test('synonym lifts a row that the literal query cannot reach', () {
      final t = GenericFoodTable.parse(_doc([
        _row('Yogurt, plain', fdc: 1),
        _row('Potatoes, baked', fdc: 2),
      ]));
      expect(t.search('yoghurt').map((h) => h.food.id), ['gen:1']);
      expect(t.search('картошка').map((h) => h.food.id), ['gen:2']);
      expect(t.search('potato').map((h) => h.food.id), ['gen:2']);
    });

    test('synonym of one token still requires all other tokens to match', () {
      final t = GenericFoodTable.parse(_doc([
        _row('Potatoes, baked', fdc: 1),
        _row('Potatoes, boiled', fdc: 2),
      ]));
      expect(t.search('картошка baked').map((h) => h.food.id), ['gen:1']);
    });
  });

  group('search on the real table', () {
    List<String> ids(List<GenericFoodHit> h) => [for (final x in h) x.food.id];

    test('scores are non-increasing and results deterministic', () {
      for (final q in ['egg', 'chicken breast', 'rice', 'молоко', 'oat']) {
        final a = table.search(q, limit: 500);
        expect(a, isNotEmpty, reason: q);
        for (var i = 1; i < a.length; i++) {
          expect(a[i - 1].score, greaterThanOrEqualTo(a[i].score), reason: q);
        }
        expect(ids(table.search(q, limit: 500)), ids(a), reason: q);
      }
    });

    test('"egg" top hits are egg foods whose first token is exactly egg', () {
      final hits = table.search('egg', limit: 5);
      expect(hits.length, 5);
      for (final h in hits) {
        expect(h.score, 3);
        expect(tokenize(h.food.name), contains('egg'), reason: h.food.name);
      }
    });

    test('"eggplant" does not return egg foods', () {
      final hits = table.search('eggplant', limit: 50);
      expect(hits, isNotEmpty);
      for (final h in hits) {
        expect(h.food.name.toLowerCase(), contains('eggplant'));
      }
    });

    test('Russian "яйцо" finds the raw egg row through the RU name', () {
      final hits = table.search('яйцо', limit: 500);
      expect(ids(hits), contains('gen:171287'));
      expect(hits.first.score, 3);
    });

    test('Russian "творог" finds cottage cheese rows', () {
      final hits = table.search('творог', limit: 100);
      expect(hits, isNotEmpty);
      final top = hits.take(5).map((h) => h.food.name.toLowerCase());
      expect(top.every((n) => n.contains('cottage')), isTrue, reason: '$top');
    });

    test('Russian "курица" reaches chicken rows through the synonym', () {
      final hits = table.search('курица', limit: 100);
      expect(hits, isNotEmpty);
      expect(
          hits.any((h) => h.food.name.toLowerCase().contains('chicken')),
          isTrue);
      expect(hits.first.score, 3);
    });

    test('"овсянка" (porridge) reaches oats rows', () {
      final hits = table.search('овсянка', limit: 100);
      expect(hits.any((h) => h.food.name.toLowerCase().startsWith('oats')),
          isTrue);
    });

    test('"peanut" finds peanut foods and they carry the peanuts allergen', () {
      final hits = table.search('peanut', limit: 200);
      expect(hits, isNotEmpty);
      final raw = hits.firstWhere((h) => h.food.name == 'Peanuts, raw');
      expect(raw.food.tags.allergens, contains(FoodAllergen.peanuts));
    });

    test('multi-token real query narrows: "chicken breast" rows have both',
        () {
      final hits = table.search('chicken breast', limit: 100);
      expect(hits, isNotEmpty);
      for (final h in hits) {
        final n = h.food.name.toLowerCase();
        expect(n.contains('chicken') || n.contains('poultry'), isTrue,
            reason: n);
        expect(n.contains('breast'), isTrue, reason: n);
      }
      expect(hits.length, lessThan(table.search('chicken', limit: 2590).length));
    });

    test('nonsense query returns nothing', () {
      expect(table.search('zzzzqqqq'), isEmpty);
    });

    test('uncertain real rows stay searchable and show the warning', () {
      final mystery = table.foods.firstWhere((f) => f.tags.isUncertain);
      final first = tokenize(mystery.name).firstWhere((t) => t.length >= 4);
      final hit = table
          .search(first, limit: 2590)
          .firstWhere((h) => h.food.id == mystery.id);
      expect(hit.showTagWarning, isTrue);
    });
  });
}
