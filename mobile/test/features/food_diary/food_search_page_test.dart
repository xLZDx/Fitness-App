// C23 food_search_page_test (FOOD-22/FOOD-14 UI half): bundled foods answer
// while typing, packaged results only after an explicit submit (3-character
// minimum), the closed state messages, saved foods, and the pick -> detail ->
// Save path. Numbers: 100 g of "Rice, white" at 130 kcal/100 g = 130 kcal.
import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/food_detail_sheet.dart';
import 'package:fitness_app/features/food_diary/food_search_page.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'food_diary_fixtures.dart';
import 'food_diary_harness.dart';

const _full = FoodCandidate(
  foodRef: 'off:111',
  name: 'Rice pudding',
  brand: 'Acme',
  per100g: Per100g(kcal: 120, proteinG: 3, carbsG: 20, fatG: 3),
  source: FoodSource.off,
  servingG: 30,
);

const _partial = FoodCandidate(
  foodRef: 'off:222',
  name: 'Rice bar',
  per100g: Per100g(kcal: 380, proteinG: 5, carbsG: 70, fatG: 8),
  source: FoodSource.off,
  complete: false,
);

class _Ctx {
  _Ctx(this.page, this.api);
  final PumpedPage page;
  final FakeFoodApi api;
  InMemoryDiaryRepository get diary =>
      page.container.read(diaryRepositoryProvider) as InMemoryDiaryRepository;
}

Future<_Ctx> _open(
  WidgetTester tester, {
  FakeFoodApi? api,
  bool lookup = true,
  bool savedOnly = false,
  String? day = kToday,
  MealSlot? slot = MealSlot.dinner,
  List<SavedFood> saved = const [],
  Locale locale = const Locale('en'),
}) async {
  final fake = api ?? FakeFoodApi();
  final savedRepo = InMemorySavedFoodsRepository();
  for (final s in saved) {
    await savedRepo.put(kDiaryUid, s);
  }
  final page = await pumpPage(
    tester,
    FoodSearchPage(day: day, slot: slot, savedOnly: savedOnly),
    locale: locale,
    overrides: diaryOverrides(
      flags: BodyScanFlags(foodLookup: lookup),
      extra: [
        foodApiProvider.overrideWithValue(fake),
        savedFoodsRepositoryProvider.overrideWithValue(savedRepo),
      ],
    ),
  );
  return _Ctx(page, fake);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('search.field')), text);
  await tester.pump();
}

/// Explicit submit through the button, then the debounce and the answer.
Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('search.submit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  await tester.pump();
}

Finder _msg() => find.byKey(const Key('search.message'));

String? _msgText(WidgetTester tester) =>
    _msg().evaluate().isEmpty ? null : tester.widget<Text>(_msg()).data;

