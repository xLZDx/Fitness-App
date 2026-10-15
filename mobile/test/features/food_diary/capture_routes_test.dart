// C24 capture_routes_test (design s21 route table, FOOD-25 add-food tiles):
// the add-food tiles push /nutrition/add/photo|barcode|label with the day and
// slot query parameters, tiles whose feature flag is off are hidden, and the
// tile / page paths agree with the routes registered in app_router.dart.
//
// Limit (stated, not hidden): the real GoRouter needs auth, profile and
// onboarding streams, so the route table is checked by reading the
// app_router.dart source (paths, page classes, `day` and `slot` parameters),
// not by navigating the production router.
import 'dart:io';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/features/food_diary/add_food_page.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'food_diary_fixtures.dart';
import 'food_diary_harness.dart';

const _all = BodyScanFlags(foodAi: true, foodLookup: true);

String _src(String path) => File(path).readAsStringSync();

/// `path: '/x', pageBuilder: ... Page(day:..., slot:...)` blocks of the router.
Map<String, String> _routeBlocks() {
  final s = _src('lib/core/router/app_router.dart');
  final re = RegExp(r"GoRoute\(\s*path: '(/nutrition/add[^']*)',(.*?)\n      \),", dotAll: true);
  return {for (final m in re.allMatches(s)) m.group(1)!: m.group(2)!};
}

Future<PumpedPage> _pump(WidgetTester tester, BodyScanFlags flags,
        {String? day, MealSlot? slot}) =>
    pumpPage(tester, AddFoodPage(day: day, slot: slot),
        overrides: diaryOverrides(flags: flags));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await settle(tester);
}

