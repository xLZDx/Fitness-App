// C23 portion_editor_test (FOOD-17 UI half, a11y F6/F15): numeric field plus
// 48 dp less/more buttons (non-drag alternative), likely range as text, only
// positive values reach the callback.
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/widgets/portion_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../food_diary_harness.dart';

class _Host extends StatefulWidget {
  const _Host({required this.initial, required this.calls, this.step = 10});
  final MacroRange initial;
  final List<double> calls;
  final double step;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late MacroRange grams = widget.initial;

  @override
  Widget build(BuildContext context) => PortionEditor(
        grams: grams,
        step: widget.step,
        onChanged: (g) {
          widget.calls.add(g);
          setState(() => grams = MacroRange.exact(g));
        },
      );
}

String _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  testWidgets('starts at the mid of the range, whole numbers without decimals',
      (tester) async {
    await pumpWidgetOnly(
        tester, _Host(initial: MacroRange(100, 150, 200), calls: []));
    expect(_field(tester), '150');
    expect(find.text('Portion (g)'), findsOneWidget);
  });

  testWidgets('a fractional mid shows one decimal', (tester) async {
    await pumpWidgetOnly(
        tester, _Host(initial: MacroRange.exact(12.5), calls: []));
    expect(_field(tester), '12.5');
  });

  testWidgets('the likely range is text, only when the range is not exact',
      (tester) async {
    await pumpWidgetOnly(
        tester, _Host(initial: MacroRange(100, 150, 200), calls: []));
    expect(find.text('Likely between 100 and 200 g'), findsOneWidget);
  });

  testWidgets('an exact portion shows no range text', (tester) async {
    await pumpWidgetOnly(
        tester, _Host(initial: MacroRange.exact(150), calls: []));
    expect(find.textContaining('Likely between'), findsNothing);
  });

  testWidgets('range numbers are localised (RU grouping)', (tester) async {
    await pumpWidgetOnly(
        tester, _Host(initial: MacroRange(1000, 1500, 2000), calls: []),
        locale: const Locale('ru'));
    final ru = l10nOf(tester);
    expect(find.text('Likely between 1,000 and 2,000 g'), findsNothing);
    expect(find.textContaining('1\u00a0000'), findsOneWidget);
    expect(ru.foodDetailPortionRange('x', 'y'), isNot(contains('between')));
  });

  group('buttons', () {
    testWidgets('more and less change by the step and collapse the range',
        (tester) async {
      final calls = <double>[];
      await pumpWidgetOnly(
          tester, _Host(initial: MacroRange(100, 150, 200), calls: calls));
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      expect(calls, [160]);
      expect(_field(tester), '160');
      expect(find.textContaining('Likely between'), findsNothing,
          reason: 'a user-set portion is exact');
      await tester.tap(find.byTooltip('Less'));
      await tester.pump();
      await tester.tap(find.byTooltip('Less'));
      await tester.pump();
      expect(calls, [160, 150, 140]);
      expect(_field(tester), '140');
    });

    testWidgets('less never reaches zero or below', (tester) async {
      final calls = <double>[];
      await pumpWidgetOnly(
          tester, _Host(initial: MacroRange.exact(10), calls: calls));
      await tester.tap(find.byTooltip('Less'));
      await tester.pump();
      expect(calls, isEmpty, reason: '10 - 10 = 0 is refused');
      expect(_field(tester), '10');
    });

    testWidgets('a custom step is honoured', (tester) async {
      final calls = <double>[];
      await pumpWidgetOnly(tester,
          _Host(initial: MacroRange.exact(100), calls: calls, step: 25));
      await tester.tap(find.byTooltip('More'));
      expect(calls, [125]);
    });

    testWidgets('targets are at least 48 x 48 dp', (tester) async {
      await pumpWidgetOnly(
          tester, _Host(initial: MacroRange.exact(100), calls: []));
      for (final tip in ['Less', 'More']) {
        final s = tester.getSize(find.byTooltip(tip));
        expect(s.width, greaterThanOrEqualTo(48), reason: tip);
        expect(s.height, greaterThanOrEqualTo(48), reason: tip);
      }
    });
  });

  group('typing', () {
    testWidgets('a valid value is reported; a decimal comma is accepted',
        (tester) async {
      final calls = <double>[];
      await pumpWidgetOnly(
          tester, _Host(initial: MacroRange.exact(100), calls: calls));
      await tester.enterText(find.byType(TextField), '175');
      await tester.enterText(find.byType(TextField), '12,5');
      expect(calls, [175, 12.5]);
      expect(find.text('Enter a portion above zero.'), findsNothing);
    });

    testWidgets('zero, negative, text, infinity and > 10000 are refused',
        (tester) async {
      final calls = <double>[];
      await pumpWidgetOnly(
          tester, _Host(initial: MacroRange.exact(100), calls: calls));
      for (final bad in ['0', '-5', 'abc', '', 'Infinity', '10001']) {
        await tester.enterText(find.byType(TextField), bad);
        await tester.pump();
        expect(find.text('Enter a portion above zero.'), findsOneWidget,
            reason: '"$bad"');
      }
      expect(calls, isEmpty);
    });

    testWidgets('10000 is the accepted upper bound', (tester) async {
      final calls = <double>[];
      await pumpWidgetOnly(
          tester, _Host(initial: MacroRange.exact(100), calls: calls));
      await tester.enterText(find.byType(TextField), '10000');
      expect(calls, [10000]);
    });

    testWidgets('the error clears after a valid value', (tester) async {
      await pumpWidgetOnly(
          tester, _Host(initial: MacroRange.exact(100), calls: []));
      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();
      expect(find.text('Enter a portion above zero.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '50');
      await tester.pump();
      expect(find.text('Enter a portion above zero.'), findsNothing);
    });

    testWidgets('the error clears after a button nudge', (tester) async {
      await pumpWidgetOnly(
          tester, _Host(initial: MacroRange.exact(100), calls: []));
      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      expect(find.text('Enter a portion above zero.'), findsNothing);
    });
  });

  testWidgets('an outside change of grams is shown in the field',
      (tester) async {
    final key = GlobalKey<State<StatefulWidget>>();
    var grams = MacroRange.exact(100);
    late StateSetter set;
    await pumpWidgetOnly(
        tester,
        StatefulBuilder(builder: (c, s) {
          set = s;
          return PortionEditor(key: key, grams: grams, onChanged: (_) {});
        }));
    set(() => grams = MacroRange.exact(222));
    await tester.pump();
    expect(_field(tester), '222');
  });
}
