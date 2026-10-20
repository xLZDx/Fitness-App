// T101 food_detail_sheet_test (FOOD-25, FOOD-20 resolution, PRIV-23 diary
// write gate, a11y F13/F14): nothing is logged until Save, the data notice
// comes before the first write, the slot picker and portion editors change
// what is saved, check-these chips resolve with exact oil maths, a failed
// write is said calmly. Expected numbers are hand-computed:
// 150 g x 130 kcal/100 g = 195; 200 g -> 260; 14 g of oil x 884/100 = 123.76.
import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/food_detail_sheet.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'food_diary_fixtures.dart';
import 'food_diary_harness.dart';

class _Opener extends StatelessWidget {
  const _Opener({required this.entry, required this.result});
  final FoodEntry entry;
  final List<bool> result;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open'),
            onPressed: () async =>
                result.add(await showFoodDetailSheet(context, entry)),
            child: const Text('open'),
          ),
        ),
      );
}

class _Sheet {
  _Sheet(this.page, this.tester, this.result, this.store);
  final PumpedPage page;
  final WidgetTester tester;
  final List<bool> result;
  final InMemoryDataNoticeStore store;

  InMemoryDiaryRepository get diary =>
      page.container.read(diaryRepositoryProvider) as InMemoryDiaryRepository;
  InMemorySavedFoodsRepository get saved =>
      page.container.read(savedFoodsRepositoryProvider)
          as InMemorySavedFoodsRepository;

  Future<List<FoodEntry>> entries([String day = kToday]) async =>
      (await tester.runAsync(() => diary.watchDay(kDiaryUid, day).first))!;

  Future<List<SavedFood>> savedFoods() async =>
      (await tester.runAsync(() => saved.watchAll(kDiaryUid).first))!;
}

Future<_Sheet> _open(
  WidgetTester tester,
  FoodEntry entry, {
  bool acknowledged = true,
}) async {
  final result = <bool>[];
  final store = InMemoryDataNoticeStore(acknowledged: acknowledged);
  final page = await pumpPage(
    tester,
    _Opener(entry: entry, result: result),
    overrides: diaryOverrides(extra: [
      dataNoticeStoreProvider.overrideWith((ref) async => store),
    ]),
  );
  await tester.tap(find.byKey(const Key('open')));
  await settle(tester);
  return _Sheet(page, tester, result, store);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await settle(tester);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await settle(tester);
}

bool _selected(WidgetTester tester, String slot) =>
    tester.widget<ChoiceChip>(find.byKey(Key('detail.slot.$slot'))).selected;

Finder _portionField(int i) => find.descendant(
    of: find.byKey(Key('detail.portion.$i')), matching: find.byType(TextField));

List<CheckItem> _oil() => const [CheckItem(code: CheckCode.hiddenIngredients)];

FoodEntry _withItems(FoodEntry e, List<FoodItem> items) => e.copyWith(
      items: items,
      totals: MacroTotals.combine([
        for (final i in items)
          MacroTotals(
            kcal: i.grams.scaled(i.per100g.kcal / 100),
            proteinG: i.grams.scaled(i.per100g.proteinG / 100),
            carbsG: i.grams.scaled(i.per100g.carbsG / 100),
            fatG: i.grams.scaled(i.per100g.fatG / 100),
          )
      ]),
    );

