// food_source_test (FOOD-23 item source tags; FOOD-09 tag set; design s5.6
// item `sourceId` allowlist). Covers the wire ids exactly.
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// design s5.6 (TECH_DESIGN line 285): the item `sourceId` allowlist.
const Set<String> _designS56Allowlist = {
  'usda_fdc',
  'open_food_facts',
  'user',
  'label_ocr',
};

FoodItem _item(FoodSource s) => FoodItem(
      foodRef: 'user:x',
      name: 'x',
      grams: MacroRange.exact(100),
      per100g: const Per100g(kcal: 100, proteinG: 0, carbsG: 0, fatG: 0),
      source: s,
    );

void main() {
  test('wire ids, tags and attribution names are exact', () {
    expect(FoodSource.off.wireId, 'open_food_facts');
    expect(FoodSource.usda.wireId, 'usda_fdc');
    expect(FoodSource.llmEstimate.wireId, 'llm_estimate');
    expect(FoodSource.user.wireId, 'user');
    expect(FoodSource.label.wireId, 'label_ocr');

    expect(FoodSource.off.tag, 'off');
    expect(FoodSource.usda.tag, 'usda');
    expect(FoodSource.llmEstimate.tag, 'llm_estimate');
    expect(FoodSource.user.tag, 'user');
    expect(FoodSource.label.tag, 'label');

    expect(FoodSource.off.attributionName, 'Open Food Facts');
    expect(FoodSource.usda.attributionName, 'USDA FoodData Central');
  });

  test('wire ids and tags are unique; attribution names non-empty', () {
    expect(FoodSource.values.map((s) => s.wireId).toSet().length,
        FoodSource.values.length);
    expect(FoodSource.values.map((s) => s.tag).toSet().length,
        FoodSource.values.length);
    for (final s in FoodSource.values) {
      expect(s.attributionName.trim(), isNotEmpty);
    }
  });

  test('only llm_estimate is an estimate', () {
    for (final s in FoodSource.values) {
      expect(s.isEstimate, s == FoodSource.llmEstimate, reason: s.name);
    }
  });

  test('only OFF and USDA require attribution', () {
    for (final s in FoodSource.values) {
      expect(s.requiresAttribution,
          s == FoodSource.off || s == FoodSource.usda,
          reason: s.name);
    }
  });

  group('tryParse', () {
    test('round-trips every wire id', () {
      for (final s in FoodSource.values) {
        expect(FoodSource.tryParse(s.wireId), s);
      }
    });

    test('rejects tags, wrong case, whitespace, non-strings', () {
      expect(FoodSource.tryParse('off'), isNull);
      expect(FoodSource.tryParse('usda'), isNull);
      expect(FoodSource.tryParse('label'), isNull);
      expect(FoodSource.tryParse('USER'), isNull);
      expect(FoodSource.tryParse(' user'), isNull);
      expect(FoodSource.tryParse(''), isNull);
      expect(FoodSource.tryParse(null), isNull);
      expect(FoodSource.tryParse(5), isNull);
      expect(FoodSource.tryParse(['user']), isNull);
    });
  });

  group('FoodItem.toJson sourceId', () {
    test('emits the wire id for each design-allowed source', () {
      expect(_item(FoodSource.usda).toJson()['sourceId'], 'usda_fdc');
      expect(_item(FoodSource.off).toJson()['sourceId'], 'open_food_facts');
      expect(_item(FoodSource.user).toJson()['sourceId'], 'user');
      expect(_item(FoodSource.label).toJson()['sourceId'], 'label_ocr');
    });

    test('llm_estimate item emits sourceId "llm_estimate"', () {
      expect(_item(FoodSource.llmEstimate).toJson()['sourceId'],
          'llm_estimate');
    });

    // DEFECT PIN (design s5.6 vs s17.3): TECH_DESIGN line 285 lists the item
    // sourceId allowlist as usda_fdc | open_food_facts | user | label_ocr, but
    // the layer also emits llm_estimate (which s17.3 / FOOD-09 require items to
    // carry). This test pins the exact difference so reconciling the design
    // text (or the layer) is a visible, deliberate change.
    test('emitted wire ids exceed the design s5.6 allowlist by exactly '
        'llm_estimate', () {
      final emitted = {
        for (final s in FoodSource.values)
          _item(s).toJson()['sourceId'] as String,
      };
      expect(emitted.difference(_designS56Allowlist), {'llm_estimate'});
      expect(_designS56Allowlist.difference(emitted), isEmpty);
    });

    test('an llm_estimate item survives a round trip through the entry', () {
      final entry = FoodEntry(
        id: 'e1',
        day: '2026-10-15',
        slot: MealSlot.lunch,
        loggedAt: DateTime.utc(2026, 10, 15, 12),
        name: 'Soup',
        source: EntrySource.photo,
        confidence: EntryConfidence.low,
        items: [_item(FoodSource.llmEstimate)],
        totals: MacroTotals.zero,
      );
      final back = FoodEntry.fromJson('e1', entry.toJson());
      expect(back.items.single.source, FoodSource.llmEstimate);
      expect(back.degraded, isFalse);
    });
  });
}
