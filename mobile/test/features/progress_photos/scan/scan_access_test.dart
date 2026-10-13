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

// Fixed "now": only the stored birth YEAR is known, so the gate uses the LOWEST
// age that year allows (now.year - birthYear - 1): the boundary year counts as
// the safer (underage) side. Literal birth years below do not depend on the
// wall clock.
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

    test('under 18 without consent is underage, with and without supporter',
        () {
      expect(run(age: 17, consent: false), ScanAccess.underage);
      expect(run(age: 17, supporter: false, consent: false),
          ScanAccess.underage);
      expect(run(age: 0, consent: false), ScanAccess.underage);
    });

    test('unknown age without consent is ageUnknown, supporter or not', () {
      expect(run(age: null, consent: false), ScanAccess.ageUnknown);
      expect(run(age: null, supporter: false, consent: false),
          ScanAccess.ageUnknown);
    });

    test('signed out wins over every other refusal, for every age', () {
      for (final age in <int?>[null, 0, 17, 18, 60]) {
        expect(
            run(signedIn: false, age: age, supporter: false, consent: false),
            ScanAccess.signedOut,
            reason: 'age $age');
        expect(run(signedIn: false, age: age), ScanAccess.signedOut,
            reason: 'age $age with everything else in order');
      }
    });

    test('the full 2x5x2x2 table matches the documented priority order', () {
      // Independent oracle: first matching refusal in the documented order
      // signed out > under 18 > unknown age > not supporter > no consent.
      ScanAccess expected(bool signedIn, int? age, bool supporter, bool consent) {
        final refusals = <(bool, ScanAccess)>[
          (!signedIn, ScanAccess.signedOut),
          (age != null && age < 18, ScanAccess.underage),
          (age == null, ScanAccess.ageUnknown),
          (!supporter, ScanAccess.needsSupporter),
          (!consent, ScanAccess.needsConsent),
        ];
        for (final (hit, result) in refusals) {
          if (hit) return result;
        }
        return ScanAccess.allowed;
      }

      var rows = 0;
      final seen = <ScanAccess>{};
      for (final signedIn in [true, false]) {
        for (final age in <int?>[null, 5, 17, 18, 45]) {
          for (final supporter in [true, false]) {
            for (final consent in [true, false]) {
              final got = run(
                  signedIn: signedIn,
                  age: age,
                  supporter: supporter,
                  consent: consent);
              expect(got, expected(signedIn, age, supporter, consent),
                  reason:
                      'signedIn=$signedIn age=$age supporter=$supporter consent=$consent');
              seen.add(got);
              rows++;
            }
          }
        }
      }
      expect(rows, 40);
      expect(seen, ScanAccess.values.toSet(),
          reason: 'every outcome is reachable, so the table is not vacuous');
    });
  });

  group('scanAccessProvider wiring', () {
    ProviderContainer make({
      String? uid = 'u1',
      int? birthYear,
      SubscriptionTier tier = SubscriptionTier.standard,
      bool consent = true,
      DateTime? now,
    }) {
      final clock = now ?? fixedNow;
      final c = ProviderContainer(overrides: [
        scanAccessClockProvider.overrideWithValue(() => clock),
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
    test(
        'birth-year boundary with a fixed now (2026-10-13): 2008 may still be 17, '
        '2007 is at least 18', () async {
      // Changed by the boundary-year decision: 2008 used to be allowed.
      expect(await access(make(birthYear: 2008)), ScanAccess.underage);
      expect(await access(make(birthYear: 2007)), ScanAccess.allowed);
      expect(await access(make(birthYear: 2009)), ScanAccess.underage);
    });

    group('December-2008 case through the real provider and a moving clock', () {
      // Born December 2008: 17 until 1 Dec 2026, so NOT an adult at any point
      // of 2026, and only certainly 18 from 1 Jan 2027. Fails if the provider
      // goes back to the calendar-year difference (`ageAt`).
      for (final d in [
        DateTime(2026, 1, 1),
        DateTime(2026, 6, 15),
        DateTime(2026, 12, 31),
      ]) {
        test('birthYear 2008 on ${d.toIso8601String().substring(0, 10)} is underage',
            () async {
          expect(await access(make(birthYear: 2008, now: d)),
              ScanAccess.underage);
        });
      }
      test('birthYear 2008 becomes allowed on 2027-01-01', () async {
        expect(await access(make(birthYear: 2008, now: DateTime(2027, 1, 1))),
            ScanAccess.allowed);
      });
      test('birthYear 2007 is allowed from 2026-01-01 through 2026-12-31',
          () async {
        for (final d in [
          DateTime(2026, 1, 1),
          DateTime(2026, 6, 15),
          DateTime(2026, 12, 31),
        ]) {
          expect(await access(make(birthYear: 2007, now: d)),
              ScanAccess.allowed,
              reason: '$d');
        }
      });
      test('birthYear null is ageUnknown on every clock', () async {
        for (final d in [DateTime(2026, 1, 1), DateTime(2027, 1, 1)]) {
          expect(await access(make(birthYear: null, now: d)),
              ScanAccess.ageUnknown);
        }
      });
      test('signed out still wins first, even for the December-2008 user',
          () async {
        expect(
            await access(make(
                uid: null,
                birthYear: 2008,
                now: DateTime(2026, 6, 15),
                tier: SubscriptionTier.free,
                consent: false)),
            ScanAccess.signedOut);
      });
      test('supporter tier and accepted consent do not rescue a possible minor',
          () async {
        expect(
            await access(make(
                birthYear: 2008,
                now: DateTime(2026, 12, 31),
                tier: SubscriptionTier.standard,
                consent: true)),
            ScanAccess.underage);
      });
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
    test('under 18 and without consent is underage, not needsConsent',
        () async {
      expect(await access(make(birthYear: 2010, consent: false)),
          ScanAccess.underage);
      expect(
          await access(make(
              birthYear: 2010, consent: false, tier: SubscriptionTier.free)),
          ScanAccess.underage);
    });
    test('signed out under 18 without consent is signedOut', () async {
      expect(
          await access(make(
              uid: null,
              birthYear: 2010,
              consent: false,
              tier: SubscriptionTier.free)),
          ScanAccess.signedOut);
    });
    test('unknown age without consent is ageUnknown', () async {
      expect(await access(make(birthYear: null, consent: false)),
          ScanAccess.ageUnknown);
    });
    test('free tier without consent is needsSupporter, not needsConsent',
        () async {
      expect(
          await access(make(
              birthYear: adultYear,
              consent: false,
              tier: SubscriptionTier.free)),
          ScanAccess.needsSupporter);
    });
    test('signed out with null age is signedOut', () async {
      expect(await access(make(uid: null, birthYear: null)),
          ScanAccess.signedOut);
    });
  });
}
