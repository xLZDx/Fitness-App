// C24 meal_scan_page_test (FOOD-27 meal photo half, D-79, PRIV-19): the data
// notice comes before the first food-AI call, a disabled feature shows a calm
// state, the photo is resized to 1024 px before it is sent, the result always
// goes through the detail sheet (nothing logged without Save) and the optional
// private thumbnail is written only after Save and only when the switch is on.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/meal_scan_page.dart';
import 'package:fitness_app/features/food_diary/state/capture_image_port.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:fitness_app/features/food_diary/state/meal_thumbnail_store.dart';
import 'package:fitness_app/features/progress_photos/data/aes_photo_cipher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'food_diary_fixtures.dart';
import 'food_diary_harness.dart';

class _Api extends FakeFoodApi {
  _Api({super.analysis, super.failure});
  String? sentBase64;
  String? sentMime;
  String? sentNote;
  String? sentText;
  String? sentLanguage;

  @override
  Future<MealAnalysis> analyzeMeal({
    String? text,
    String? imageBase64,
    String? mimeType,
    String? note,
    required String languageCode,
  }) {
    sentBase64 = imageBase64;
    sentMime = mimeType;
    sentNote = note;
    sentText = text;
    sentLanguage = languageCode;
    return super.analyzeMeal(
        text: text,
        imageBase64: imageBase64,
        mimeType: mimeType,
        note: note,
        languageCode: languageCode);
  }
}

/// In-memory stand-in for the encrypted store: records writes, no disk.
class _MemStore extends MealThumbnailStore {
  _MemStore()
      : super(
            dir: Directory('unused'),
            cipher: AesPhotoCipher(Uint8List(32)));
  final Map<String, Uint8List> puts = {};

  @override
  Future<bool> put(String entryId, Uint8List jpeg) async {
    puts[entryId] = jpeg;
    return true;
  }
}

Uint8List _png(int w, int h) {
  final i = img.Image(width: w, height: h);
  img.fill(i, color: img.ColorRgb8(120, 160, 90));
  return Uint8List.fromList(img.encodePng(i));
}

MealAnalysis _meal({
  List<AnalysedItem>? items,
  List<CheckCode> assumptions = const [],
  EntryConfidence confidence = EntryConfidence.medium,
  String name = 'Chicken and rice',
}) =>
    MealAnalysis(
        mealName: name,
        items: items ?? [_item('Rice', 150), _item('Chicken breast', 120)],
        confidence: confidence,
        assumptions: assumptions);

AnalysedItem _item(String name, double grams, {Per100g? per100g, bool hasPer100 = true}) =>
    AnalysedItem(
      name: name,
      grams: MacroRange(grams * 0.8, grams, grams * 1.2),
      per100g: hasPer100
          ? (per100g ?? const Per100g(kcal: 130, proteinG: 2.7, carbsG: 28, fatG: 0.3))
          : null,
      source: FoodSource.llmEstimate,
      matchQuality: MatchQuality.none,
      confidence: 0.7,
    );

late _MemStore _store;

Future<PumpedPage> _pump(
  WidgetTester tester,
  _Api api,
  FakeCaptureImagePort port, {
  bool noticeAcknowledged = true,
  String? day,
  MealSlot? slot,
  Locale locale = const Locale('en'),
}) =>
    pumpPage(
      tester,
      MealScanPage(day: day, slot: slot),
      locale: locale,
      overrides: diaryOverrides(extra: [
        foodApiProvider.overrideWithValue(api),
        captureImagePortProvider.overrideWithValue(port),
        mealThumbnailStoreProvider.overrideWith((ref) async => _store),
        dataNoticeStoreProvider.overrideWith((ref) async =>
            InMemoryDataNoticeStore(acknowledged: noticeAcknowledged)),
      ]),
    );

Future<void> _until(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 200 && f.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(f, findsWidgets);
}

Future<void> _pick(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('meal.pick')));
  await _until(tester, find.byKey(const Key('meal.preview')));
}

Future<void> _analyse(WidgetTester tester) async {
  await _pick(tester);
  await tester.tap(find.byKey(const Key('meal.analyse')));
  await settle(tester);
}

