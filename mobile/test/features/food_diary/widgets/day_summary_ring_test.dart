// C23 day_summary_ring_test (D-78, ux.md: no budget-game wording): neutral
// status sentence, SECONDARY "room left" text, one summary semantics node, the
// painted ring is decoration, no plan means no range text.
import 'package:fitness_app/features/food_diary/data/day_totals.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/widgets/day_summary_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../food_diary_fixtures.dart';
import '../food_diary_harness.dart';

const _targets = DayTargets(
    kcalLow: 1800, kcalTarget: 2000, kcalHigh: 2200, proteinMinG: 100);

DayTotals _day(double kcal, {double protein = 0}) => computeDayTotals(
    [quickEntry(kcal: kcal, protein: protein).totals], _targets);

Widget _ring(DayTotals d, {DayTargets? t = _targets, bool entries = true}) =>
    DaySummaryRing(totals: d, targets: t, hasEntries: entries);

double _progress(WidgetTester tester) {
  for (final p in tester.widgetList<CustomPaint>(find.descendant(
      of: find.byType(DaySummaryRing), matching: find.byType(CustomPaint)))) {
    if (p.painter.runtimeType.toString() == '_RingPainter') {
      return (p.painter as dynamic).progress as double;
    }
  }
  fail('ring painter not found');
}

List<String> _texts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null) t.data!,
    ];

final _gameWords = RegExp(
    r'budget|cheat|behind|fail|bad|good|points|score|allowance|exceed|over the|remaining calories|burn|earn',
    caseSensitive: false);

void main() {
  group('statuses (EN)', () {
    testWidgets('below the range: not over, with room left as secondary text',
        (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(500)));
      expect(find.text('The day is not over. Eat what suits you.'),
          findsOneWidget);
      expect(find.text('Room left in your range: about 1,700 kcal'),
          findsOneWidget);
      expect(find.text('500'), findsOneWidget, reason: 'eaten number in the ring');
    });

    testWidgets('within the range', (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(2000)));
      expect(find.text('In your range today.'), findsOneWidget);
      expect(find.text('Room left in your range: about 200 kcal'),
          findsOneWidget);
    });

    testWidgets('exactly at the top of the range is within, no room text',
        (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(2200)));
      expect(find.text('In your range today.'), findsOneWidget);
      expect(find.textContaining('Room left'), findsNothing);
    });

    testWidgets('above the range: calm sentence, no room-left text',
        (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(2500)));
      expect(
          find.text(
              'A little above your range today. One day does not change the trend.'),
          findsOneWidget);
      expect(find.textContaining('Room left'), findsNothing);
    });

    testWidgets('an empty day shows no status and no room-left text',
        (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(0), entries: false));
      expect(find.textContaining('not over'), findsNothing);
      expect(find.textContaining('Room left'), findsNothing);
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('no plan', () {
    testWidgets('only the eaten amount: no range, status or room text',
        (tester) async {
      final d = computeDayTotals([quickEntry(kcal: 500).totals],
          const DayTargets(kcalLow: 0, kcalTarget: 0, kcalHigh: double.maxFinite));
      final h = tester.ensureSemantics();
      await pumpWidgetOnly(tester, _ring(d, t: null));
      expect(
          find.bySemanticsLabel('Eaten today. About 500 kilocalories eaten.'),
          findsOneWidget);
      expect(find.textContaining('Room left'), findsNothing);
      expect(find.textContaining('your range'), findsNothing);
      expect(_progress(tester), 0.0);
      h.dispose();
    });
  });

  group('protein minimum', () {
    testWidgets('shown at exactly the minimum', (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(500, protein: 100)));
      expect(find.text('Protein minimum reached'), findsOneWidget);
    });

    testWidgets('not shown just below it', (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(500, protein: 99.9)));
      expect(find.text('Protein minimum reached'), findsNothing);
    });
  });

  group('semantics and painting', () {
    testWidgets('one summary node carries the numbers; ring text is excluded',
        (tester) async {
      final h = tester.ensureSemantics();
      await pumpWidgetOnly(tester, _ring(_day(1100)));
      expect(
          find.bySemanticsLabel(
              'Eaten today. About 1,100 kilocalories eaten. Your range is 1,800 to 2,200 kilocalories.'),
          findsOneWidget);
      h.dispose();
    });

    testWidgets('ring progress is eaten / top of range, clamped to 1',
        (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(1100)));
      expect(_progress(tester), closeTo(0.5, 1e-9));
      await pumpWidgetOnly(tester, _ring(_day(5000)));
      expect(_progress(tester), 1.0);
      await pumpWidgetOnly(tester, _ring(_day(0), entries: false));
      expect(_progress(tester), 0.0);
    });

    testWidgets('the macro rows are part of the summary', (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(500, protein: 20)));
      expect(find.text('Protein'), findsOneWidget);
      expect(find.text('20 g'), findsOneWidget);
    });
  });

  group('wording (ux: no budget game)', () {
    testWidgets('no budget, score or failure words in any state', (tester) async {
      for (final kcal in [0.0, 500.0, 2000.0, 2200.0, 3500.0]) {
        await pumpWidgetOnly(tester, _ring(_day(kcal), entries: kcal > 0));
        for (final t in _texts(tester)) {
          expect(_gameWords.hasMatch(t), isFalse, reason: '"$t" at $kcal kcal');
        }
      }
    });

    testWidgets('no warning or error icon is drawn, even above the range',
        (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(3500)));
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('status text is not coloured with the error colour',
        (tester) async {
      await pumpWidgetOnly(tester, _ring(_day(3500)));
      final err = Theme.of(tester.element(find.byType(DaySummaryRing)))
          .colorScheme
          .error;
      final t = tester.widget<Text>(find.textContaining('A little above'));
      expect(t.style?.color, isNot(err));
    });
  });

  testWidgets('RU: sentences and grouped numbers come from the RU locale',
      (tester) async {
    await pumpWidgetOnly(tester, _ring(_day(500)), locale: const Locale('ru'));
    final ru = l10nOf(tester);
    expect(find.text(ru.foodDiaryStatusBelow), findsOneWidget);
    expect(ru.foodDiaryStatusBelow, isNot('The day is not over. Eat what suits you.'));
    expect(
        find.text(ru.foodDiaryRemaining(NumberFormat.decimalPattern('ru').format(1700))),
        findsOneWidget);
  });
}
