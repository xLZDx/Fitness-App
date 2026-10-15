/// Diet / allergen / exclusion filtered example foods (C21, design 17.8, D-71).
///
/// Pure Dart. Lives in `food_diary/data`, not `nutrition_plan/data`, so that
/// `nutrition_plan` never imports `food_diary`. For the macros still remaining
/// today it lists up to [maxSuggestions] example foods from the bundled table
/// that fit the user's diet pattern, allergens and exclusions. Suggestions
/// only: no prescriptions and no good/bad labelling.
///
/// ## Restrictive by default
///
/// A row is eligible only when every relevant tag is KNOWN and compatible:
/// - any declared allergen hides every row whose allergen list is not certain;
/// - vegan / vegetarian / pescatarian hide rows whose animal or pescatarian tag
///   is unknown;
/// - halal and kosher hide pork, alcohol and uncertain rows, and also land-animal
///   meat, because slaughter certification is not modelled (kosher also hides
///   shellfish);
/// - gluten-free and dairy-free need a certain allergen list.
/// Hidden rows remain searchable in [GenericFoodTable.search].
library;

import '../../profile/data/profile_models.dart';
import '../../safety/data/health_flags.dart';
import 'generic_foods.dart';

const int maxSuggestions = 5;

/// What the user told the app about food.
class SuggestionFilter {
  const SuggestionFilter({
    this.diets = const {},
    this.allergens = const {},
    this.exclusions = const [],
  });

  final Set<DietaryPreference> diets;
  final Set<FoodAllergen> allergens;

  /// Free-text excluded foods (profile `excludedFoods`), EN or RU.
  final List<String> exclusions;
}

/// Macros still to eat today (grams); null or non-positive means none left.
class RemainingMacros {
  const RemainingMacros({this.proteinG, this.carbsG, this.fatG});
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
}

enum MacroFocus { protein, carbs, fat }

class FoodSuggestion {
  const FoodSuggestion(this.food, this.focus);
  final GenericFood food;
  final MacroFocus focus;
}

bool _matchesExclusion(GenericFood food, String exclusion) {
  final ex = tokenize(exclusion).where((t) => t.length >= 3).toList();
  if (ex.isEmpty) return false;
  final foodTokens = {
    ...tokenize(food.name),
    if (food.nameRu != null) ...tokenize(food.nameRu!),
  };
  for (final e in ex) {
    final alts = [e, ...?GenericFoodTable.synonyms[e]];
    for (final a in alts) {
      for (final t in foodTokens) {
        // Prefix both ways so "nuts" hides "nut" rows and "яблок" hides "яблоки".
        if (t.startsWith(a) || (t.length >= 3 && a.startsWith(t))) return true;
      }
    }
  }
  return false;
}

/// True when [food] may be suggested under [filter]. Uncertain tags fail.
bool fitsFilter(GenericFood food, SuggestionFilter filter) {
  final t = food.tags;

  for (final ex in filter.exclusions) {
    if (_matchesExclusion(food, ex)) return false;
  }

  if (filter.allergens.isNotEmpty) {
    if (!t.allergenCertain) return false;
    if (t.allergens.any(filter.allergens.contains)) return false;
  }

  final isMeat = t.animalProduct == true && t.pescatarianOk == false;
  final dairyEggOnly = t.animalProduct == true &&
      t.pescatarianOk == true &&
      t.allergenCertain &&
      t.allergens.isNotEmpty &&
      t.allergens.every(
          (a) => a == FoodAllergen.milk || a == FoodAllergen.eggs);

  for (final d in filter.diets) {
    switch (d) {
      case DietaryPreference.vegan:
        if (t.animalProduct != false) return false;
      case DietaryPreference.vegetarian:
        if (t.animalProduct != false && !dairyEggOnly) return false;
      case DietaryPreference.pescatarian:
        if (t.pescatarianOk != true) return false;
      case DietaryPreference.glutenFree:
        if (!t.allergenCertain || t.allergens.contains(FoodAllergen.gluten)) {
          return false;
        }
      case DietaryPreference.dairyFree:
        if (!t.allergenCertain || t.allergens.contains(FoodAllergen.milk)) {
          return false;
        }
      case DietaryPreference.halal:
        if (t.pork || t.alcohol || t.animalProduct == null || isMeat) {
          return false;
        }
      case DietaryPreference.kosher:
        if (t.pork ||
            t.alcohol ||
            t.animalProduct == null ||
            isMeat ||
            t.allergens.contains(FoodAllergen.crustaceans) ||
            t.allergens.contains(FoodAllergen.molluscs)) {
          return false;
        }
      case DietaryPreference.none:
        break;
    }
  }
  return true;
}

const _neverSuggested = {'Spices and Herbs', 'Sweets', 'Beverages'};

/// Up to [limit] example foods that fit [filter] and are dense in the macro
/// the day is furthest behind on (largest remaining share of energy). Returns
/// an empty list when nothing remains or nothing fits. Deterministic.
List<FoodSuggestion> suggestFoods(
  GenericFoodTable table,
  SuggestionFilter filter,
  RemainingMacros remaining, {
  int limit = maxSuggestions,
}) {
  final cap = limit < maxSuggestions ? limit : maxSuggestions;
  if (cap <= 0) return const [];
  final p = (remaining.proteinG ?? 0) * 4;
  final c = (remaining.carbsG ?? 0) * 4;
  final f = (remaining.fatG ?? 0) * 9;
  if (p <= 0 && c <= 0 && f <= 0) return const [];
  final focus = p >= c && p >= f
      ? MacroFocus.protein
      : (c >= f ? MacroFocus.carbs : MacroFocus.fat);

  double share(GenericFood x) {
    final kcal = x.per100g.kcal;
    if (kcal < 20) return 0;
    final macroKcal = switch (focus) {
      MacroFocus.protein => x.per100g.proteinG * 4,
      MacroFocus.carbs => x.per100g.carbsG * 4,
      MacroFocus.fat => x.per100g.fatG * 9,
    };
    return macroKcal / kcal;
  }

  final minShare = focus == MacroFocus.protein ? 0.3 : 0.5;
  final ranked = <(GenericFood, double)>[];
  for (final food in table.foods) {
    if (_neverSuggested.contains(food.category)) continue;
    if (focus != MacroFocus.fat && food.category == 'Fats and Oils') continue;
    if (!fitsFilter(food, filter)) continue;
    final s = share(food);
    if (s >= minShare) ranked.add((food, s));
  }
  ranked.sort((a, b) {
    final bySharep = b.$2.compareTo(a.$2);
    if (bySharep != 0) return bySharep;
    final byName = a.$1.name.compareTo(b.$1.name);
    return byName != 0 ? byName : a.$1.id.compareTo(b.$1.id);
  });

  // Variety: at most two foods per category.
  final perCategory = <String, int>{};
  final out = <FoodSuggestion>[];
  for (final (food, _) in ranked) {
    final n = perCategory[food.category] ?? 0;
    if (n >= 2) continue;
    perCategory[food.category] = n + 1;
    out.add(FoodSuggestion(food, focus));
    if (out.length >= cap) break;
  }
  return out;
}
