// C23 food_diary_text_scale_test (A11Y-06, I18N-07): the diary, add-food,
// search pages and the detail / quick-log / describe sheets at text scale 2.0
// in RU on a 360x640 phone: no RenderFlex overflow, content reachable by
// scrolling. An overflow is reported as a FlutterError, which
// `tester.takeException()` returns.
import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/features/food_diary/add_food_page.dart';
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/food_detail_sheet.dart';
import 'package:fitness_app/features/food_diary/food_diary_page.dart';
import 'package:fitness_app/features/food_diary/food_search_page.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'food_diary_fixtures.dart';
import 'food_diary_harness.dart';

const _phone = Size(360, 640);
const _ru = Locale('ru');
const _flags = BodyScanFlags(foodAi: true, foodLookup: true);

const _longName = 'Овсяная каша на молоке с бананом, грецкими орехами и мёдом';

Future<PumpedPage> _pump(
  WidgetTester tester,
  Widget home, {
  BodyScanFlags flags = _flags,
  InMemoryDiaryRepository? repo,
  List<Override> extra = const [],
  NutritionEligibility? verdict = const Eligible(),
}) =>
    pumpPage(
      tester,
      home,
      locale: _ru,
      textScale: 2.0,
      size: _phone,
      overrides: diaryOverrides(verdict: verdict, flags: flags, extra: [
        if (repo != null) diaryRepositoryProvider.overrideWithValue(repo),
        ...extra,
      ]),
    );

void _noOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

/// Scrolls the first vertical scrollable to its end in steps; an overflow
/// appearing in lazily built rows would surface as an exception.
Future<void> _scrollAll(WidgetTester tester) async {
  final s = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(s, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<InMemoryDiaryRepository> _repoWithLongEntries() async {
  final r = InMemoryDiaryRepository();
  for (final slot in MealSlot.values) {
    await r.put(
        kDiaryUid,
        quickEntry(
            id: 'e-${slot.name}',
            slot: slot,
            name: _longName,
            kcal: 1234,
            protein: 123.4));
  }
  return r;
}

void main() {
  testWidgets('diary page with long RU entries', (tester) async {
    final p = await _pump(tester, const FoodDiaryPage(),
        repo: await _repoWithLongEntries());
    _noOverflow(tester);
    expect(find.byType(Scrollable), findsWidgets);
    await _scrollAll(tester);
    _noOverflow(tester);
    expect(p.container.read(selectedDiaryDayProvider), kToday);
  });

  testWidgets('diary page empty day and AI-off note', (tester) async {
    await _pump(tester, const FoodDiaryPage(), flags: const BodyScanFlags());
    _noOverflow(tester);
    await _scrollAll(tester);
    _noOverflow(tester);
  });

  testWidgets('diary page notices (hidden and needs profile)', (tester) async {
    await _pump(tester, const FoodDiaryPage(),
        verdict: const ReferProfessional(ReferReason.guidance));
    _noOverflow(tester);
    await _pump(tester, const FoodDiaryPage(),
        verdict: const NeedsAnswer(NutritionQuestion.nutritionGuidance));
    _noOverflow(tester);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('add-food page with every tile', (tester) async {
    await _pump(tester, const AddFoodPage(day: kToday, slot: MealSlot.lunch));
    _noOverflow(tester);
    await _scrollAll(tester);
    _noOverflow(tester);
    final ru = l10nOf(tester);
    expect(find.text(ru.foodAddSaved), findsOneWidget,
        reason: 'the last tile is reachable by scrolling');
  });

  testWidgets('quick-log and describe sheets', (tester) async {
    await _pump(tester, const AddFoodPage(day: kToday, slot: MealSlot.lunch));
    await tester.scrollUntilVisible(find.byKey(const Key('add.quick')), 200);
    await tester.ensureVisible(find.byKey(const Key('add.quick')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add.quick')));
    await settle(tester);
    _noOverflow(tester);
    expect(find.byKey(const Key('quick.name')), findsOneWidget, reason: 'sheet open');
    expect(find.byKey(const Key('quick.add'), skipOffstage: false), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('add.describe')), -200);
    await tester.ensureVisible(find.byKey(const Key('add.describe')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add.describe')));
    await settle(tester);
    _noOverflow(tester);
    expect(find.byKey(const Key('describe.go')), findsOneWidget);
  });

  testWidgets('search page with bundled and packaged rows', (tester) async {
    final api = FakeFoodApi(search: const [
      FoodCandidate(
        foodRef: 'off:1',
        name: 'Рисовый пудинг с ванилью и корицей',
        brand: 'Очень Длинное Название Бренда',
        per100g: Per100g(kcal: 120, proteinG: 3, carbsG: 20, fatG: 3),
        source: FoodSource.off,
        complete: false,
      ),
    ]);
    await _pump(tester, const FoodSearchPage(day: kToday, slot: MealSlot.lunch),
        extra: [foodApiProvider.overrideWithValue(api)]);
    await tester.enterText(find.byKey(const Key('search.field')), 'rice');
    await tester.pump();
    await tester.tap(find.byKey(const Key('search.submit')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    _noOverflow(tester);
    expect(api.searchCalls, 1);
    await _scrollAll(tester);
    _noOverflow(tester);
  });

  testWidgets('detail sheet with chips, two items and a range portion',
      (tester) async {
    final base = riceEntry(
      grams: MacroRange(100, 150, 200),
      checks: const [
        CheckItem(code: CheckCode.hiddenIngredients),
        CheckItem(code: CheckCode.portionUnclear),
        CheckItem(code: CheckCode.cookingMethod),
      ],
      source: FoodSource.llmEstimate,
    ).copyWith(name: _longName);
    await _pump(
        tester,
        Builder(
            builder: (c) => Scaffold(
                  body: TextButton(
                    key: const Key('open'),
                    onPressed: () => showFoodDetailSheet(c, base),
                    child: const Text('open'),
                  ),
                )));
    await tester.tap(find.byKey(const Key('open')));
    await settle(tester);
    _noOverflow(tester);
    expect(find.byType(FoodDetailSheet), findsOneWidget);
    // Save is reachable by scrolling inside the sheet.
    await tester.scrollUntilVisible(find.byKey(const Key('detail.save')), 200,
        scrollable: find.descendant(
                of: find.byType(FoodDetailSheet),
                matching: find.byType(Scrollable))
            .first);
    _noOverflow(tester);
    expect(find.byKey(const Key('detail.save')), findsOneWidget);
  });
}
