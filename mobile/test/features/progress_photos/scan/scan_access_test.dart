import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/progress_photos/data/photo_consent.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';

// Fixed "now": ages are year arithmetic (now.year - birthYear), so literal
// birth years below do not depend on the wall clock.
final fixedNow = DateTime(2026, 10, 13);

void main() {
  group('evaluateScanAccess priority table', () {
    ScanAccess run({
      bool signedIn = true,
      int? age = 30,
      bool supporter = true,
      bool consent = true,
    }) =>
        evaluateScanAccess(
            signedIn: signedIn,
            age: age,
            supporter: supporter,
            consentAccepted: consent);

    test('all good is allowed', () => expect(run(), ScanAccess.allowed));
    test('signed out beats everything', () {
      expect(run(signedIn: false, age: 10, supporter: false, consent: false),
          ScanAccess.signedOut);
    });
    test('underage beats supporter and consent', () {
      expect(
          run(age: 17, supporter: false, consent: false), ScanAccess.underage);
    });
    test('18 is allowed, 17 is not', () {
      expect(run(age: 18), ScanAccess.allowed);
      expect(run(age: 17), ScanAccess.underage);
    });
    test('unknown age beats supporter and consent', () {
      expect(run(age: null, supporter: false, consent: false),
          ScanAccess.ageUnknown);
    });
    test('needs supporter beats needs consent', () {
      expect(run(supporter: false, consent: false), ScanAccess.needsSupporter);
    });
    test('consent last', () {
      expect(run(consent: false), ScanAccess.needsConsent);
    });
  });

  group('scanAccessProvider wiring', () {
    ProviderContainer make({
      String? uid = 'u1',
      int? birthYear,
      SubscriptionTier tier = SubscriptionTier.standard,
      bool consent = true,
    }) {
      final c = ProviderContainer(overrides: [
        scanAccessClockProvider.overrideWithValue(() => fixedNow),
        authUserProvider.overrideWith((_) => Stream.value(
            uid == null ? null : AuthUser(uid: uid, displayName: 'x'))),
        currentProfileProvider.overrideWith((_) => Stream.value(UserProfile(
            uid: 'u1', personal: PersonalInfo(birthYear: birthYear)))),
        effectiveTierProvider.overrideWithValue(tier),
        photoConsentStoreProvider.overrideWith(
            (_) async => InMemoryPhotoConsentStore(accepted: consent)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<ScanAccess> access(ProviderContainer c) async {
      await c.read(authUserProvider.future);
      await c.read(currentProfileProvider.future);
      await c.read(scanConsentAcceptedProvider.future);
      return c.read(scanAccessProvider);
    }

    final adultYear = fixedNow.year - 30;
    final minorYear = fixedNow.year - 15;

    test('adult supporter with consent', () async {
      expect(await access(make(birthYear: adultYear)), ScanAccess.allowed);
    });
    test('signed out', () async {
      expect(await access(make(uid: null, birthYear: adultYear)),
          ScanAccess.signedOut);
    });
    test('minor', () async {
      expect(await access(make(birthYear: minorYear)), ScanAccess.underage);
    });
    test('no birth year', () async {
      expect(await access(make(birthYear: null)), ScanAccess.ageUnknown);
    });
    test('free tier', () async {
      expect(
          await access(
              make(birthYear: adultYear, tier: SubscriptionTier.free)),
          ScanAccess.needsSupporter);
    });
    test('no consent', () async {
      expect(await access(make(birthYear: adultYear, consent: false)),
          ScanAccess.needsConsent);
    });
    test('birth-year boundary with a fixed now: 2008 is 18, 2009 is 17', () async {
      expect(await access(make(birthYear: 2008)), ScanAccess.allowed);
      expect(await access(make(birthYear: 2009)), ScanAccess.underage);
    });
    test('a supporter with an under-18 profile is underage, not needsSupporter',
        () async {
      expect(
          await access(
              make(birthYear: 2010, tier: SubscriptionTier.standard)),
          ScanAccess.underage);
      expect(
          await access(make(birthYear: 2010, tier: SubscriptionTier.free)),
          ScanAccess.underage,
          reason: 'age is checked before the supporter tier');
    });
    test('unknown age beats needsSupporter through the provider', () async {
      expect(
          await access(make(birthYear: null, tier: SubscriptionTier.free)),
          ScanAccess.ageUnknown);
    });
    test('signed out with null age is signedOut', () async {
      expect(await access(make(uid: null, birthYear: null)),
          ScanAccess.signedOut);
    });
  });
}
