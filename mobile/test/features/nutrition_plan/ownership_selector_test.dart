// OwnershipSelector (PLAN-14 UI, design s18): Coached / Shared / Manual radio
// rows with one-line explanations; choosing the current one is a no-op.
import 'package:fitness_app/features/nutrition_plan/widgets/ownership_selector.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_widget_host.dart';

void main() {
  Future<List<PlanOwnership>> pump(
    WidgetTester tester, {
    PlanOwnership value = PlanOwnership.coached,
    bool enabled = true,
    Locale locale = const Locale('en'),
  }) async {
    final picked = <PlanOwnership>[];
    tallSurface(tester);
    await tester.pumpWidget(planApp(
      Scaffold(
        body: SingleChildScrollView(
          child: OwnershipSelector(
              value: value, enabled: enabled, onChanged: picked.add),
        ),
      ),
      locale: locale,
    ));
    await tester.pump();
    return picked;
  }

  testWidgets('three rows with title and one-line explanation (EN)',
      (tester) async {
    await pump(tester);
    expect(find.text('Who adjusts your plan'), findsOneWidget);
    for (final t in [
      'Coached',
      'Shared',
      'Manual',
      'The app adjusts your plan weekly within safe limits and tells you. You can undo a change for 7 days.',
      'The app suggests changes and you choose whether to accept them.',
      'You set the numbers. The app only shows insights and never changes your plan.',
      'Safety limits apply in every mode. A change takes effect from your next weekly review.',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('exactly the current value is selected', (tester) async {
    for (final v in PlanOwnership.values) {
      await pump(tester, value: v);
      for (final o in PlanOwnership.values) {
        final tile = tester.widget<RadioListTile<PlanOwnership>>(
            find.byKey(Key('nutrition.ownership.${o.name}')));
        expect(tile.groupValue, v);
        expect(tile.value == tile.groupValue, o == v, reason: '$v / $o');
      }
    }
  });

  testWidgets('tapping another row reports exactly that ownership',
      (tester) async {
    final picked = await pump(tester);
    await tester.tap(find.byKey(const Key('nutrition.ownership.manual')));
    await tester.pump();
    expect(picked, [PlanOwnership.manual]);
    await tester.tap(find.byKey(const Key('nutrition.ownership.shared')));
    await tester.pump();
    expect(picked, [PlanOwnership.manual, PlanOwnership.shared]);
  });

  testWidgets('tapping the already selected row reports nothing',
      (tester) async {
    final picked = await pump(tester, value: PlanOwnership.shared);
    await tester.tap(find.byKey(const Key('nutrition.ownership.shared')));
    await tester.pump();
    expect(picked, isEmpty);
  });

  testWidgets('disabled: taps report nothing', (tester) async {
    final picked = await pump(tester, enabled: false);
    await tester.tap(find.byKey(const Key('nutrition.ownership.manual')),
        warnIfMissed: false);
    await tester.pump();
    expect(picked, isEmpty);
  });

  testWidgets('the heading is a semantics header', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    final node = tester.getSemantics(find.text('Who adjusts your plan'));
    // ignore: deprecated_member_use
    expect(node.hasFlag(SemanticsFlag.isHeader), isTrue);
    handle.dispose();
  });

  testWidgets('RU titles and explanations', (tester) async {
    final picked = await pump(tester, locale: const Locale('ru'));
    expect(find.text('Кто корректирует ваш план'), findsOneWidget);
    expect(find.text('С помощником'), findsOneWidget);
    expect(find.text('Совместно'), findsOneWidget);
    expect(find.text('Вручную'), findsOneWidget);
    expect(
        find.text(
            'Приложение предлагает изменения, а вы решаете, принимать ли их.'),
        findsOneWidget);
    await tester.tap(find.text('Вручную'));
    await tester.pump();
    expect(picked, [PlanOwnership.manual]);
  });
}
