// PlanExplainerPage (design s15, s18, PLAN-17 "how your plan adapts" page):
// weekly rules, the three ownership modes, safety limits; no promises.
import 'package:fitness_app/features/nutrition_plan/plan_explainer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_widget_host.dart';

void main() {
  Future<void> pump(WidgetTester tester,
      {Locale locale = const Locale('en'), double scale = 1.0}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        planApp(const PlanExplainerPage(), locale: locale, textScale: scale));
    await tester.pump();
  }

  List<String> texts(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? ''
      ];

  testWidgets('EN: three sections with their headings and lines',
      (tester) async {
    await pump(tester);
    final t = texts(tester);
    for (final s in [
      'How your plan adapts',
      'Each week',
      'Who decides',
      'Safety limits',
      'Once a week the app compares your weight trend with what the plan expects.',
      'Every review explains why it did or did not change anything.',
      'Your calorie range always stays inside limits worked out from your own data, in every mode.',
      'Automatic changes are small and have a total limit.',
      'The steps goal is raised before calories, because it is the gentler change.',
    ]) {
      expect(t, contains(s));
    }
  });

  testWidgets('the "who decides" section lists all three ownership modes',
      (tester) async {
    await pump(tester);
    final t = texts(tester);
    expect(t, contains('The app adjusts your plan weekly within safe limits and tells you. You can undo a change for 7 days.'));
    expect(t, contains('The app suggests changes and you choose whether to accept them.'));
    expect(t, contains('You set the numbers. The app only shows insights and never changes your plan.'));
  });

  testWidgets('the weekly rule mentions the cooldown and consecutive reviews',
      (tester) async {
    await pump(tester);
    final rule = texts(tester).firstWhere((s) => s.startsWith('A change needs'));
    expect(rule, contains('two reviews in a row'));
    expect(rule, contains('2 weeks'));
  });

  testWidgets('no promise of dates or results', (tester) async {
    await pump(tester);
    for (final s in texts(tester)) {
      final l = s.toLowerCase();
      for (final w in ['guarantee', 'will lose', 'you will reach', 'by december']) {
        expect(l.contains(w), isFalse, reason: '$w in: $s');
      }
      expect(RegExp(r'(^|\W)eta(\W|$)').hasMatch(l), isFalse, reason: s);
    }
  });

  testWidgets('200% text scale does not overflow', (tester) async {
    await pump(tester, scale: 2.0, locale: const Locale('ru'));
    expect(tester.takeException(), isNull);
    await pump(tester, scale: 2.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RU: title, headings and mode lines', (tester) async {
    await pump(tester, locale: const Locale('ru'));
    final t = texts(tester);
    expect(t, contains('Как адаптируется план'));
    expect(t, contains('Каждую неделю'));
    expect(t, contains('Кто решает'));
    expect(t, contains('Безопасные пределы'));
    expect(t, contains('Приложение предлагает изменения, а вы решаете, принимать ли их.'));
  });
}