void main() {
  group('tiles push the planned routes with day and slot', () {
    final cases = {
      'add.photo': '/nutrition/add/photo',
      'add.barcode': '/nutrition/add/barcode',
      'add.label': '/nutrition/add/label',
    };
    for (final c in cases.entries) {
      testWidgets('${c.key} -> ${c.value}?day=2026-10-14&slot=dinner',
          (tester) async {
        final p = await _pump(tester, _all, day: '2026-10-14', slot: MealSlot.dinner);
        await _tap(tester, c.key);
        expect(p.stubUri, '${c.value}?day=2026-10-14&slot=dinner');
      });

      testWidgets('${c.key} without day/slot -> empty day, snack slot',
          (tester) async {
        final p = await _pump(tester, _all);
        await _tap(tester, c.key);
        expect(p.stubUri, '${c.value}?day=&slot=snack');
      });
    }

    testWidgets('each slot name is passed through', (tester) async {
      for (final s in MealSlot.values) {
        final p = await _pump(tester, _all, day: kToday, slot: s);
        await _tap(tester, 'add.photo');
        expect(p.stubUri, '/nutrition/add/photo?day=$kToday&slot=${s.name}');
      }
    });

    testWidgets('search and saved tiles keep their own routes', (tester) async {
      var p = await _pump(tester, _all, day: kToday, slot: MealSlot.lunch);
      await _tap(tester, 'add.search');
      expect(p.stubUri, '/nutrition/add/search?day=$kToday&slot=lunch');
      p = await _pump(tester, _all, day: kToday, slot: MealSlot.lunch);
      await _tap(tester, 'add.saved');
      expect(p.stubUri, '/nutrition/add/search?day=$kToday&slot=lunch&saved=1');
    });
  });

  group('flags off hide the capture tiles', () {
    final tiles = ['add.photo', 'add.describe', 'add.label', 'add.barcode'];

    testWidgets('default build (all flags off): only search, quick, saved',
        (tester) async {
      await _pump(tester, const BodyScanFlags());
      for (final t in tiles) {
        expect(find.byKey(Key(t)), findsNothing, reason: t);
      }
      for (final t in ['add.search', 'add.quick', 'add.saved']) {
        expect(find.byKey(Key(t)), findsOneWidget, reason: t);
      }
    });

    testWidgets('foodAi only: photo, describe, label; no barcode', (tester) async {
      await _pump(tester, const BodyScanFlags(foodAi: true));
      expect(find.byKey(const Key('add.photo')), findsOneWidget);
      expect(find.byKey(const Key('add.describe')), findsOneWidget);
      expect(find.byKey(const Key('add.label')), findsOneWidget);
      expect(find.byKey(const Key('add.barcode')), findsNothing);
    });

    testWidgets('foodLookup only: barcode; no photo, describe, label',
        (tester) async {
      await _pump(tester, const BodyScanFlags(foodLookup: true));
      expect(find.byKey(const Key('add.barcode')), findsOneWidget);
      for (final t in ['add.photo', 'add.describe', 'add.label']) {
        expect(find.byKey(Key(t)), findsNothing, reason: t);
      }
    });

    testWidgets('both on: all four capture tiles', (tester) async {
      await _pump(tester, _all);
      for (final t in tiles) {
        expect(find.byKey(Key(t)), findsOneWidget, reason: t);
      }
    });

    testWidgets('the cloud-photo flag does not reveal food tiles', (tester) async {
      await _pump(tester, const BodyScanFlags(cloudPhotos: true));
      for (final t in tiles) {
        expect(find.byKey(Key(t)), findsNothing, reason: t);
      }
    });
  });

  group('tile paths agree with the registered routes (source contract)', () {
    final routes = _routeBlocks();

    test('the three capture routes are registered', () {
      expect(routes.keys, containsAll([
        '/nutrition/add/photo',
        '/nutrition/add/barcode',
        '/nutrition/add/label',
      ]));
    });

    test('each route builds its own page and forwards day and slot', () {
      final expected = {
        '/nutrition/add/photo': 'MealScanPage(',
        '/nutrition/add/barcode': 'BarcodeScanPage(',
        '/nutrition/add/label': 'LabelScanPage(',
      };
      for (final e in expected.entries) {
        final block = routes[e.key]!;
        expect(block, contains(e.value), reason: e.key);
        expect(block, contains("queryParameters['day']"), reason: e.key);
        expect(block, contains("_slotParam(state.uri.queryParameters['slot'])"),
            reason: e.key);
      }
    });

    test('every path pushed by AddFoodPage is a registered route', () {
      final add = _src('lib/features/food_diary/add_food_page.dart');
      final pushed = RegExp(r"context\.push\('(/nutrition/[a-z/]+)")
          .allMatches(add)
          .map((m) => m.group(1)!)
          .toSet();
      expect(pushed, containsAll([
        '/nutrition/add/search',
        '/nutrition/add/photo',
        '/nutrition/add/barcode',
        '/nutrition/add/label',
      ]));
      expect(routes.keys.toSet().containsAll(pushed), isTrue,
          reason: 'unregistered: ${pushed.difference(routes.keys.toSet())}');
    });

    test('paths used inside the barcode page exist too', () {
      final page = _src('lib/features/food_diary/barcode_scan_page.dart');
      final used = RegExp(r"'(/nutrition/[a-z/]+)")
          .allMatches(page)
          .map((m) => m.group(1)!)
          .toSet();
      expect(used, containsAll(['/nutrition/add/label', '/nutrition/add', '/nutrition/diary']));
      final all = _src('lib/core/router/app_router.dart');
      for (final u in used) {
        expect(all, contains("path: '$u'"), reason: u);
      }
    });

    test('the old, disagreeing /nutrition/scan paths are gone', () {
      for (final f in [
        'lib/features/food_diary/add_food_page.dart',
        'lib/core/router/app_router.dart',
        'lib/features/food_diary/meal_scan_page.dart',
        'lib/features/food_diary/barcode_scan_page.dart',
        'lib/features/food_diary/label_scan_page.dart',
      ]) {
        expect(_src(f), isNot(contains('/nutrition/scan/')), reason: f);
      }
    });
  });
}
