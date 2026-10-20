import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// E2 / ONB-08: `/nutrition/profile` lives outside the onboarding redirect for
/// users who finished onboarding, and finished users are never routed back to
/// `/onboarding` because their nutrition block is empty.
void main() {
  late MockAuthRepository auth;
  late MockProfileRepository profiles;
  late String uid;

  setUp(() async {
    auth = MockAuthRepository(latency: Duration.zero);
    profiles = MockProfileRepository(latency: Duration.zero);
    uid = (await auth.signInAnonymously()).uid;
  });

  tearDown(() {
    auth.dispose();
    profiles.dispose();
  });

  Future<void> seed(UserProfile p) => profiles.save(p);

  const paths = [
    '/nutrition/profile',
    '/home',
    '/plan',
    '/nutrition',
    '/body-scan',
    '/body-scan?scanId=abc',
  ];

  group('a user who finished onboarding (completedAt set)', () {
    test('is not redirected from /nutrition/profile with an empty nutrition '
        'block and no health answers', () async {
      await seed(UserProfile.empty(uid)
          .copyWith(completedAt: DateTime.utc(2026, 9, 1)));
      expect(profiles.cached(uid)!.nutrition, NutritionPrefs.empty);
      expect(redirectFor(auth, profiles, '/nutrition/profile'), isNull);
    });

    test('is never sent back to /onboarding from any nutrition or body-scan '
        'location, loaded or not', () async {
      await seed(UserProfile.empty(uid)
          .copyWith(completedAt: DateTime.utc(2026, 9, 1)));
      for (final loaded in [true, false]) {
        for (final p in paths) {
          final target = redirectFor(auth, profiles, p, profileLoaded: loaded);
          expect(target, isNot('/onboarding'), reason: '$p loaded=$loaded');
          expect(target, isNot('/splash'),
              reason: '$p: a cached finished profile must not hold on splash');
        }
      }
    });

    test('redirectFor is unchanged for the old paths: an onboarded user '
        'opening /onboarding still bounces to /home', () async {
      await seed(UserProfile.empty(uid)
          .copyWith(completedAt: DateTime.utc(2026, 9, 1)));
      expect(redirectFor(auth, profiles, '/onboarding'), '/home');
      // The edit entry stays reachable for an onboarded user.
      expect(redirectFor(auth, profiles, '/onboarding/edit'), isNull);
    });

    test('pure resolver agrees (signed in, onboarded)', () {
      for (final p in paths) {
        expect(
            resolveRedirect(
              isSignedIn: true,
              isOnboarded: true,
              isAnonymous: false,
              location: p,
              demoFeaturesEnabled: false,
            ),
            isNot('/onboarding'),
            reason: p);
      }
    });
  });

  group('a user who has NOT finished onboarding', () {
    test('is still sent to /onboarding from /nutrition/profile (the flow is for '
        'finished users only)', () async {
      await seed(UserProfile.empty(uid));
      expect(redirectFor(auth, profiles, '/nutrition/profile'), '/onboarding');
    });

    test('a draft with nutrition answers but no completedAt is still '
        'incomplete', () async {
      await seed(UserProfile.empty(uid).copyWith(
          nutrition: NutritionPrefs(completedAt: DateTime.utc(2026, 10, 1))));
      expect(profiles.cached(uid)!.hasCompletedOnboarding, isFalse,
          reason: 'NutritionPrefs.completedAt must not complete onboarding');
      expect(redirectFor(auth, profiles, '/home'), '/onboarding');
    });

    test('signed out users go to the login gate, not the flow', () {
      final target = resolveRedirect(
        isSignedIn: false,
        isOnboarded: false,
        isAnonymous: false,
        location: '/nutrition/profile',
        demoFeaturesEnabled: false,
      );
      expect(target, isNotNull);
      expect(target, isNot('/nutrition/profile'));
    });
  });

  group('route registration', () {
    test('app_router.dart registers /nutrition/profile exactly once, with the '
        'flow page', () {
      final src = File('lib/core/router/app_router.dart').readAsStringSync();
      expect(RegExp(r"path: '/nutrition/profile'").allMatches(src), hasLength(1));
      expect(src, contains('NutritionProfileFlowPage()'));
    });
  });
}
