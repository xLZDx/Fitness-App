// C24 label_scan_page_test (FOOD-15 client half, FOOD-16, N-34, PRIV-19): the
// label result ALWAYS goes through the editable confirmation sheet; a
// saved_food is written only after Confirm; Cancel writes nothing; per-serving
// values are converted only with a usable serving weight; the data notice
// comes before the first call; failures are calm and closed.
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/label_scan_page.dart';
import 'package:fitness_app/features/food_diary/state/capture_image_port.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'food_diary_fixtures.dart';
import 'food_diary_harness.dart';

/// Records what the page sent.
class _Api extends FakeFoodApi {
  _Api({super.label, super.failure});
  String? sentBase64;
  String? sentMime;
  String? sentLanguage;

  @override
  Future<LabelReading> parseLabel({
    required String imageBase64,
    required String mimeType,
    required String languageCode,
  }) {
    sentBase64 = imageBase64;
    sentMime = mimeType;
    sentLanguage = languageCode;
    return super.parseLabel(
        imageBase64: imageBase64, mimeType: mimeType, languageCode: languageCode);
  }
}

Uint8List _png(int w, int h) {
  final i = img.Image(width: w, height: h);
  img.fill(i, color: img.ColorRgb8(200, 200, 200));
  return Uint8List.fromList(img.encodePng(i));
}

const _per100 = Per100g(kcal: 500, proteinG: 12.5, carbsG: 75, fatG: 15);

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
      LabelScanPage(day: day, slot: slot),
      locale: locale,
      overrides: diaryOverrides(extra: [
        foodApiProvider.overrideWithValue(api),
        captureImagePortProvider.overrideWithValue(port),
        dataNoticeStoreProvider.overrideWith((ref) async =>
            InMemoryDataNoticeStore(acknowledged: noticeAcknowledged)),
      ]),
    );

/// Real-async wait (the resize runs in an isolate) until [f] is found.
Future<void> _until(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 200 && f.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(f, findsWidgets);
}

Future<void> _pickAndRead(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('label.pick')));
  await _until(tester, find.byKey(const Key('label.preview')));
  await tester.tap(find.byKey(const Key('label.read')));
  await settle(tester);
}

Future<void> _fill(WidgetTester tester, Map<String, String> fields) async {
  for (final e in fields.entries) {
    await tester.enterText(find.byKey(Key('labelSheet.${e.key}')), e.value);
  }
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key('labelSheet.$key'))).controller!.text;

Future<List<SavedFood>> _saved(PumpedPage p) =>
    p.container.read(savedFoodsRepositoryProvider).watchAll(kDiaryUid).first;

int _writes(PumpedPage p) =>
    (p.container.read(diaryRepositoryProvider) as InMemoryDiaryRepository).writes;