void main() {
  group('typing (bundled foods, no network)', () {
    testWidgets('idle: field, submit button, no message', (tester) async {
      await _open(tester);
      expect(find.text('Search foods'), findsOneWidget);
      expect(find.byKey(const Key('search.field')), findsOneWidget);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(_msg(), findsNothing);
    });

    testWidgets('1-2 characters: the minimum-length message, no rows',
        (tester) async {
      final c = await _open(tester);
      await _type(tester, 'ri');
      expect(_msgText(tester), 'Type at least 3 characters.');
      expect(find.text('Common foods'), findsNothing);
      expect(c.api.searchCalls, 0);
    });

    testWidgets('3 characters list bundled rows at once and call nothing',
        (tester) async {
      final c = await _open(tester);
      await _type(tester, 'ric');
      expect(find.text('Common foods'), findsOneWidget);
      expect(find.byKey(const Key('search.gen.gen:1')), findsOneWidget);
      expect(find.byKey(const Key('search.gen.gen:2')), findsOneWidget);
      expect(find.byKey(const Key('search.gen.gen:3')), findsNothing,
          reason: 'chicken does not match rice');
      expect(find.text('Rice, white'), findsOneWidget);
      expect(find.text('130 kcal per 100 g'), findsOneWidget);
      expect(find.text(l10nOf(tester).foodSourceUsda), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
      expect(c.api.searchCalls, 0, reason: 'typing never reaches the server');
      expect(find.text('Packaged foods'), findsNothing);
    });

    testWidgets('rows are at least 56 dp tall', (tester) async {
      await _open(tester);
      await _type(tester, 'ric');
      expect(tester.getSize(find.byKey(const Key('search.gen.gen:1'))).height,
          greaterThanOrEqualTo(56));
    });
  });

  group('explicit submit (packaged foods)', () {
    testWidgets('shows loading, then Packaged foods with brand and source',
        (tester) async {
      final c = await _open(tester, api: FakeFoodApi(search: const [_full]));
      await _type(tester, 'rice');
      await tester.tap(find.byKey(const Key('search.submit')));
      await tester.pump();
      expect(_msgText(tester), 'Searching');
      expect(c.api.searchCalls, 0, reason: 'debounce still running');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump();
      expect(c.api.searchCalls, 1);
      expect(c.api.lastQuery, 'rice');
      expect(find.text('Packaged foods'), findsOneWidget);
      expect(find.text('Rice pudding - Acme'), findsOneWidget);
      expect(find.text('120 kcal per 100 g'), findsOneWidget);
      expect(find.text(l10nOf(tester).foodSourceOff), findsOneWidget);
      expect(_msg(), findsNothing);
    });

    testWidgets('the keyboard search action submits too', (tester) async {
      final c = await _open(tester, api: FakeFoodApi(search: const [_full]));
      await tester.enterText(find.byKey(const Key('search.field')), 'rice');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(c.api.searchCalls, 1);
    });

    testWidgets('a partial database record says so', (tester) async {
      await _open(tester, api: FakeFoodApi(search: const [_partial]));
      await _type(tester, 'rice');
      await _submit(tester);
      expect(find.text('Some values are missing for this product.'),
          findsOneWidget);
    });

    testWidgets('submitting under 3 characters never calls the server',
        (tester) async {
      final c = await _open(tester, api: FakeFoodApi(search: const [_full]));
      await _type(tester, 'ri');
      await _submit(tester);
      expect(c.api.searchCalls, 0);
      expect(_msgText(tester), 'Type at least 3 characters.');
    });

    testWidgets('server flag off: no call, bundled rows still answer',
        (tester) async {
      final c = await _open(tester,
          lookup: false, api: FakeFoodApi(search: const [_full]));
      await _type(tester, 'rice');
      await _submit(tester);
      expect(c.api.searchCalls, 0);
      expect(find.text('Common foods'), findsOneWidget);
      expect(find.text('Packaged foods'), findsNothing);
    });

    testWidgets('a repeat of the same query is served from the cache',
        (tester) async {
      final c = await _open(tester, api: FakeFoodApi(search: const [_full]));
      await _type(tester, 'rice');
      await _submit(tester);
      await _submit(tester);
      expect(c.api.searchCalls, 1);
      expect(find.text('Rice pudding - Acme'), findsOneWidget);
    });
  });

  group('closed states', () {
    testWidgets('nothing found: the calm empty line', (tester) async {
      await _open(tester, api: FakeFoodApi());
      await _type(tester, 'zzzz');
      await _submit(tester);
      expect(_msgText(tester), 'No foods found. Try another word or use quick log.');
    });

    testWidgets('server flag off and no bundled hit: the same empty line',
        (tester) async {
      await _open(tester, lookup: false);
      await _type(tester, 'zzzz');
      expect(_msgText(tester), 'No foods found. Try another word or use quick log.');
    });

    testWidgets('feature-disabled: not available yet, bundled rows stay',
        (tester) async {
      await _open(tester,
          api: FakeFoodApi(failure: FoodApiFailure.featureDisabled));
      await _type(tester, 'rice');
      await _submit(tester);
      expect(_msgText(tester),
          'Packaged-food search is not available yet. Bundled foods still work.');
      expect(find.text('Common foods'), findsOneWidget);
    });

    testWidgets('upstream failure with nothing else: the error line',
        (tester) async {
      await _open(tester,
          api: FakeFoodApi(failure: FoodApiFailure.upstreamUnavailable));
      await _type(tester, 'zzzz');
      await _submit(tester);
      expect(_msgText(tester),
          'Search could not finish. Check your connection and try again.');
    });

    testWidgets('rate limited with bundled rows: the rate message plus rows',
        (tester) async {
      await _open(tester, api: FakeFoodApi(failure: FoodApiFailure.rateLimited));
      await _type(tester, 'rice');
      await _submit(tester);
      expect(_msgText(tester), 'You searched a lot just now. Try again in a minute.');
      expect(find.text('Common foods'), findsOneWidget);
    });

    testWidgets('the message is a live region', (tester) async {
      final h = tester.ensureSemantics();
      await _open(tester);
      await _type(tester, 'ri');
      expect(
          tester.getSemantics(find.text('Type at least 3 characters.')),
          matchesSemantics(
              label: 'Type at least 3 characters.', isLiveRegion: true));
      h.dispose();
    });
  });

  group('picking a food', () {
    testWidgets('a bundled row opens the detail sheet at 100 g, nothing logged',
        (tester) async {
      final c = await _open(tester);
      await _type(tester, 'ric');
      await tester.tap(find.byKey(const Key('search.gen.gen:1')));
      await settle(tester);
      expect(find.byType(FoodDetailSheet), findsOneWidget);
      expect(find.text('About 130 kcal, range 130 to 130'), findsOneWidget);
      expect(find.text('Rice, white'), findsWidgets);
      expect(c.diary.writes, 0);
    });

    testWidgets('Save writes a search entry for the page day and slot and '
        'opens the diary', (tester) async {
      final c = await _open(tester, slot: MealSlot.dinner);
      await _type(tester, 'ric');
      await tester.tap(find.byKey(const Key('search.gen.gen:1')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);
      final e = (await tester.runAsync(
              () => c.diary.watchDay(kDiaryUid, kToday).first))!
          .single;
      expect(e.source, EntrySource.search);
      expect(e.slot, MealSlot.dinner);
      expect(e.items.single.foodRef, 'gen:1');
      expect(e.items.single.grams, MacroRange.exact(100));
      expect(e.confidence, EntryConfidence.high);
      expect(c.page.stubUri, '/nutrition/diary');
    });

    testWidgets('a malformed day parameter falls back to the clock day',
        (tester) async {
      final c = await _open(tester, day: 'garbage');
      await _type(tester, 'ric');
      await tester.tap(find.byKey(const Key('search.gen.gen:1')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);
      final e = (await tester.runAsync(
              () => c.diary.watchDay(kDiaryUid, kToday).first))!
          .single;
      expect(e.day, kToday);
    });

    testWidgets('a packaged row starts at its serving size and keeps its ref',
        (tester) async {
      final c = await _open(tester, api: FakeFoodApi(search: const [_full]));
      await _type(tester, 'rice');
      await _submit(tester);
      await tester.tap(find.byKey(const Key('search.remote.off:111')));
      await settle(tester);
      // 30 g x 120 / 100 = 36
      expect(find.text('About 36 kcal, range 36 to 36'), findsOneWidget);
      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);
      final e = (await tester.runAsync(
              () => c.diary.watchDay(kDiaryUid, kToday).first))!
          .single;
      expect(e.items.single.foodRef, 'off:111');
      expect(e.items.single.source, FoodSource.off);
      expect(e.items.single.grams, MacroRange.exact(30));
    });
  });

  group('saved foods', () {
    const oats = SavedFood(
      id: 's1',
      name: 'Oat porridge',
      per100g: Per100g(kcal: 70, proteinG: 2.5, carbsG: 12, fatG: 1.4),
      servingG: 250,
    );

    testWidgets('saved=1: title, no search field, the list, user source',
        (tester) async {
      await _open(tester, savedOnly: true, saved: [oats]);
      expect(find.text('Saved foods'), findsWidgets);
      expect(find.byKey(const Key('search.field')), findsNothing);
      expect(find.byKey(const Key('search.saved.s1')), findsOneWidget);
      expect(find.text('Oat porridge'), findsOneWidget);
      expect(find.text(l10nOf(tester).foodSourceUser), findsOneWidget);
    });

    testWidgets('picking a saved food starts at its serving and uses user:<id>',
        (tester) async {
      final c = await _open(tester, savedOnly: true, saved: [oats]);
      await tester.tap(find.byKey(const Key('search.saved.s1')));
      await settle(tester);
      // 250 g x 70 / 100 = 175
      expect(find.text('About 175 kcal, range 175 to 175'), findsOneWidget);
      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);
      final e = (await tester.runAsync(
              () => c.diary.watchDay(kDiaryUid, kToday).first))!
          .single;
      expect(e.items.single.foodRef, 'user:s1');
      expect(e.items.single.source, FoodSource.user);
    });

    testWidgets('while searching, only saved foods matching the query show',
        (tester) async {
      await _open(tester, saved: [oats]);
      await _type(tester, 'oat');
      expect(find.byKey(const Key('search.saved.s1')), findsOneWidget);
      await _type(tester, 'chi');
      expect(find.byKey(const Key('search.saved.s1')), findsNothing);
    });

    testWidgets('an empty saved list is not an error', (tester) async {
      await _open(tester, savedOnly: true);
      expect(find.byKey(const Key('search.message')), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });
  });

  testWidgets('RU: title, hint and the too-short message are Russian',
      (tester) async {
    await _open(tester, locale: const Locale('ru'));
    final ru = l10nOf(tester);
    expect(find.text(ru.foodSearchTitle), findsOneWidget);
    expect(ru.foodSearchTitle, isNot('Search foods'));
    await _type(tester, 'ри');
    expect(_msgText(tester), ru.foodSearchTooShort);
    expect(ru.foodSearchTooShort, isNot('Type at least 3 characters.'));
  });
}
