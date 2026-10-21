import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/config/demo_features.dart';
import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/donor_wall/donor_wall_page.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

/// A profile repository whose first snapshot is withheld until [release],
/// modelling a cold start where auth restores before Firestore answers.
class _SlowProfiles extends MockProfileRepository {
  _SlowProfiles() : super(latency: Duration.zero);

  final Completer<void> _gate = Completer<void>();
  UserProfile? _hidden;

  void seed(UserProfile p) => _hidden = p;
  void release() => _gate.complete();

  @override
  UserProfile? cached(String uid) =>
      _gate.isCompleted ? _hidden : null;

  @override
  Stream<UserProfile?> watch(String uid) async* {
    await _gate.future;
    yield _hidden;
  }
}

void main() {
  const gated = [
    '/community',
    '/celebrity-plans',
    '/contribute',
    '/moderate',
    '/team/abc',
    // v1 scope: the coach marketplace is demo-gated too.
    '/coaches',
    '/coaches/x',
  ];

  group('demo-feature gating (pure)', () {
    String? resolve(String loc,
            {bool demo = false, bool signedIn = true, bool onboarded = true}) =>
        resolveRedirect(
          isSignedIn: signedIn,
          isOnboarded: onboarded,
          isAnonymous: false,
          location: loc,
          demoFeaturesEnabled: demo,
        );

    test('gated paths redirect to /home when demo features are off', () {
      for (final p in gated) {
        expect(resolve(p), '/home', reason: p);
      }
    });

    test('gated paths are untouched when demo features are on', () {
      for (final p in gated) {
        expect(resolve(p, demo: true), isNull, reason: p);
      }
    });

    test('other paths are unaffected', () {
      for (final p in [
        '/home',
        '/profile',
        '/settings',
        '/teams',
        '/community-guidelines',
      ]) {
        expect(resolve(p), isNull, reason: p);
      }
    });

    test('a signed-out caller still goes to /login first', () {
      expect(resolve('/community', signedIn: false), '/login');
    });

    test('isDemoGatedPath matches exactly the demo routes', () {
      for (final p in gated) {
        expect(isDemoGatedPath(p), isTrue, reason: p);
      }
      expect(isDemoGatedPath('/team'), isFalse);
      // Prefix look-alikes must not be swallowed by the /coaches family.
      expect(isDemoGatedPath('/coachesx'), isFalse);
      expect(isDemoGatedPath('/coach'), isFalse);
    });

    test('v1 scope: /coaches and /coaches/x go to /home with the flag off, '
        'stay with it on', () {
      for (final p in ['/coaches', '/coaches/x']) {
        expect(isDemoGatedPath(p), isTrue, reason: p);
        expect(resolve(p), '/home', reason: 'flag off: $p');
        expect(resolve(p, demo: true), isNull, reason: 'flag on: $p');
      }
    });

    test('v1 scope: /donors is login-only (no longer a public path)', () {
      // (a) signed-out deep link -> /login, whatever the demo flag says.
      for (final demo in [false, true]) {
        expect(
            resolve('/donors', signedIn: false, onboarded: false, demo: demo),
            '/login',
            reason: 'signed-out, demo=$demo');
      }
      // (b) signed-in and onboarded -> reachable.
      for (final demo in [false, true]) {
        expect(resolve('/donors', demo: demo), isNull,
            reason: 'signed-in onboarded, demo=$demo');
      }
      // Signed-in but not onboarded: the onboarding rule now applies.
      expect(resolve('/donors', onboarded: false), '/onboarding');
      // Control: the remaining public pages are still open when signed out.
      for (final p in ['/about', '/licences', '/terms', '/privacy']) {
        expect(resolve(p, signedIn: false, onboarded: false), isNull,
            reason: p);
      }
    });
  });

  group('redirectFor: profile not loaded yet (cold start)', () {
    late MockAuthRepository auth;
    late MockProfileRepository profiles;

    setUp(() async {
      auth = MockAuthRepository(latency: Duration.zero);
      profiles = MockProfileRepository(latency: Duration.zero);
      await auth.signInAnonymously();
    });

    tearDown(() {
      auth.dispose();
      profiles.dispose();
    });

    test('an unknown profile is held on /splash, not sent to /onboarding', () {
      expect(redirectFor(auth, profiles, '/home', profileLoaded: false),
          '/splash');
    });

    test('a loaded-but-absent profile still goes to /onboarding', () {
      expect(redirectFor(auth, profiles, '/home', profileLoaded: true),
          '/onboarding');
    });

    test('public and scan paths are not held', () {
      for (final p in ['/splash', '/about', '/login', '/equipment/1']) {
        expect(redirectFor(auth, profiles, p, profileLoaded: false), isNull,
            reason: p);
      }
    });

    test('a cached onboarded profile is never held', () async {
      final u = auth.currentUser!;
      await profiles.save(UserProfile(uid: u.uid, completedAt: DateTime(2026)));
      expect(redirectFor(auth, profiles, '/home', profileLoaded: false),
          isNull);
    });
  });

  group('J3/T1 release gating via redirectFor (the router derivation)', () {
    late MockAuthRepository auth;
    late MockProfileRepository profiles;

    setUp(() async {
      auth = MockAuthRepository(latency: Duration.zero);
      profiles = MockProfileRepository(latency: Duration.zero);
      final u = (await auth.signInAnonymously())!;
      await profiles.save(UserProfile(uid: u.uid, completedAt: DateTime(2026)));
    });

    tearDown(() {
      auth.dispose();
      profiles.dispose();
    });

    const denied = [
      '/community',
      '/team/abc',
      '/celebrity-plans',
      '/contribute',
      '/moderate',
      '/coaches',
      '/coaches/x',
      // Sub-paths: /team/ and /coaches/ have parametrised families.
      '/team/abc/x',
      '/team/abc/',
      '/team/other-id',
    ];

    test('flag off: every gated path lands on /home for an onboarded user',
        () {
      for (final p in denied) {
        expect(
            redirectFor(auth, profiles, p, demoFeaturesEnabled: false),
            '/home',
            reason: p);
      }
    });

    test('flag on: the same paths are not redirected (gate is not a blanket)',
        () {
      for (final p in denied) {
        expect(
            redirectFor(auth, profiles, p, demoFeaturesEnabled: true), isNull,
            reason: p);
      }
    });

    test('flag off: /coaches and /coaches/x land on /home; flag on keeps them',
        () {
      for (final p in ['/coaches', '/coaches/x']) {
        expect(isDemoGatedPath(p), isTrue, reason: p);
        expect(redirectFor(auth, profiles, p, demoFeaturesEnabled: false),
            '/home',
            reason: p);
        expect(redirectFor(auth, profiles, p, demoFeaturesEnabled: true),
            isNull,
            reason: p);
      }
    });

    test('/donors: an onboarded signed-in user is not redirected', () {
      expect(redirectFor(auth, profiles, '/donors', demoFeaturesEnabled: false),
          isNull);
    });

    test('flag off: a signed-in, NOT onboarded user never reaches a gated '
        'target; the chain ends on /onboarding', () async {
      await profiles.save(UserProfile(uid: auth.currentUser!.uid));
      for (final p in denied) {
        final first = resolveRedirect(
            isSignedIn: true,
            isOnboarded: false,
            isAnonymous: true,
            location: p,
            demoFeaturesEnabled: false);
        expect(first, '/home', reason: p);
        final second = resolveRedirect(
            isSignedIn: true,
            isOnboarded: false,
            isAnonymous: true,
            location: first!,
            demoFeaturesEnabled: false);
        expect(second, '/onboarding', reason: p);
      }
    });

    test('flag off: a signed-out caller is sent to /login, not /home', () {
      for (final p in denied) {
        expect(
            resolveRedirect(
                isSignedIn: false,
                isOnboarded: false,
                isAnonymous: false,
                location: p,
                demoFeaturesEnabled: false),
            '/login',
            reason: p);
      }
    });
  });

  group('J3/T1 live GoRouter (demoFeaturesEnabledProvider override)', () {
    // The router's redirect closure calls redirectFor with the compile-time
    // default, and appRouterProvider has no injection point for the flag, so
    // the release (false) side cannot be driven through the live router
    // without a production change. What can be proven live: the control half
    // (gated pages ARE reachable, so the gate is not a blanket redirect),
    // and the exact location string the live router hands to the gate for
    // query / trailing-slash variants, fed into the gate with the flag off.
    Future<GoRouter> mount(WidgetTester tester,
        {bool onboarded = true,
        bool signedIn = true,
        bool? demo}) async {
      final auth = MockAuthRepository(latency: Duration.zero);
      final profiles = MockProfileRepository(latency: Duration.zero);
      if (signedIn) {
        final u = (await tester.runAsync(() => auth.signInAnonymously()))!;
        if (onboarded) {
          await tester.runAsync(() => profiles
              .save(UserProfile(uid: u.uid, completedAt: DateTime(2026))));
        }
      }
      late GoRouter router;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          if (demo != null)
            demoFeaturesEnabledProvider.overrideWithValue(demo),
          authRepositoryProvider.overrideWith((ref) {
            ref.onDispose(auth.dispose);
            return auth;
          }),
          profileRepositoryProvider.overrideWith((ref) {
            ref.onDispose(profiles.dispose);
            return profiles;
          }),
        ],
        child: Consumer(builder: (context, ref, _) {
          router = ref.watch(appRouterProvider);
          return MaterialApp.router(
            theme: AppTheme.light(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          );
        }),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
      return router;
    }

    String pathOf(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

    Future<void> go(WidgetTester tester, GoRouter r, String loc) async {
      r.go(loc);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
    }

    const gatedLocations = [
      '/community',
      '/team/abc',
      '/team/abc/x',
      '/celebrity-plans',
      '/contribute',
      '/moderate',
      '/community?x=1',
      '/team/abc?x=1',
      '/celebrity-plans?x=1',
      '/contribute?x=1',
      '/moderate?x=1',
      '/community/',
      '/team/abc/',
      '/celebrity-plans/',
      '/contribute/',
      '/moderate/',
      '/coaches',
      '/coaches/x',
    ];

    testWidgets(
        'release (provider false): router.go to every gated location lands '
        'on /home', (tester) async {
      final router = await mount(tester, demo: false);
      expect(pathOf(router), '/home');
      for (final p in gatedLocations) {
        await go(tester, router, p);
        expect(pathOf(router), '/home', reason: p);
      }
      await unmount(tester);
    });

    testWidgets(
        'release: notification-tap style navigation (go and push) is denied',
        (tester) async {
      final router = await mount(tester, demo: false);
      for (final payload in ['/moderate', '/community', '/team/abc']) {
        router.go(payload);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(pathOf(router), '/home', reason: 'go $payload');
        router.push(payload);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(pathOf(router), '/home', reason: 'push $payload');
      }
      await unmount(tester);
    });

    testWidgets('release: cold start with a restored gated location lands on '
        '/home', (tester) async {
      for (final restored in ['/community', '/team/abc/x', '/moderate']) {
        tester.platformDispatcher.defaultRouteNameTestValue = restored;
        final router = await mount(tester, demo: false);
        expect(pathOf(router), '/home', reason: restored);
        await unmount(tester);
      }
      tester.platformDispatcher.clearDefaultRouteNameTestValue();
    });

    testWidgets('release: /coaches and /coaches/x land on /home',
        (tester) async {
      final router = await mount(tester, demo: false);
      for (final p in ['/coaches/x', '/coaches']) {
        await go(tester, router, p);
        expect(pathOf(router), '/home', reason: p);
      }
      await unmount(tester);
    });

    testWidgets('/donors: signed-out deep link redirects to /login',
        (tester) async {
      for (final demo in [false, true]) {
        final router = await mount(tester, demo: demo, signedIn: false);
        await go(tester, router, '/donors');
        expect(pathOf(router), '/login', reason: 'demo=$demo');
        await unmount(tester);
      }
    });

    testWidgets('/donors: a signed-in onboarded user can open it',
        (tester) async {
      for (final demo in [false, true]) {
        final router = await mount(tester, demo: demo);
        await go(tester, router, '/donors');
        expect(pathOf(router), '/donors', reason: 'demo=$demo');
        expect(find.byType(DonorWallPage), findsOneWidget,
            reason: 'demo=$demo');
        await unmount(tester);
      }
    });

    testWidgets('/donors: a signed-in NOT onboarded user goes to /onboarding',
        (tester) async {
      final router = await mount(tester, onboarded: false);
      await go(tester, router, '/donors');
      expect(pathOf(router), '/onboarding');
      await unmount(tester);
    });

    testWidgets('release: signed-in not-onboarded user ends on /onboarding, '
        'signed-out on /login', (tester) async {
      var router = await mount(tester, demo: false, onboarded: false);
      for (final p in ['/community', '/team/abc', '/moderate?x=1']) {
        await go(tester, router, p);
        expect(pathOf(router), '/onboarding', reason: p);
      }
      await unmount(tester);
      router = await mount(tester, demo: false, signedIn: false);
      for (final p in ['/community', '/team/abc/x']) {
        await go(tester, router, p);
        expect(pathOf(router), '/login', reason: p);
      }
      await unmount(tester);
    });

    testWidgets('demo provider true: the same locations are reachable (the '
        'gate is not a blanket redirect)', (tester) async {
      final router = await mount(tester, demo: true);
      const reachable = {
        '/community': '/community',
        '/team/abc': '/team/abc',
        '/celebrity-plans': '/celebrity-plans',
        '/contribute': '/contribute',
        '/moderate': '/moderate',
        '/coaches': '/coaches',
        '/coaches/x': '/coaches/x',
        '/community?x=1': '/community',
        '/team/abc?x=1': '/team/abc',
        '/moderate/': '/moderate',
        '/contribute/': '/contribute',
      };
      for (final e in reachable.entries) {
        await go(tester, router, e.key);
        expect(pathOf(router), e.value, reason: e.key);
      }
      await unmount(tester);
    });

    testWidgets('demo provider true: cold start restored gated location is '
        'honoured', (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue = '/community';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final router = await mount(tester, demo: true);
      expect(pathOf(router), '/community');
      await unmount(tester);
    });

    testWidgets('control: gated paths are reachable with demo features on',
        (tester) async {
      final router = await mount(tester);
      for (final p in ['/community', '/celebrity-plans', '/contribute',
          '/moderate', '/team/abc']) {
        await go(tester, router, p);
        expect(pathOf(router), p, reason: p);
      }
      await unmount(tester);
    });

    testWidgets(
        'what the live router hands to the gate is a gated path for query '
        'and trailing-slash variants (flag off then denies every one)',
        (tester) async {
      final router = await mount(tester);
      const variants = {
        '/community?x=1': '/community',
        '/community/': '/community',
        '/moderate?x=1': '/moderate',
        '/contribute/': '/contribute',
        '/celebrity-plans/?a=b': '/celebrity-plans',
        '/team/abc?x=1': '/team/abc',
        '/team/abc/': '/team/abc',
        '/team/abc/x': '/team/abc/x',
      };
      for (final e in variants.entries) {
        await go(tester, router, e.key);
        final seen = pathOf(router);
        expect(seen, e.value, reason: 'location seen for ${e.key}');
        expect(isDemoGatedPath(seen), isTrue, reason: e.key);
        expect(
            resolveRedirect(
                isSignedIn: true,
                isOnboarded: true,
                isAnonymous: true,
                location: seen,
                demoFeaturesEnabled: false),
            '/home',
            reason: e.key);
      }
      await unmount(tester);
    });

    testWidgets('notification-tap style navigation uses the same gate',
        (tester) async {
      final router = await mount(tester);
      for (final payload in ['/moderate', '/community', '/team/abc']) {
        await go(tester, router, payload);
        expect(pathOf(router), payload, reason: 'flag on reaches $payload');
        final signedOut = MockAuthRepository(latency: Duration.zero);
        final emptyProfiles = MockProfileRepository(latency: Duration.zero);
        expect(
            redirectFor(signedOut, emptyProfiles, payload,
                demoFeaturesEnabled: false),
            '/login',
            reason: 'signed-out payload tap is sent to login first');
        signedOut.dispose();
        emptyProfiles.dispose();
      }
      await unmount(tester);
    });

    testWidgets('/coaches/x is a demo-gated path, reachable with the flag on',
        (tester) async {
      final router = await mount(tester, demo: true);
      await go(tester, router, '/coaches/x');
      expect(pathOf(router), '/coaches/x');
      expect(isDemoGatedPath(pathOf(router)), isTrue);
      await unmount(tester);
    });

    testWidgets(
        'signed in but not onboarded: onboarding rule still applies, gated '
        'target is never reached', (tester) async {
      final router = await mount(tester, onboarded: false);
      expect(pathOf(router), '/onboarding');
      for (final p in ['/community', '/team/abc', '/moderate?x=1']) {
        await go(tester, router, p);
        expect(pathOf(router), '/onboarding', reason: p);
      }
      await unmount(tester);
    });

    testWidgets('signed out: gated paths go to /login', (tester) async {
      final router = await mount(tester, signedIn: false);
      for (final p in ['/community', '/team/abc', '/contribute']) {
        await go(tester, router, p);
        expect(pathOf(router), '/login', reason: p);
      }
      await unmount(tester);
    });

    testWidgets('cold start with a restored gated location (flag on: honoured)',
        (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue = '/community';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final router = await mount(tester);
      expect(pathOf(router), '/community');
      await unmount(tester);
    });

    testWidgets('cold start restored gated location, not onboarded: '
        'onboarding wins', (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue = '/team/abc';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final router = await mount(tester, onboarded: false);
      expect(pathOf(router), '/onboarding');
      await unmount(tester);
    });
  });

  group('router integration: cold start with a slow profile snapshot', () {
    testWidgets(
        'an onboarded user is held on /splash until the profile arrives, '
        'never bounced to /onboarding', (tester) async {
      final auth = MockAuthRepository(latency: Duration.zero);
      final user = (await tester.runAsync(() => auth.signInAnonymously()))!;
      final profiles = _SlowProfiles()
        ..seed(UserProfile(uid: user.uid, completedAt: DateTime(2026)));
      final visited = <String>[];
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
        ],
        child: Consumer(builder: (context, ref, _) {
          router = ref.watch(appRouterProvider);
          router.routerDelegate.addListener(() => visited
              .add(router.routerDelegate.currentConfiguration.uri.path));
          return MaterialApp.router(
            theme: AppTheme.light(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          );
        }),
      ));

      // Splash dwell passes (1.3s) but the profile has not arrived.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
      expect(router.routerDelegate.currentConfiguration.uri.path, '/splash');
      expect(visited, isNot(contains('/onboarding')));

      // The fallback bound is 5s: dispose the router's timer by finishing the
      // test before it, after proving the hold. Release leaves splash.
      profiles.release();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final after = router.routerDelegate.currentConfiguration.uri.path;
      expect(after, isNot('/splash'));
      expect(visited, isNot(contains('/onboarding')));

      // Unmount so the router's providers dispose before the test ends.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
