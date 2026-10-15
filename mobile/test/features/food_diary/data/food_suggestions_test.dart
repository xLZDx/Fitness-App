// C21 food_suggestions_test: fitsFilter and suggestFoods.
//
// Restrictive-by-default contract (design 17.8, D-71): a row is suggested only
// when every relevant tag is KNOWN and compatible. Hidden rows stay searchable.
// Synthetic rows pin each rule exactly; the real bundled table proves the
// invariants on production data (dart:io read relative to `mobile/`).
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/food_diary/data/food_suggestions.dart';
import 'package:fitness_app/features/food_diary/data/generic_foods.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_test/flutter_test.dart';

GenericFood food(
  String name, {
  String id = '',
  String category = 'Test',
  double kcal = 100,
  double p = 0,
  double c = 0,
  double fat = 0,
  String? nameRu,
  GenericFoodTags tags = _vegan,
}) =>
    GenericFood(
      id: id.isEmpty ? 'gen:${name.hashCode}' : id,
      name: name,
      category: category,
      per100g: GenericPer100g(kcal: kcal, proteinG: p, carbsG: c, fatG: fat),
      fdcId: 1,
      tags: tags,
      nameRu: nameRu,
    );

// Known plant food with a certain, empty allergen list.
const _vegan = GenericFoodTags(
  allergenCertain: true,
  animalProduct: false,
  pescatarianOk: true,
);

GenericFoodTags animalTags({
  Set<FoodAllergen> allergens = const {},
  bool certain = true,
  bool? animal = true,
  bool? pesc = false,
  bool pork = false,
  bool alcohol = false,
}) =>
    GenericFoodTags(
      allergens: allergens,
      allergenCertain: certain,
      animalProduct: animal,
      pescatarianOk: pesc,
      pork: pork,
      alcohol: alcohol,
    );

const _unknown = GenericFoodTags(); // nothing certain, nothing known

SuggestionFilter diet(DietaryPreference d) => SuggestionFilter(diets: {d});
SuggestionFilter allergy(FoodAllergen a) => SuggestionFilter(allergens: {a});

String _foodsPath() => 'assets/nutrition/generic_foods_v1.json';
String _ruPath() => 'assets/nutrition/generic_foods_ru.json';

