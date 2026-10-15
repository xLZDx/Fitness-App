// C23 add_food_page_test (FOOD-25, PRIV-23 food-AI gate, C24 route agreement):
// tiles hidden when their flag is off, tile routes match the registered
// /nutrition/add/{search,photo,barcode,label} routes, quick log validation,
// the describe sheet (notice BEFORE the first food-AI call, calm
// feature-disabled line, nothing found, failure) and the save path.
import 'dart:async';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/food_diary/add_food_page.dart';
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/food_detail_sheet.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'food_diary_fixtures.dart';
import 'food_diary_harness.dart';

const _all = BodyScanFlags(foodAi: true, foodLookup: true);

class _Held extends FakeFoodApi {
  final Completer<MealAnalysis> gate = Completer();

  @override
  Future<MealAnalysis> analyzeMeal({
    String? text,
    String? imageBase64,
    String? mimeType,
    String? note,
    required String languageCode,
  }) {
    analyzeCalls++;
    return gate.future;
  }
}

MealAnalysis _eggs() => MealAnalysis(
      mealName: 'Eggs and toast',
      confidence: EntryConfidence.medium,
      assumptions: const [CheckCode.cookingMethod],
      items: [
        AnalysedItem(
          name: 'Egg',
          grams: MacroRange.exact(100),
          per100g: const Per100g(kcal: 143, proteinG: 12.6, carbsG: 0.7, fatG: 9.5),
          source: FoodSource.llmEstimate,
          matchQuality: MatchQuality.none,
          confidence: 0.6,
          checkCodes: const [CheckCode.portionUnclear],
        ),
        AnalysedItem(
          name: 'Mystery sauce',
          grams: MacroRange.exact(20),
          per100g: null,
          source: FoodSource.llmEstimate,
          matchQuality: MatchQuality.none,
          confidence: 0.2,
        ),
      ],
    );

class _Ctx {
  _Ctx(this.page, this.api, this.store);
  final PumpedPage page;
  final FakeFoodApi api;
  final InMemoryDataNoticeStore store;
  InMemoryDiaryRepository get diary =>
      page.container.read(diaryRepositoryProvider) as InMemoryDiaryRepository;
}

Future<_Ctx> _open(
  WidgetTester tester, {
  BodyScanFlags flags = _all,
  bool acknowledged = true,
  FakeFoodApi? api,
  String? day = kToday,
  MealSlot? slot = MealSlot.lunch,
}) async {
  final fake = api ?? FakeFoodApi();
  final store = InMemoryDataNoticeStore(acknowledged: acknowledged);
  final page = await pumpPage(
    tester,
    AddFoodPage(day: day, slot: slot),
    overrides: diaryOverrides(flags: flags, extra: [
      foodApiProvider.overrideWithValue(fake),
      dataNoticeStoreProvider.overrideWith((ref) async => store),
    ]),
  );
  return _Ctx(page, fake, store);
}

Finder _k(String k) => find.byKey(Key(k));

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await settle(tester);
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(_k(key), text);
  await tester.pump();
}

