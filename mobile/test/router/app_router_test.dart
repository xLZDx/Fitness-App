import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

void main() {
  group('resolveRedirect (pure)', () {
    test('splash always passes through', () {
      expect(
          resolveRedirect(
              isSignedIn: false,
              isOnboarded: false,
              location: '/splash',
              isAnonymous: false),
          isNull);
      expect(
          resolveRedirect(
              isSignedIn: true,
              isOnboarded: true,
              location: '/splash',
              isAnonymous: false),
          isNull);
    });

    test('login is reachable when signed out', () {
      expect(
          resolveRedirect(
              isSignedIn: false,
              isOnboarded: false,
              location: '/login',
              isAnonymous: false),
          isNull);
    });

    test('signed-in user on /login bounces to /home when onboarded', () {
      expect(
        resolveRedirect(
            isSignedIn: true,
            isOnboarded: true,
            location: '/login',
            isAnonymous: false),
        '/home',
      );
    });

    test('signed-in user on /login bounces to /onboarding when not onboarded',
        () {
      expect(
        resolveRedirect(
            isSignedIn: true,
            isOnboarded: false,
            location: '/login',
            isAnonymous: false),
        '/onboarding',
      );
    });

    test('every gated tab redirects to /login when signed out', () {
      for (final p in [
        '/home',
        '/scan',
        '/workouts',
        '/progress',
        '/profile',
        '/onboarding'
      ]) {
        expect(
          resolveRedirect(
              isSignedIn: false,
              isOnboarded: false,
              location: p,
              isAnonymous: false),
          '/login',
          reason: 'gated path $p must redirect when signed out',
        );
      }
    });

    test('signed-in but not onboarded → forced into /onboarding', () {
      for (final p in [
        '/home',
        '/scan',
        '/workouts',
        '/progress',
        '/profile'
      ]) {
        expect(
          resolveRedirect(
              isSignedIn: true,
              isOnboarded: false,
              location: p,
              isAnonymous: false),
          '/onboarding',
          reason: '$p should redirect to /onboarding while not onboarded',
        );
      }
    });

    test('signed-in and onboarded passes through every tab', () {
      for (final p in [
        '/home',
        '/scan',
        '/workouts',
        '/progress',
        '/profile'
      ]) {
        expect(
          resolveRedirect(
              isSignedIn: true,
              isOnboarded: true,
              location: p,
              isAnonymous: false),
          isNull,
        );
      }
    });

    test('onboarded user landing on /onboarding is bounced to /home', () {
      expect(
        resolveRedirect(
            isSignedIn: true,
            isOnboarded: true,
            location: '/onboarding',
            isAnonymous: false),
        '/home',
      );
    });

    test(
        'onboarded user landing on /onboarding/edit is NOT bounced -- '
        'Profile\'s "edit your answers" tile must actually reach '
        'OnboardingPage', () {
      expect(
        resolveRedirect(
            isSignedIn: true,
            isOnboarded: true,
            location: '/onboarding/edit',
            isAnonymous: false),
        isNull,
      );
    });

    test('not-yet-onboarded user on /onboarding/edit is still forced into '
        'plain /onboarding', () {
      expect(
        resolveRedirect(
            isSignedIn: true,
            isOnboarded: false,
            location: '/onboarding/edit',
            isAnonymous: false),
        '/onboarding',
      );
    });

    test('a public page reaches a signed-in, not-yet-onboarded user', () {
      // Found reviewing L0a: /terms, /about, /donors and /licences are all
      // listed in _publicPaths, but before this the onboarding gate ignored
      // that list entirely and bounced every one of them to /onboarding
      // anyway -- directly contradicting the claim that a public page is
      // reachable regardless of sign-in state.
      for (final p in ['/terms', '/privacy', '/about', '/donors', '/licences']) {
        expect(
          resolveRedirect(
              isSignedIn: true,
              isOnboarded: false,
              location: p,
              isAnonymous: false),
          isNull,
          reason: '$p is public and must not force onboarding first',
        );
      }
    });
  });

  // The guest upgrade path. `linkWithCredential` keeps the SAME uid, so
  // reaching /login as a guest preserves the profile, injuries, history and
  // schedule already under `users/{uid}`. Signing out instead mints a fresh
  // uid on the next sign-in and orphans all of it, silently and permanently,
  // because an anonymous account has no credential to sign back in with.
  //
  // These cases are the difference between "already signed in, nothing to do"
  // and "already signed in, but with nothing to sign back in AS".
  group('resolveRedirect: a guest may reach /login', () {
    test('an anonymous user is NOT bounced away from /login', () {
      for (final onboarded in [false, true]) {
        expect(
          resolveRedirect(
              isSignedIn: true,
              isOnboarded: onboarded,
              location: '/login',
              isAnonymous: true),
          isNull,
          reason: 'an onboarded=$onboarded guest must still be able to link '
              'their account, which is only possible on /login',
        );
      }
    });

    test('a real identity is still bounced away from /login', () {
      // The exemption is for guests specifically. For a user who already has
      // a credential, /login genuinely has nothing to offer, and letting them
      // sit on a sign-in screen while signed in is the confusion the original
      // redirect existed to prevent.
      expect(
        resolveRedirect(
            isSignedIn: true,
            isOnboarded: true,
            location: '/login',
            isAnonymous: false),
        '/home',
      );
      expect(
        resolveRedirect(
            isSignedIn: false,
            isOnboarded: false,
            location: '/login',
            isAnonymous: false),
        isNull,
      );
    });

    test('the exemption does not leak into any other route', () {
      // A guest is a signed-in user everywhere else. If `isAnonymous` widened
      // any other gate, this would catch it: onboarding is still enforced,
      // and no gated tab opens early.
      for (final p in ['/home', '/scan', '/workouts', '/progress', '/profile']) {
        expect(
          resolveRedirect(
              isSignedIn: true,
              isOnboarded: false,
              location: p,
              isAnonymous: true),
          '/onboarding',
          reason: '$p must still force onboarding for a guest',
        );
        expect(
          resolveRedirect(
              isSignedIn: true,
              isOnboarded: true,
              location: p,
              isAnonymous: true),
          isNull,
        );
      }
      expect(
        resolveRedirect(
            isSignedIn: true,
            isOnboarded: true,
            location: '/onboarding',
            isAnonymous: true),
        '/home',
      );
    });

    test('an anonymous flag on a signed-out caller changes nothing', () {
      // Defensive: the caller derives `isAnonymous` from `user?.provider`, so
      // signed-out means false today. If that ever inverts, a signed-out user
      // must still be pushed to /login rather than into the app.
      for (final p in ['/home', '/profile', '/onboarding']) {
        expect(
          resolveRedirect(
              isSignedIn: false,
              isOnboarded: false,
              location: p,
              isAnonymous: true),
          '/login',
        );
      }
    });
  });

  group('appRouter integration', () {
    Widget buildApp({
      required MockAuthRepository auth,
      required MockProfileRepository profiles,
      void Function(GoRouter)? capture,
    }) {
      return ProviderScope(
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
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(appRouterProvider);
            capture?.call(router);
            return MaterialApp.router(
              theme: AppTheme.light(),
              locale: kTestLocale,
              localizationsDelegates: kTestLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            );
          },
        ),
      );
    }

    String pathOf(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

    testWidgets('boots to /splash, then redirects unsigned users to /login',
        (tester) async {
      late GoRouter router;
      await tester.pumpWidget(buildApp(
        auth: MockAuthRepository(latency: Duration.zero),
        profiles: MockProfileRepository(latency: Duration.zero),
        capture: (r) => router = r,
      ));
      await tester.pump();
      expect(pathOf(router), '/splash');

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
      expect(pathOf(router), '/login');
    });

    // D-03: `login_page_test.dart` proves the "Continue" button's own onTap
    // works when `LoginPage` is mounted directly under `MaterialApp`. It says
    // nothing about the button once it is reached the way a real device
    // reaches it -- through splash's redirect and the router's own
    // `_fadeThrough` CustomTransitionPage. If a stale transition layer, a
    // stuck animation, or anything else in that path were eating the tap,
    // this is the one test that would catch it and the isolated test above
    // would stay green regardless.
    testWidgets(
        'the Continue button still works after reaching /login through '
        'the real splash → redirect → fade-transition path', (tester) async {
      final auth = _RecordingMockAuth(latency: Duration.zero);
      late GoRouter router;
      await tester.pumpWidget(buildApp(
        auth: auth,
        profiles: MockProfileRepository(latency: Duration.zero),
        capture: (r) => router = r,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 600));
      expect(pathOf(router), '/login');

      // Let any in-flight page-transition animation fully settle before
      // tapping -- the device repro tapped anywhere from 2s to 15s after the
      // page appeared, so a mid-animation timing gap is not the point of
      // this test.
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(auth.anonymousCalls, 1,
          reason: 'the tap must reach LoginPage\'s onTap and call '
              'signInAnonymously exactly once, the same as the isolated '
              'widget test -- if this is 0, the router/transition layer is '
              'swallowing the gesture, not the button itself');
    });

  });

  // The pure tests above prove `resolveRedirect` DECIDES correctly about a
  // guest. They prove nothing about whether the router ever TELLS it who the
  // guest is: `isAnonymous:` is derived at exactly one place, and a constant
  // there passes every one of them while the door stays shut. `redirectFor`
  // is that derivation, split out precisely so it can be tested without
  // building `/home` — mounting the real router to check would drag the whole
  // app shell, and every provider behind it, into a unit test.
  group('redirectFor (the derivation, not the decision)', () {
    late MockAuthRepository auth;
    late MockProfileRepository profiles;

    setUp(() {
      auth = MockAuthRepository(latency: Duration.zero);
      profiles = MockProfileRepository(latency: Duration.zero);
    });

    tearDown(() {
      auth.dispose();
      profiles.dispose();
    });

    Future<void> onboard(String uid) =>
        profiles.save(UserProfile(uid: uid, completedAt: DateTime(2026, 8, 18)));

    test('a signed-out caller is sent to /login', () {
      expect(redirectFor(auth, profiles, '/home'), '/login');
      expect(redirectFor(auth, profiles, '/login'), isNull);
    });

    test('an onboarded guest reaches /login', () async {
      final guest = await auth.signInAnonymously();
      await onboard(guest.uid);
      expect(redirectFor(auth, profiles, '/home'), isNull,
          reason: 'an onboarded guest is a normal user everywhere else');
      expect(redirectFor(auth, profiles, '/login'), isNull,
          reason: 'the provider is read from the live AuthUser, so a guest '
              'must be recognised as one here and not only in the pure '
              'decision below it');
    });

    test('a not-yet-onboarded guest still reaches /login', () async {
      await auth.signInAnonymously();
      expect(redirectFor(auth, profiles, '/home'), '/onboarding');
      expect(redirectFor(auth, profiles, '/login'), isNull);
    });

    test('a Google user is still bounced off /login', () async {
      final user = (await auth.signInWithGoogle()).user;
      await onboard(user.uid);
      expect(redirectFor(auth, profiles, '/login'), '/home',
          reason: 'the exemption is for guests only; this is the case that '
              'fails if the derivation hard-codes isAnonymous to true');
    });

    test('linking a guest to Google closes the exemption again', () async {
      // The whole point of the exemption, end to end: the guest walks through
      // /login, `linkWithCredential` keeps the SAME uid, the profile written
      // under it survives, and the door shuts behind them.
      final guest = await auth.signInAnonymously();
      await onboard(guest.uid);
      expect(redirectFor(auth, profiles, '/login'), isNull);

      final linked = (await auth.signInWithGoogle()).user;
      expect(linked.uid, guest.uid, reason: 'link, do not replace');
      expect(profiles.cached(linked.uid)?.hasCompletedOnboarding, isTrue,
          reason: 'the data the exemption exists to save is still there');
      expect(redirectFor(auth, profiles, '/login'), '/home',
          reason: 'once they have a credential, /login has nothing to offer');
    });
  });
}

class _RecordingMockAuth extends MockAuthRepository {
  _RecordingMockAuth({super.latency});
  int anonymousCalls = 0;

  @override
  Future<AuthUser> signInAnonymously() {
    anonymousCalls += 1;
    return super.signInAnonymously();
  }
}
