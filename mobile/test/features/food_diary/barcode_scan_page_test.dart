// C24 barcode_scan_page_test (FOOD-26, FOOD-12 client half, N-32): the port
// fake emits decoded values; only GtinValidator-valid values (EAN-8, UPC-A,
// EAN-13, ITF-14) reach lookupBarcode, duplicate scans are debounced, not
// found offers the label scan, nothing is logged before Save.
import 'dart:async';

import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/food_diary/barcode_scan_page.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/data/food_source.dart';
import 'package:fitness_app/features/food_diary/state/barcode_port.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'food_diary_fixtures.dart';
import 'food_diary_harness.dart';

const String kEan13 = '3017620422003';
const String kEan8 = '96385074';
const String kUpcA = '036000291452';
const String kItf14 = '10012345678902';

/// Records every barcode and can hold the answer until [release].
class _Api extends FakeFoodApi {
  _Api({super.barcode, super.failure});
  final List<String> codes = [];
  Completer<void>? gate;

  @override
  Future<BarcodeLookup> lookupBarcode(String barcodeValue) async {
    codes.add(barcodeValue);
    final g = gate;
    if (g != null) await g.future;
    return super.lookupBarcode(barcodeValue);
  }
}

FoodCandidate _candidate({double? servingG, bool complete = true}) => FoodCandidate(
      foodRef: 'off:$kEan13',
      name: 'Hazelnut spread',
      per100g: const Per100g(kcal: 539, proteinG: 6.3, carbsG: 57.5, fatG: 30.9),
      source: FoodSource.off,
      servingG: servingG,
      complete: complete,
    );

Future<PumpedPage> _pump(
  WidgetTester tester,
  FakeBarcodePort port,
  _Api api, {
  String? day,
  MealSlot? slot,
  Locale locale = const Locale('en'),
}) =>
    pumpPage(
      tester,
      BarcodeScanPage(day: day, slot: slot),
      locale: locale,
      overrides: diaryOverrides(extra: [
        barcodePortFactoryProvider.overrideWithValue(() => port),
        foodApiProvider.overrideWithValue(api),
        dataNoticeStoreProvider
            .overrideWith((ref) async => InMemoryDataNoticeStore(acknowledged: true)),
      ]),
    );

Future<List<FoodEntry>> _entries(PumpedPage p, String day) =>
    p.container.read(diaryRepositoryProvider).watchDay(kDiaryUid, day).first;

Future<void> _emit(WidgetTester tester, FakeBarcodePort port, String v) async {
  port.emit(v);
  await settle(tester);
}

