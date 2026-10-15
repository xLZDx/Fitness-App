// Widget harness of the C23 food diary tests (not a test file itself): the real
// page under a real GoRouter whose other routes are recording stubs, with the
// real providers over in-memory repositories and a fixed clock.
import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/food_diary/data/generic_foods.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:fitness_app/features/nutrition_plan/state/nutrition_providers.dart';
import 'package:fitness_app/features/nutrition_plan/state/weight_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../nutrition_plan/plan_state_fixtures.dart';
import 'food_diary_fixtures.dart';

/// A tiny bundled table (no rootBundle): rice x2, chicken, olive oil.
String _row(int fdc, String name, double kcal, double p, double c, double f) =>
    '{"id":"gen:$fdc","name":"$name","category":"T","fdcId":$fdc,'
    '"per100g":{"kcal":$kcal,"proteinG":$p,"carbsG":$c,"fatG":$f}}';

final GenericFoodTable kTestTable = GenericFoodTable.parse('{"version":1,"foods":['
    '${_row(1, 'Rice, white', 130, 2.7, 28, 0.3)},'
    '${_row(2, 'Rice, brown', 112, 2.3, 24, 0.8)},'
    '${_row(3, 'Chicken breast', 165, 31, 0, 3.6)},'
    '${_row(4, 'Olive oil', 884, 0, 0, 100)}]}');

/// Olive oil per 100 g in [kTestTable] (hand copy for expected values).
const double kOilKcalPer100 = 884;

List<Override> diaryOverrides({
  String? uid = kDiaryUid,
  NutritionEligibility? verdict = const Eligible(),
  bool withPlan = true,
  BodyScanFlags flags = const BodyScanFlags(),
  bool noticeAcknowledged = true,
  DateTime? now,
  List<Override> extra = const [],
}) =>
    [
      authUserProvider.overrideWith((ref) => Stream.value(
          uid == null ? null : AuthUser(uid: uid, displayName: 'T'))),
      nutritionEligibilityProvider.overrideWithValue(verdict),
      storedNutritionPlanProvider.overrideWith(
          (ref) => Stream.value(withPlan ? storedPlan() : null)),
      nutritionClockProvider.overrideWithValue(() => now ?? kDiaryNow),
      bodyScanFlagsProvider.overrideWithValue(flags),
      dataNoticeAcknowledgedProvider
          .overrideWith((ref) async => noticeAcknowledged),
      genericFoodTableProvider.overrideWith((ref) async => kTestTable),
      ...extra,
    ];

const List<String> kStubPaths = [
  '/nutrition/profile',
  '/nutrition/weight',
  '/nutrition/diary',
  '/nutrition/add',
  '/nutrition/add/search',
  '/nutrition/add/photo',
  '/nutrition/add/barcode',
  '/nutrition/add/label',
];

class PumpedPage {
  PumpedPage(this.router, this.tester);
  final GoRouter router;
  final WidgetTester tester;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  /// Full URI of the topmost stub page (`STUB <uri>`), or null.
  String? get stubUri {
    for (final e in tester.widgetList<Text>(find.byType(Text))) {
      final d = e.data;
      if (d != null && d.startsWith('STUB ')) return d.substring(5);
    }
    return null;
  }
}

/// Pumps [home] at `/home` of a GoRouter that also serves recording stubs for
/// [kStubPaths] (except the ones in [real]).
Future<PumpedPage> pumpPage(
  WidgetTester tester,
  Widget home, {
  List<Override>? overrides,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  Size size = const Size(800, 3000),
  Map<String, Widget Function(GoRouterState)> real = const {},
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => home),
      for (final p in kStubPaths)
        if (!real.containsKey(p))
          GoRoute(
            path: p,
            builder: (_, s) => Scaffold(body: Text('STUB ${s.uri}')),
          ),
      for (final e in real.entries)
        GoRoute(path: e.key, builder: (_, s) => e.value(s)),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: overrides ?? diaryOverrides(),
    child: MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  // The write actions read the signed-in user synchronously; in the app some
  // watcher always keeps the auth stream alive, so do the same here.
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
      .read(authUserProvider);
  await settle(tester);
  return PumpedPage(router, tester);
}

/// Lets streams/futures deliver and animations of a few frames finish without
/// waiting on an indefinite progress indicator.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps a single widget (no router) for pure-widget tests.
Future<void> pumpWidgetOnly(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  Size size = const Size(800, 1600),
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ));
  await tester.pump();
}

AppLocalizations l10nOf(WidgetTester tester, [Type t = Scaffold]) =>
    AppLocalizations.of(tester.element(find.byType(t).first));
