// C23 food_diary_routes_test: /nutrition/diary, /nutrition/add and
// /nutrition/add/search resolve on the REAL app router for a signed-in,
// onboarded user (query parameters reach the pages; an unknown slot means
// none), and every route the add-food tiles push is registered.
import 'dart:io';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/food_diary/add_food_page.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/food_diary_page.dart';
import 'package:fitness_app/features/food_diary/food_search_page.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'food_diary_harness.dart';

Future<GoRouter> _boot(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  final auth = MockAuthRepository(latency: Duration.zero);
  final profiles = MockProfileRepository(latency: Duration.zero);
  await tester.runAsync(() async {
    final u = await auth.signInAnonymously();
    await profiles.save(
        UserProfile.empty(u.uid).copyWith(completedAt: DateTime.utc(2026, 9, 1)));
  });
  late GoRouter router;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWith((ref) {
        ref.onDispose(auth.dispose);
        return auth;
      }),
      profileRepositoryProvider.overrideWith((ref) {
        ref.onDispose(profiles.dispose);
        return profiles;
      }),
      // Everything except the first override (the auth stream), which the
      // mock auth repository above provides for real.
      ...diaryOverrides().skip(1),
    ],
    child: Consumer(builder: (context, ref, _) {
      router = ref.watch(appRouterProvider);
      return MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      );
    }),
  ));
  await settle(tester, frames: 4);
  return router;
}

Future<void> _go(WidgetTester tester, GoRouter r, String loc) async {
  r.go(loc);
  await settle(tester, frames: 6);
}

/// The router holds a 5 s splash timer while a profile loads; dispose the tree
/// and run it out so the binding sees no pending timer.
Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  testWidgets('/nutrition/diary shows the food diary page', (tester) async {
    final r = await _boot(tester);
    await _go(tester, r, '/nutrition/diary');
    expect(find.byType(FoodDiaryPage), findsOneWidget);
    expect(find.text('Food diary'), findsWidgets);await _end(tester);
  });

  testWidgets('/nutrition/add passes day and slot to the page',
      (tester) async {
    final r = await _boot(tester);
    await _go(tester, r, '/nutrition/add?day=2026-10-14&slot=dinner');
    final p = tester.widget<AddFoodPage>(find.byType(AddFoodPage));
    expect(p.day, '2026-10-14');
    expect(p.slot, MealSlot.dinner);await _end(tester);
  });

  testWidgets('an unknown slot means no slot; no query means no day',
      (tester) async {
    final r = await _boot(tester);
    await _go(tester, r, '/nutrition/add?slot=brunch');
    var p = tester.widget<AddFoodPage>(find.byType(AddFoodPage));
    expect(p.slot, isNull);
    expect(p.day, isNull);await _end(tester);
  });

  testWidgets('/nutrition/add/search passes day, slot and saved=1',
      (tester) async {
    final r = await _boot(tester);
    await _go(tester, r, '/nutrition/add/search?day=2026-10-14&slot=snack&saved=1');
    final p = tester.widget<FoodSearchPage>(find.byType(FoodSearchPage));
    expect(p.day, '2026-10-14');
    expect(p.slot, MealSlot.snack);
    expect(p.savedOnly, isTrue);await _end(tester);
  });

  testWidgets('search without saved=1 is the search page, not saved-only',
      (tester) async {
    final r = await _boot(tester);
    await _go(tester, r, '/nutrition/add/search?saved=0');
    expect(tester.widget<FoodSearchPage>(find.byType(FoodSearchPage)).savedOnly,
        isFalse);
    expect(find.byKey(const Key('search.field')), findsOneWidget);await _end(tester);
  });

  testWidgets('a signed-out user is sent to /login, not shown the diary',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);
    final auth = MockAuthRepository(latency: Duration.zero);
    final profiles = MockProfileRepository(latency: Duration.zero);
    expect(redirectFor(auth, profiles, '/nutrition/diary'), '/login');
    expect(redirectFor(auth, profiles, '/nutrition/add'), '/login');
    expect(redirectFor(auth, profiles, '/nutrition/add/search'), '/login');
    auth.dispose();
    profiles.dispose();
  });

  group('route agreement (source level)', () {
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final page = File('lib/features/food_diary/add_food_page.dart')
        .readAsStringSync();
    final registered = RegExp(r"path:\s*'([^']+)'")
        .allMatches(router)
        .map((m) => m.group(1)!)
        .toSet();

    test('every path the add-food page pushes or goes to is registered', () {
      final pushed = RegExp(r"context\.(?:push|go)\('(/[a-z/-]+)")
          .allMatches(page)
          .map((m) => m.group(1)!)
          .toSet();
      expect(pushed, containsAll([
        '/nutrition/add/search',
        '/nutrition/add/photo',
        '/nutrition/add/barcode',
        '/nutrition/add/label',
        '/nutrition/diary',
      ]));
      for (final p in pushed) {
        expect(registered, contains(p), reason: '$p is pushed but not registered');
      }
    });

    test('the diary routes themselves are registered', () {
      expect(registered, containsAll(
          ['/nutrition/diary', '/nutrition/add', '/nutrition/add/search']));
    });
  });
}
