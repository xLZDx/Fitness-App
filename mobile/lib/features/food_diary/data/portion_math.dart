/// Portion maths: grams range x per-100 g -> macro ranges (design s17.3,
/// s17.7, FOOD-17, FOOD-20). Pure Dart.
///
/// Macros are ALWAYS recomputed from `per100g x grams`; stored or model
/// totals are never trusted.
library;

import 'check_these.dart';
import 'food_entry.dart';
import 'food_source.dart';

/// Pseudo-portion used by the quick log: one item of 100 g.
const double quickLogGrams = 100;

/// Macro range of [grams] of a food with [per100g] values. Zero grams give
/// zero. `low <= mid <= high` is preserved (all factors are non-negative).
MacroTotals itemMacros(Per100g per100g, MacroRange grams) {
  MacroRange of(double per100) => grams.scaled(per100 / 100);
  return MacroTotals(
    kcal: of(per100g.kcal),
    proteinG: of(per100g.proteinG),
    carbsG: of(per100g.carbsG),
    fatG: of(per100g.fatG),
  );
}

/// Macro range of one [FoodItem].
MacroTotals itemTotals(FoodItem item) => itemMacros(item.per100g, item.grams);

/// Entry totals: items combined as independent errors (RSS, design s17.7).
MacroTotals entryTotalsOf(Iterable<FoodItem> items) =>
    MacroTotals.combine(items.map(itemTotals));

/// Replaces the grams of the item at [index] with a user-confirmed exact
/// portion and recomputes ONLY that item's contribution (other items are
/// untouched; totals are re-derived from all items).
FoodEntry editItemGrams(FoodEntry entry, int index, double grams) {
  if (index < 0 || index >= entry.items.length) {
    throw RangeError.index(index, entry.items, 'index');
  }
  final g = grams.isFinite && grams > 0 ? grams : 0.0;
  final items = [...entry.items];
  items[index] = items[index].copyWith(grams: MacroRange.exact(g));
  return entry.copyWith(items: items, totals: entryTotalsOf(items));
}

/// Same entry with [items] swapped in and totals recomputed.
FoodEntry withItems(FoodEntry entry, List<FoodItem> items) =>
    entry.copyWith(items: items, totals: entryTotalsOf(items));

/// Builds an entry from items, deriving `totals`.
FoodEntry buildEntry({
  required String id,
  required String day,
  required MealSlot slot,
  required DateTime loggedAt,
  required String name,
  required EntrySource source,
  required EntryConfidence confidence,
  required List<FoodItem> items,
  List<CheckItem> checkThese = const [],
  ModelRef? model,
}) =>
    FoodEntry(
      id: id,
      day: day,
      slot: slot,
      loggedAt: loggedAt,
      name: name,
      source: source,
      confidence: confidence,
      items: items,
      totals: entryTotalsOf(items),
      checkThese: checkThese,
      model: model,
    );

/// Quick log: ONE `quick` item with a 100 g pseudo-portion whose per-100 g
/// values equal the typed calories/macros, so totals equal the typed values.
FoodEntry quickLogEntry({
  required String id,
  required String day,
  required MealSlot slot,
  required DateTime loggedAt,
  required String name,
  required double kcal,
  double proteinG = 0,
  double carbsG = 0,
  double fatG = 0,
}) {
  final item = FoodItem(
    foodRef: 'user:quick',
    name: name,
    grams: MacroRange.exact(quickLogGrams),
    per100g: Per100g(
      kcal: kcal.isFinite && kcal > 0 ? kcal : 0,
      proteinG: proteinG.isFinite && proteinG > 0 ? proteinG : 0,
      carbsG: carbsG.isFinite && carbsG > 0 ? carbsG : 0,
      fatG: fatG.isFinite && fatG > 0 ? fatG : 0,
    ),
    matchQuality: MatchQuality.exact,
    source: FoodSource.user,
  );
  return buildEntry(
    id: id,
    day: day,
    slot: slot,
    loggedAt: loggedAt,
    name: name,
    source: EntrySource.manual,
    confidence: EntryConfidence.high,
    items: [item],
  );
}

/// Energy sanity for per-100 g data (design s17.7): consistent when
/// `|kcal - (4P + 4C + 9F)| <= max(25 % of kcal, 10 kcal)`. Small gaps
/// (fibre, rounding) must NOT raise `dataInconsistent`; 25 %+ gaps do.
bool isAtwaterConsistent(Per100g p) {
  final atwater = 4 * p.proteinG + 4 * p.carbsG + 9 * p.fatG;
  final tolerance = p.kcal * 0.25 > 10 ? p.kcal * 0.25 : 10.0;
  return (p.kcal - atwater).abs() <= tolerance;
}

/// True for an item previously added by [applyHiddenOil] (same food, exact
/// 5 g or 14 g portion), so a re-choice replaces it instead of stacking.
bool _isAddedOil(FoodItem i, String oilFoodRef) =>
    i.foodRef == oilFoodRef &&
    i.grams.low == i.grams.mid &&
    i.grams.mid == i.grams.high &&
    (i.grams.mid == OilChoice.teaspoon.grams ||
        i.grams.mid == OilChoice.tablespoon.grams);

/// Resolves `hiddenIngredients`: adds [choice] grams of the generic oil row
/// (`oilFoodRef`/`oilName`/`oilPer100g`, taken from the bundled table by the
/// caller) as an exact item, replacing an earlier oil choice, recomputes
/// totals and marks the chip resolved. `OilChoice.none` adds nothing.
///
/// Returns null when adding the item would exceed [FoodEntry.maxItems].
FoodEntry? applyHiddenOil(
  FoodEntry entry,
  OilChoice choice, {
  required String oilFoodRef,
  required String oilName,
  required Per100g oilPer100g,
  FoodSource oilSource = FoodSource.usda,
}) {
  final items = [
    for (final i in entry.items)
      if (!_isAddedOil(i, oilFoodRef)) i,
  ];
  if (choice != OilChoice.none) {
    if (items.length >= FoodEntry.maxItems) return null;
    items.add(FoodItem(
      foodRef: oilFoodRef,
      name: oilName,
      grams: MacroRange.exact(choice.grams),
      per100g: oilPer100g,
      matchQuality: MatchQuality.exact,
      source: oilSource,
    ));
  }
  return entry.copyWith(
    items: items,
    totals: entryTotalsOf(items),
    checkThese:
        CheckThese.markResolved(entry.checkThese, CheckCode.hiddenIngredients),
  );
}