void main() {
  group('FakeBarcodePort (the double the page tests rely on)', () {
    test('emit reaches every listener of codes', () async {
      final port = FakeBarcodePort();
      final got = <String>[];
      port.codes.listen(got.add);
      port.emit('a');
      port.emit('b');
      await Future<void>.delayed(Duration.zero);
      expect(got, ['a', 'b']);
    });

    test('counters and dispose', () async {
      final port = FakeBarcodePort();
      await port.pause();
      await port.resume();
      await port.resume();
      await port.toggleTorch();
      await port.dispose();
      expect([port.pauses, port.resumes, port.torchToggles, port.disposed],
          [1, 2, 1, true]);
    });
  });

  group('valid values are looked up', () {
    for (final entry in {
      'EAN-13': kEan13,
      'EAN-8': kEan8,
      'UPC-A': kUpcA,
      'ITF-14': kItf14,
    }.entries) {
      testWidgets('${entry.key} ${entry.value} calls lookupBarcode once with it',
          (tester) async {
        final port = FakeBarcodePort();
        final api = _Api(barcode: _candidate());
        await _pump(tester, port, api);
        await _emit(tester, port, entry.value);
        expect(api.codes, [entry.value]);
        expect(find.byKey(const Key('detail.save')), findsOneWidget,
            reason: 'the confirm sheet opens for a found product');
      });
    }

    testWidgets('surrounding whitespace is trimmed, digits are kept as scanned',
        (tester) async {
      final port = FakeBarcodePort();
      final api = _Api(barcode: _candidate());
      await _pump(tester, port, api);
      await _emit(tester, port, '  $kEan13\n');
      expect(api.codes, [kEan13]);
    });

    testWidgets('the preview is shown and the scan is paused during the lookup',
        (tester) async {
      final port = FakeBarcodePort();
      final api = _Api(barcode: _candidate())..gate = Completer<void>();
      await _pump(tester, port, api);
      expect(find.byKey(const Key('fake.preview')), findsOneWidget);
      await _emit(tester, port, kEan13);
      expect(port.pauses, 1);
      expect(find.byKey(const Key('barcode.looking')), findsOneWidget);
      api.gate!.complete();
      await settle(tester);
      expect(find.byKey(const Key('barcode.looking')), findsNothing);
    });
  });

  group('invalid values never reach the server (N-32)', () {
    final bad = {
      'wrong check digit EAN-13': '3017620422004',
      'wrong check digit EAN-8': '96385075',
      'length 10': '1234567890',
      'length 11': '12345678901',
      'length 15': '301762042200312',
      'letters': '30176204220A3',
      'empty-ish': ' ',
      'QR-like text': 'https://example.com/x',
    };
    for (final e in bad.entries) {
      testWidgets('${e.key}: no call, inline error', (tester) async {
        final port = FakeBarcodePort();
        final api = _Api(barcode: _candidate());
        await _pump(tester, port, api);
        await _emit(tester, port, e.value);
        expect(api.codes, isEmpty);
        expect(api.barcodeCalls, 0);
        expect(find.byKey(const Key('barcode.invalid')), findsOneWidget);
        expect(find.text(l10nOf(tester).foodBarcodeInvalid), findsOneWidget);
        expect(find.byKey(const Key('detail.save')), findsNothing);
      });
    }

    testWidgets('a valid scan after an invalid one still works and clears the error',
        (tester) async {
      final port = FakeBarcodePort();
      final api = _Api(barcode: _candidate());
      await _pump(tester, port, api);
      await _emit(tester, port, '3017620422004');
      expect(find.byKey(const Key('barcode.invalid')), findsOneWidget);
      await _emit(tester, port, kEan13);
      expect(api.codes, [kEan13]);
      expect(find.byKey(const Key('barcode.invalid')), findsNothing);
    });
  });

  group('duplicate scans are debounced', () {
    testWidgets('the same code three times during one lookup -> one call',
        (tester) async {
      final port = FakeBarcodePort();
      final api = _Api(barcode: _candidate())..gate = Completer<void>();
      await _pump(tester, port, api);
      port.emit(kEan13);
      port.emit(kEan13);
      port.emit(kEan13);
      await settle(tester);
      expect(api.codes, [kEan13]);
      api.gate!.complete();
      await settle(tester);
      expect(api.barcodeCalls, 1);
    });

    testWidgets('a different valid code during a lookup is ignored too',
        (tester) async {
      final port = FakeBarcodePort();
      final api = _Api(barcode: _candidate())..gate = Completer<void>();
      await _pump(tester, port, api);
      port.emit(kEan13);
      await settle(tester);
      port.emit(kEan8);
      await settle(tester);
      expect(api.codes, [kEan13]);
      api.gate!.complete();
      await settle(tester);
    });

    testWidgets('after not found, further scans are ignored until Scan again',
        (tester) async {
      final port = FakeBarcodePort();
      final api = _Api(); // not found
      await _pump(tester, port, api);
      await _emit(tester, port, kEan13);
      expect(find.byKey(const Key('barcode.notFound')), findsOneWidget);
      await _emit(tester, port, kEan13);
      expect(api.barcodeCalls, 1, reason: 'no hammering of the not-found code');

      await tester.tap(find.byKey(const Key('barcode.again')));
      await settle(tester);
      expect(port.resumes, 1);
      expect(find.byKey(const Key('barcode.notFound')), findsNothing);
      await _emit(tester, port, kEan13);
      expect(api.barcodeCalls, 2);
    });
  });

  group('not found', () {
    testWidgets('offers the label scan and quick log, keeps day and slot',
        (tester) async {
      final port = FakeBarcodePort();
      final p = await _pump(tester, port, _Api(),
          day: '2026-10-14', slot: MealSlot.dinner);
      await _emit(tester, port, kEan13);
      final l10n = l10nOf(tester);
      expect(find.text(l10n.foodBarcodeNotFound), findsOneWidget);
      expect(find.byKey(const Key('barcode.toLabel')), findsOneWidget);
      expect(find.byKey(const Key('barcode.toQuick')), findsOneWidget);

      await tester.tap(find.byKey(const Key('barcode.toLabel')));
      await settle(tester);
      expect(p.stubUri, '/nutrition/add/label?day=2026-10-14&slot=dinner');
    });

    testWidgets('quick log button goes to /nutrition/add with day and slot',
        (tester) async {
      final port = FakeBarcodePort();
      final p = await _pump(tester, port, _Api(), slot: MealSlot.breakfast);
      await _emit(tester, port, kEan13);
      await tester.tap(find.byKey(const Key('barcode.toQuick')));
      await settle(tester);
      expect(p.stubUri, '/nutrition/add?day=&slot=breakfast');
    });

    testWidgets('nothing is written for a not-found product', (tester) async {
      final port = FakeBarcodePort();
      final p = await _pump(tester, port, _Api());
      await _emit(tester, port, kEan13);
      expect(
          (p.container.read(diaryRepositoryProvider) as InMemoryDiaryRepository)
              .writes,
          0);
      expect(
          (await p.container.read(savedFoodsRepositoryProvider).watchAll(kDiaryUid).first),
          isEmpty);
    });
  });

  group('found product: confirm, then Save', () {
    testWidgets('nothing is logged until Save', (tester) async {
      final port = FakeBarcodePort();
      final p = await _pump(tester, port, _Api(barcode: _candidate()));
      await _emit(tester, port, kEan13);
      expect(find.byKey(const Key('detail.save')), findsOneWidget);
      expect(
          (p.container.read(diaryRepositoryProvider) as InMemoryDiaryRepository)
              .writes,
          0);
    });

    testWidgets('Save writes a barcode entry with the serving size and goes to the diary',
        (tester) async {
      final port = FakeBarcodePort();
      final p = await _pump(tester, port, _Api(barcode: _candidate(servingG: 30)),
          day: '2026-10-14', slot: MealSlot.dinner);
      await _emit(tester, port, kEan13);
      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);

      final entries = await _entries(p, '2026-10-14');
      expect(entries, hasLength(1));
      final e = entries.single;
      expect(e.source, EntrySource.barcode);
      expect(e.slot, MealSlot.dinner);
      expect(e.confidence, EntryConfidence.high);
      expect(e.items.single.foodRef, 'off:$kEan13');
      expect(e.items.single.grams.mid, 30);
      expect(e.items.single.source, FoodSource.off);
      expect(p.stubUri, '/nutrition/diary');
    });

    testWidgets('no serving size -> a 100 g portion', (tester) async {
      final port = FakeBarcodePort();
      final p = await _pump(tester, port, _Api(barcode: _candidate()),
          day: kToday, slot: MealSlot.snack);
      await _emit(tester, port, kEan13);
      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);
      expect((await _entries(p, kToday)).single.items.single.grams.mid, 100);
    });

    testWidgets('a partial source record is saved with medium confidence',
        (tester) async {
      final port = FakeBarcodePort();
      final p = await _pump(
          tester, port, _Api(barcode: _candidate(complete: false)),
          day: kToday, slot: MealSlot.snack);
      await _emit(tester, port, kEan13);
      await tester.tap(find.byKey(const Key('detail.save')));
      await settle(tester);
      expect((await _entries(p, kToday)).single.confidence, EntryConfidence.medium);
    });

    testWidgets('dismissing the sheet logs nothing and resumes scanning',
        (tester) async {
      final port = FakeBarcodePort();
      final p = await _pump(tester, port, _Api(barcode: _candidate()));
      await _emit(tester, port, kEan13);
      await tester.tapAt(const Offset(5, 5)); // the modal barrier
      await settle(tester);
      expect(find.byKey(const Key('detail.save')), findsNothing);
      expect(port.resumes, 1);
      expect(
          (p.container.read(diaryRepositoryProvider) as InMemoryDiaryRepository)
              .writes,
          0);
      expect(p.stubUri, isNull, reason: 'still on the barcode page');
    });
  });

  group('failures use closed, calm messages', () {
    testWidgets('rate limited', (tester) async {
      final port = FakeBarcodePort();
      await _pump(tester, port, _Api(failure: FoodApiFailure.rateLimited));
      await _emit(tester, port, kEan13);
      expect(find.byKey(const Key('barcode.failed')), findsOneWidget);
      expect(find.text(l10nOf(tester).foodScanRateLimited), findsOneWidget);
    });

    testWidgets('feature disabled shows the calm not-available text',
        (tester) async {
      final port = FakeBarcodePort();
      await _pump(tester, port, _Api(failure: FoodApiFailure.featureDisabled));
      await _emit(tester, port, kEan13);
      expect(find.text(l10nOf(tester).foodDiaryNotAvailableYet), findsOneWidget);
    });

    testWidgets('unknown failure -> the generic lookup sentence, retry offered',
        (tester) async {
      final port = FakeBarcodePort();
      final api = _Api(failure: FoodApiFailure.unknown);
      await _pump(tester, port, api);
      await _emit(tester, port, kEan13);
      expect(find.text(l10nOf(tester).foodBarcodeFailed), findsOneWidget);
      expect(find.byKey(const Key('barcode.again')), findsOneWidget);

      api.failure = null;
      api.barcode = _candidate();
      await tester.tap(find.byKey(const Key('barcode.again')));
      await settle(tester);
      await _emit(tester, port, kEan13);
      expect(api.barcodeCalls, 2);
      expect(find.byKey(const Key('detail.save')), findsOneWidget);
    });

    testWidgets('not signed in -> sign-in text', (tester) async {
      final port = FakeBarcodePort();
      await _pump(tester, port, _Api(failure: FoodApiFailure.notAllowed));
      await _emit(tester, port, kEan13);
      expect(find.text(l10nOf(tester).foodScanNotAllowed), findsOneWidget);
    });
  });

  group('typed barcode and camera problems', () {
    testWidgets('typed invalid barcode: error, no call', (tester) async {
      final port = FakeBarcodePort();
      final api = _Api(barcode: _candidate());
      await _pump(tester, port, api);
      await tester.enterText(find.byKey(const Key('barcode.manual')), '12345');
      await tester.tap(find.byKey(const Key('barcode.manualGo')));
      await settle(tester);
      expect(api.barcodeCalls, 0);
      expect(find.byKey(const Key('barcode.invalid')), findsOneWidget);
    });

    testWidgets('typed valid barcode is looked up', (tester) async {
      final port = FakeBarcodePort();
      final api = _Api(barcode: _candidate());
      await _pump(tester, port, api);
      await tester.enterText(find.byKey(const Key('barcode.manual')), kEan13);
      await tester.tap(find.byKey(const Key('barcode.manualGo')));
      await settle(tester);
      expect(api.codes, [kEan13]);
    });

    testWidgets('camera denied: calm message and typing still works',
        (tester) async {
      final port = FakeBarcodePort(failed: true);
      final api = _Api(barcode: _candidate());
      await _pump(tester, port, api);
      expect(find.byKey(const Key('barcode.cameraError')), findsOneWidget);
      expect(find.text(l10nOf(tester).foodBarcodeCameraError), findsOneWidget);
      expect(find.byKey(const Key('fake.preview')), findsNothing);
      await tester.enterText(find.byKey(const Key('barcode.manual')), kEan8);
      await tester.tap(find.byKey(const Key('barcode.manualGo')));
      await settle(tester);
      expect(api.codes, [kEan8]);
    });

    testWidgets('torch button toggles the port', (tester) async {
      final port = FakeBarcodePort();
      await _pump(tester, port, _Api());
      await tester.tap(find.byKey(const Key('barcode.torch')));
      await tester.pump();
      expect(port.torchToggles, 1);
    });

    testWidgets('leaving the page disposes the port', (tester) async {
      final port = FakeBarcodePort();
      await _pump(tester, port, _Api());
      expect(port.disposed, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(port.disposed, isTrue);
    });
  });

  testWidgets('Russian: title, hint and invalid text are localised',
      (tester) async {
    final port = FakeBarcodePort();
    await _pump(tester, port, _Api(), locale: const Locale('ru'));
    await _emit(tester, port, '3017620422004');
    final l10n = l10nOf(tester);
    expect(l10n.localeName, 'ru');
    expect(find.text(l10n.foodBarcodeTitle), findsOneWidget);
    expect(find.text(l10n.foodBarcodeInvalid), findsOneWidget);
    expect(l10n.foodBarcodeInvalid, isNot('That is not a valid product barcode.'));
  });
}