void main() {
  group('content', () {
    testWidgets('title, name, confidence, per-100 g line and totals',
        (tester) async {
      await _open(tester, riceEntry());
      expect(find.text('Add to diary'), findsNWidgets(2),
          reason: 'sheet heading and the Save button');
      expect(find.text('Rice'), findsWidgets);
      expect(find.text(l10nOf(tester).foodConfidenceHigh), findsOneWidget);
      expect(
          find.text('Per 100 g: 130 kcal, protein 2.7 g, carbs 28 g, fat 0.3 g'),
          findsOneWidget);
      expect(find.text('About 195 kcal, range 195 to 195'), findsOneWidget);
      expect(find.text('Protein'), findsOneWidget);
    });

    testWidgets('a range portion shows its likely range and a range total',
        (tester) async {
      await _open(tester, riceEntry(grams: MacroRange(100, 150, 200)));
      expect(find.text('Likely between 100 and 200 g'), findsOneWidget);
      expect(find.text('About 195 kcal, range 130 to 260'), findsOneWidget);
    });

    testWidgets('the estimate note appears only for model estimates',
        (tester) async {
      await _open(tester, riceEntry(source: FoodSource.llmEstimate));
      expect(find.text('These values are an estimate, not a database record.'),
          findsOneWidget);
      expect(find.text('Estimate'), findsOneWidget, reason: 'source badge');
    });

    testWidgets('no estimate note for database foods', (tester) async {
      await _open(tester, riceEntry());
      expect(find.textContaining('estimate, not a database'), findsNothing);
    });

    testWidgets('initial focus lands on the heading (F14)', (tester) async {
      await _open(tester, riceEntry());
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'detail.heading');
    });

    testWidgets('the sheet is a framework modal bottom sheet', (tester) async {
      await _open(tester, riceEntry());
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ModalBarrier), findsWidgets);
    });

    testWidgets('an unnamed entry shows its first item name', (tester) async {
      await _open(tester, riceEntry().copyWith(name: ''));
      expect(find.text('Rice'), findsWidgets);
    });
  });

  group('nothing is logged until Save (FOOD-25)', () {
    testWidgets('opening, editing and changing the slot write nothing',
        (tester) async {
      final s = await _open(tester, riceEntry());
      await tester.enterText(_portionField(0), '300');
      await _tapKey(tester, 'detail.slot.dinner');
      expect(s.diary.writes, 0);
      expect(s.result, isEmpty);
    });

    testWidgets('closing without Save writes nothing and resolves false',
        (tester) async {
      final s = await _open(tester, riceEntry());
      await tester.tapAt(const Offset(5, 5)); // modal barrier
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(s.result, [false]);
      expect(s.diary.writes, 0);
    });
  });

  group('slot picker', () {
    testWidgets('the entry slot is selected; tapping another moves selection',
        (tester) async {
      await _open(tester, riceEntry(slot: MealSlot.lunch));
      expect(_selected(tester, 'lunch'), isTrue);
      expect(_selected(tester, 'breakfast'), isFalse);
      await _tapKey(tester, 'detail.slot.breakfast');
      expect(_selected(tester, 'breakfast'), isTrue);
      expect(_selected(tester, 'lunch'), isFalse);
    });

    testWidgets('chips are at least 48 dp tall', (tester) async {
      await _open(tester, riceEntry());
      for (final s in MealSlot.values) {
        expect(tester.getSize(find.byKey(Key('detail.slot.${s.name}'))).height,
            greaterThanOrEqualTo(48));
      }
    });

    testWidgets('the saved entry carries the picked slot', (tester) async {
      final s = await _open(tester, riceEntry(slot: MealSlot.lunch));
      await _tapKey(tester, 'detail.slot.snack');
      await _tapKey(tester, 'detail.save');
      expect((await s.entries()).single.slot, MealSlot.snack);
    });
  });

  group('portion editing and Save', () {
    testWidgets('a typed portion recomputes the totals and is what is saved',
        (tester) async {
      final s = await _open(tester, riceEntry());
      await tester.enterText(_portionField(0), '200');
      await tester.pump();
      expect(find.text('About 260 kcal, range 260 to 260'), findsOneWidget);
      await _tapKey(tester, 'detail.save');
      final e = (await s.entries()).single;
      expect(e.items.single.grams, MacroRange.exact(200));
      expect(e.totals.kcal.mid, closeTo(260, 1e-9));
      expect(s.result, [true]);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('the less button lowers the portion by 10 g', (tester) async {
      await _open(tester, riceEntry());
      await tester.tap(find.descendant(
          of: find.byKey(const Key('detail.portion.0')),
          matching: find.byTooltip('Less')));
      await tester.pump();
      expect(find.text('About 182 kcal, range 182 to 182'), findsOneWidget,
          reason: '140 g x 1.3 = 182');
    });

    testWidgets('two items: editing one leaves the other untouched',
        (tester) async {
      const per = Per100g(kcal: 200, proteinG: 0, carbsG: 0, fatG: 0);
      final base = riceEntry();
      final entry = _withItems(base, [
        base.items.single,
        FoodItem(
            foodRef: 'gen:9',
            name: 'Bread',
            grams: MacroRange.exact(50),
            per100g: per,
            source: FoodSource.usda),
      ]);
      await _open(tester, entry);
      expect(find.text('About 295 kcal, range 295 to 295'), findsOneWidget);
      expect(find.byKey(const Key('detail.saveFood')), findsNothing,
          reason: 'only single-item entries offer Save this food');
      await tester.enterText(_portionField(1), '100');
      await tester.pump();
      expect(find.text('About 395 kcal, range 395 to 395'), findsOneWidget);
    });
  });

  group('data-notice gate before the first diary write (D-79, PRIV-23)', () {
    testWidgets('unacknowledged: the notice shows and NOTHING is written yet',
        (tester) async {
      final s = await _open(tester, riceEntry(), acknowledged: false);
      await _tapKey(tester, 'detail.save');
      expect(find.text(l10nOf(tester).dataNoticeTitle), findsOneWidget);
      expect(s.diary.writes, 0);
      expect(s.result, isEmpty);
    });

    testWidgets('acknowledging then writes once, and records the answer',
        (tester) async {
      final s = await _open(tester, riceEntry(), acknowledged: false);
      await _tapKey(tester, 'detail.save');
      await _tapText(tester, l10nOf(tester).dataNoticeAcknowledge);
      expect(s.store.acknowledgeCalls, 1);
      expect(s.diary.writes, 1);
      expect(s.result, [true]);
    });

    testWidgets('dismissing the notice defers the write: nothing lost, still open',
        (tester) async {
      final s = await _open(tester, riceEntry(), acknowledged: false);
      await _tapKey(tester, 'detail.save');
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(s.diary.writes, 0);
      expect(s.store.acknowledgeCalls, 0);
      expect(find.byKey(const Key('detail.save')), findsOneWidget,
          reason: 'the sheet stays so the user can try again');
      expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('detail.save')))
              .onPressed,
          isNotNull,
          reason: 'Save is enabled again');
      await _tapKey(tester, 'detail.save');
      await _tapText(tester, l10nOf(tester).dataNoticeAcknowledge);
      expect((await s.entries()).single.id, 'r1');
    });

    testWidgets('already acknowledged: no notice at all', (tester) async {
      final s = await _open(tester, riceEntry());
      await _tapKey(tester, 'detail.save');
      expect(find.text(l10nOf(tester).dataNoticeTitle), findsNothing);
      expect(s.diary.writes, 1);
    });

    testWidgets('Save this food is gated too', (tester) async {
      final s = await _open(tester, riceEntry(), acknowledged: false);
      await _tapKey(tester, 'detail.saveFood');
      expect(find.text(l10nOf(tester).dataNoticeTitle), findsOneWidget);
      expect(await s.savedFoods(), isEmpty);
    });
  });

  group('failed write', () {
    testWidgets('a repository failure shows a calm message and keeps the sheet',
        (tester) async {
      final s = await _open(tester, riceEntry());
      s.diary.offline = true;
      await _tapKey(tester, 'detail.save');
      expect(find.text('Could not save. Try again.'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(s.result, isEmpty);
      expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('detail.save')))
              .onPressed,
          isNotNull);
      s.diary.offline = false;
      await _tapKey(tester, 'detail.save');
      expect(s.result, [true]);
      expect(s.diary.writes, 1);
    });
  });

  group('Save this food', () {
    testWidgets('stores the single item as a saved food and says so',
        (tester) async {
      final s = await _open(tester, riceEntry());
      await _tapKey(tester, 'detail.saveFood');
      expect(find.text('Food saved'), findsOneWidget);
      final f = (await s.savedFoods()).single;
      expect(f.id, 'gen_1', reason: 'foodRef made safe as a document id');
      expect(f.name, 'Rice');
      expect(f.per100g.kcal, 130);
      expect(s.diary.writes, 0, reason: 'saving a food is not logging a meal');
    });
  });

  group('check these (FOOD-20)', () {
    testWidgets('chips are shown with their state', (tester) async {
      await _open(tester, riceEntry(checks: _oil()));
      expect(
          find.text('Cooking oil or sauce - Needs checking'), findsOneWidget);
    });

    testWidgets('hidden ingredients: 1 tablespoon adds exactly 14 g of oil',
        (tester) async {
      final s = await _open(tester, riceEntry(checks: _oil()));
      await _tapText(tester, 'Cooking oil or sauce - Needs checking');
      expect(find.text(l10nOf(tester).foodCheckHelpHiddenIngredients),
          findsOneWidget);
      await _tapKey(tester, 'resolve.oil.tablespoon');
      // 195 + 14 x 884 / 100 = 318.76
      expect(find.text('About 319 kcal, range 319 to 319'), findsOneWidget);
      expect(find.text('Cooking oil or sauce - Checked'), findsOneWidget);
      expect(find.text('Olive oil'), findsOneWidget);
      await _tapKey(tester, 'detail.save');
      final e = (await s.entries()).single;
      expect(
          e.totals.kcal.mid, closeTo(195 + 14 * kOilKcalPer100 / 100, 1e-9));
      expect(e.items.map((i) => i.name), ['Rice', 'Olive oil']);
      expect(e.items.last.foodRef, 'gen:4',
          reason: 'the table id already carries the gen: prefix');
      expect(e.checkThese.single.resolved, isTrue);
    });

    testWidgets('1 teaspoon adds 5 g; re-choosing replaces, never stacks',
        (tester) async {
      await _open(tester, riceEntry(checks: _oil()));
      await _tapText(tester, 'Cooking oil or sauce - Needs checking');
      await _tapKey(tester, 'resolve.oil.teaspoon');
      // 195 + 44.2 = 239.2
      expect(find.text('About 239 kcal, range 239 to 239'), findsOneWidget);
      await _tapText(tester, 'Cooking oil or sauce - Checked');
      await _tapKey(tester, 'resolve.oil.tablespoon');
      expect(find.text('About 319 kcal, range 319 to 319'), findsOneWidget);
      expect(find.text('Olive oil'), findsOneWidget, reason: 'one oil item');
    });

    testWidgets('No oil resolves the chip and leaves the totals unchanged',
        (tester) async {
      await _open(tester, riceEntry(checks: _oil()));
      await _tapText(tester, 'Cooking oil or sauce - Needs checking');
      await _tapKey(tester, 'resolve.oil.none');
      expect(find.text('About 195 kcal, range 195 to 195'), findsOneWidget);
      expect(find.text('Cooking oil or sauce - Checked'), findsOneWidget);
      expect(find.text('Olive oil'), findsNothing);
    });

    testWidgets('other chips resolve with "Mark as checked" only',
        (tester) async {
      await _open(
          tester,
          riceEntry(checks: const [
            CheckItem(code: CheckCode.portionUnclear),
            CheckItem(code: CheckCode.cookingMethod),
          ]));
      await _tapText(tester, 'Portion size - Needs checking');
      expect(find.byKey(const Key('resolve.done')), findsOneWidget);
      expect(find.byKey(const Key('resolve.oil.none')), findsNothing);
      await _tapKey(tester, 'resolve.done');
      expect(find.text('Portion size - Checked'), findsOneWidget);
      expect(
          find.text('${l10nOf(tester).foodCheckCookingMethod} - Needs checking'),
          findsOneWidget,
          reason: 'only the tapped chip was resolved');
      expect(find.text('About 195 kcal, range 195 to 195'), findsOneWidget);
    });

    testWidgets('focus moves to the next unresolved chip after resolving',
        (tester) async {
      await _open(
          tester,
          riceEntry(checks: const [
            CheckItem(code: CheckCode.portionUnclear),
            CheckItem(code: CheckCode.cookingMethod),
          ]));
      await _tapText(tester, 'Portion size - Needs checking');
      await _tapKey(tester, 'resolve.done');
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'check.cookingMethod');
    });
  });
}
