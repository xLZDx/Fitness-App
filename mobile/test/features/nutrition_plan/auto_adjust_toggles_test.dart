// AutoAdjustToggles (PLAN-14, design s18): two toggles; in Manual they are shown
// off and disabled; each toggle changes only its own flag.
import 'package:fitness_app/features/nutrition_plan/data/weekly_review.dart';
import 'package:fitness_app/features/nutrition_plan/widgets/auto_adjust_toggles.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_widget_host.dart';

void main() {
  Future<List<AutoAdjust>> pump(
    WidgetTester tester, {
    AutoAdjust value = const AutoAdjust(),
    PlanOwnership ownership = PlanOwnership.coached,
    Locale locale = const Locale('en'),
  }) async {
    final changes = <AutoAdjust>[];
    tallSurface(tester);
    await tester.pumpWidget(planApp(
      Scaffold(
        body: SingleChildScrollView(
          child: AutoAdjustToggles(
              value: value, ownership: ownership, onChanged: changes.add),
        ),
      ),
      locale: locale,
    ));
    await tester.pump();
    return changes;
  }

  SwitchListTile tile(WidgetTester t, String key) =>
      t.widget<SwitchListTile>(find.byKey(Key(key)));

  testWidgets('coached: both toggles follow the stored value', (tester) async {
    await pump(tester,
        value: const AutoAdjust(steps: true, kcal: false),
        ownership: PlanOwnership.coached);
    expect(tile(tester, 'nutrition.auto.steps').value, isTrue);
    expect(tile(tester, 'nutrition.auto.kcal').value, isFalse);
    expect(tile(tester, 'nutrition.auto.steps').onChanged, isNotNull);
    expect(find.text('Turn one off to keep that part of your plan fixed.'),
        findsOneWidget);
  });

  testWidgets('toggling steps keeps kcal and vice versa', (tester) async {
    final changes = await pump(tester,
        value: const AutoAdjust(steps: true, kcal: true));
    await tester.tap(find.byKey(const Key('nutrition.auto.steps')));
    await tester.pump();
    expect(changes.last.steps, isFalse);
    expect(changes.last.kcal, isTrue);
    await tester.tap(find.byKey(const Key('nutrition.auto.kcal')));
    await tester.pump();
    expect(changes.last.steps, isTrue, reason: 'value is controlled, unchanged');
    expect(changes.last.kcal, isFalse);
    expect(changes.length, 2);
  });

  testWidgets('turning an off toggle on reports true for that flag only',
      (tester) async {
    final changes = await pump(tester,
        value: const AutoAdjust(steps: false, kcal: false));
    await tester.tap(find.byKey(const Key('nutrition.auto.kcal')));
    await tester.pump();
    expect(changes.single.kcal, isTrue);
    expect(changes.single.steps, isFalse);
  });

  testWidgets('manual: shown off and disabled even when stored on',
      (tester) async {
    final changes = await pump(tester,
        value: const AutoAdjust(steps: true, kcal: true),
        ownership: PlanOwnership.manual);
    for (final k in ['nutrition.auto.steps', 'nutrition.auto.kcal']) {
      expect(tile(tester, k).value, isFalse, reason: k);
      expect(tile(tester, k).onChanged, isNull, reason: k);
    }
    await tester.tap(find.byKey(const Key('nutrition.auto.steps')),
        warnIfMissed: false);
    await tester.pump();
    expect(changes, isEmpty);
    expect(find.text('Off while your plan is Manual.'), findsOneWidget);
  });

  testWidgets('shared: hint says suggestions', (tester) async {
    await pump(tester, ownership: PlanOwnership.shared);
    expect(find.text('In Shared mode these become suggestions you can accept.'),
        findsOneWidget);
    expect(tile(tester, 'nutrition.auto.steps').onChanged, isNotNull);
  });

  testWidgets('RU labels and hints', (tester) async {
    await pump(tester, locale: const Locale('ru'));
    expect(find.text('Автоматическая корректировка'), findsOneWidget);
    expect(find.text('Корректировать цель по шагам'), findsOneWidget);
    expect(find.text('Корректировать диапазон калорий'), findsOneWidget);
    expect(
        find.text('Выключите переключатель, чтобы эта часть плана не менялась.'),
        findsOneWidget);
    await pump(tester,
        ownership: PlanOwnership.manual, locale: const Locale('ru'));
    expect(find.text('Выключено, пока план в режиме «Вручную».'),
        findsOneWidget);
  });
}