void main() {
  group('fitsFilter: no restriction', () {
    test('empty filter accepts every row, uncertain ones included', () {
      const f = SuggestionFilter();
      expect(fitsFilter(food('Plant'), f), isTrue);
      expect(fitsFilter(food('Mystery', tags: _unknown), f), isTrue);
      expect(
          fitsFilter(
              food('Pork', tags: animalTags(pork: true, alcohol: true)), f),
          isTrue);
    });

    test('diet "none" alone is not a restriction', () {
      expect(fitsFilter(food('Mystery', tags: _unknown),
              diet(DietaryPreference.none)),
          isTrue);
    });

    test('exclusions alone do not hide uncertain rows (name based only)', () {
      expect(
          fitsFilter(food('Mystery bread', tags: _unknown),
              const SuggestionFilter(exclusions: ['fish'])),
          isTrue);
    });
  });

  group('fitsFilter: allergens certain / uncertain', () {
    test('certain row without the declared allergen fits', () {
      final f = food('Apple');
      expect(fitsFilter(f, allergy(FoodAllergen.milk)), isTrue);
    });

    test('certain row containing the declared allergen is hidden', () {
      final f = food('Cheese',
          tags: animalTags(
              allergens: {FoodAllergen.milk}, pesc: true, animal: true));
      expect(fitsFilter(f, allergy(FoodAllergen.milk)), isFalse);
    });

    test('only DECLARED allergens matter: eggs row fits a milk allergy', () {
      final egg = food('Egg',
          tags: animalTags(
              allergens: {FoodAllergen.eggs}, pesc: true, animal: true));
      expect(fitsFilter(egg, allergy(FoodAllergen.milk)), isTrue);
      expect(fitsFilter(egg, allergy(FoodAllergen.eggs)), isFalse);
    });

    test('any of several declared allergens hides the row', () {
      const filter =
          SuggestionFilter(allergens: {FoodAllergen.soy, FoodAllergen.sesame});
      final soy = food('Tofu',
          tags: const GenericFoodTags(
              allergens: {FoodAllergen.soy},
              allergenCertain: true,
              animalProduct: false,
              pescatarianOk: true));
      final multi = food('Mix',
          tags: const GenericFoodTags(
              allergens: {FoodAllergen.peanuts, FoodAllergen.sesame},
              allergenCertain: true,
              animalProduct: false,
              pescatarianOk: true));
      expect(fitsFilter(soy, filter), isFalse);
      expect(fitsFilter(multi, filter), isFalse);
      expect(fitsFilter(food('Rice'), filter), isTrue);
    });

    test('UNCERTAIN row is hidden for any allergy even with an empty list',
        () {
      final unsure = food('Bread roll',
          tags: animalTags(certain: false, animal: false, pesc: true));
      expect(unsure.tags.allergens, isEmpty);
      expect(fitsFilter(unsure, allergy(FoodAllergen.milk)), isFalse);
      expect(fitsFilter(unsure, allergy(FoodAllergen.treeNuts)), isFalse);
    });

    test('uncertain row that lists a different allergen is still hidden', () {
      final unsure = food('Cookie',
          tags: animalTags(
              allergens: {FoodAllergen.gluten},
              certain: false,
              animal: null,
              pesc: null));
      expect(fitsFilter(unsure, allergy(FoodAllergen.fish)), isFalse);
    });

    test('row with unknown allergen name in JSON is hidden for an allergy', () {
      final t = GenericFoodTable.parse('''
{"foods":[{"id":"gen:1","name":"Weird","per100g":{"kcal":1,"proteinG":1,"carbsG":1,"fatG":1},"fdcId":1,
"tags":{"allergens":["kryptonite"],"allergenCertain":true,"animalProduct":false,"pescatarianOk":true}}]}''');
      expect(fitsFilter(t.foods.single, allergy(FoodAllergen.milk)), isFalse);
    });

    test('every EU-14 allergen individually hides a certain row that has it',
        () {
      for (final a in FoodAllergen.values) {
        final withA = food('With ${a.name}',
            tags: GenericFoodTags(
                allergens: {a},
                allergenCertain: true,
                animalProduct: false,
                pescatarianOk: true));
        expect(fitsFilter(withA, allergy(a)), isFalse, reason: a.name);
        for (final other in FoodAllergen.values) {
          if (other == a) continue;
          expect(fitsFilter(withA, allergy(other)), isTrue,
              reason: '${a.name} vs ${other.name}');
        }
      }
    });
  });

  group('fitsFilter: vegan', () {
    final f = diet(DietaryPreference.vegan);
    test('known plant food fits', () {
      expect(fitsFilter(food('Lentils'), f), isTrue);
    });
    test('animal product, unknown status, and meat are hidden', () {
      expect(fitsFilter(food('Beef', tags: animalTags()), f), isFalse);
      expect(fitsFilter(food('Mystery', tags: _unknown), f), isFalse);
      expect(
          fitsFilter(
              food('Egg',
                  tags: animalTags(
                      allergens: {FoodAllergen.eggs}, pesc: true)),
              f),
          isFalse);
      expect(
          fitsFilter(food('Fish', tags: animalTags(pesc: true)), f), isFalse);
    });
    test('unknown flag with otherwise plant tags is hidden (animal null)', () {
      expect(
          fitsFilter(
              food('Unknown', tags: animalTags(animal: null, pesc: true)), f),
          isFalse);
    });
  });

  group('fitsFilter: vegetarian', () {
    final f = diet(DietaryPreference.vegetarian);
    test('plant food fits', () {
      expect(fitsFilter(food('Lentils'), f), isTrue);
    });
    test('meat and fish are hidden', () {
      expect(fitsFilter(food('Beef', tags: animalTags()), f), isFalse);
      expect(
          fitsFilter(
              food('Salmon',
                  tags: animalTags(
                      allergens: {FoodAllergen.fish}, pesc: true)),
              f),
          isFalse);
    });
    test('certain dairy / egg only rows fit', () {
      expect(
          fitsFilter(
              food('Egg',
                  tags: animalTags(
                      allergens: {FoodAllergen.eggs}, pesc: true)),
              f),
          isTrue);
      expect(
          fitsFilter(
              food('Milk',
                  tags: animalTags(
                      allergens: {FoodAllergen.milk}, pesc: true)),
              f),
          isTrue);
      expect(
          fitsFilter(
              food('Custard',
                  tags: animalTags(
                      allergens: {FoodAllergen.milk, FoodAllergen.eggs},
                      pesc: true)),
              f),
          isTrue);
    });
    test('dairy row that also has fish, or an uncertain list, is hidden', () {
      expect(
          fitsFilter(
              food('Milk + fish',
                  tags: animalTags(
                      allergens: {FoodAllergen.milk, FoodAllergen.fish},
                      pesc: true)),
              f),
          isFalse);
      expect(
          fitsFilter(
              food('Maybe dairy',
                  tags: animalTags(
                      allergens: {FoodAllergen.milk},
                      certain: false,
                      pesc: true)),
              f),
          isFalse);
    });
    test('animal row with an empty allergen list (e.g. honey) is hidden', () {
      expect(
          fitsFilter(food('Honey', tags: animalTags(pesc: true)), f), isFalse);
    });
    test('unknown row is hidden', () {
      expect(fitsFilter(food('Mystery', tags: _unknown), f), isFalse);
    });
  });

  group('fitsFilter: pescatarian', () {
    final f = diet(DietaryPreference.pescatarian);
    test('known pescatarian-ok rows fit: plants, fish, dairy', () {
      expect(fitsFilter(food('Lentils'), f), isTrue);
      expect(
          fitsFilter(
              food('Tuna',
                  tags: animalTags(allergens: {FoodAllergen.fish}, pesc: true)),
              f),
          isTrue);
    });
    test('land meat is hidden', () {
      expect(fitsFilter(food('Beef', tags: animalTags()), f), isFalse);
    });
    test('unknown pescatarian status is hidden', () {
      expect(fitsFilter(food('Mystery', tags: _unknown), f), isFalse);
      expect(
          fitsFilter(
              food('Soup', tags: animalTags(animal: false, pesc: null)), f),
          isFalse);
    });
  });

  group('fitsFilter: gluten-free and dairy-free need certain lists', () {
    test('gluten-free', () {
      final f = diet(DietaryPreference.glutenFree);
      expect(fitsFilter(food('Rice'), f), isTrue);
      expect(
          fitsFilter(
              food('Bread',
                  tags: const GenericFoodTags(
                      allergens: {FoodAllergen.gluten},
                      allergenCertain: true,
                      animalProduct: false,
                      pescatarianOk: true)),
              f),
          isFalse);
      expect(
          fitsFilter(
              food('Cake',
                  tags: animalTags(certain: false, animal: false, pesc: true)),
              f),
          isFalse);
    });
    test('dairy-free', () {
      final f = diet(DietaryPreference.dairyFree);
      expect(fitsFilter(food('Rice'), f), isTrue);
      expect(
          fitsFilter(
              food('Cheese',
                  tags: animalTags(
                      allergens: {FoodAllergen.milk}, pesc: true)),
              f),
          isFalse);
      expect(
          fitsFilter(
              food('Egg',
                  tags: animalTags(
                      allergens: {FoodAllergen.eggs}, pesc: true)),
              f),
          isTrue);
      expect(fitsFilter(food('Mystery', tags: _unknown), f), isFalse);
    });
  });

  group('fitsFilter: halal', () {
    final f = diet(DietaryPreference.halal);
    test('plants, fish and dairy fit', () {
      expect(fitsFilter(food('Lentils'), f), isTrue);
      expect(
          fitsFilter(
              food('Tuna',
                  tags: animalTags(allergens: {FoodAllergen.fish}, pesc: true)),
              f),
          isTrue);
      expect(
          fitsFilter(
              food('Milk',
                  tags: animalTags(
                      allergens: {FoodAllergen.milk}, pesc: true)),
              f),
          isTrue);
    });
    test('pork and alcohol tags hide the row even if otherwise plant', () {
      expect(
          fitsFilter(
              food('Pork-flavoured', tags: animalTags(animal: false, pesc: true, pork: true)),
              f),
          isFalse);
      expect(
          fitsFilter(
              food('Wine',
                  tags: animalTags(animal: false, pesc: true, alcohol: true)),
              f),
          isFalse);
    });
    test('land-animal meat is hidden (slaughter is not modelled)', () {
      expect(fitsFilter(food('Chicken', tags: animalTags()), f), isFalse);
      expect(fitsFilter(food('Pork', tags: animalTags(pork: true)), f),
          isFalse);
    });
    test('unknown animal status is hidden', () {
      expect(fitsFilter(food('Mystery', tags: _unknown), f), isFalse);
    });
    test('an uncertain row is hidden even when animal is known', () {
      // animalProduct false but pescatarianOk unknown: not fully known.
      expect(
          fitsFilter(
              food('Unclear', tags: animalTags(animal: false, pesc: null)), f),
          isFalse);
      expect(
          fitsFilter(
              food('Unclear', tags: animalTags(animal: false, pesc: true, certain: false)),
              f),
          isFalse);
    });
  });

  group('fitsFilter: kosher', () {
    final f = diet(DietaryPreference.kosher);
    test('plants, fish and dairy fit', () {
      expect(fitsFilter(food('Lentils'), f), isTrue);
      expect(
          fitsFilter(
              food('Tuna',
                  tags: animalTags(allergens: {FoodAllergen.fish}, pesc: true)),
              f),
          isTrue);
    });
    test('pork, alcohol and land meat are hidden', () {
      expect(fitsFilter(food('Pork', tags: animalTags(pork: true)), f),
          isFalse);
      expect(
          fitsFilter(
              food('Beer',
                  tags: animalTags(animal: false, pesc: true, alcohol: true)),
              f),
          isFalse);
      expect(fitsFilter(food('Beef', tags: animalTags()), f), isFalse);
    });
    test('crustaceans and molluscs are hidden, finfish are not', () {
      expect(
          fitsFilter(
              food('Shrimp',
                  tags: animalTags(
                      allergens: {FoodAllergen.crustaceans}, pesc: true)),
              f),
          isFalse);
      expect(
          fitsFilter(
              food('Mussels',
                  tags: animalTags(
                      allergens: {FoodAllergen.molluscs}, pesc: true)),
              f),
          isFalse);
      expect(
          fitsFilter(
              food('Cod',
                  tags: animalTags(allergens: {FoodAllergen.fish}, pesc: true)),
              f),
          isTrue);
    });
    test('unknown row is hidden', () {
      expect(fitsFilter(food('Mystery', tags: _unknown), f), isFalse);
    });
    test('shellfish is NOT hidden for halal (only kosher)', () {
      expect(
          fitsFilter(
              food('Shrimp',
                  tags: animalTags(
                      allergens: {FoodAllergen.crustaceans}, pesc: true)),
              diet(DietaryPreference.halal)),
          isTrue);
    });
  });

  group('fitsFilter: combinations', () {
    test('all diets must hold together', () {
      const f = SuggestionFilter(
          diets: {DietaryPreference.vegan, DietaryPreference.glutenFree});
      final glutenPlant = food('Wheat',
          tags: const GenericFoodTags(
              allergens: {FoodAllergen.gluten},
              allergenCertain: true,
              animalProduct: false,
              pescatarianOk: true));
      expect(fitsFilter(glutenPlant, f), isFalse);
      expect(fitsFilter(food('Rice'), f), isTrue);
    });

    test('diet + allergen + exclusion: failing any one hides the row', () {
      const f = SuggestionFilter(
        diets: {DietaryPreference.vegetarian},
        allergens: {FoodAllergen.peanuts},
        exclusions: ['broccoli'],
      );
      expect(fitsFilter(food('Rice, white'), f), isTrue);
      expect(fitsFilter(food('Broccoli, raw'), f), isFalse);
      expect(fitsFilter(food('Chicken', tags: animalTags()), f), isFalse);
      expect(
          fitsFilter(
              food('Peanuts',
                  tags: const GenericFoodTags(
                      allergens: {FoodAllergen.peanuts},
                      allergenCertain: true,
                      animalProduct: false,
                      pescatarianOk: true)),
              f),
          isFalse);
    });
  });

  group('fitsFilter: excludedFoods', () {
    bool fits(GenericFood x, List<String> ex) =>
        fitsFilter(x, SuggestionFilter(exclusions: ex));

    test('English token hides matching rows, case-insensitive', () {
      expect(fits(food('Fish, salmon, raw'), ['SALMON']), isFalse);
      expect(fits(food('Fish, salmon, raw'), ['  salmon  ']), isFalse);
      expect(fits(food('Rice, white'), ['salmon']), isTrue);
    });

    test('RU exclusion hides via RU name and via synonym to English name', () {
      final apple = food('Apples, raw', nameRu: 'Яблоки сырые');
      expect(fits(apple, ['яблоки']), isFalse);
      expect(fits(apple, ['яблок']), isFalse);
      final chicken = food('Chicken, breast, raw');
      expect(fits(chicken, ['курица']), isFalse);
      expect(fits(food('Beef, raw'), ['курица']), isTrue);
    });

    test('plural exclusion hides singular row and vice versa (prefix both ways)',
        () {
      expect(fits(food('Nut, hazel'), ['nuts']), isFalse);
      expect(fits(food('Nuts, almonds'), ['nut']), isFalse);
    });

    test('tokens shorter than 3 letters are ignored; empty strings too', () {
      expect(fits(food('Ham, sliced'), ['ha']), isTrue);
      expect(fits(food('Ham, sliced'), ['']), isTrue);
      expect(fits(food('Ham, sliced'), ['   ']), isTrue);
      expect(fits(food('Ham, sliced'), ['!?']), isTrue);
      expect(fits(food('Ham, sliced'), ['ham']), isFalse);
    });

    test('multi-word exclusion hides a row matching ANY of its tokens', () {
      expect(fits(food('Butter, salted'), ['peanut butter']), isFalse);
      expect(fits(food('Peanuts, raw'), ['peanut butter']), isFalse);
      expect(fits(food('Rice'), ['peanut butter']), isTrue);
    });

    test('any entry in the list can hide the row', () {
      expect(fits(food('Tofu'), ['beef', 'tofu']), isFalse);
      expect(fits(food('Tofu'), ['beef', 'pork']), isTrue);
    });

    test('exclusion matches token prefixes only, not mid-word substrings', () {
      expect(fits(food('Chickpeas'), ['pea']), isTrue);
    });
  });

  group('suggestFoods: gating and focus', () {
    test('nothing remaining returns empty', () {
      final t = GenericFoodTable.parse('{"foods":[]}');
      expect(suggestFoods(t, const SuggestionFilter(), const RemainingMacros()),
          isEmpty);
    });

    test('null / zero / negative remaining macros return empty', () {
      final table = _table([food('Chicken', p: 25, id: 'gen:1')]);
      for (final r in [
        const RemainingMacros(),
        const RemainingMacros(proteinG: 0, carbsG: 0, fatG: 0),
        const RemainingMacros(proteinG: -5, carbsG: -1, fatG: -1),
      ]) {
        expect(suggestFoods(table, const SuggestionFilter(), r), isEmpty);
      }
    });

    test('focus is the macro with the largest remaining energy (4/4/9)', () {
      final table = _table([food('X', p: 25, id: 'gen:1')]);
      MacroFocus? focusOf(RemainingMacros r) {
        final s = suggestFoods(
            _table([
              food('P', p: 25, id: 'gen:1'),
              food('C', c: 25, id: 'gen:2'),
              food('F', fat: 11, kcal: 100, id: 'gen:3'),
            ]),
            const SuggestionFilter(),
            r);
        return s.isEmpty ? null : s.first.focus;
      }

      expect(table.foods, isNotEmpty);
      expect(focusOf(const RemainingMacros(proteinG: 30, carbsG: 20, fatG: 5)),
          MacroFocus.protein);
      expect(focusOf(const RemainingMacros(proteinG: 10, carbsG: 11)),
          MacroFocus.carbs);
      // fat: 4.5 g * 9 = 40.5 beats carbs 10 g * 4 = 40.
      expect(focusOf(const RemainingMacros(carbsG: 10, fatG: 4.5)),
          MacroFocus.fat);
      expect(focusOf(const RemainingMacros(carbsG: 10, fatG: 4)),
          MacroFocus.carbs);
    });

    test('tie goes protein over carbs over fat', () {
      final table = _table([
        food('P', p: 25, id: 'gen:1'),
        food('C', c: 25, id: 'gen:2'),
        food('F', fat: 11, id: 'gen:3', kcal: 100),
      ]);
      final s = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(proteinG: 10, carbsG: 10));
      expect(s.single.focus, MacroFocus.protein);
      expect(s.single.food.id, 'gen:1');
      final s2 = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(carbsG: 9, fatG: 4));
      expect(s2.single.focus, MacroFocus.carbs);
      expect(s2.single.food.id, 'gen:2');
    });
  });

  group('suggestFoods: thresholds and ranking', () {
    test('protein needs >= 30% of energy from protein', () {
      final table = _table([
        food('Exactly 30', p: 7.5, id: 'gen:1'),
        food('Just under', p: 7.4, id: 'gen:2'),
        food('High', p: 25, id: 'gen:3'),
      ]);
      final s = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(proteinG: 40));
      expect(s.map((x) => x.food.id), ['gen:3', 'gen:1']);
    });

    test('carbs and fat need >= 50% of energy', () {
      final table = _table([
        food('Carb 50%', c: 12.5, id: 'gen:1'),
        food('Carb 48%', c: 12, id: 'gen:2'),
        food('Fat 50%', fat: 5, kcal: 90, id: 'gen:3'),
        food('Fat 45%', fat: 5, kcal: 100, id: 'gen:4'),
      ]);
      final carbs = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(carbsG: 50));
      expect(carbs.map((x) => x.food.id), ['gen:1']);
      final fat = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(fatG: 50));
      expect(fat.map((x) => x.food.id), ['gen:3']);
      expect(fat.single.focus, MacroFocus.fat);
    });

    test('ranked by macro energy share, ties by name then id', () {
      final table = _table([
        food('B tie', p: 20, id: 'gen:2', category: 'A'),
        food('A tie', p: 20, id: 'gen:9', category: 'B'),
        food('A tie', p: 20, id: 'gen:1', category: 'C'),
        food('Top', p: 25, id: 'gen:7', category: 'D'),
        food('Low', p: 10, id: 'gen:8', category: 'E'),
      ]);
      final s = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(proteinG: 50));
      expect(s.map((x) => x.food.id),
          ['gen:7', 'gen:1', 'gen:9', 'gen:2', 'gen:8']);
    });

    test('rows under 20 kcal per 100 g never qualify (no share on water)', () {
      final table = _table([
        food('Leaf', kcal: 19, p: 4.7, id: 'gen:1'), // 99% by share
        food('Lean', kcal: 20, p: 5, id: 'gen:2'), // 100% by share
      ]);
      final s = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(proteinG: 10));
      expect(s.map((x) => x.food.id), ['gen:2']);
    });

    test('Spices, Sweets and Beverages are never suggested', () {
      final table = _table([
        food('Spice', p: 25, id: 'gen:1', category: 'Spices and Herbs'),
        food('Candy', p: 25, id: 'gen:2', category: 'Sweets'),
        food('Shake', p: 25, id: 'gen:3', category: 'Beverages'),
        food('Meat', p: 25, id: 'gen:4', category: 'Beef Products'),
      ]);
      final s = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(proteinG: 10));
      expect(s.map((x) => x.food.id), ['gen:4']);
    });

    test('Fats and Oils only for a fat focus', () {
      final table = _table([
        food('Oil', fat: 11, kcal: 100, id: 'gen:1', category: 'Fats and Oils'),
        food('Nuts', fat: 11, kcal: 100, id: 'gen:2', category: 'Nut and Seed Products'),
      ]);
      final fat = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(fatG: 20));
      expect(fat.map((x) => x.food.id).toSet(), {'gen:1', 'gen:2'});
      final protein = suggestFoods(
          _table([
            food('Oil', p: 25, id: 'gen:1', category: 'Fats and Oils'),
            food('Meat', p: 25, id: 'gen:2', category: 'Beef Products'),
          ]),
          const SuggestionFilter(),
          const RemainingMacros(proteinG: 20));
      expect(protein.map((x) => x.food.id), ['gen:2']);
    });

    test('at most two per category, then the next category fills in', () {
      final table = _table([
        for (var i = 0; i < 4; i++)
          food('Beef $i', p: 30 - i.toDouble(), id: 'gen:${10 + i}', category: 'Beef Products'),
        food('Fish', p: 20, id: 'gen:20', category: 'Finfish'),
      ]);
      final s = suggestFoods(table, const SuggestionFilter(),
          const RemainingMacros(proteinG: 50));
      expect(s.map((x) => x.food.id), ['gen:10', 'gen:11', 'gen:20']);
    });

    test('result is capped at 5 even if more fit or a larger limit is asked',
        () {
      final table = _table([
        for (var i = 0; i < 12; i++)
          food('Food $i', p: 25, id: 'gen:${100 + i}', category: 'Cat ${i ~/ 2}'),
      ]);
      expect(maxSuggestions, 5);
      expect(
          suggestFoods(table, const SuggestionFilter(),
                  const RemainingMacros(proteinG: 50))
              .length,
          5);
      expect(
          suggestFoods(table, const SuggestionFilter(),
                  const RemainingMacros(proteinG: 50),
                  limit: 50)
              .length,
          5);
      expect(
          suggestFoods(table, const SuggestionFilter(),
                  const RemainingMacros(proteinG: 50),
                  limit: 2)
              .length,
          2);
      expect(
          suggestFoods(table, const SuggestionFilter(),
              const RemainingMacros(proteinG: 50),
              limit: 0),
          isEmpty);
      expect(
          suggestFoods(table, const SuggestionFilter(),
              const RemainingMacros(proteinG: 50),
              limit: -3),
          isEmpty);
    });

    test('deterministic: same input twice, reversed table order, same output',
        () {
      final rows = [
        for (var i = 0; i < 9; i++)
          food('Food ${i % 3}', p: 20 + (i % 3).toDouble(), id: 'gen:$i', category: 'Cat $i'),
      ];
      List<String> run(List<GenericFood> r) => suggestFoods(
              _table(r),
              const SuggestionFilter(),
              const RemainingMacros(proteinG: 30))
          .map((x) => x.food.id)
          .toList();
      expect(run(rows), run(rows));
      expect(run(rows), run(rows.reversed.toList()));
    });
  });

  group('suggestFoods: filter integration (synthetic)', () {
    final rows = [
      food('Chicken', p: 30, id: 'gen:1', category: 'Poultry Products', tags: animalTags()),
      food('Salmon', p: 22, id: 'gen:2', category: 'Finfish',
          tags: animalTags(allergens: {FoodAllergen.fish}, pesc: true)),
      food('Tofu', p: 17, id: 'gen:3', category: 'Legumes',
          tags: const GenericFoodTags(
              allergens: {FoodAllergen.soy},
              allergenCertain: true,
              animalProduct: false,
              pescatarianOk: true)),
      food('Lentils', p: 26, id: 'gen:4', category: 'Legumes2'),
      food('Mystery protein', p: 40, id: 'gen:5', category: 'Meals', tags: _unknown),
      food('Cheese', p: 25, id: 'gen:6', category: 'Dairy',
          tags: animalTags(allergens: {FoodAllergen.milk}, pesc: true)),
      food('Pork loin', p: 27, id: 'gen:7', category: 'Pork Products',
          tags: animalTags(pork: true)),
    ];
    List<String> ids(SuggestionFilter f) => suggestFoods(
            _table(rows), f, const RemainingMacros(proteinG: 60))
        .map((x) => x.food.id)
        .toList();

    test('no filter: everything dense enough is suggested, uncertain too', () {
      expect(ids(const SuggestionFilter()), contains('gen:5'));
      expect(ids(const SuggestionFilter()).length, 5);
    });

    test('vegan: only certain plant rows', () {
      expect(ids(diet(DietaryPreference.vegan)), ['gen:4', 'gen:3']);
    });

    test('pescatarian: plants, fish and dairy but not meat or unknown', () {
      expect(ids(diet(DietaryPreference.pescatarian)).toSet(),
          {'gen:2', 'gen:3', 'gen:4', 'gen:6'});
    });

    test('halal drops pork, meat and unknown; keeps fish, dairy, plants', () {
      expect(ids(diet(DietaryPreference.halal)).toSet(),
          {'gen:2', 'gen:3', 'gen:4', 'gen:6'});
    });

    test('milk allergy hides cheese AND the uncertain row', () {
      final got = ids(allergy(FoodAllergen.milk)).toSet();
      expect(got, isNot(contains('gen:6')));
      expect(got, isNot(contains('gen:5')));
      expect(got, containsAll(['gen:1', 'gen:2', 'gen:3', 'gen:4', 'gen:7']));
    });

    test('exclusion hides by name without hiding the uncertain row', () {
      final got = ids(const SuggestionFilter(exclusions: ['chicken'])).toSet();
      expect(got, isNot(contains('gen:1')));
      expect(got, contains('gen:5'));
    });

    test('everything filtered out gives an empty list, not an error', () {
      expect(
          ids(const SuggestionFilter(
              diets: {DietaryPreference.vegan},
              allergens: {FoodAllergen.soy, FoodAllergen.sesame},
              exclusions: ['lentils'])),
          isEmpty);
    });
  });

  group('suggestFoods on the real bundled table', () {
    late GenericFoodTable table;
    setUpAll(() {
      table = GenericFoodTable.parse(File(_foodsPath()).readAsStringSync(),
          ruJson: File(_ruPath()).readAsStringSync());
    });

    const protein = RemainingMacros(proteinG: 60);
    const carbs = RemainingMacros(carbsG: 100);
    const fat = RemainingMacros(fatG: 40);

    test('no filter returns 5 protein-dense suggestions for each focus', () {
      for (final (r, focus) in [
        (protein, MacroFocus.protein),
        (carbs, MacroFocus.carbs),
        (fat, MacroFocus.fat),
      ]) {
        final s = suggestFoods(table, const SuggestionFilter(), r);
        expect(s.length, 5, reason: focus.name);
        for (final x in s) {
          expect(x.focus, focus);
        }
      }
    });

    test('protein suggestions are really protein-dense and varied', () {
      final s = suggestFoods(table, const SuggestionFilter(), protein);
      for (final x in s) {
        final p = x.food.per100g;
        expect(p.proteinG * 4 / p.kcal, greaterThanOrEqualTo(0.3),
            reason: x.food.name);
      }
      final perCat = <String, int>{};
      for (final x in s) {
        perCat[x.food.category] = (perCat[x.food.category] ?? 0) + 1;
      }
      expect(perCat.values.every((n) => n <= 2), isTrue);
    });

    test('output is deterministic', () {
      List<String> run() => suggestFoods(table, const SuggestionFilter(), protein)
          .map((x) => x.food.id)
          .toList();
      expect(run(), run());
    });

    test('vegan: every suggestion is a certain plant food', () {
      for (final r in [protein, carbs, fat]) {
        final s = suggestFoods(table, diet(DietaryPreference.vegan), r);
        expect(s, isNotEmpty);
        for (final x in s) {
          expect(x.food.tags.animalProduct, isFalse, reason: x.food.name);
          expect(x.food.tags.allergenCertain, isTrue, reason: x.food.name);
        }
      }
    });

    test('vegetarian: no meat or fish in any suggestion', () {
      for (final r in [protein, carbs, fat]) {
        for (final x in suggestFoods(table, diet(DietaryPreference.vegetarian), r)) {
          expect(x.food.tags.pescatarianOk == true || x.food.tags.animalProduct == false,
              isTrue, reason: x.food.name);
          const meat = {
            'Beef Products',
            'Poultry Products',
            'Pork Products',
            'Lamb, Veal, and Game Products',
            'Finfish and Shellfish Products',
            'Sausages and Luncheon Meats',
          };
          expect(meat.contains(x.food.category), isFalse, reason: x.food.name);
        }
      }
    });

    test('pescatarian: only pescatarian-ok rows', () {
      for (final r in [protein, carbs, fat]) {
        for (final x in suggestFoods(table, diet(DietaryPreference.pescatarian), r)) {
          expect(x.food.tags.pescatarianOk, isTrue, reason: x.food.name);
        }
      }
    });

    test('halal and kosher: no pork, alcohol, land meat or unknown rows', () {
      for (final d in [DietaryPreference.halal, DietaryPreference.kosher]) {
        for (final r in [protein, carbs, fat]) {
          for (final x in suggestFoods(table, diet(d), r)) {
            final t = x.food.tags;
            expect(t.pork, isFalse, reason: '${d.name} ${x.food.name}');
            expect(t.alcohol, isFalse, reason: '${d.name} ${x.food.name}');
            expect(t.animalProduct, isNotNull, reason: x.food.name);
            expect(t.animalProduct == true && t.pescatarianOk == false, isFalse,
                reason: '${d.name} ${x.food.name}');
          }
        }
      }
    });

    test('kosher: no crustaceans or molluscs', () {
      for (final r in [protein, carbs, fat]) {
        for (final x in suggestFoods(table, diet(DietaryPreference.kosher), r)) {
          expect(x.food.tags.allergens, isNot(contains(FoodAllergen.crustaceans)));
          expect(x.food.tags.allergens, isNot(contains(FoodAllergen.molluscs)));
        }
      }
    });

    test('each single allergy: suggestions are certain and free of it', () {
      for (final a in FoodAllergen.values) {
        for (final r in [protein, carbs, fat]) {
          for (final x in suggestFoods(table, allergy(a), r)) {
            expect(x.food.tags.allergenCertain, isTrue,
                reason: '${a.name} ${x.food.name}');
            expect(x.food.tags.allergens, isNot(contains(a)),
                reason: '${a.name} ${x.food.name}');
          }
        }
      }
    });

    test('a brutal multi-restriction filter still never leaks a violation', () {
      final f = SuggestionFilter(
        diets: {
          DietaryPreference.vegan,
          DietaryPreference.glutenFree,
          DietaryPreference.halal
        },
        allergens: {FoodAllergen.peanuts, FoodAllergen.soy, FoodAllergen.treeNuts},
        exclusions: const ['oats', 'яблоко'],
      );
      for (final r in [protein, carbs, fat]) {
        for (final x in suggestFoods(table, f, r)) {
          expect(fitsFilter(x.food, f), isTrue);
          expect(x.food.tags.allergens,
              isNot(contains(FoodAllergen.gluten)));
          expect(x.food.name.toLowerCase(), isNot(contains('oats')));
        }
      }
    });

    test('exclusion hides the food from suggestions but not from search', () {
      final first = suggestFoods(table, const SuggestionFilter(), protein).first;
      final token = tokenize(first.food.name).firstWhere((t) => t.length >= 4);
      final filtered = suggestFoods(
          table, SuggestionFilter(exclusions: [token]), protein);
      expect(filtered.map((x) => x.food.id), isNot(contains(first.food.id)));
      expect(table.search(token, limit: 2590).map((h) => h.food.id),
          contains(first.food.id));
    });

    test('uncertain real rows are hidden from suggestions under any allergy',
        () {
      final uncertainIds = {
        for (final f in table.foods)
          if (!f.tags.allergenCertain) f.id
      };
      expect(uncertainIds.length, greaterThan(500));
      for (final r in [protein, carbs, fat]) {
        final s = suggestFoods(table, allergy(FoodAllergen.fish), r);
        expect(s.where((x) => uncertainIds.contains(x.food.id)), isEmpty);
      }
    });

    test('regression: eggplant is a valid suggestion under an egg allergy', () {
      final eggplant = table.foods.firstWhere((f) => f.name == 'Eggplant, raw');
      expect(fitsFilter(eggplant, allergy(FoodAllergen.eggs)), isTrue);
    });
  });
}

GenericFoodTable _table(List<GenericFood> foods) {
  // Round-trip through the real parser so rows are built exactly as in the app.
  final rows = [
    for (final f in foods)
      {
        'id': f.id,
        'name': f.name,
        'category': f.category,
        'per100g': {
          'kcal': f.per100g.kcal,
          'proteinG': f.per100g.proteinG,
          'carbsG': f.per100g.carbsG,
          'fatG': f.per100g.fatG,
        },
        'fdcId': 1,
        'tags': {
          'allergens': [for (final a in f.tags.allergens) a.name],
          'allergenCertain': f.tags.allergenCertain,
          if (f.tags.animalProduct != null)
            'animalProduct': f.tags.animalProduct,
          if (f.tags.pescatarianOk != null)
            'pescatarianOk': f.tags.pescatarianOk,
          'pork': f.tags.pork,
          'alcohol': f.tags.alcohol,
        },
      }
  ];
  final ru = {
    for (final f in foods)
      if (f.nameRu != null) f.name: f.nameRu!
  };
  return GenericFoodTable.parse(
    _json({'foods': rows}),
    ruJson: ru.isEmpty ? null : _json({'names': ru}),
  );
}

String _json(Object o) => jsonEncode(o);
