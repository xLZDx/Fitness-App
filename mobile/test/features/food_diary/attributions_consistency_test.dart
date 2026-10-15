// C24 attributions_consistency_test (FOOD-29, design s17.9): the rows of
// core/ATTRIBUTIONS_NUTRITION.md and the in-app "Software and references" /
// "Food data" lists of the sources page name the same components with the same
// licences, the dependency in pubspec has its row, and nothing GPL is claimed
// as copied.
import 'dart:io';

import 'package:fitness_app/features/nutrition_plan/plan_sources_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'food_diary_harness.dart';

class _Row {
  _Row(this.cells);
  final List<String> cells;
  String get component => cells[0];
  String get source => cells[1];
  String get licence => cells[2];
  String get copied => cells[5];
  String get date => cells[6];
}

List<_Row> _rows() {
  final lines = File('../core/ATTRIBUTIONS_NUTRITION.md').readAsLinesSync();
  final out = <_Row>[];
  var inTable = false;
  for (final l in lines) {
    if (l.startsWith('| Component')) {
      inTable = true;
      continue;
    }
    if (!inTable) continue;
    if (!l.startsWith('|')) break;
    if (l.startsWith('|---')) continue;
    final cells = l.substring(1, l.length - 1).split('|').map((c) => c.trim()).toList();
    out.add(_Row(cells));
  }
  return out;
}

_Row _row(String startsWith) =>
    _rows().firstWhere((r) => r.component.startsWith(startsWith),
        orElse: () => throw StateError('no attribution row "$startsWith"'));

Future<String> _pageText(WidgetTester tester, Locale locale) async {
  await pumpPage(tester, const PlanSourcesPage(), locale: locale);
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .join('\n');
}

