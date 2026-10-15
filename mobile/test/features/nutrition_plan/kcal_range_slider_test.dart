// T84 kcal_range_slider (PLAN-18, SAFE-16, A11Y-05, A11Y-10; a11y F6).
//
// Fixture bounds are the hand-derived 1850..2400 of plan_state_fixtures.dart;
// every expected number below is derived by hand from design s13.3 / D-82
// (step 10, width 100..400), never read back from the widget.
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/nutrition_plan/widgets/kcal_range_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'plan_state_fixtures.dart';
import 'plan_widget_host.dart';

KcalSliderMove move(KcalRange r, bool low, int target,
        {PlanBounds bounds = kLoseBounds}) =>
    moveKcalThumb(bounds: bounds, range: r, lowThumb: low, target: target);

void main() {
  group('moveKcalThumb (pure)', () {
    const r = KcalRange(2000, 2200);

    test('a free move of one step changes only the moved thumb', () {
      final up = move(r, true, 2010);
      expect(up.range, const KcalRange(2010, 2200));
      expect(up.limit, isNull);
      final down = move(r, false, 2190);
      expect(down.range, const KcalRange(2000, 2190));
      expect(down.limit, isNull);
    });

    test('targets snap to the 10 kcal step (half rounds up)', () {
      expect(move(r, true, 2004).range.low, 2000);
      expect(move(r, true, 2005).range.low, 2010);
      expect(move(r, true, 2014).range.low, 2010);
      expect(move(r, false, 2194).range.high, 2190);
      expect(move(r, false, 2196).range.high, 2200);
    });

    test('low thumb cannot go below the lower bound (far drag = bound)', () {
      final m = move(r, true, 100);
      expect(m.range.low, 1850);
      expect(m.limit, KcalSliderLimit.minBound);
      expect(m.range.high, 2200);
    });

    test('high thumb cannot go above the upper bound (far drag = bound)', () {
      final m = move(r, false, 9000);
      expect(m.range.high, 2400);
      expect(m.limit, KcalSliderLimit.maxBound);
      expect(m.range.low, 2000);
    });

    test('landing exactly on a bound is not a limit hit; one past it is', () {
      const atEdge = KcalRange(1900, 2200);
      final exact = move(atEdge, true, 1850);
      expect(exact.range.low, 1850);
      expect(exact.limit, isNull);
      final past = move(atEdge, true, 1840);
      expect(past.range.low, 1850);
      expect(past.limit, KcalSliderLimit.minBound);
      final topExact = move(const KcalRange(2200, 2300), false, 2400);
      expect(topExact.range.high, 2400);
      expect(topExact.limit, isNull);
    });

    test('minimum gap 100: low stops at high-100, high stops at low+100', () {
      final lowM = move(r, true, 2150);
      expect(lowM.range, const KcalRange(2100, 2200));
      expect(lowM.limit, KcalSliderLimit.minGap);
      final highM = move(r, false, 2050);
      expect(highM.range, const KcalRange(2000, 2100));
      expect(highM.limit, KcalSliderLimit.minGap);
      // Exactly 100 apart is allowed and not a limit hit.
      final exact = move(r, true, 2100);
      expect(exact.range, const KcalRange(2100, 2200));
      expect(exact.limit, isNull);
    });

    test('maximum gap 400: low stops at high-400, high stops at low+400', () {
      const wide = KcalRange(1900, 2300);
      final lowM = move(wide, true, 1860);
      expect(lowM.range, const KcalRange(1900, 2300));
      expect(lowM.limit, KcalSliderLimit.maxGap);
      const narrow = KcalRange(1900, 2000);
      final highM = move(narrow, false, 2350);
      expect(highM.range, const KcalRange(1900, 2300));
      expect(highM.limit, KcalSliderLimit.maxGap);
      final exact = move(narrow, false, 2300);
      expect(exact.limit, isNull);
    });

    test('the result never leaves bounds or the 100..400 width, any target',
        () {
      for (final low in [true, false]) {
        for (var target = 1000; target <= 3500; target += 7) {
          final m = move(r, low, target);
          expect(m.range.low, greaterThanOrEqualTo(1850), reason: '$target');
          expect(m.range.high, lessThanOrEqualTo(2400), reason: '$target');
          final w = m.range.high - m.range.low;
          expect(w, inInclusiveRange(100, 400), reason: '$low $target');
          expect(m.range.low % 10, 0);
          expect(m.range.high % 10, 0);
        }
      }
    });
  });

  group('KcalRangeSlider widget', () {
    late List<KcalRange> ends;
    late List<KcalRange> lives;

    Future<void> pump(
      WidgetTester tester, {
      KcalRange initial = const KcalRange(2000, 2200),
      Locale locale = const Locale('en'),
      bool enabled = true,
    }) async {
      ends = [];
      lives = [];
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1600);
      addTearDown(tester.view.reset);
      var current = initial;
      await tester.pumpWidget(planApp(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 500,
              child: StatefulBuilder(builder: (context, setState) {
                return KcalRangeSlider(
                  bounds: kLoseBounds,
                  range: current,
                  enabled: enabled,
                  onChanged: (r) {
                    lives.add(r);
                    setState(() => current = r);
                  },
                  onChangeEnd: ends.add,
                );
              }),
            ),
          ),
        ),
        locale: locale,
      ));
      await tester.pump();
    }

    SemanticsNode node(WidgetTester tester, String label) =>
        tester.getSemantics(find.bySemanticsLabel(label));

    void act(WidgetTester tester, String label, SemanticsAction a) {
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(node(tester, label).id, a);
    }

    testWidgets('each thumb is its own slider node with spoken value + unit',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      final low = node(tester, 'Lowest daily calories');
      final high = node(tester, 'Highest daily calories');
      expect(low.id, isNot(high.id));
      expect(low.value, '2,000 kilocalories');
      expect(high.value, '2,200 kilocalories');
      expect(low.increasedValue, '2,010 kilocalories');
      expect(low.decreasedValue, '1,990 kilocalories');
      expect(high.increasedValue, '2,210 kilocalories');
      expect(high.decreasedValue, '2,190 kilocalories');
      for (final n in [low, high]) {
        // ignore: deprecated_member_use
        expect(n.hasFlag(SemanticsFlag.isSlider), isTrue);
        expect(n.getSemanticsData().hasAction(SemanticsAction.increase), isTrue);
        expect(n.getSemanticsData().hasAction(SemanticsAction.decrease), isTrue);
      }
      handle.dispose();
    });

    testWidgets('increase on the low thumb moves 10 and persists once, silently',
        (tester) async {
      final handle = tester.ensureSemantics();
      final spoken = captureAnnouncements(tester);
      await pump(tester);
      act(tester, 'Lowest daily calories', SemanticsAction.increase);
      await tester.pump();
      expect(ends, [const KcalRange(2010, 2200)]);
      expect(lives, [const KcalRange(2010, 2200)]);
      expect(spoken, isEmpty, reason: 'a free move announces no limit');
      expect(node(tester, 'Lowest daily calories').value, '2,010 kilocalories');
      act(tester, 'Highest daily calories', SemanticsAction.decrease);
      await tester.pump();
      expect(ends.last, const KcalRange(2010, 2190));
      handle.dispose();
    });

    testWidgets('hitting the lower bound announces it and writes nothing',
        (tester) async {
      final handle = tester.ensureSemantics();
      final spoken = captureAnnouncements(tester);
      await pump(tester, initial: const KcalRange(1850, 2200));
      act(tester, 'Lowest daily calories', SemanticsAction.decrease);
      await tester.pump();
      expect(spoken, ['Minimum reached, 1,850']);
      expect(ends, isEmpty);
      expect(node(tester, 'Lowest daily calories').value, '1,850 kilocalories');
      handle.dispose();
    });

    testWidgets('hitting the upper bound announces it', (tester) async {
      final handle = tester.ensureSemantics();
      final spoken = captureAnnouncements(tester);
      await pump(tester, initial: const KcalRange(2200, 2400));
      act(tester, 'Highest daily calories', SemanticsAction.increase);
      await tester.pump();
      expect(spoken, ['Maximum reached, 2,400']);
      expect(ends, isEmpty);
      handle.dispose();
    });

    testWidgets('low cannot cross high-100; the gap hit is announced',
        (tester) async {
      final handle = tester.ensureSemantics();
      final spoken = captureAnnouncements(tester);
      await pump(tester, initial: const KcalRange(2000, 2100));
      act(tester, 'Lowest daily calories', SemanticsAction.increase);
      await tester.pump();
      expect(spoken, ['Range cannot be narrower than 100']);
      expect(ends, isEmpty);
      expect(node(tester, 'Lowest daily calories').value, '2,000 kilocalories');
      act(tester, 'Highest daily calories', SemanticsAction.decrease);
      await tester.pump();
      expect(spoken.length, 2);
      expect(spoken.last, 'Range cannot be narrower than 100');
      handle.dispose();
    });

    testWidgets('the 400 maximum width is announced', (tester) async {
      final handle = tester.ensureSemantics();
      final spoken = captureAnnouncements(tester);
      await pump(tester, initial: const KcalRange(1900, 2300));
      act(tester, 'Lowest daily calories', SemanticsAction.decrease);
      await tester.pump();
      expect(spoken, ['Range cannot be wider than 400']);
      expect(ends, isEmpty);
      handle.dispose();
    });

    testWidgets('steppers produce exactly what the thumbs produce',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      Future<void> stepper(String label) async {
        await tester.tap(find.bySemanticsLabel(label));
        await tester.pump();
      }

      // +10 stepper == increase action on the same thumb.
      await stepper('Lowest daily calories: increase by 10');
      final viaStepper = ends.last;
      expect(viaStepper, const KcalRange(2010, 2200));
      await pump(tester);
      act(tester, 'Lowest daily calories', SemanticsAction.increase);
      await tester.pump();
      expect(ends.last, viaStepper);

      await pump(tester);
      await stepper('Highest daily calories: decrease by 100');
      expect(ends.last, const KcalRange(2000, 2100));
      expect(ends.last, move(const KcalRange(2000, 2200), false, 2100).range);

      await pump(tester);
      await stepper('Highest daily calories: increase by 100');
      expect(ends.last, const KcalRange(2000, 2300));
      await pump(tester);
      await stepper('Lowest daily calories: decrease by 10');
      expect(ends.last, const KcalRange(1990, 2200));
      handle.dispose();
    });

    testWidgets('a +100 stepper that would pass a limit stops at the limit',
        (tester) async {
      final spoken = captureAnnouncements(tester);
      await pump(tester, initial: const KcalRange(2000, 2150));
      await tester.tap(
          find.bySemanticsLabel('Lowest daily calories: increase by 100'));
      await tester.pump();
      // high-100 = 2050: low moves 2000 -> 2050 and the gap hit is spoken.
      expect(ends, [const KcalRange(2050, 2150)]);
      expect(spoken, ['Range cannot be narrower than 100']);
    });

    testWidgets('dragging far beyond either end holds the bound',
        (tester) async {
      await pump(tester);
      final lowThumb = find.bySemanticsLabel('Lowest daily calories');
      await tester.drag(lowThumb, const Offset(-3000, 0));
      await tester.pump();
      expect(lives.last, const KcalRange(1850, 2200));
      expect(ends.last, const KcalRange(1850, 2200));

      await pump(tester);
      final highThumb = find.bySemanticsLabel('Highest daily calories');
      await tester.drag(highThumb, const Offset(3000, 0));
      await tester.pump();
      expect(lives.last, const KcalRange(2000, 2400));
      expect(ends.last, const KcalRange(2000, 2400));
    });

    testWidgets('a drag never narrows or widens past the width limits',
        (tester) async {
      await pump(tester);
      await tester.drag(
          find.bySemanticsLabel('Lowest daily calories'), const Offset(3000, 0));
      await tester.pump();
      expect(lives.last, const KcalRange(2100, 2200));
    });

    testWidgets('disabled: no actions on thumbs and steppers do nothing',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, enabled: false);
      final low = node(tester, 'Lowest daily calories');
      expect(low.getSemanticsData().hasAction(SemanticsAction.increase), isFalse);
      expect(low.getSemanticsData().hasAction(SemanticsAction.decrease), isFalse);
      await tester.tap(
          find.bySemanticsLabel('Lowest daily calories: increase by 10'),
          warnIfMissed: false);
      await tester.pump();
      expect(ends, isEmpty);
      handle.dispose();
    });

    testWidgets('stepper and thumb touch targets are at least 48 dp',
        (tester) async {
      await pump(tester);
      final buttons = find.byType(OutlinedButton);
      expect(buttons, findsNWidgets(8));
      for (final b in buttons.evaluate()) {
        final size = tester.getSize(find.byWidget(b.widget));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('RU: labels, spoken value and announcements are Russian',
        (tester) async {
      final handle = tester.ensureSemantics();
      final spoken = captureAnnouncements(tester);
      await pump(tester,
          initial: const KcalRange(1850, 2200), locale: const Locale('ru'));
      final f = NumberFormat.decimalPattern('ru');
      final low = node(tester, 'Нижняя граница калорий в день');
      expect(low.value, '${f.format(1850)} килокалорий');
      expect(low.increasedValue, '${f.format(1860)} килокалорий');
      act(tester, 'Нижняя граница калорий в день', SemanticsAction.decrease);
      await tester.pump();
      expect(spoken, ['Достигнут минимум, ${f.format(1850)}']);
      expect(find.bySemanticsLabel(
              'Нижняя граница калорий в день: увеличить на 100'),
          findsOneWidget);
      expect(find.bySemanticsLabel(
              'Верхняя граница калорий в день: уменьшить на 10'),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('RU: gap announcement', (tester) async {
      final handle = tester.ensureSemantics();
      final spoken = captureAnnouncements(tester);
      await pump(tester,
          initial: const KcalRange(2000, 2100), locale: const Locale('ru'));
      act(tester, 'Нижняя граница калорий в день', SemanticsAction.increase);
      await tester.pump();
      expect(spoken, ['Диапазон не может быть уже 100']);
      handle.dispose();
    });
  });
}
