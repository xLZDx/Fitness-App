// Shared fixtures of the C23 food diary tests (not a test file itself).
// Numbers are hand-derived: quick-log entries are ONE 100 g item whose per-100 g
// values equal the typed values, so the entry totals equal the typed values.
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/data/portion_math.dart';

const String kDiaryUid = 'u1';

/// 2026-10-15 09:00 local, a Thursday.
final DateTime kDiaryNow = DateTime(2026, 10, 15, 9);
const String kToday = '2026-10-15';

FoodEntry quickEntry({
  String id = 'e1',
  String day = kToday,
  MealSlot slot = MealSlot.lunch,
  String name = 'Soup',
  double kcal = 500,
  double protein = 20,
  double carbs = 50,
  double fat = 10,
  DateTime? at,
}) =>
    quickLogEntry(
      id: id,
      day: day,
      slot: slot,
      loggedAt: at ?? kDiaryNow,
      name: name,
      kcal: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
    );

/// A single-item search entry of 150 g of a 130 kcal / 100 g food (195 kcal).
FoodEntry riceEntry({
  String id = 'r1',
  String day = kToday,
  MealSlot slot = MealSlot.lunch,
  MacroRange? grams,
  List<CheckItem> checks = const [],
  FoodSource source = FoodSource.usda,
  EntryConfidence confidence = EntryConfidence.high,
}) =>
    buildEntry(
      id: id,
      day: day,
      slot: slot,
      loggedAt: kDiaryNow,
      name: 'Rice',
      source: EntrySource.search,
      confidence: confidence,
      items: [
        FoodItem(
          foodRef: 'gen:1',
          name: 'Rice',
          grams: grams ?? MacroRange.exact(150),
          per100g:
              const Per100g(kcal: 130, proteinG: 2.7, carbsG: 28, fatG: 0.3),
          source: source,
        ),
      ],
      checkThese: checks,
    );