void main() {
  group('tiles and flags', () {
    testWidgets('all flags off: only search, quick log and saved foods',
        (tester) async {
      await _open(tester, flags: const BodyScanFlags());
      expect(_k('add.search'), findsOneWidget);
      expect(_k('add.quick'), findsOneWidget);
      expect(_k('add.saved'), findsOneWidget);
      for (final hidden in ['add.describe', 'add.photo', 'add.barcode', 'add.label']) {
        expect(_k(hidden), findsNothing, reason: hidden);
      }
    });

    testWidgets('foodAi only: describe, photo, label; no barcode',
        (tester) async {
      await _open(tester, flags: const BodyScanFlags(foodAi: true));
      for (final k in ['add.describe', 'add.photo', 'add.label']) {
        expect(_k(k), findsOneWidget, reason: k);
      }
      expect(_k('add.barcode'), findsNothing);
    });

    testWidgets('foodLookup only: barcode, but no AI tiles', (tester) async {
      await _open(tester, flags: const BodyScanFlags(foodLookup: true));
      expect(_k('add.barcode'), findsOneWidget);
      for (final k in ['add.describe', 'add.photo', 'add.label']) {
        expect(_k(k), findsNothing, reason: k);
      }
    });

    testWidgets('all flags on: every tile, with its label', (tester) async {
      await _open(tester);
      for (final t in [
        'Search foods',
        'Describe a meal',
        'Photograph a meal',
        'Scan a barcode',
        'Scan a nutrition label',
        'Quick log',
        'Saved foods',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('tiles are at least 56 dp tall', (tester) async {
      await _open(tester);
      for (final k in ['add.search', 'add.describe', 'add.photo', 'add.barcode',
          'add.label', 'add.quick', 'add.saved']) {
        expect(tester.getSize(_k(k)).height, greaterThanOrEqualTo(56), reason: k);
      }
    });
  });

  group('tile routes (C24 alignment)', () {
    const q = '?day=2026-10-15&slot=lunch';
    for (final c in {
      'add.search': '/nutrition/add/search$q',
      'add.photo': '/nutrition/add/photo$q',
      'add.barcode': '/nutrition/add/barcode$q',
      'add.label': '/nutrition/add/label$q',
      'add.saved': '/nutrition/add/search$q&saved=1',
    }.entries) {
      testWidgets('${c.key} pushes ${c.value}', (tester) async {
        final ctx = await _open(tester);
        await _tap(tester, _k(c.key));
        expect(ctx.page.stubUri, c.value);
      });
    }

    testWidgets('without day and slot the slot defaults to snack',
        (tester) async {
      final ctx = await _open(tester, day: null, slot: null);
      await _tap(tester, _k('add.search'));
      expect(ctx.page.stubUri, '/nutrition/add/search?day=&slot=snack');
    });
  });

  group('quick log', () {
    Future<_Ctx> sheet(WidgetTester tester, {bool ack = true}) async {
      final c = await _open(tester, acknowledged: ack);
      await _tap(tester, _k('add.quick'));
      return c;
    }

    testWidgets('empty name or calories: the calm hint, no detail sheet',
        (tester) async {
      await sheet(tester);
      await _tap(tester, _k('quick.add'));
      expect(find.text('Enter a name and calories.'), findsOneWidget);
      expect(find.byType(FoodDetailSheet), findsNothing);
      await _type(tester, 'quick.name', 'Soup');
      await _tap(tester, _k('quick.add'));
      expect(find.text('Enter a name and calories.'), findsOneWidget);
      expect(find.byType(FoodDetailSheet), findsNothing);
    });

    testWidgets('calories above 1000 or negative are refused', (tester) async {
      await sheet(tester);
      await _type(tester, 'quick.name', 'Soup');
      await _type(tester, 'quick.kcal', '1001');
      await _tap(tester, _k('quick.add'));
      expect(find.byType(FoodDetailSheet), findsNothing);
      await _type(tester, 'quick.kcal', '-5');
      await _tap(tester, _k('quick.add'));
      expect(find.byType(FoodDetailSheet), findsNothing);
      await _type(tester, 'quick.kcal', '1000');
      await _tap(tester, _k('quick.add'));
      expect(find.byType(FoodDetailSheet), findsOneWidget);
    });

    testWidgets('valid values open the detail sheet with those totals',
        (tester) async {
      final c = await sheet(tester);
      await _type(tester, 'quick.name', 'Soup');
      await _type(tester, 'quick.kcal', '350');
      await _type(tester, 'quick.protein', '20,5');
      await _tap(tester, _k('quick.add'));
      expect(find.byType(FoodDetailSheet), findsOneWidget);
      expect(find.text('About 350 kcal, range 350 to 350'), findsOneWidget);
      expect(find.text('20.5 g'), findsOneWidget, reason: 'decimal comma parsed');
      expect(c.diary.writes, 0, reason: 'nothing logged until Save');
    });

    testWidgets('Save writes the entry for the page day and slot, then opens '
        'the diary', (tester) async {
      final c = await sheet(tester);
      await _type(tester, 'quick.name', 'Soup');
      await _type(tester, 'quick.kcal', '350');
      await _tap(tester, _k('quick.add'));
      await _tap(tester, _k('detail.save'));
      expect(c.diary.writes, 1);
      final e = (await tester.runAsync(
              () => c.diary.watchDay(kDiaryUid, kToday).first))!
          .single;
      expect(e.slot, MealSlot.lunch);
      expect(e.source, EntrySource.manual);
      expect(e.items.single.foodRef, 'user:quick');
      expect(e.totals.kcal.mid, 350);
      expect(c.page.stubUri, '/nutrition/diary');
    });

    testWidgets('unacknowledged notice defers the quick-log write',
        (tester) async {
      final c = await sheet(tester, ack: false);
      await _type(tester, 'quick.name', 'Soup');
      await _type(tester, 'quick.kcal', '350');
      await _tap(tester, _k('quick.add'));
      await _tap(tester, _k('detail.save'));
      expect(find.text(l10nOf(tester).dataNoticeTitle), findsOneWidget);
      expect(c.diary.writes, 0);
    });

    testWidgets('a very long name is cut to 80 characters', (tester) async {
      final c = await sheet(tester);
      await _type(tester, 'quick.name', 'n' * 120);
      await _type(tester, 'quick.kcal', '10');
      await _tap(tester, _k('quick.add'));
      await _tap(tester, _k('detail.save'));
      final e = (await tester.runAsync(
              () => c.diary.watchDay(kDiaryUid, kToday).first))!
          .single;
      expect(e.name.length, 80);
      expect(e.items.single.name.length, 80);
    });
  });

  group('describe a meal', () {
    Future<_Ctx> sheet(
      WidgetTester tester, {
      bool ack = true,
      FakeFoodApi? api,
    }) async {
      final c = await _open(tester, acknowledged: ack, api: api);
      await _tap(tester, _k('add.describe'));
      return c;
    }

    testWidgets('under 3 characters: no notice, no call', (tester) async {
      final c = await sheet(tester, ack: false);
      await _type(tester, 'describe.text', 'ab');
      await _tap(tester, _k('describe.go'));
      expect(find.text(l10nOf(tester).dataNoticeTitle), findsNothing);
      expect(c.api.analyzeCalls, 0);
    });

    testWidgets('the notice comes BEFORE the first food-AI call (D-79)',
        (tester) async {
      final api = FakeFoodApi(analysis: _eggs());
      final c = await sheet(tester, ack: false, api: api);
      await _type(tester, 'describe.text', 'two eggs and toast');
      await _tap(tester, _k('describe.go'));
      expect(find.text(l10nOf(tester).dataNoticeTitle), findsOneWidget);
      expect(api.analyzeCalls, 0, reason: 'no AI call before acknowledgement');
      await _tap(tester, find.text(l10nOf(tester).dataNoticeAcknowledge));
      expect(api.analyzeCalls, 1);
      expect(c.store.acknowledgeCalls, 1);
    });

    testWidgets('dismissing the notice makes no AI call and keeps the text',
        (tester) async {
      final api = FakeFoodApi(analysis: _eggs());
      await sheet(tester, ack: false, api: api);
      await _type(tester, 'describe.text', 'two eggs and toast');
      await _tap(tester, _k('describe.go'));
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(api.analyzeCalls, 0);
      expect(find.text('two eggs and toast'), findsOneWidget);
    });

    testWidgets('acknowledged: one call, items with values become a draft, '
        'unmatched items become a chip', (tester) async {
      final api = FakeFoodApi(analysis: _eggs());
      final c = await sheet(tester, api: api);
      await _type(tester, 'describe.text', '  two eggs and toast ');
      await _tap(tester, _k('describe.go'));
      expect(api.analyzeCalls, 1);
      expect(find.byType(FoodDetailSheet), findsOneWidget);
      expect(find.text('Eggs and toast'), findsOneWidget);
      expect(find.text('Egg'), findsOneWidget);
      expect(find.text('Mystery sauce'), findsNothing,
          reason: 'an item without values is never written as zeros');
      expect(find.text('About 143 kcal, range 143 to 143'), findsOneWidget);
      expect(find.text('Portion size - Needs checking'), findsOneWidget);
      expect(find.text('${l10nOf(tester).foodCheckCookingMethod} - Needs checking'),
          findsOneWidget);
      expect(
          find.text(
              '${l10nOf(tester).foodCheckFoodNotMatched} - Needs checking'),
          findsOneWidget);
      expect(find.text('These values are an estimate, not a database record.'),
          findsOneWidget);
      expect(c.diary.writes, 0);
    });

    testWidgets('Save stores a describe entry with its model values',
        (tester) async {
      final c = await sheet(tester, api: FakeFoodApi(analysis: _eggs()));
      await _type(tester, 'describe.text', 'two eggs and toast');
      await _tap(tester, _k('describe.go'));
      await _tap(tester, _k('detail.save'));
      final e = (await tester.runAsync(
              () => c.diary.watchDay(kDiaryUid, kToday).first))!
          .single;
      expect(e.source, EntrySource.describe);
      expect(e.name, 'Eggs and toast');
      expect(e.confidence, EntryConfidence.medium);
      expect(e.items.single.source, FoodSource.llmEstimate);
      expect(e.items.single.foodRef, 'llm:egg');
      expect(e.checkThese.map((i) => i.code),
          containsAll([CheckCode.portionUnclear, CheckCode.cookingMethod,
            CheckCode.foodNotMatched]));
      expect(c.page.stubUri, '/nutrition/diary');
    });

    testWidgets('feature-disabled is a calm "not available yet", not an error',
        (tester) async {
      await sheet(tester,
          api: FakeFoodApi(failure: FoodApiFailure.featureDisabled));
      await _type(tester, 'describe.text', 'two eggs');
      await _tap(tester, _k('describe.go'));
      expect(_k('describe.off'), findsOneWidget);
      expect(find.text('This is not available yet. Search and quick log still work.'),
          findsOneWidget);
      expect(_k('describe.msg'), findsNothing);
      expect(find.byType(FoodDetailSheet), findsNothing);
      expect(
          tester.widget<FilledButton>(_k('describe.go')).onPressed, isNotNull,
          reason: 'the button is usable again');
    });

    testWidgets('other failures give the retry message', (tester) async {
      await sheet(tester,
          api: FakeFoodApi(failure: FoodApiFailure.upstreamUnavailable));
      await _type(tester, 'describe.text', 'two eggs');
      await _tap(tester, _k('describe.go'));
      expect(_k('describe.msg'), findsOneWidget);
      expect(find.text('The estimate could not finish. Try again, or use search.'),
          findsOneWidget);
    });

    testWidgets('no food found: says so and opens nothing', (tester) async {
      await sheet(tester, api: FakeFoodApi());
      await _type(tester, 'describe.text', 'asdf qwer');
      await _tap(tester, _k('describe.go'));
      expect(
          find.text('No food was found in that text. Try describing it differently.'),
          findsOneWidget);
      expect(find.byType(FoodDetailSheet), findsNothing);
    });

    testWidgets('while the estimate runs the button is disabled and labelled',
        (tester) async {
      final api = _Held();
      await sheet(tester, api: api);
      await _type(tester, 'describe.text', 'two eggs');
      await tester.tap(_k('describe.go'));
      await settle(tester);
      expect(tester.widget<FilledButton>(_k('describe.go')).onPressed, isNull);
      expect(find.bySemanticsLabel('Estimating'), findsOneWidget);
      await tester.tap(_k('describe.go'), warnIfMissed: false);
      expect(api.analyzeCalls, 1, reason: 'no second call while working');
      api.gate.complete(_eggs());
      await settle(tester);
      expect(find.byType(FoodDetailSheet), findsOneWidget);
    });

    testWidgets('the text field is capped at 200 characters', (tester) async {
      await sheet(tester);
      await _type(tester, 'describe.text', 'x' * 260);
      final t = tester.widget<TextField>(_k('describe.text'));
      expect(t.controller!.text.length, 200);
    });
  });
}
