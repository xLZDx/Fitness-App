import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_app.dart';
import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
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

    test('other paths are unaffected, including /coaches', () {
      for (final p in [
        '/home',
        '/profile',
        '/coaches',
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
      expect(isDemoGatedPath('/coaches'), isFalse);
      expect(isDemoGatedPath('/team'), isFalse);
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
