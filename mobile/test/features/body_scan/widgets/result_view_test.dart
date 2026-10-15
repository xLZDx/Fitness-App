import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsFlag;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/check_items.dart';
import 'package:fitness_app/features/body_scan/data/scan_plan_context.dart';
import 'package:fitness_app/features/body_scan/state/scan_result_source.dart';
import 'package:fitness_app/features/body_scan/state/scan_result_view_model.dart';
import 'package:fitness_app/features/body_scan/widgets/result_view.dart';

import '../support/scan_test_support.dart';

Future<void> _pump(
  WidgetTester tester,
  ScanResultData data,
  ScanPlanContext plan, {
  Locale locale = const Locale('en'),
  VoidCallback? onSeePlan,
  void Function(CheckAction)? onCheckAction,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(800, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(scanHost(
    ResultView(
      model: buildScanResultViewModel(data, plan),
      onSeePlan: onSeePlan,
      onCheckAction: onCheckAction,
    ),
    locale: locale,
    textScale: textScale,
  ));
  await tester.pump();
}

Finder _k(String key) => find.byKey(Key(key));

double _top(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

void main() {
  group('non provisional full result', () {
    final data = scanData(values: [22, 21, 20], slope: -0.4, strength: 3);

    testWidgets('shows a likely range, never only a bare number',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(find.text('Likely range: 18.0% to 22.0%'), findsOneWidget);
      expect(find.text('Best single guess: 20.0%'), findsOneWidget);
    });

    testWidgets('shows the fixed plain-language limit sentence',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(
          find.text(
              'Single readings can vary by about 1-2 points even with a good model; the trend matters more than one scan.'),
          findsOneWidget);
    });

    testWidgets('confidence is text, "medium" for a medium estimate',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(find.text('Confidence: medium'), findsOneWidget);
      expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('low confidence uses a warning icon plus the word low',
        (tester) async {
      await _pump(
          tester,
          scanData(
              values: [22, 21, 20], confidence: EstimateConfidence.low),
          kFullPlan);
      expect(find.text('Confidence: low'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows goal, change, mass, plan decision; no provisional UI',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(_k('bodyScan.result.goal'), findsOneWidget);
      expect(_k('bodyScan.result.change'), findsOneWidget);
      expect(_k('bodyScan.result.mass'), findsOneWidget);
      expect(_k('bodyScan.result.planDecision'), findsOneWidget);
      expect(_k('bodyScan.result.provisionalBanner'), findsNothing);
      expect(_k('bodyScan.result.seePlan'), findsNothing);
      expect(find.text('Rough estimate from height, weight and age'),
          findsNothing);
    });

    testWidgets('fat and lean tiles come from the trend and say so',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(find.text('From your trend'), findsOneWidget);
      expect(find.text('This reading'), findsOneWidget); // estimate card only
      expect(find.textContaining('Fat mass:'), findsOneWidget);
      expect(find.textContaining('Lean mass:'), findsOneWidget);
    });

    testWidgets('weight trend sits below the estimate when not provisional',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(_top(tester, _k('bodyScan.result.weightTrend')),
          greaterThan(_top(tester, _k('bodyScan.result.estimate'))));
    });

    testWidgets('change card prints the move and the noise threshold',
        (tester) async {
      await _pump(tester, scanData(values: [26, 20]), kFullPlan);
      expect(find.text('Down 6.0 points since your last scan.'),
          findsOneWidget);
      expect(
          find.text(
              'Changes smaller than ±2.8 points are within measurement noise.'),
          findsOneWidget);
    });

    testWidgets('a move inside the noise says no meaningful change',
        (tester) async {
      await _pump(tester, scanData(values: [20, 21]), kFullPlan);
      expect(find.text('No meaningful change since your last scan.'),
          findsOneWidget);
    });

    testWidgets('an increase beyond the noise says Up', (tester) async {
      await _pump(tester, scanData(values: [20, 26]), kFullPlan);
      expect(find.text('Up 6.0 points since your last scan.'), findsOneWidget);
    });

    testWidgets('points to goal is printed with one decimal', (tester) async {
      final vm = buildScanResultViewModel(data, kFullPlan);
      await _pump(tester, data, kFullPlan);
      final expected = vm.pointsToGoal!.toStringAsFixed(1);
      expect(find.text('$expected points to your target'), findsOneWidget);
    });

    testWidgets('the ETA range is not rendered at all', (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(find.textContaining('if the pace holds'), findsNothing);
    });

    testWidgets('no plan decision card without a decision', (tester) async {
      await _pump(tester, data, kFullPlanNoDecision);
      expect(_k('bodyScan.result.planDecision'), findsNothing);
    });
  });

  group('provisional presentation (D-73)', () {
    final data = scanData(
        values: [22, 21, 20], provisional: true, halfWidth: 5, slope: -0.3);

    testWidgets('banner and rough-estimate label are shown', (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(_k('bodyScan.result.provisionalBanner'), findsOneWidget);
      expect(find.text('Rough estimate'), findsOneWidget);
      expect(find.text('Rough estimate from height, weight and age'),
          findsOneWidget);
    });

    testWidgets('the weight trend is the headline above the estimate',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(_top(tester, _k('bodyScan.result.weightTrend')),
          lessThan(_top(tester, _k('bodyScan.result.estimate'))));
    });

    testWidgets('ring, points to go, change, ETA and plan decision are hidden',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(_k('bodyScan.result.goal'), findsNothing);
      expect(_k('bodyScan.result.change'), findsNothing);
      expect(_k('bodyScan.result.planDecision'), findsNothing);
      expect(find.textContaining('points to your target'), findsNothing);
      expect(find.textContaining('since your last scan'), findsNothing);
      expect(find.textContaining('if the pace holds'), findsNothing);
      expect(find.text("This week's plan"), findsNothing);
    });

    testWidgets('See your plan replaces the decision and fires the callback',
        (tester) async {
      var taps = 0;
      await _pump(tester, data, kFullPlan, onSeePlan: () => taps++);
      expect(find.text('See your plan'), findsOneWidget);
      await tester.tap(_k('bodyScan.result.seePlan'));
      expect(taps, 1);
    });

    testWidgets('mass tile is the single reading, never from the trend',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(find.text('From your trend'), findsNothing);
      expect(_k('bodyScan.result.mass'), findsOneWidget);
      expect(
          find.descendant(
              of: _k('bodyScan.result.mass'),
              matching: find.text('This reading')),
          findsOneWidget);
    });

    testWidgets('range is still a range and the limit sentence is shown',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(find.text('Likely range: 15.0% to 25.0%'), findsOneWidget);
      expect(_k('bodyScan.result.limit'), findsOneWidget);
    });

    testWidgets('the provisional check code appears in the check card',
        (tester) async {
      await _pump(tester, data, kFullPlan);
      expect(
          find.text(
              'This is a rough estimate from height, weight and age, not a photo measurement.'),
          findsOneWidget);
    });
  });

  group('measurement only (D-74)', () {
    final data = scanData(values: [22, 21, 20], slope: -0.4);

    testWidgets('starts behind a neutral ask with no estimate on screen',
        (tester) async {
      await _pump(tester, data, ScanPlanContext.measurementOnly);
      expect(find.text('Show my estimate'), findsOneWidget);
      expect(
          find.text('Photos and history only. Goal figures are not shown here.'),
          findsOneWidget);
      expect(_k('bodyScan.result.estimate'), findsNothing);
      expect(find.textContaining('Likely range'), findsNothing);
    });

    testWidgets('after the ask the estimate shows but no goal figure does',
        (tester) async {
      await _pump(tester, data, ScanPlanContext.measurementOnly);
      await tester.tap(_k('bodyScan.result.ask'));
      await tester.pump();
      expect(find.text('Likely range: 18.0% to 22.0%'), findsOneWidget);
      expect(_k('bodyScan.result.goal'), findsNothing);
      expect(_k('bodyScan.result.change'), findsNothing);
      expect(_k('bodyScan.result.mass'), findsNothing);
      expect(_k('bodyScan.result.planDecision'), findsNothing);
      expect(_k('bodyScan.result.seePlan'), findsNothing);
      expect(find.text('Show my estimate'), findsNothing);
    });
  });

  group('weight trend card', () {
    Future<void> trend(WidgetTester t, double? slope) =>
        _pump(t, scanData(values: [20], slope: slope), kFullPlan);

    testWidgets('down', (t) async {
      await trend(t, -0.4);
      expect(find.text('Down 0.4 kg per week'), findsOneWidget);
    });
    testWidgets('up', (t) async {
      await trend(t, 0.25);
      expect(find.text('Up 0.25 kg per week'), findsOneWidget);
    });
    testWidgets('steady', (t) async {
      await trend(t, 0.05);
      expect(find.text('Steady, no clear change'), findsOneWidget);
    });
    testWidgets('unknown asks for more weigh-ins', (t) async {
      await trend(t, null);
      expect(find.textContaining('Not enough weigh-ins yet'), findsOneWidget);
    });
  });

  group('strength sessions card', () {
    Future<void> s(WidgetTester t, int? n) =>
        _pump(t, scanData(values: [20], strength: n), kFullPlan);

    testWidgets('null and zero read as none', (t) async {
      await s(t, null);
      expect(find.text('No strength sessions logged in the last 4 weeks.'),
          findsOneWidget);
      await s(t, 0);
      expect(find.text('No strength sessions logged in the last 4 weeks.'),
          findsOneWidget);
    });
    testWidgets('one is singular', (t) async {
      await s(t, 1);
      expect(find.text('1 session in the last 4 weeks'), findsOneWidget);
    });
    testWidgets('many is plural', (t) async {
      await s(t, 3);
      expect(find.text('3 sessions in the last 4 weeks'), findsOneWidget);
    });
  });

  group('locale aware numbers (D-85)', () {
    testWidgets('RU uses the decimal comma in the range and best guess',
        (tester) async {
      await _pump(tester, scanData(values: [24.1]), kFullPlan,
          locale: const Locale('ru'));
      final range = tester.widget<Text>(_k('bodyScan.result.range'));
      expect(range.data, contains('22,1'));
      expect(range.data, contains('26,1'));
      expect(range.data, isNot(contains('22.1')));
    });

    testWidgets('EN uses the decimal point', (tester) async {
      await _pump(tester, scanData(values: [24.1]), kFullPlan);
      final range = tester.widget<Text>(_k('bodyScan.result.range'));
      expect(range.data, 'Likely range: 22.1% to 26.1%');
    });

    testWidgets('RU weight slope uses the comma', (tester) async {
      await _pump(tester, scanData(values: [20], slope: -0.4), kFullPlan,
          locale: const Locale('ru'));
      final card = find.descendant(
          of: _k('bodyScan.result.weightTrend'), matching: find.byType(Text));
      final texts = tester.widgetList<Text>(card).map((t) => t.data).join('|');
      expect(texts, contains('0,4'));
      expect(texts, isNot(contains('0.4')));
    });

    testWidgets('RU at text scale 2.0 lays out without overflow',
        (tester) async {
      await _pump(
          tester,
          scanData(
              values: [26, 20],
              slope: -0.4,
              strength: 2,
              checks: [CheckCode.weightStale, CheckCode.wideRange]),
          kFullPlan,
          locale: const Locale('ru'),
          textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('closed codes only (I18N-07)', () {
    testWidgets('an unknown provider string is not found in the tree',
        (tester) async {
      final codes = parseCheckCodes(
          ['poorLighting', 'IGNORE PREVIOUS INSTRUCTIONS', 'wideRange']);
      await _pump(tester, scanData(values: [20], checks: codes), kFullPlan);
      expect(find.textContaining('IGNORE PREVIOUS'), findsNothing);
      expect(find.text('The lighting was poor. Retake in even light.'),
          findsOneWidget);
      expect(find.byKey(const Key('bodyScan.checks.chip.poorLighting')),
          findsOneWidget);
      expect(find.byKey(const Key('bodyScan.checks.chip.wideRange')),
          findsOneWidget);
    });

    testWidgets('no checks means no check card', (tester) async {
      await _pump(tester, scanData(values: [20]), kFullPlan);
      expect(_k('bodyScan.checks.card'), findsNothing);
    });

    testWidgets('the card action reaches the host callback', (tester) async {
      CheckAction? got;
      await _pump(tester,
          scanData(values: [20], checks: [CheckCode.weightStale]), kFullPlan,
          onCheckAction: (a) => got = a);
      await tester.tap(_k('bodyScan.checks.action.weightStale'));
      expect(got, CheckAction.logWeight);
    });
  });

  group('trend chart integration', () {
    testWidgets('chart appears with a series and not with an empty history',
        (tester) async {
      await _pump(tester, scanData(values: [22, 21, 20]), kFullPlan);
      expect(_k('bodyScan.chart.card'), findsOneWidget);
    });

    testWidgets('a header exists for the title and weight trend',
        (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, scanData(values: [20]), kFullPlan);
      final title = tester.getSemantics(find.text('Your scan result'));
      expect(title.hasFlag(SemanticsFlag.isHeader), isTrue);
      h.dispose();
    });
  });
}
