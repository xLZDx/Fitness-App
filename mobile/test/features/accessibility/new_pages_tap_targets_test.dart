// T125 / A11Y-24 (C26, Y-F15): androidTapTargetGuideline and
// labeledTapTargetGuideline over every new page (body scan flow / result /
// history / privacy, nutrition plan / weight log / sources / explainer, food
// diary / add / search / meal / barcode / label) in EN and RU at text scale 1.0
// and 2.0 on a 360x640 phone, with the repo's fakes and overrides.
//
// The file is named apart from semantics_targets_test.dart, which already
// exists (P2b questionnaire pills) and is left untouched.
import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/body_scan/body_scan_flow_page.dart';
import 'package:fitness_app/features/body_scan/body_scan_history_page.dart';
import 'package:fitness_app/features/body_scan/body_scan_privacy_page.dart';
import 'package:fitness_app/features/body_scan/body_scan_result_page.dart';
import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/body_scan/state/scan_history_actions.dart';
import 'package:fitness_app/features/body_scan/state/scan_history_rows.dart';
import 'package:fitness_app/features/body_scan/state/scan_plan_context_provider.dart';
import 'package:fitness_app/features/body_scan/state/scan_result_source.dart';
import 'package:fitness_app/features/food_diary/add_food_page.dart';
import 'package:fitness_app/features/food_diary/barcode_scan_page.dart';
import 'package:fitness_app/features/food_diary/food_diary_page.dart';
import 'package:fitness_app/features/food_diary/food_search_page.dart';
import 'package:fitness_app/features/food_diary/label_scan_page.dart';
import 'package:fitness_app/features/food_diary/meal_scan_page.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/state/barcode_port.dart';
import 'package:fitness_app/features/food_diary/state/capture_image_port.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/food_diary/state/food_api.dart';
import 'package:fitness_app/features/nutrition_plan/nutrition_plan_page.dart';
import 'package:fitness_app/features/nutrition_plan/plan_explainer_page.dart';
import 'package:fitness_app/features/nutrition_plan/plan_sources_page.dart';
import 'package:fitness_app/features/nutrition_plan/weight_log_page.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../body_scan/support/driver_harness.dart';
import '../body_scan/support/scan_test_support.dart';
import '../food_diary/food_diary_fixtures.dart';
import '../food_diary/food_diary_harness.dart';
import '../nutrition_plan/plan_state_fixtures.dart';
import '../nutrition_plan/plan_state_harness.dart';
import '../nutrition_plan/plan_widget_host.dart';

const _phone = Size(360, 640);
const _flags = BodyScanFlags(foodAi: true, foodLookup: true);

typedef _Pump = Future<void> Function(WidgetTester t, Locale l, double scale);

void _phoneSurface(WidgetTester t) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = _phone;
  addTearDown(t.view.reset);
}

/// A router so pages that call GoRouter.of(context) can build.
GoRouter _router(Widget page) => GoRouter(
      initialLocation: '/page',
      routes: [GoRoute(path: '/page', builder: (_, __) => page)],
    );

// ---- body scan ----------------------------------------------------------

Future<void> _flow(WidgetTester t, Locale l, double s) async {
  _phoneSurface(t);
  await t.pumpWidget(ProviderScope(
    overrides: [
      ...driverOverrides(
          flags: _flags,
          weights: [WeightEntry(at: kDriverNow.subtract(const Duration(hours: 2)), kg: 80)]),
      scanAccessProvider.overrideWithValue(ScanAccess.allowed),
      bodyScanSettingsStoreProvider
          .overrideWithValue(InMemoryBodyScanSettingsStore()),
    ],
    child: planApp(const SizedBox(),
        router: _router(const BodyScanFlowPage()), locale: l, textScale: s),
  ));
  await t.pumpAndSettle();
}

class _ResultSource implements ScanResultSource {
  @override
  Future<ScanResultData?> load(String scanId) async =>
      scanData(values: [22, 21, 20], slope: -0.4, strength: 3);
}

Future<void> _result(WidgetTester t, Locale l, double s) async {
  _phoneSurface(t);
  await t.pumpWidget(ProviderScope(
    overrides: [
      scanResultSourceProvider.overrideWithValue(_ResultSource()),
      scanPlanContextValueProvider.overrideWithValue(kFullPlan),
      scanHistoryRowsProvider.overrideWithValue(const []),
    ],
    child: planApp(const SizedBox(),
        router: _router(const BodyScanResultPage(scanId: 's')),
        locale: l,
        textScale: s),
  ));
  await t.pumpAndSettle();
}

Future<void> _history(WidgetTester t, Locale l, double s) async {
  _phoneSurface(t);
  BodyFatEstimate est(double v) => BodyFatEstimate(
        value: v,
        low: v - 2,
        high: v + 2,
        confidence: EstimateConfidence.medium,
        modelId: 'photo-model',
        modelVersion: '1',
        provisional: false,
      );
  final rows = [
    for (var i = 0; i < 3; i++)
      ScanHistoryRow(
        id: 'r$i',
        takenAt: DateTime(2026, 10, 1 + i, 9),
        weightKg: 80.0 - i,
        estimate: est(22.0 - i),
      ),
  ];
  await t.pumpWidget(ProviderScope(
    overrides: [scanHistoryRowsProvider.overrideWithValue(rows)],
    child: planApp(const SizedBox(),
        router: _router(const BodyScanHistoryPage()), locale: l, textScale: s),
  ));
  await t.pumpAndSettle();
}

