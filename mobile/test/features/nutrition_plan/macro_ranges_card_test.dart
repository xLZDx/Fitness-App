// MacroRangesCard (PLAN-17): macro RANGES (never exact targets) and the steps
// goal with +/-500 steppers. EN and RU, RU plural forms of the steps value.
import 'package:fitness_app/features/nutrition_plan/widgets/macro_ranges_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_state_fixtures.dart';
import 'plan_widget_host.dart';

void main() {
  Future<List<int>> pump(
    WidgetTester tester, {
    int steps = 8500,
    Locale locale = const Locale('en'),
  }) async {
    final changes = <int>[];
    tallSurface(tester);
    await tester.pumpWidget(planApp(
      Scaffold(
        body: SingleChildScrollView(
          child: MacroRangesCard(
            plan: storedPlan(stepsGoal: steps),
            onStepsChanged: changes.add,
          ),
        ),
      ),
      locale: locale,
    ));
    await tester.pump();
    return changes;
  }

  testWidgets('shows protein, fat and carbs as g ranges taken from the plan',
      (tester) async {
    await pump(tester);
    final p = storedPlan();
    expect(find.text('Macros'), findsOneWidget);
    expect(find.text('Protein'), findsOneWidget);
    expect(find.text('Fat'), findsOneWidget);
    expect(find.text('Carbs'), findsOneWidget);
    expect(find.text('${p.protein.minG}–${p.protein.maxG} g'), findsOneWidget);
    expect(find.text('${p.fat.minG}–${p.fat.maxG} g'), findsOneWidget);
    expect(find.text('${p.carbs.minG}–${p.carbs.maxG} g'), findsOneWidget);
    // Each is a RANGE: min is strictly below max.
    expect(p.protein.minG, lessThan(p.protein.maxG));
    expect(p.fat.minG, lessThan(p.fat.maxG));
    expect(p.carbs.minG, lessThan(p.carbs.maxG));
  });

  testWidgets('protein aim line and the "ranges, not exact targets" note',
      (tester) async {
    await pump(tester);
    final p = storedPlan();
    expect(find.text('Aim for about ${p.protein.targetG} g'), findsOneWidget);
    expect(
        find.text(
            'These are ranges, not exact targets. Anywhere inside them is fine.'),
        findsOneWidget);
  });

  testWidgets('steps goal shows the value and the steppers move it by 500',
      (tester) async {
    final changes = await pump(tester);
    expect(find.text('8500 steps'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Lower the steps goal by 500'));
    await tester.pump();
    expect(changes, [8000]);
    await tester.tap(find.bySemanticsLabel('Raise the steps goal by 500'));
    await tester.pump();
    expect(changes, [8000, 9000]);
  });

  testWidgets('stepper buttons are at least 48 dp', (tester) async {
    await pump(tester);
    for (final icon in [Icons.remove, Icons.add]) {
      final size = tester.getSize(find.ancestor(
          of: find.byIcon(icon), matching: find.byType(IconButton)));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('the card is controlled: it re-renders a new plan value',
      (tester) async {
    await pump(tester, steps: 8500);
    await pump(tester, steps: 6000);
    expect(find.text('6000 steps'), findsOneWidget);
    expect(find.text('8500 steps'), findsNothing);
  });

  group('RU', () {
    testWidgets('titles, ranges unit and stepper labels are Russian',
        (tester) async {
      await pump(tester, locale: const Locale('ru'));
      final p = storedPlan();
      expect(find.text('Макронутриенты'), findsOneWidget);
      expect(find.text('Белки'), findsOneWidget);
      expect(find.text('Жиры'), findsOneWidget);
      expect(find.text('Углеводы'), findsOneWidget);
      expect(find.text('${p.protein.minG}–${p.protein.maxG} г'), findsOneWidget);
      expect(find.bySemanticsLabel('Уменьшить цель по шагам на 500'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Увеличить цель по шагам на 500'),
          findsOneWidget);
    });

    testWidgets('steps plural: one / few / many forms', (tester) async {
      String stepsText() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((s) => RegExp(r'шаг').hasMatch(s) &&
              !s.contains('Цель') &&
              !s.contains('цель'));
      await pump(tester, steps: 2001, locale: const Locale('ru'));
      expect(stepsText().endsWith(' шаг'), isTrue, reason: stepsText());
      await pump(tester, steps: 2002, locale: const Locale('ru'));
      expect(stepsText().endsWith(' шага'), isTrue, reason: stepsText());
      await pump(tester, steps: 2005, locale: const Locale('ru'));
      expect(stepsText().endsWith(' шагов'), isTrue, reason: stepsText());
      await pump(tester, steps: 8500, locale: const Locale('ru'));
      expect(stepsText().endsWith(' шагов'), isTrue, reason: stepsText());
    });
  });
}