void main() {
  group('picking the photo', () {
    testWidgets('cancelled pick keeps the pick buttons and calls nothing',
        (tester) async {
      final port = FakeCaptureImagePort(null);
      final api = _Api();
      await _pump(tester, api, port);
      await tester.tap(find.byKey(const Key('label.take')));
      await settle(tester);
      expect(port.picks, 1);
      expect(port.lastSource, CaptureSource.camera);
      expect(find.byKey(const Key('label.preview')), findsNothing);
      expect(find.byKey(const Key('label.take')), findsOneWidget);
      expect(api.labelCalls, 0);
    });

    testWidgets('the gallery button uses the gallery', (tester) async {
      final port = FakeCaptureImagePort(null);
      await _pump(tester, _Api(), port);
      await tester.tap(find.byKey(const Key('label.pick')));
      await settle(tester);
      expect(port.lastSource, CaptureSource.gallery);
    });

    testWidgets('bytes that are not an image -> calm message, no call',
        (tester) async {
      final port = FakeCaptureImagePort(Uint8List.fromList([1, 2, 3, 4]));
      final api = _Api();
      await _pump(tester, api, port);
      await tester.tap(find.byKey(const Key('label.pick')));
      await _until(tester, find.byKey(const Key('label.msg')));
      expect(find.text(l10nOf(tester).foodMealImageInvalid), findsOneWidget);
      expect(find.byKey(const Key('label.read')), findsNothing);
      expect(api.labelCalls, 0);
    });

    testWidgets('Choose another photo returns to the pick buttons',
        (tester) async {
      final port = FakeCaptureImagePort(_png(300, 200));
      await _pump(tester, _Api(), port);
      await tester.tap(find.byKey(const Key('label.pick')));
      await _until(tester, find.byKey(const Key('label.preview')));
      await tester.tap(find.byKey(const Key('label.change')));
      await settle(tester);
      expect(find.byKey(const Key('label.preview')), findsNothing);
      expect(find.byKey(const Key('label.pick')), findsOneWidget);
    });
  });

  group('what is sent', () {
    testWidgets('a resized JPEG (long edge 1280) with its mime and language',
        (tester) async {
      final port = FakeCaptureImagePort(_png(2400, 1200));
      final api = _Api(label: const LabelReading(per100g: _per100));
      await _pump(tester, api, port);
      await _pickAndRead(tester);
      expect(api.labelCalls, 1);
      expect(api.sentMime, 'image/jpeg');
      expect(api.sentLanguage, 'en');
      final sent = base64Decode(api.sentBase64!);
      expect(sent[0], 0xFF);
      expect(sent[1], 0xD8);
      final d = img.decodeJpg(sent)!;
      expect(d.width, 1280);
      expect(d.height, 640);
    });

    testWidgets('Russian UI sends languageCode ru', (tester) async {
      final api = _Api(label: const LabelReading(per100g: _per100));
      await _pump(tester, api, FakeCaptureImagePort(_png(300, 200)),
          locale: const Locale('ru'));
      await _pickAndRead(tester);
      expect(api.sentLanguage, 'ru');
    });
  });

  group('the confirmation sheet is always shown', () {
    testWidgets('per-100 g reading: values prefilled, name empty, no conversion note',
        (tester) async {
      final p = await _pump(tester, _Api(label: const LabelReading(per100g: _per100)),
          FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      expect(find.text(l10nOf(tester).foodLabelConfirmTitle), findsOneWidget);
      expect(_text(tester, 'kcal'), '500');
      expect(_text(tester, 'protein'), '12.5');
      expect(_text(tester, 'carbs'), '75');
      expect(_text(tester, 'fat'), '15');
      expect(_text(tester, 'name'), '');
      expect(find.byKey(const Key('labelSheet.converted')), findsNothing);
      expect(find.byKey(const Key('labelSheet.unreadable')), findsNothing);
      expect(await _saved(p), isEmpty, reason: 'nothing saved before Confirm');
    });

    testWidgets('per-serving + serving weight: converted values and a note',
        (tester) async {
      final api = _Api(
          label: const LabelReading(
              perServing: Per100g(kcal: 200, proteinG: 5, carbsG: 30, fatG: 6),
              servingG: 40));
      await _pump(tester, api, FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      expect(_text(tester, 'kcal'), '500'); // 200 x 100 / 40
      expect(_text(tester, 'protein'), '12.5');
      expect(_text(tester, 'carbs'), '75');
      expect(_text(tester, 'fat'), '15');
      expect(_text(tester, 'serving'), '40');
      expect(find.byKey(const Key('labelSheet.converted')), findsOneWidget);
    });

    testWidgets('per-serving without a usable serving weight is NOT guessed',
        (tester) async {
      final api = _Api(
          label: const LabelReading(
              perServing: Per100g(kcal: 200, proteinG: 5, carbsG: 30, fatG: 6)));
      await _pump(tester, api, FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      expect(find.byKey(const Key('labelSheet.unreadable')), findsOneWidget);
      expect(_text(tester, 'kcal'), '');
      expect(find.byKey(const Key('labelSheet.converted')), findsNothing);
    });

    testWidgets('nothing readable: the sheet still opens, empty, with a note',
        (tester) async {
      await _pump(tester, _Api(label: const LabelReading()),
          FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      expect(find.byKey(const Key('labelSheet.confirm')), findsOneWidget);
      expect(find.byKey(const Key('labelSheet.unreadable')), findsOneWidget);
      expect(find.text(l10nOf(tester).foodLabelNothing), findsOneWidget);
      expect(_text(tester, 'kcal'), '');
    });

    testWidgets('labelAmbiguous shows the check text', (tester) async {
      final api = _Api(
          label: const LabelReading(
              per100g: _per100, checkCodes: [CheckCode.labelAmbiguous]));
      await _pump(tester, api, FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      expect(find.byKey(const Key('labelSheet.ambiguous')), findsOneWidget);
    });
  });

  group('Confirm', () {
    testWidgets('writes the EDITED values as a saved food, then logs only on Save',
        (tester) async {
      final p = await _pump(
          tester,
          _Api(label: const LabelReading(per100g: _per100, servingG: 40)),
          FakeCaptureImagePort(_png(300, 200)),
          day: '2026-10-14',
          slot: MealSlot.dinner);
      await _pickAndRead(tester);
      await _fill(tester, {'name': 'Oat bar', 'kcal': '410,5'});
      await tester.tap(find.byKey(const Key('labelSheet.confirm')));
      await settle(tester);

      final saved = await _saved(p);
      expect(saved, hasLength(1));
      expect(saved.single.name, 'Oat bar');
      expect(saved.single.per100g.kcal, 410.5, reason: 'the edit, not the reading');
      expect(saved.single.per100g.proteinG, 12.5);
      expect(saved.single.servingG, 40);

      // The detail sheet is open; nothing is in the diary yet.
      expect(find.byKey(const Key('detail.save')), findsOneWidget);
      expect(_writes(p), 0);

      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);
      final entries =
          await p.container.read(diaryRepositoryProvider).watchDay(kDiaryUid, '2026-10-14').first;
      expect(entries, hasLength(1));
      final e = entries.single;
      expect(e.source, EntrySource.label);
      expect(e.slot, MealSlot.dinner);
      expect(e.confidence, EntryConfidence.medium);
      expect(e.items.single.source, FoodSource.label);
      expect(e.items.single.grams.mid, 40);
      expect(e.items.single.per100g.kcal, 410.5);
      expect(e.checkThese.map((c) => c.code), isNot(contains(CheckCode.scaleMissing)));
      expect(p.stubUri, '/nutrition/diary');
    });

    testWidgets('no serving typed -> 100 g portion and a scaleMissing chip',
        (tester) async {
      final p = await _pump(
          tester,
          _Api(label: const LabelReading(per100g: _per100)),
          FakeCaptureImagePort(_png(300, 200)),
          day: kToday,
          slot: MealSlot.snack);
      await _pickAndRead(tester);
      await _fill(tester, {'name': 'Bar'});
      await tester.tap(find.byKey(const Key('labelSheet.confirm')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);
      final e = (await p.container.read(diaryRepositoryProvider).watchDay(kDiaryUid, kToday).first).single;
      expect(e.items.single.grams.mid, 100);
      expect(e.checkThese.map((c) => c.code), contains(CheckCode.scaleMissing));
    });

    testWidgets('numbers that break kcal vs 4P+4C+9F get dataInconsistent',
        (tester) async {
      final p = await _pump(
          tester,
          _Api(label: const LabelReading(per100g: _per100, servingG: 30)),
          FakeCaptureImagePort(_png(300, 200)),
          day: kToday,
          slot: MealSlot.snack);
      await _pickAndRead(tester);
      // 4*10 + 4*10 + 9*1 = 89 vs 400 kcal.
      await _fill(tester, {
        'name': 'Odd',
        'kcal': '400',
        'protein': '10',
        'carbs': '10',
        'fat': '1'
      });
      await tester.tap(find.byKey(const Key('labelSheet.confirm')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);
      final e = (await p.container.read(diaryRepositoryProvider).watchDay(kDiaryUid, kToday).first).single;
      expect(e.checkThese.map((c) => c.code), contains(CheckCode.dataInconsistent));
    });

    testWidgets('invalid input keeps the sheet open and saves nothing',
        (tester) async {
      final p = await _pump(tester, _Api(label: const LabelReading(per100g: _per100)),
          FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      // Name missing.
      await tester.tap(find.byKey(const Key('labelSheet.confirm')));
      await settle(tester);
      expect(find.byKey(const Key('labelSheet.invalid')), findsOneWidget);
      expect(find.text(l10nOf(tester).foodLabelInvalid), findsOneWidget);
      // Value out of range.
      await _fill(tester, {'name': 'X', 'kcal': '1001'});
      await tester.tap(find.byKey(const Key('labelSheet.confirm')));
      await settle(tester);
      expect(find.byKey(const Key('labelSheet.confirm')), findsOneWidget);
      expect(await _saved(p), isEmpty);
      expect(_writes(p), 0);
    });

    testWidgets('the unreadable sheet cannot be confirmed empty', (tester) async {
      final p = await _pump(tester, _Api(label: const LabelReading()),
          FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      await _fill(tester, {'name': 'Mystery'});
      await tester.tap(find.byKey(const Key('labelSheet.confirm')));
      await settle(tester);
      expect(find.byKey(const Key('labelSheet.invalid')), findsOneWidget);
      expect(await _saved(p), isEmpty);
    });

    testWidgets('values typed by hand after an unreadable label can be saved',
        (tester) async {
      final p = await _pump(tester, _Api(label: const LabelReading()),
          FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      await _fill(tester,
          {'name': 'Гречка', 'kcal': '343', 'protein': '13', 'carbs': '62', 'fat': '3.4'});
      await tester.tap(find.byKey(const Key('labelSheet.confirm')));
      await settle(tester);
      final saved = await _saved(p);
      expect(saved.single.name, 'Гречка');
      expect(saved.single.per100g.kcal, 343);
    });
  });

  group('Cancel and dismiss write nothing', () {
    testWidgets('Cancel button', (tester) async {
      final api = _Api(label: const LabelReading(per100g: _per100));
      final p = await _pump(tester, api, FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      await _fill(tester, {'name': 'Typed but cancelled'});
      await tester.tap(find.byKey(const Key('labelSheet.cancel')));
      await settle(tester);
      expect(find.byKey(const Key('labelSheet.confirm')), findsNothing);
      expect(await _saved(p), isEmpty);
      expect(_writes(p), 0);
      expect(p.stubUri, isNull);
      expect(find.byKey(const Key('label.read')), findsOneWidget,
          reason: 'back on the page, can read again');
    });

    testWidgets('dismissing by tapping outside', (tester) async {
      final p = await _pump(tester, _Api(label: const LabelReading(per100g: _per100)),
          FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(await _saved(p), isEmpty);
      expect(_writes(p), 0);
    });

    testWidgets('closing the detail sheet after Confirm logs no entry',
        (tester) async {
      final p = await _pump(tester, _Api(label: const LabelReading(per100g: _per100)),
          FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      await _fill(tester, {'name': 'Bar'});
      await tester.tap(find.byKey(const Key('labelSheet.confirm')));
      await settle(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(_writes(p), 0);
      expect(p.stubUri, isNull);
    });
  });

  group('data notice (D-79) comes before the first food-AI call', () {
    testWidgets('unacknowledged: the notice shows, no call until accepted',
        (tester) async {
      final api = _Api(label: const LabelReading(per100g: _per100));
      await _pump(tester, api, FakeCaptureImagePort(_png(300, 200)),
          noticeAcknowledged: false);
      await tester.tap(find.byKey(const Key('label.pick')));
      await _until(tester, find.byKey(const Key('label.preview')));
      await tester.tap(find.byKey(const Key('label.read')));
      await settle(tester);
      expect(find.text(l10nOf(tester).dataNoticeTitle), findsOneWidget);
      expect(api.labelCalls, 0);

      await tester.tap(find.text(l10nOf(tester).dataNoticeAcknowledge));
      await settle(tester);
      expect(api.labelCalls, 1);
      expect(find.byKey(const Key('labelSheet.confirm')), findsOneWidget);
    });

    testWidgets('dismissing the notice means no call at all', (tester) async {
      final api = _Api(label: const LabelReading(per100g: _per100));
      await _pump(tester, api, FakeCaptureImagePort(_png(300, 200)),
          noticeAcknowledged: false);
      await tester.tap(find.byKey(const Key('label.pick')));
      await _until(tester, find.byKey(const Key('label.preview')));
      await tester.tap(find.byKey(const Key('label.read')));
      await settle(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(api.labelCalls, 0);
      expect(find.byKey(const Key('labelSheet.confirm')), findsNothing);
    });
  });

  group('failures', () {
    testWidgets('feature disabled: calm not-available text, Read is disabled',
        (tester) async {
      final api = _Api(failure: FoodApiFailure.featureDisabled);
      await _pump(tester, api, FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      expect(find.byKey(const Key('label.off')), findsOneWidget);
      expect(find.text(l10nOf(tester).foodDiaryNotAvailableYet), findsOneWidget);
      final read = tester.widget<FilledButton>(find.byKey(const Key('label.read')));
      expect(read.onPressed, isNull);
      expect(find.byKey(const Key('labelSheet.confirm')), findsNothing);
    });

    testWidgets('rate limited', (tester) async {
      await _pump(tester, _Api(failure: FoodApiFailure.rateLimited),
          FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      expect(find.text(l10nOf(tester).foodScanRateLimited), findsOneWidget);
    });

    testWidgets('unknown failure: generic sentence and Read can be retried',
        (tester) async {
      final api = _Api(failure: FoodApiFailure.unknown);
      await _pump(tester, api, FakeCaptureImagePort(_png(300, 200)));
      await _pickAndRead(tester);
      expect(find.text(l10nOf(tester).foodLabelFailed), findsOneWidget);
      api.failure = null;
      api.label = const LabelReading(per100g: _per100);
      await tester.tap(find.byKey(const Key('label.read')));
      await settle(tester);
      expect(api.labelCalls, 2);
      expect(find.byKey(const Key('labelSheet.confirm')), findsOneWidget);
    });
  });

  testWidgets('Russian: confirmation sheet text is localised', (tester) async {
    await _pump(tester, _Api(label: const LabelReading(per100g: _per100)),
        FakeCaptureImagePort(_png(300, 200)),
        locale: const Locale('ru'));
    await _pickAndRead(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.foodLabelConfirmTitle), findsOneWidget);
    expect(l10n.foodLabelConfirmTitle, isNot('Check the label values'));
  });
}
