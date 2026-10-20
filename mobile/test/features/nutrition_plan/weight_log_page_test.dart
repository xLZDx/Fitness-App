// T128 weight_log_page (PLAN-25, PRIV-23, D-72, D-79): add / edit / delete a
// weigh-in, the first-review expectation, the data-notice gate before every
// write, the 30..300 kg rule. Real providers and in-memory repositories.
import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_repository.dart';
import 'package:fitness_app/features/nutrition_plan/weight_log_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_state_fixtures.dart';
import 'plan_state_harness.dart';
import 'plan_widget_host.dart';

class _Ctx {
  _Ctx(this.h, this.notice);
  final PlanHarness h;
  final InMemoryDataNoticeStore notice;
}

void main() {
  group('parseLoggedWeight (pure)', () {
    test('accepts point and comma decimals and trims', () {
      expect(parseLoggedWeight('80.5'), 80.5);
      expect(parseLoggedWeight('80,5'), 80.5);
      expect(parseLoggedWeight('  80.5 '), 80.5);
      expect(parseLoggedWeight('80'), 80.0);
    });

    test('30 and 300 are the inclusive limits', () {
      expect(parseLoggedWeight('30'), 30.0);
      expect(parseLoggedWeight('300'), 300.0);
      expect(parseLoggedWeight('29.9'), isNull);
      expect(parseLoggedWeight('29.99'), isNull);
      expect(parseLoggedWeight('300.1'), isNull);
      expect(parseLoggedWeight('300,01'), isNull);
    });

    test('garbage, empty and non-finite are rejected', () {
      for (final s in ['', ' ', 'abc', '8o', '--', 'NaN', 'Infinity', '1e999', '.']) {
        expect(parseLoggedWeight(s), isNull, reason: s);
      }
    });
  });

  Future<_Ctx> open(
    WidgetTester tester, {
    bool noticeAcknowledged = true,
    String? uid = kUid,
    List<WeightEntry> seed = const [],
    Locale locale = const Locale('en'),
  }) async {
    final notice = InMemoryDataNoticeStore(acknowledged: noticeAcknowledged);
    final h = (await tester.runAsync(() => makeHarness(
          uid: uid,
          noticeAcknowledged: noticeAcknowledged,
          extra: [dataNoticeStoreProvider.overrideWith((ref) async => notice)],
        )))!;
    addTearDown(h.dispose);
    await tester.runAsync(() async {
      for (final e in seed) {
        await h.weights.put(kUid, e);
      }
    });
    tallSurface(tester, size: const Size(800, 2000));
    await tester.pumpWidget(planApp(const WeightLogPage(),
        container: h.container, locale: locale));
    await settleAsync(tester);
    return _Ctx(h, notice);
  }

  WeightEntry entry(int daysAgo, double kg,
          {WeightSource source = WeightSource.manual}) =>
      WeightEntry(
          at: DateTime(2026, 10, 15, 8).subtract(Duration(days: daysAgo)),
          kg: kg,
          source: source);

  Future<List<WeightLogItem>> log(WidgetTester t, _Ctx c) async =>
      (await t.runAsync<List<WeightLogItem>>(() => c.h.weights.loadLog(kUid)))!;

  Future<void> addWeight(WidgetTester tester, String text) async {
    await tester.tap(find.byKey(const Key('weightLog.add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('weightLog.field')), text);
    await tester.tap(find.byKey(const Key('weightLog.save')));
    await settleAsync(tester);
    await tester.pumpAndSettle();
  }

  final noticeSheetButton = find.descendant(
      of: find.byType(BottomSheet), matching: find.byType(FilledButton));

  testWidgets('empty log: intro states the first-review expectation',
      (tester) async {
    await open(tester);
    expect(find.text('Weight log'), findsOneWidget);
    expect(find.text('No weigh-ins yet.'), findsOneWidget);
    expect(
        find.text(
            'Log your weight whenever you like. The first plan review needs about 3 weigh-ins over 2 weeks.'),
        findsOneWidget);
  });

  testWidgets('entries are listed newest first with value, date and source',
      (tester) async {
    await open(tester, seed: [
      entry(10, 81.0),
      entry(1, 79.5, source: WeightSource.scan),
      entry(5, 80.25),
    ]);
    final values = [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if ((t.data ?? '').endsWith(' kg')) t.data!
    ];
    expect(values, ['79.5 kg', '80.25 kg', '81.0 kg']);
    expect(find.text('Oct 14, 2026 - From a scan'), findsOneWidget);
    expect(find.text('Oct 10, 2026 - Added by you'), findsOneWidget);
    expect(find.text('No weigh-ins yet.'), findsNothing);
  });

  group('add', () {
    testWidgets('saves a typed weight dated today and confirms',
        (tester) async {
      final c = await open(tester);
      await addWeight(tester, '81.5');
      final items = await log(tester, c);
      expect(items.length, 1);
      expect(items.single.entry.kg, 81.5);
      expect(items.single.entry.source, WeightSource.manual);
      expect(items.single.id, '2026-10-15');
      expect(find.text('Weight saved.'), findsOneWidget);
      expect(find.text('81.5 kg'), findsOneWidget);
    });

    testWidgets('a comma decimal is accepted', (tester) async {
      final c = await open(tester);
      await addWeight(tester, '81,5');
      expect((await log(tester, c)).single.entry.kg, 81.5);
    });

    testWidgets('30 and 300 are accepted', (tester) async {
      final c = await open(tester);
      await addWeight(tester, '30');
      expect((await log(tester, c)).single.entry.kg, 30.0);
      await addWeight(tester, '300');
      // Same local day: the second write replaces the first.
      expect((await log(tester, c)).single.entry.kg, 300.0);
    });

    testWidgets('29.9 and 300.1 show the error, keep the sheet, write nothing',
        (tester) async {
      final c = await open(tester);
      for (final bad in ['29.9', '300.1', '0', '']) {
        await tester.tap(find.byKey(const Key('weightLog.add')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('weightLog.field')), bad);
        await tester.tap(find.byKey(const Key('weightLog.save')));
        await tester.pump();
        expect(find.text('Enter a weight between 30 and 300 kg.'),
            findsOneWidget,
            reason: bad);
        expect(find.byKey(const Key('weightLog.field')), findsOneWidget);
        expect(await log(tester, c), isEmpty, reason: bad);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('typing clears the error; letters are filtered out',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('weightLog.add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weightLog.field')), '5');
      await tester.tap(find.byKey(const Key('weightLog.save')));
      await tester.pump();
      expect(find.text('Enter a weight between 30 and 300 kg.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('weightLog.field')), '8x0');
      await tester.pump();
      expect(find.text('Enter a weight between 30 and 300 kg.'), findsNothing);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('weightLog.field')))
              .controller!
              .text,
          '80');
    });

    testWidgets('cancel writes nothing', (tester) async {
      final c = await open(tester);
      await tester.tap(find.byKey(const Key('weightLog.add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weightLog.field')), '80');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await log(tester, c), isEmpty);
    });

    testWidgets('signed out: "could not save", nothing written',
        (tester) async {
      final c = await open(tester, uid: null);
      await addWeight(tester, '80');
      expect(find.text('We could not save that. Check that you are signed in.'),
          findsOneWidget);
      expect(await log(tester, c), isEmpty);
    });
  });

  group('data notice gate (D-79)', () {
    testWidgets('declined notice defers the add: nothing is written',
        (tester) async {
      final c = await open(tester, noticeAcknowledged: false);
      await tester.tap(find.byKey(const Key('weightLog.add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weightLog.field')), '80');
      await tester.tap(find.byKey(const Key('weightLog.save')));
      await tester.pumpAndSettle();
      expect(noticeSheetButton, findsOneWidget, reason: 'notice sheet shown');
      expect(await log(tester, c), isEmpty);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(await log(tester, c), isEmpty);
      expect(c.notice.acknowledgeCalls, 0);
      expect(find.text('Weight saved.'), findsNothing);
    });

    testWidgets('acknowledging the notice releases the write exactly once',
        (tester) async {
      final c = await open(tester, noticeAcknowledged: false);
      await tester.tap(find.byKey(const Key('weightLog.add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weightLog.field')), '80');
      await tester.tap(find.byKey(const Key('weightLog.save')));
      await tester.pumpAndSettle();
      await tester.tap(noticeSheetButton);
      await settleAsync(tester);
      await tester.pumpAndSettle();
      expect(c.notice.acknowledgeCalls, 1);
      expect((await log(tester, c)).single.entry.kg, 80.0);
    });

    testWidgets('declined notice defers a delete', (tester) async {
      final c = await open(tester,
          noticeAcknowledged: false, seed: [entry(1, 80.0)]);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Delete')));
      await tester.pumpAndSettle();
      expect(noticeSheetButton, findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect((await log(tester, c)).length, 1);
    });
  });

  group('edit', () {
    testWidgets('prefills the value and replaces the entry', (tester) async {
      final c = await open(tester, seed: [entry(2, 80.0)]);
      await tester.tap(find.byTooltip('Edit weight'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('weightLog.field')))
              .controller!
              .text,
          '80.0');
      await tester.enterText(find.byKey(const Key('weightLog.field')), '79.2');
      await tester.tap(find.byKey(const Key('weightLog.save')));
      await settleAsync(tester);
      await tester.pumpAndSettle();
      final items = await log(tester, c);
      expect(items.length, 1, reason: 'edit replaces, never duplicates');
      expect(items.single.entry.kg, 79.2);
      expect(items.single.id, '2026-10-13');
      expect(find.text('79.2 kg'), findsOneWidget);
      expect(find.text('Weight saved.'), findsOneWidget);
    });

    testWidgets('an invalid edit keeps the old value', (tester) async {
      final c = await open(tester, seed: [entry(2, 80.0)]);
      await tester.tap(find.byTooltip('Edit weight'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weightLog.field')), '301');
      await tester.tap(find.byKey(const Key('weightLog.save')));
      await tester.pump();
      expect(find.text('Enter a weight between 30 and 300 kg.'), findsOneWidget);
      expect((await log(tester, c)).single.entry.kg, 80.0);
    });
  });

  group('delete', () {
    testWidgets('cancel in the dialog keeps the entry', (tester) async {
      final c = await open(tester, seed: [entry(2, 80.0)]);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this weigh-in?'), findsOneWidget);
      expect(find.text('It will no longer count towards your plan.'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await log(tester, c)).length, 1);
      expect(find.text('Weigh-in deleted.'), findsNothing);
    });

    testWidgets('confirm removes only that entry and confirms', (tester) async {
      final c = await open(tester, seed: [entry(2, 80.0), entry(1, 79.0)]);
      // Newest first: the first delete icon belongs to 79.0.
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Delete')));
      await settleAsync(tester);
      await tester.pumpAndSettle();
      final items = await log(tester, c);
      expect(items.map((i) => i.entry.kg), [80.0]);
      expect(find.text('Weigh-in deleted.'), findsOneWidget);
      expect(find.text('79.0 kg'), findsNothing);
    });
  });

  testWidgets('RU: texts, dates and units', (tester) async {
    await open(tester,
        seed: [entry(1, 79.5, source: WeightSource.scan)],
        locale: const Locale('ru'));
    expect(find.text('Журнал веса'), findsOneWidget);
    expect(find.text('Добавить вес'), findsOneWidget);
    expect(find.text('79,5 кг'), findsOneWidget);
    expect(
        find.textContaining('Для первой проверки плана нужно примерно 3 записи за 2 недели'),
        findsOneWidget);
    expect(find.textContaining('Из сканирования'), findsOneWidget);
  });
}
