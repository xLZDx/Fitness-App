// C23 meal_slot_section_test (FOOD-25 list half, a11y F11/F15): slot heading
// with total, entries with source badge and confidence, calm empty line,
// add/open/delete callbacks with 48 dp targets.
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/widgets/meal_slot_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../food_diary_fixtures.dart';
import '../food_diary_harness.dart';

class _Calls {
  int adds = 0;
  final opened = <String>[];
  final deleted = <String>[];
}

Widget _section(MealSlot slot, List<FoodEntry> entries, _Calls c) =>
    MealSlotSection(
      slot: slot,
      entries: entries,
      onAdd: () => c.adds++,
      onOpen: (e) => c.opened.add(e.id),
      onDelete: (e) => c.deleted.add(e.id),
    );

void main() {
  testWidgets('empty slot: heading, calm hint, add button, no total',
      (tester) async {
    await pumpWidgetOnly(tester, _section(MealSlot.dinner, const [], _Calls()));
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.byKey(const Key('diary.add.dinner')), findsOneWidget);
    expect(find.byKey(const Key('diary.slot.dinner')), findsOneWidget);
  });

  testWidgets('slot total is the sum of entry mids and the hint disappears',
      (tester) async {
    await pumpWidgetOnly(
        tester,
        _section(
            MealSlot.lunch,
            [quickEntry(id: 'a', kcal: 400), quickEntry(id: 'b', kcal: 250)],
            _Calls()));
    expect(find.text('650 kcal'), findsOneWidget, reason: 'slot total');
    expect(find.text('400 kcal'), findsOneWidget);
    expect(find.text('250 kcal'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('entry row: name, source badge, confidence', (tester) async {
    await pumpWidgetOnly(
        tester,
        _section(
            MealSlot.lunch,
            [riceEntry(source: FoodSource.llmEstimate, confidence: EntryConfidence.low)],
            _Calls()));
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('Estimate'), findsOneWidget);
    // 150 g x 130 kcal / 100 g = 195: once as the slot total, once on the row.
    expect(find.text('195 kcal'), findsNWidgets(2));
    expect(find.text(l10nOf(tester).foodConfidenceLow), findsOneWidget);
  });

  testWidgets('an unnamed entry falls back to its first item name',
      (tester) async {
    final e = riceEntry().copyWith(name: '');
    await pumpWidgetOnly(tester, _section(MealSlot.lunch, [e], _Calls()));
    expect(find.text('Rice'), findsOneWidget);
  });

  testWidgets('add button: tooltip names the slot and fires onAdd',
      (tester) async {
    final c = _Calls();
    await pumpWidgetOnly(tester, _section(MealSlot.lunch, const [], c));
    expect(find.byTooltip('Add to Lunch'), findsOneWidget);
    await tester.tap(find.byKey(const Key('diary.add.lunch')));
    expect(c.adds, 1);
  });

  testWidgets('tap opens the entry; delete deletes it and does not open',
      (tester) async {
    final c = _Calls();
    await pumpWidgetOnly(tester,
        _section(MealSlot.lunch, [quickEntry(id: 'a'), quickEntry(id: 'b')], c));
    await tester.tap(find.byKey(const Key('diary.entry.b')));
    expect(c.opened, ['b']);
    await tester.tap(find.byTooltip('Delete entry').first);
    expect(c.deleted, ['a']);
    expect(c.opened, ['b'], reason: 'delete must not also open the sheet');
  });

  testWidgets('add and delete targets are at least 48 x 48 dp', (tester) async {
    await pumpWidgetOnly(
        tester, _section(MealSlot.lunch, [quickEntry()], _Calls()));
    for (final f in [
      find.byKey(const Key('diary.add.lunch')),
      find.byTooltip('Delete entry'),
    ]) {
      final s = tester.getSize(f);
      expect(s.width, greaterThanOrEqualTo(48));
      expect(s.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('slot heading is a semantics header', (tester) async {
    final h = tester.ensureSemantics();
    await pumpWidgetOnly(tester, _section(MealSlot.snack, const [], _Calls()));
    expect(
        tester.getSemantics(find.text('Snacks')),
        matchesSemantics(label: 'Snacks', isHeader: true));
    h.dispose();
  });

  testWidgets('RU slot names', (tester) async {
    await pumpWidgetOnly(tester, _section(MealSlot.breakfast, const [], _Calls()),
        locale: const Locale('ru'));
    final ru = l10nOf(tester);
    expect(find.text(ru.foodDiarySlotBreakfast), findsOneWidget);
    expect(ru.foodDiarySlotBreakfast, isNot('Breakfast'));
    expect(find.text(ru.foodDiarySlotEmpty), findsOneWidget);
  });
}
