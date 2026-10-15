// PlanSourcesPage (design s17.9, FOOD-29 attribution, I18N-05): formulas, food
// data attribution, limits; estimates labelled as estimates; no medical claims.
import 'package:fitness_app/features/nutrition_plan/plan_sources_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_widget_host.dart';

void main() {
  Future<void> pump(WidgetTester tester,
      {Locale locale = const Locale('en'), double scale = 1.0}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        planApp(const PlanSourcesPage(), locale: locale, textScale: scale));
    await tester.pump();
  }

  List<String> texts(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? ''
      ];

  Future<List<String>> scrollAll(WidgetTester tester) async {
    // The list is lazy on a small screen: walk it and collect every text.
    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      seen.addAll(texts(tester));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
    }
    return seen.toList();
  }

  testWidgets('EN: title, intro and the three section headings',
      (tester) async {
    await pump(tester);
    expect(find.text('Data sources and limits'), findsOneWidget);
    expect(find.text('Where your numbers come from, and what they cannot tell you.'),
        findsOneWidget);
    expect(find.text('Formulas'), findsOneWidget);
    final all = await scrollAll(tester);
    expect(all, contains('Food data'));
    expect(all, contains('Limits'));
  });

  testWidgets('EN: formulas and licences are cited by name', (tester) async {
    await pump(tester);
    final joined = (await scrollAll(tester)).join('\n');
    expect(joined, contains('Mifflin-St Jeor'));
    expect(joined, contains('Jäger 2017'));
    expect(joined, contains('7,700'));
    expect(joined, contains('USDA FoodData Central'));
    expect(joined, contains('CC0 1.0'));
    expect(joined, contains('Open Food Facts'));
    expect(joined, contains('Open Database License'));
  });

  testWidgets('EN: limits say estimates and no medical advice', (tester) async {
    await pump(tester);
    final all = await scrollAll(tester);
    expect(
        all,
        contains(
            'All figures are estimates. Real needs vary from person to person and from week to week.'));
    expect(
        all,
        contains(
            'This app does not give medical advice. If you have a health condition, ask a doctor or dietitian.'));
    expect(all.any((s) => s.contains('likely range, not an exact measurement')),
        isTrue);
  });

  testWidgets('section headings are semantics headers', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    final node = tester.getSemantics(find.text('Formulas'));
    // ignore: deprecated_member_use
    expect(node.hasFlag(SemanticsFlag.isHeader), isTrue);
    handle.dispose();
  });

  testWidgets('200% text scale does not overflow (EN and RU)', (tester) async {
    for (final l in const [Locale('en'), Locale('ru')]) {
      await pump(tester, locale: l, scale: 2.0);
      await scrollAll(tester);
      expect(tester.takeException(), isNull, reason: '$l');
    }
  });

  testWidgets('RU: Russian title, headings and citations', (tester) async {
    await pump(tester, locale: const Locale('ru'));
    expect(find.text('Источники данных и ограничения'), findsOneWidget);
    expect(find.text('Формулы'), findsOneWidget);
    final joined = (await scrollAll(tester)).join('\n');
    expect(joined, contains('Данные о продуктах'));
    expect(joined, contains('USDA FoodData Central'));
    expect(joined, contains('Open Food Facts'));
    expect(joined, contains('Ограничения'));
  });
}
