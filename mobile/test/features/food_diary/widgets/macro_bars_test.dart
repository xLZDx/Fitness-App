// C23 macro_bars_test (A11Y-06 macro half, I18N-07): labelled rows whose VALUES
// are text; the bar is decoration only and proportional to the largest macro.
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/widgets/macro_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../food_diary_harness.dart';

MacroTotals _t(double p, double c, double f) => MacroTotals(
      kcal: MacroRange.zero,
      proteinG: MacroRange.exact(p),
      carbsG: MacroRange.exact(c),
      fatG: MacroRange.exact(f),
    );

List<double> _bars(WidgetTester tester) => [
      for (final b in tester.widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator)))
        b.value!,
    ];

void main() {
  testWidgets('rows show name and gram value as text (EN)', (tester) async {
    await pumpWidgetOnly(tester, MacroBars(totals: _t(30.5, 28, 0.3)));
    expect(find.text('Protein'), findsOneWidget);
    expect(find.text('Carbs'), findsOneWidget);
    expect(find.text('Fat'), findsOneWidget);
    expect(find.text('30.5 g'), findsOneWidget);
    expect(find.text('28 g'), findsOneWidget);
    expect(find.text('0.3 g'), findsOneWidget);
  });

  testWidgets('values use one decimal at most and thousands separators',
      (tester) async {
    await pumpWidgetOnly(tester, MacroBars(totals: _t(12.34, 1234.5, 7)));
    expect(find.text('12.3 g'), findsOneWidget);
    expect(find.text('1,234.5 g'), findsOneWidget);
    expect(find.text('7 g'), findsOneWidget);
  });

  testWidgets('RU uses the decimal comma and the Russian unit', (tester) async {
    await pumpWidgetOnly(tester, MacroBars(totals: _t(30.5, 28, 0.3)),
        locale: const Locale('ru'));
    final ru = l10nOf(tester);
    expect(find.text(ru.foodUnitGrams('30,5')), findsOneWidget);
    expect(find.text(ru.foodUnitGrams('0,3')), findsOneWidget);
    expect(find.text('30.5 g'), findsNothing);
    expect(find.text(ru.foodMacroProtein), findsOneWidget);
  });

  testWidgets('one semantics node per row carries "name, value"',
      (tester) async {
    final h = tester.ensureSemantics();
    await pumpWidgetOnly(tester, MacroBars(totals: _t(30.5, 28, 0.3)));
    expect(find.bySemanticsLabel('Protein, 30.5 g'), findsOneWidget);
    expect(find.bySemanticsLabel('Carbs, 28 g'), findsOneWidget);
    expect(find.bySemanticsLabel('Fat, 0.3 g'), findsOneWidget);
    h.dispose();
  });

  testWidgets('bars are proportional to the largest macro', (tester) async {
    await pumpWidgetOnly(tester, MacroBars(totals: _t(20, 40, 10)));
    expect(_bars(tester), [0.5, 1.0, 0.25]);
  });

  testWidgets('an all-zero day draws empty bars, never a division error',
      (tester) async {
    await pumpWidgetOnly(tester, MacroBars(totals: MacroTotals.zero));
    expect(_bars(tester), [0.0, 0.0, 0.0]);
    expect(find.text('0 g'), findsNWidgets(3));
  });

  testWidgets('uses the MID of a range, not its bounds', (tester) async {
    await pumpWidgetOnly(
        tester,
        MacroBars(
            totals: MacroTotals(
          kcal: MacroRange.zero,
          proteinG: MacroRange(10, 20, 40),
          carbsG: MacroRange.zero,
          fatG: MacroRange.zero,
        )));
    expect(find.text('20 g'), findsOneWidget);
    expect(find.text('40 g'), findsNothing);
  });
}