Future<void> _privacy(WidgetTester t, Locale l, double s) async {
  _phoneSurface(t);
  await t.pumpWidget(ProviderScope(
    child: planApp(const SizedBox(),
        router: _router(const BodyScanPrivacyPage()), locale: l, textScale: s),
  ));
  await t.pumpAndSettle();
}

// ---- nutrition ----------------------------------------------------------

Future<void> _plan(WidgetTester t, Locale l, double s) async {
  final h = (await t.runAsync(() => makeHarness(
        profile: eligibleProfile(),
        extra: [
          dataNoticeStoreProvider.overrideWith(
              (ref) async => InMemoryDataNoticeStore(acknowledged: true)),
          bodyScanSettingsStoreProvider
              .overrideWithValue(InMemoryBodyScanSettingsStore()),
        ],
      )))!;
  addTearDown(h.dispose);
  h.plans.seedPlan(kUid, storedPlan());
  _phoneSurface(t);
  await t.pumpWidget(planApp(const SizedBox(),
      container: h.container,
      router: _router(const NutritionPlanPage()),
      locale: l,
      textScale: s));
  await settleAsync(t);
}

Future<void> _weightLog(WidgetTester t, Locale l, double s) async {
  final h = (await t.runAsync(() => makeHarness(
        extra: [
          dataNoticeStoreProvider.overrideWith(
              (ref) async => InMemoryDataNoticeStore(acknowledged: true)),
        ],
      )))!;
  addTearDown(h.dispose);
  await t.runAsync(() async {
    for (var i = 0; i < 3; i++) {
      await h.weights.put(
          kUid,
          WeightEntry(
              at: DateTime(2026, 10, 15, 8).subtract(Duration(days: i * 3)),
              kg: 80.0 - i * 0.4,
              source: WeightSource.manual));
    }
  });
  _phoneSurface(t);
  await t.pumpWidget(planApp(const WeightLogPage(),
      container: h.container, locale: l, textScale: s));
  await settleAsync(t);
}

Future<void> _sources(WidgetTester t, Locale l, double s) async {
  _phoneSurface(t);
  await t.pumpWidget(planApp(const PlanSourcesPage(), locale: l, textScale: s));
  await t.pump();
}

Future<void> _explainer(WidgetTester t, Locale l, double s) async {
  _phoneSurface(t);
  await t.pumpWidget(planApp(const PlanExplainerPage(), locale: l, textScale: s));
  await t.pump();
}

// ---- food diary ---------------------------------------------------------

Future<void> _diaryPage(WidgetTester t, Locale l, double s, Widget page,
    {List<Override> extra = const []}) async {
  final repo = InMemoryDiaryRepository();
  for (final slot in MealSlot.values) {
    await repo.put(kDiaryUid,
        quickEntry(id: 'e-${slot.name}', slot: slot, name: 'Soup'));
  }
  await pumpPage(t, page,
      locale: l,
      textScale: s,
      size: _phone,
      overrides: diaryOverrides(flags: _flags, extra: [
        diaryRepositoryProvider.overrideWithValue(repo),
        dataNoticeStoreProvider.overrideWith(
            (ref) async => InMemoryDataNoticeStore(acknowledged: true)),
        foodApiProvider.overrideWithValue(FakeFoodApi()),
        captureImagePortProvider.overrideWithValue(FakeCaptureImagePort()),
        barcodePortFactoryProvider.overrideWithValue(() => FakeBarcodePort()),
        ...extra,
      ]));
}

final Map<String, _Pump> _pages = {
  'body_scan flow': _flow,
  'body_scan result': _result,
  'body_scan history': _history,
  'body_scan privacy': _privacy,
  'nutrition plan': _plan,
  'nutrition weight log': _weightLog,
  'nutrition sources': _sources,
  'nutrition explainer': _explainer,
  'food diary': (t, l, s) => _diaryPage(t, l, s, const FoodDiaryPage()),
  'food add': (t, l, s) => _diaryPage(t, l, s, const AddFoodPage()),
  'food search': (t, l, s) => _diaryPage(t, l, s, const FoodSearchPage()),
  'food meal scan': (t, l, s) => _diaryPage(t, l, s, const MealScanPage()),
  'food barcode scan': (t, l, s) => _diaryPage(t, l, s, const BarcodeScanPage()),
  'food label scan': (t, l, s) => _diaryPage(t, l, s, const LabelScanPage()),
};

void main() {
  for (final page in _pages.entries) {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets(
            '${page.key} ${locale.languageCode} x$scale: tap targets and labels',
            (tester) async {
          final handle = tester.ensureSemantics();
          // Keep the full details (render object path) of any layout error.
          final details = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            details.add(d.toString());
            prev?.call(d);
          };
          addTearDown(() => FlutterError.onError = prev);
          await page.value(tester, locale, scale);
          // The page really rendered (not an error placeholder): something
          // is on screen and no exception was thrown while building it.
          final ex = tester.takeException();
          expect(ex, isNull,
              reason: details.join('\n'));
          expect(find.byType(Scaffold), findsWidgets);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
        });
      }
    }
  }
}