void main() {
  group('ATTRIBUTIONS_NUTRITION.md', () {
    test('has the eight design rows with all seven columns filled', () {
      final rows = _rows();
      expect(rows.map((r) => r.component.split(' (').first.split(' ').first), [
        'USDA',
        'Open',
        '`mobile_scanner`',
        '`calorie-tracker`',
        '`calorie-count`',
        'OpenNutriTracker',
        'Mifflin-St',
        'Nutrition5k',
      ]);
      for (final r in rows) {
        expect(r.cells, hasLength(7), reason: r.component);
        for (final c in r.cells) {
          expect(c, isNotEmpty, reason: r.component);
        }
        expect(r.date, '2026-10-15', reason: r.component);
      }
    });

    test('licences of the rows', () {
      expect(_row('USDA').licence, contains('CC0 1.0'));
      expect(_row('Open Food Facts').licence, contains('ODbL 1.0'));
      expect(_row('`mobile_scanner`').licence, 'BSD-3-Clause');
      expect(_row('`calorie-tracker`').licence, 'MIT');
      expect(_row('OpenNutriTracker').licence, 'GPL-3.0');
      expect(_row('`calorie-count`').licence, startsWith('Ambiguous'));
    });

    test('copyleft and ambiguous sources are never marked as copied', () {
      expect(_row('OpenNutriTracker').copied, contains('Nothing pasted'));
      expect(_row('`calorie-count`').copied, contains('Nothing copied'));
      expect(_row('`calorie-tracker`').copied, contains('No code pasted'));
    });

    test('Open Food Facts images are stated as not used', () {
      expect(_row('Open Food Facts').licence, contains('NOT used'));
    });

    test('the file is registered in core/INDEX.md', () {
      expect(File('../core/INDEX.md').readAsStringSync(),
          contains('ATTRIBUTIONS_NUTRITION.md'));
    });

    test('the repo locations named in the file exist', () {
      final locs = {
        '../mobile/lib/features/food_diary/state/barcode_port.dart',
        '../mobile/lib/features/food_diary/data/gtin_validator.dart',
        '../mobile/lib/features/nutrition_plan/plan_sources_page.dart',
      };
      final text = File('../core/ATTRIBUTIONS_NUTRITION.md').readAsStringSync();
      expect(text, contains('plan_sources_page.dart'));
      for (final l in locs) {
        expect(File(l).existsSync(), isTrue, reason: l);
      }
    });
  });

  group('dependency has its row', () {
    test('mobile_scanner is in pubspec.yaml with the 6.x constraint', () {
      final pub = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'^\s{2}mobile_scanner:\s*\^6\.0\.11\s*$', multiLine: true)
          .hasMatch(pub), isTrue);
      expect(_row('`mobile_scanner`').source, contains('pub.dev/packages/mobile_scanner'));
    });
  });

  group('in-app list matches the file (EN)', () {
    testWidgets('section titles and the software section exist', (tester) async {
      final text = await _pageText(tester, const Locale('en'));
      expect(text, contains('Software and references'));
      expect(text, contains('Food data'));
      expect(text, contains('Data sources and limits'));
    });

    testWidgets('the section title is a header for assistive tech', (tester) async {
      await pumpPage(tester, const PlanSourcesPage());
      final header = find.ancestor(
          of: find.text('Software and references'),
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.header == true));
      expect(header, findsOneWidget);
    });

    testWidgets('every licensed component of the file is named with its licence',
        (tester) async {
      final text = await _pageText(tester, const Locale('en'));
      // component in the file -> (name shown in app, licence token shown in app)
      final expected = {
        'USDA': ('USDA FoodData Central', 'CC0 1.0'),
        'Open Food Facts': ('Open Food Facts', 'Open Database License'),
        '`mobile_scanner`': ('mobile_scanner', 'BSD-3-Clause'),
        '`calorie-tracker`': ('calorie-tracker', 'MIT'),
        'OpenNutriTracker': ('OpenNutriTracker', 'GPL-3.0'),
        '`calorie-count`': ('calorie-count', 'licence unclear'),
        'Mifflin-St': ('Mifflin-St Jeor', '1990'),
      };
      for (final e in expected.entries) {
        final r = _row(e.key);
        expect(r, isNotNull);
        expect(text, contains(e.value.$1), reason: '${e.key} name');
        expect(text, contains(e.value.$2), reason: '${e.key} licence');
      }
      // The same licence tokens appear in the file rows.
      expect(_row('USDA').licence, contains('CC0'));
      expect(_row('`mobile_scanner`').licence, contains('BSD-3'));
      expect(_row('OpenNutriTracker').licence, contains('GPL-3.0'));
      expect(_row('`calorie-tracker`').licence, contains('MIT'));
    });

    testWidgets('copied / not copied statements agree', (tester) async {
      final text = await _pageText(tester, const Locale('en'));
      expect(text, contains('No code was copied'));
      expect(text, contains('Nothing was copied'));
      expect(text.contains('code was pasted'), isFalse);
    });

    testWidgets('the app points at the full list file that exists', (tester) async {
      final text = await _pageText(tester, const Locale('en'));
      expect(text, contains('ATTRIBUTIONS_NUTRITION.md'));
      expect(File('../core/ATTRIBUTIONS_NUTRITION.md').existsSync(), isTrue);
    });

    testWidgets('the Nutrition5k pointer is evaluation-only and not shown as a source',
        (tester) async {
      final text = await _pageText(tester, const Locale('en'));
      expect(_row('Nutrition5k').copied, 'No');
      expect(text.contains('Nutrition5k'), isFalse,
          reason: 'nothing of it is bundled, so the app does not claim it');
    });
  });

  group('in-app list (RU)', () {
    testWidgets('software section is localised and keeps the identifiers',
        (tester) async {
      final text = await _pageText(tester, const Locale('ru'));
      expect(text.contains('Software and references'), isFalse);
      for (final token in [
        'mobile_scanner',
        'BSD-3-Clause',
        'calorie-tracker',
        'MIT',
        'OpenNutriTracker',
        'GPL-3.0',
        'calorie-count',
        'ATTRIBUTIONS_NUTRITION.md',
      ]) {
        expect(text, contains(token), reason: token);
      }
    });
  });
}
