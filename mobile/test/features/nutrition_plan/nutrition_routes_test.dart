// C19 routes: /nutrition, /nutrition/weight, /nutrition/sources and
// /nutrition/how-it-adapts are registered in the REAL router, are not redirected
// for a user who finished onboarding, and resolve to the right page.
import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/nutrition_plan/nutrition_plan_page.dart';
import 'package:fitness_app/features/nutrition_plan/nutrition_profile_flow_page.dart';
import 'package:fitness_app/features/nutrition_plan/plan_explainer_page.dart';
import 'package:fitness_app/features/nutrition_plan/plan_sources_page.dart';
import 'package:fitness_app/features/nutrition_plan/weight_log_page.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';

const _paths = <String, Type>{
  '/nutrition': NutritionPlanPage,
  '/nutrition/weight': WeightLogPage,
  '/nutrition/sources': PlanSourcesPage,
  '/nutrition/how-it-adapts': PlanExplainerPage,
  '/nutrition/profile': NutritionProfileFlowPage,
};

void _collect(List<RouteBase> routes, String prefix, Set<String> out) {
  for (final r in routes) {
    if (r is GoRoute) {
      final full = r.path.startsWith('/')
          ? r.path
          : '${prefix == '/' ? '' : prefix}/${r.path}';
      out.add(full);
      _collect(r.routes, full, out);
    } else if (r is ShellRouteBase) {
      _collect(r.routes, prefix, out);
    }
  }
}

void main() {
  late MockAuthRepository auth;
  late MockProfileRepository profiles;
  late String uid;

  setUp(() async {
    auth = MockAuthRepository(latency: Duration.zero);
    profiles = MockProfileRepository(latency: Duration.zero);
    uid = (await auth.signInAnonymously()).uid;
    await profiles.save(UserProfile.empty(uid)
        .copyWith(completedAt: DateTime.utc(2026, 9, 1)));
  });

  tearDown(() {
    auth.dispose();
    profiles.dispose();
  });

  test('a finished user is never redirected away from any /nutrition* path',
      () {
    for (final p in _paths.keys) {
      expect(redirectFor(auth, profiles, p), isNull, reason: p);
    }
  });

  test('the route table registers every /nutrition* path', () {
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(profiles),
    ]);
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    final found = <String>{};
    _collect(router.configuration.routes, '/', found);
    for (final p in _paths.keys) {
      expect(found, contains(p), reason: 'route $p is registered');
    }
    // No stray sibling spellings.
    expect(found, isNot(contains('/nutrition/')));
    expect(found, isNot(contains('/nutrition/plan')));
  });

  for (final e in _paths.entries) {
    if (e.key == '/nutrition' || e.key == '/nutrition/weight') continue;
    testWidgets('${e.key} resolves to ${e.value}', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 2400);
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
      ]);
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      router.go(e.key);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(e.value), findsOneWidget);
      expect(
          GoRouter.of(tester.element(find.byType(e.value))).state.uri.path,
          e.key);
      // Let the splash timer of the real router fire before teardown.
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