/// The save in the detail sheet also needs the thumbnail work (isolate) to end.
Future<void> _saveDetail(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('detail.save')));
  await settle(tester);
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<List<FoodEntry>> _entries(PumpedPage p, String day) =>
    p.container.read(diaryRepositoryProvider).watchDay(kDiaryUid, day).first;

int _writes(PumpedPage p) =>
    (p.container.read(diaryRepositoryProvider) as InMemoryDiaryRepository).writes;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _store = _MemStore();
  });

  group('picking', () {
    testWidgets('camera and gallery buttons use their source; cancel keeps them',
        (tester) async {
      final port = FakeCaptureImagePort(null);
      final api = _Api();
      await _pump(tester, api, port);
      await tester.tap(find.byKey(const Key('meal.take')));
      await settle(tester);
      expect(port.lastSource, CaptureSource.camera);
      await tester.tap(find.byKey(const Key('meal.pick')));
      await settle(tester);
      expect(port.lastSource, CaptureSource.gallery);
      expect(port.picks, 2);
      expect(find.byKey(const Key('meal.preview')), findsNothing);
      expect(api.analyzeCalls, 0);
    });

    testWidgets('not an image -> calm message, no analyse button', (tester) async {
      final api = _Api();
      await _pump(tester, api, FakeCaptureImagePort(Uint8List.fromList([9, 9, 9])));
      await tester.tap(find.byKey(const Key('meal.pick')));
      await _until(tester, find.byKey(const Key('meal.msg')));
      expect(find.text(l10nOf(tester).foodMealImageInvalid), findsOneWidget);
      expect(find.byKey(const Key('meal.analyse')), findsNothing);
    });

    testWidgets('preview shows the note field and the thumbnail switch ON by default',
        (tester) async {
      await _pump(tester, _Api(), FakeCaptureImagePort(_png(400, 300)));
      await _pick(tester);
      expect(find.byKey(const Key('meal.note')), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('meal.thumb'))).value,
          isTrue);
    });

    testWidgets('the note is limited to 200 characters', (tester) async {
      await _pump(tester, _Api(), FakeCaptureImagePort(_png(400, 300)));
      await _pick(tester);
      await tester.enterText(find.byKey(const Key('meal.note')), 'x' * 250);
      final t = tester.widget<TextField>(find.byKey(const Key('meal.note')));
      expect(t.controller!.text.length, 200);
    });
  });

  group('data notice gate (D-79)', () {
    testWidgets('unacknowledged: notice first, no call until accepted',
        (tester) async {
      final api = _Api(analysis: _meal());
      await _pump(tester, api, FakeCaptureImagePort(_png(400, 300)),
          noticeAcknowledged: false);
      await _analyse(tester);
      expect(find.text(l10nOf(tester).dataNoticeTitle), findsOneWidget);
      expect(api.analyzeCalls, 0);

      await tester.tap(find.text(l10nOf(tester).dataNoticeAcknowledge));
      await settle(tester);
      expect(api.analyzeCalls, 1);
      expect(find.byKey(const Key('detail.save')), findsOneWidget);
    });

    testWidgets('dismissing the notice -> no call, page unchanged', (tester) async {
      final api = _Api(analysis: _meal());
      await _pump(tester, api, FakeCaptureImagePort(_png(400, 300)),
          noticeAcknowledged: false);
      await _analyse(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(api.analyzeCalls, 0);
      expect(find.byKey(const Key('meal.analyse')), findsOneWidget);
    });

    testWidgets('acknowledged: no notice at all', (tester) async {
      final api = _Api(analysis: _meal());
      await _pump(tester, api, FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      expect(find.text(l10nOf(tester).dataNoticeTitle), findsNothing);
      expect(api.analyzeCalls, 1);
    });
  });

  group('what is sent', () {
    testWidgets('a 1024 px JPEG, the trimmed note, no describe text',
        (tester) async {
      final api = _Api(analysis: _meal());
      await _pump(tester, api, FakeCaptureImagePort(_png(3000, 1500)),
          locale: const Locale('ru'));
      await _pick(tester);
      await tester.enterText(find.byKey(const Key('meal.note')), '  this is oat milk  ');
      await tester.tap(find.byKey(const Key('meal.analyse')));
      await settle(tester);
      expect(api.sentMime, 'image/jpeg');
      expect(api.sentNote, 'this is oat milk');
      expect(api.sentText, isNull);
      expect(api.sentLanguage, 'ru');
      final d = img.decodeJpg(base64Decode(api.sentBase64!))!;
      expect(d.width, 1024);
      expect(d.height, 512);
    });

    testWidgets('no note typed -> an empty note, never null text', (tester) async {
      final api = _Api(analysis: _meal());
      await _pump(tester, api, FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      expect(api.sentNote, '');
    });
  });

  group('result goes through the detail sheet, nothing is logged without Save',
      () {
    testWidgets('sheet shows the meal; the diary stays empty until Save',
        (tester) async {
      final p = await _pump(tester, _Api(analysis: _meal()),
          FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      expect(find.byKey(const Key('detail.save')), findsOneWidget);
      expect(find.text('Chicken and rice'), findsOneWidget);
      expect(_writes(p), 0);
    });

    testWidgets('Save writes a photo entry with items, slot, day, confidence, chips',
        (tester) async {
      final p = await _pump(
          tester,
          _Api(
              analysis: _meal(
                  assumptions: [CheckCode.hiddenIngredients],
                  confidence: EntryConfidence.low)),
          FakeCaptureImagePort(_png(400, 300)),
          day: '2026-10-14',
          slot: MealSlot.dinner);
      await _analyse(tester);
      await _saveDetail(tester);

      final e = (await _entries(p, '2026-10-14')).single;
      expect(e.source, EntrySource.photo);
      expect(e.slot, MealSlot.dinner);
      expect(e.confidence, EntryConfidence.low);
      expect(e.name, 'Chicken and rice');
      expect(e.items.map((i) => i.name), ['Rice', 'Chicken breast']);
      expect(e.items.first.grams.mid, 150);
      expect(e.items.first.grams.low, closeTo(120, 1e-9));
      expect(e.items.first.grams.high, closeTo(180, 1e-9));
      expect(e.checkThese.map((c) => c.code), contains(CheckCode.hiddenIngredients));
      expect(p.stubUri, '/nutrition/diary');
    });

    testWidgets('an item without nutrition values is dropped and flagged',
        (tester) async {
      final p = await _pump(
          tester,
          _Api(
              analysis: _meal(items: [
            _item('Rice', 150),
            _item('Mystery sauce', 30, hasPer100: false),
          ])),
          FakeCaptureImagePort(_png(400, 300)),
          day: kToday,
          slot: MealSlot.lunch);
      await _analyse(tester);
      await _saveDetail(tester);
      final e = (await _entries(p, kToday)).single;
      expect(e.items.map((i) => i.name), ['Rice'], reason: 'never written as zeros');
      expect(e.checkThese.map((c) => c.code), contains(CheckCode.foodNotMatched));
    });

    testWidgets('all items unusable -> "no food" message, no sheet', (tester) async {
      final p = await _pump(
          tester,
          _Api(analysis: _meal(items: [_item('Mystery', 30, hasPer100: false)])),
          FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      expect(find.text(l10nOf(tester).foodMealNoFood), findsOneWidget);
      expect(find.byKey(const Key('detail.save')), findsNothing);
      expect(_writes(p), 0);
    });

    testWidgets('no food found in the photo (empty items)', (tester) async {
      await _pump(tester, _Api(), FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      expect(find.text(l10nOf(tester).foodMealNoFood), findsOneWidget);
      expect(find.byKey(const Key('meal.analyse')), findsOneWidget,
          reason: 'the user can try again');
    });

    testWidgets('closing the sheet without Save logs nothing and stores no thumbnail',
        (tester) async {
      final p = await _pump(tester, _Api(analysis: _meal()),
          FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(_writes(p), 0);
      expect(_store.puts, isEmpty);
      expect(p.stubUri, isNull);
    });
  });

  group('calm failures', () {
    testWidgets('feature disabled: calm state, the button is disabled',
        (tester) async {
      final api = _Api(failure: FoodApiFailure.featureDisabled);
      await _pump(tester, api, FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      expect(find.byKey(const Key('meal.off')), findsOneWidget);
      expect(find.text(l10nOf(tester).foodDiaryNotAvailableYet), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('meal.analyse'))).onPressed,
          isNull);
      expect(find.byKey(const Key('detail.save')), findsNothing);
    });

    testWidgets('source not configured is treated like not available',
        (tester) async {
      await _pump(tester, _Api(failure: FoodApiFailure.sourceNotConfigured),
          FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      expect(find.byKey(const Key('meal.off')), findsOneWidget);
    });

    testWidgets('rate limited and not allowed use their closed texts',
        (tester) async {
      final api = _Api(failure: FoodApiFailure.rateLimited);
      await _pump(tester, api, FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      expect(find.text(l10nOf(tester).foodScanRateLimited), findsOneWidget);
      api.failure = FoodApiFailure.notAllowed;
      await tester.tap(find.byKey(const Key('meal.analyse')));
      await settle(tester);
      expect(find.text(l10nOf(tester).foodScanNotAllowed), findsOneWidget);
    });

    testWidgets('unknown failure: generic text, retry works', (tester) async {
      final api = _Api(failure: FoodApiFailure.unknown);
      await _pump(tester, api, FakeCaptureImagePort(_png(400, 300)));
      await _analyse(tester);
      expect(find.text(l10nOf(tester).foodMealFailed), findsOneWidget);
      api.failure = null;
      api.analysis = _meal();
      await tester.tap(find.byKey(const Key('meal.analyse')));
      await settle(tester);
      expect(api.analyzeCalls, 2);
      expect(find.byKey(const Key('detail.save')), findsOneWidget);
    });
  });

  group('optional private thumbnail', () {
    testWidgets('switch ON: a 256 px JPEG is stored under the entry id after Save',
        (tester) async {
      final p = await _pump(tester, _Api(analysis: _meal()),
          FakeCaptureImagePort(_png(1600, 800)),
          day: kToday, slot: MealSlot.lunch);
      await _analyse(tester);
      await _saveDetail(tester);
      final e = (await _entries(p, kToday)).single;
      expect(_store.puts.keys, [e.id]);
      final thumb = img.decodeJpg(_store.puts[e.id]!)!;
      expect([thumb.width, thumb.height], [256, 128]);
    });

    testWidgets('switch OFF: nothing is stored, the entry is still saved',
        (tester) async {
      final p = await _pump(tester, _Api(analysis: _meal()),
          FakeCaptureImagePort(_png(400, 300)),
          day: kToday, slot: MealSlot.lunch);
      await _pick(tester);
      await tester.tap(find.byKey(const Key('meal.thumb')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('meal.analyse')));
      await settle(tester);
      await _saveDetail(tester);
      expect(_store.puts, isEmpty);
      expect(await _entries(p, kToday), hasLength(1));
    });

    testWidgets('the choice is remembered on this device', (tester) async {
      await _pump(tester, _Api(), FakeCaptureImagePort(_png(400, 300)));
      await _pick(tester);
      await tester.tap(find.byKey(const Key('meal.thumb')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getBool(kMealThumbnailPref), isFalse);
    });

    testWidgets('a stored OFF choice is applied on the next visit', (tester) async {
      SharedPreferences.setMockInitialValues({kMealThumbnailPref: false});
      await _pump(tester, _Api(), FakeCaptureImagePort(_png(400, 300)));
      await _pick(tester);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('meal.thumb'))).value,
          isFalse);
    });
  });

  testWidgets('Russian: the intro and the button are localised', (tester) async {
    await _pump(tester, _Api(), FakeCaptureImagePort(null),
        locale: const Locale('ru'));
    final l10n = l10nOf(tester);
    expect(find.text(l10n.foodMealScanIntro), findsOneWidget);
    expect(l10n.foodMealTake, isNot('Take a photo'));
  });
}
