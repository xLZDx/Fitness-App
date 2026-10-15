import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/data/scan_trend.dart';
import 'package:fitness_app/features/body_scan/widgets/trend_chart.dart';

import '../support/scan_test_support.dart';

TrendSeries _series(List<double> values, {double hw = 2.0}) =>
    computeScanTrend(weeklyReadings(values, halfWidth: hw)).active!;

Future<SemanticsHandle> _pump(
  WidgetTester tester,
  TrendSeries series, {
  ChangeLabel? label,
  List<DateTime> modelChangeAt = const [],
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = tester.ensureSemantics();
  await tester.pumpWidget(scanHost(
    TrendChart(
        series: series, trendLabel: label, modelChangeAt: modelChangeAt),
    locale: locale,
  ));
  await tester.pump();
  return h;
}

List<SemanticsNode> _nodes(WidgetTester tester) {
  final out = <SemanticsNode>[];
  void walk(SemanticsNode n) {
    out.add(n);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return out;
}

Finder _k(String key) => find.byKey(Key(key));

Future<AppLocalizations> _l10n(WidgetTester tester) async =>
    AppLocalizations.of(tester.element(_k('bodyScan.chart.card')));

void main() {
  group('trendSummaryText', () {
    late AppLocalizations en;
    late AppLocalizations ru;

    setUp(() async {
      en = await AppLocalizations.delegate.load(const Locale('en'));
      ru = await AppLocalizations.delegate.load(const Locale('ru'));
    });

    test('one reading: the few-scans sentence with one decimal', () {
      final s = _series([24.1]);
      expect(trendSummaryText(en, s, null),
          'Smoothed trend 24.1 percent. More scans are needed to describe a change.');
    });

    test('RU uses the decimal comma', () {
      final s = _series([24.1]);
      final t = trendSummaryText(ru, s, null);
      expect(t, contains('24,1'));
      expect(t, isNot(contains('24.1')));
    });

    test('a null label with many readings still uses the few sentence', () {
      final s = _series([24, 23, 22]);
      expect(trendSummaryText(en, s, null), contains('More scans are needed'));
    });

    test('down: value, points and whole weeks (14 days is 2 weeks)', () {
      final s = _series([30, 28, 26]);
      final pts = (s.smoothedNow - s.points.first.smoothed).abs();
      final text = trendSummaryText(en, s, ChangeLabel.down);
      expect(
          text,
          'Smoothed trend ${s.smoothedNow.toStringAsFixed(1)} percent, '
          'down ${pts.toStringAsFixed(1)} points over 2 weeks.');
    });

    test('up and flat select their own sentences', () {
      final s = _series([20, 22, 24]);
      expect(trendSummaryText(en, s, ChangeLabel.up), contains(', up '));
      final f = trendSummaryText(en, s, ChangeLabel.noMeaningfulChange);
      expect(f, contains('no meaningful change over 2 weeks'));
      expect(f, isNot(contains('down')));
    });

    test('a span under half a week still reads at least 1 week', () {
      final readings = [
        reading(kScanDay, 20),
        reading(kScanDay.add(const Duration(days: 2)), 19),
      ];
      final s = computeScanTrend(readings).active!;
      expect(trendSummaryText(en, s, ChangeLabel.noMeaningfulChange),
          contains('over 1 weeks'));
    });
  });

  group('semantics (D-85)', () {
    testWidgets('exactly one summary node, carrying the sentence and Expand',
        (tester) async {
      final s = _series([30, 28, 26]);
      final h = await _pump(tester, s, label: ChangeLabel.down);
      final l10n = await _l10n(tester);
      final summary = trendSummaryText(l10n, s, ChangeLabel.down);
      final matching =
          _nodes(tester).where((n) => n.label == summary).toList();
      expect(matching, hasLength(1));
      final data = matching.single.getSemanticsData();
      final labels = [
        for (final id in data.customSemanticsActionIds!)
          CustomSemanticsAction.getAction(id)!.label
      ];
      expect(labels, ['Show data table']);
      h.dispose();
    });

    testWidgets('no per-point semantics nodes before expanding',
        (tester) async {
      final h = await _pump(tester, _series([30, 28, 26, 25, 24]),
          label: ChangeLabel.down);
      final pointNodes = _nodes(tester)
          .where((n) => n.label.contains('reading') && n.label.contains('range'))
          .toList();
      expect(pointNodes, isEmpty);
      h.dispose();
    });

    testWidgets('the painted chart contributes no semantics node',
        (tester) async {
      final h = await _pump(tester, _series([30, 28, 26]),
          label: ChangeLabel.down);
      final paintRect = tester.getRect(_k('bodyScan.chart.paint'));
      final hits = _nodes(tester).where((n) {
        if (n.label.isEmpty) return false;
        final r = MatrixUtils.transformRect(
            _toRoot(n), n.rect);
        return paintRect.contains(r.center) &&
            !n.label.startsWith('Smoothed trend');
      });
      expect(hits, isEmpty);
      h.dispose();
    });

    testWidgets('the Expand custom action opens the table; Collapse closes it',
        (tester) async {
      final s = _series([30, 28, 26]);
      final h = await _pump(tester, s, label: ChangeLabel.down);
      final l10n = await _l10n(tester);
      final summary = trendSummaryText(l10n, s, ChangeLabel.down);
      SemanticsNode node() =>
          _nodes(tester).firstWhere((n) => n.label == summary);
      final id = node().getSemanticsData().customSemanticsActionIds!.single;
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(node().id, SemanticsAction.customAction, id);
      await tester.pump();
      expect(_k('bodyScan.chart.table'), findsOneWidget);
      final id2 = node().getSemanticsData().customSemanticsActionIds!.single;
      expect(CustomSemanticsAction.getAction(id2)!.label, 'Hide data table');
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(node().id, SemanticsAction.customAction, id2);
      await tester.pump();
      expect(_k('bodyScan.chart.table'), findsNothing);
      h.dispose();
    });
  });

  group('data table', () {
    testWidgets('toggle button shows and hides the table', (tester) async {
      final h = await _pump(tester, _series([30, 28, 26]));
      expect(_k('bodyScan.chart.table'), findsNothing);
      expect(find.text('Show data table'), findsOneWidget);
      await tester.tap(_k('bodyScan.chart.toggle'));
      await tester.pump();
      expect(_k('bodyScan.chart.table'), findsOneWidget);
      expect(find.text('Hide data table'), findsOneWidget);
      for (final col in ['Date', 'Reading', 'Smoothed', 'Outlier']) {
        expect(find.text(col), findsOneWidget);
      }
      await tester.tap(_k('bodyScan.chart.toggle'));
      await tester.pump();
      expect(_k('bodyScan.chart.table'), findsNothing);
      h.dispose();
    });

    testWidgets('rows are newest first with reading, range and smoothed',
        (tester) async {
      final s = _series([30, 28, 26]);
      final h = await _pump(tester, s);
      await tester.tap(_k('bodyScan.chart.toggle'));
      await tester.pump();
      final rowLabels = _nodes(tester)
          .map((n) => n.label)
          .where((l) => l.contains(': reading '))
          .toList();
      expect(rowLabels, hasLength(3));
      expect(
          rowLabels.first,
          '10/15/2026: reading 26.0 percent, range 24.0 to 28.0, '
          'smoothed ${s.points.last.smoothed.toStringAsFixed(1)} percent, outlier no');
      expect(rowLabels.last, startsWith('10/1/2026: reading 30.0 percent'));
      expect(find.text('26.0 (24.0-28.0)'), findsOneWidget);
      h.dispose();
    });

    testWidgets('an outlier row says yes', (tester) async {
      final s = _series([20, 20, 20, 35]);
      expect(s.points.last.isOutlier, isTrue, reason: 'fixture must be an outlier');
      final h = await _pump(tester, s);
      await tester.tap(_k('bodyScan.chart.toggle'));
      await tester.pump();
      final rows = _nodes(tester)
          .map((n) => n.label)
          .where((l) => l.contains(': reading '))
          .toList();
      expect(rows.first, endsWith('outlier yes'));
      expect(rows.where((r) => r.endsWith('outlier no')), hasLength(3));
      h.dispose();
    });

    testWidgets('at most the latest 12 readings are listed', (tester) async {
      final values = [for (var i = 0; i < 15; i++) 30.0 - i * 0.5];
      final h = await _pump(tester, _series(values));
      await tester.tap(_k('bodyScan.chart.toggle'));
      await tester.pump();
      final rows = _nodes(tester)
          .map((n) => n.label)
          .where((l) => l.contains(': reading '))
          .toList();
      expect(rows, hasLength(kTrendChartMaxPoints));
      // The oldest three (30.0, 29.5, 29.0) are cut.
      expect(rows.any((r) => r.contains('reading 30.0 percent')), isFalse);
      expect(rows.any((r) => r.contains('reading 29.0 percent')), isFalse);
      expect(rows.last, contains('reading 28.5 percent'));
      h.dispose();
    });
  });

  group('locale (D-85)', () {
    testWidgets('RU table uses decimal comma and a localized date',
        (tester) async {
      final h = await _pump(tester, _series([24.1, 23.5]),
          locale: const Locale('ru'), label: ChangeLabel.noMeaningfulChange);
      await tester.tap(_k('bodyScan.chart.toggle'));
      await tester.pump();
      final rows = _nodes(tester)
          .map((n) => n.label)
          .where((l) => l.contains('24,1'))
          .toList();
      expect(rows, isNotEmpty);
      expect(rows.single, contains('01.10.2026'));
      expect(rows.single, isNot(contains('24.1')));
      expect(find.text('24,1 (22,1-26,1)'), findsOneWidget);
      h.dispose();
    });

    testWidgets('RU summary sentence has the comma', (tester) async {
      final h = await _pump(tester, _series([24.1]), locale: const Locale('ru'));
      final summaryNodes =
          _nodes(tester).where((n) => n.label.contains('24,1'));
      expect(summaryNodes, hasLength(1));
      h.dispose();
    });
  });

  group('legend and estimator marker', () {
    testWidgets('legend is always visible (shape, not colour only)',
        (tester) async {
      final h = await _pump(tester, _series([20, 21]));
      expect(find.text('Dots are single noisy readings. The line is the smoothed trend.'),
          findsOneWidget);
      h.dispose();
    });

    testWidgets('new estimator marker only when the model changed',
        (tester) async {
      final h = await _pump(tester, _series([20, 21]));
      expect(find.text('New estimator starts here'), findsNothing);
      h.dispose();
      final h2 = await _pump(tester, _series([20, 21]), modelChangeAt: [kScanDay]);
      expect(find.text('New estimator starts here'), findsOneWidget);
      h2.dispose();
    });

    testWidgets('a single reading paints without error', (tester) async {
      final h = await _pump(tester, _series([20]));
      expect(tester.takeException(), isNull);
      expect(_k('bodyScan.chart.paint'), findsOneWidget);
      h.dispose();
    });
  });
}

Matrix4 _toRoot(SemanticsNode n) {
  final m = Matrix4.identity();
  SemanticsNode? cur = n;
  while (cur != null) {
    if (cur.transform != null) m.multiply(cur.transform!);
    cur = cur.parent;
  }
  return m;
}
