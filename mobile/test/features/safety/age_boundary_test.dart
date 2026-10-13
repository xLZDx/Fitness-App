// Decision A: an age derived from a birth YEAR only (no month) must resolve the
// boundary year on the cautious side. Someone born in December 2008 is 17 on
// 1 January 2026 although `2026 - 2008 = 18`; the old arithmetic let them into
// the adults-only body scan and off the minor training path.
//
// Every expectation is a literal number or band. The result may only depend on
// the calendar YEAR of the clock, never on the month or day.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/home/data/suggestion_builder.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/progress_photos/data/photo_consent.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import 'package:fitness_app/features/safety/data/age_policy.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';

final _clocks = [
  DateTime(2026, 1, 1),
  DateTime(2026, 6, 15),
  DateTime(2026, 12, 31),
];

UserProfile _profile(int? birthYear) => UserProfile.empty('u1').copyWith(
      personal: PersonalInfo(birthYear: birthYear),
      completedAt: DateTime(2026, 1, 1),
    );

ExerciseItem _ex(String id, String muscle, {bool stretch = false}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      muscles: [muscle],
      primaryMuscles: [muscle],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 10,
      summary: '',
      steps: const [],
      contraindications: const [],
      isStretch: stretch,
      vendorGroup: stretch ? 'Stretching - Mobility' : null,
    );

void main() {
  group('lowestAgeAt / ageBandForPersonal table (all three clock days)', () {
    // year difference -> (lowest age, band)
    final rows = <int, (int, AgeBand)>{
      0: (-1, AgeBand.minor),
      15: (14, AgeBand.minor),
      16: (15, AgeBand.minor),
      17: (16, AgeBand.minor),
      18: (17, AgeBand.minor),
      19: (18, AgeBand.adult),
      20: (19, AgeBand.adult),
      64: (63, AgeBand.adult),
      65: (64, AgeBand.senior),
      66: (65, AgeBand.senior),
    };

    for (final clock in _clocks) {
      for (final e in rows.entries) {
        test('${clock.toIso8601String().substring(0, 10)} difference ${e.key}',
            () {
          final p = PersonalInfo(birthYear: clock.year - e.key);
          expect(p.lowestAgeAt(clock.year), e.value.$1);
          expect(p.ageAt(clock.year), e.key);
          expect(ageBandForPersonal(p, clock.year), e.value.$2);
        });
      }
    }

    test('the band is identical on all three clock days of the year', () {
      for (final diff in rows.keys) {
        final bands = {
          for (final c in _clocks)
            ageBandForPersonal(PersonalInfo(birthYear: c.year - diff), c.year)
        };
        expect(bands, {rows[diff]!.$2}, reason: 'difference $diff');
      }
    });
  });

  group('unknown, legacy stored age and future birth year', () {
    test('no birth year and no stored age: unknown, adult', () {
      const p = PersonalInfo();
      expect(p.lowestAgeAt(2026), isNull);
      expect(ageBandForPersonal(p, 2026), AgeBand.adult);
      expect(ageBandForPersonal(null, 2026), AgeBand.adult);
    });

    test('legacy stored age: lowestAgeAt == ageAt and the plain bands apply', () {
      for (final (age, band) in [
        (17, AgeBand.minor),
        (18, AgeBand.adult),
        (65, AgeBand.senior),
      ]) {
        final p = PersonalInfo(age: age);
        expect(p.lowestAgeAt(2026), age);
        expect(p.lowestAgeAt(2026), p.ageAt(2026));
        expect(ageBandForPersonal(p, 2026), band, reason: 'stored age $age');
      }
    });

    test('a future birth year is the cautious minor band', () {
      const p = PersonalInfo(birthYear: 2030);
      expect(p.lowestAgeAt(2026), -5);
      expect(ageBandForPersonal(p, 2026), AgeBand.minor);
    });
  });

  group('scanAccessProvider (real provider, moving clock)', () {
    ProviderContainer make({
      String? uid = 'u1',
      int? birthYear,
      required DateTime now,
    }) {
      final c = ProviderContainer(overrides: [
        scanAccessClockProvider.overrideWithValue(() => now),
        authUserProvider.overrideWith((_) => Stream.value(
            uid == null ? null : AuthUser(uid: uid, displayName: 'x'))),
        currentProfileProvider.overrideWith((_) => Stream.value(UserProfile(
            uid: 'u1', personal: PersonalInfo(birthYear: birthYear)))),
        effectiveTierProvider.overrideWithValue(SubscriptionTier.standard),
        photoConsentStoreProvider.overrideWith(
            (_) async => InMemoryPhotoConsentStore(accepted: true)),
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

    for (final d in _clocks) {
      test('birthYear 2008 is underage on ${d.toIso8601String().substring(0, 10)}',
          () async {
        expect(await access(make(birthYear: 2008, now: d)), ScanAccess.underage);
      });
      test('birthYear 2007 is allowed on ${d.toIso8601String().substring(0, 10)}',
          () async {
        expect(await access(make(birthYear: 2007, now: d)), ScanAccess.allowed);
      });
    }

    test('birthYear 2008 is allowed on 2027-01-01', () async {
      expect(await access(make(birthYear: 2008, now: DateTime(2027, 1, 1))),
          ScanAccess.allowed);
    });

    test('birthYear null is ageUnknown', () async {
      expect(await access(make(birthYear: null, now: DateTime(2026, 6, 15))),
          ScanAccess.ageUnknown);
    });

    test('signed out wins first, even for an underage profile', () async {
      expect(
          await access(
              make(uid: null, birthYear: 2008, now: DateTime(2026, 6, 15))),
          ScanAccess.signedOut);
    });
  });

  group('safetyContextFor at 2026-01-01', () {
    final now = DateTime(2026, 1, 1);
    for (final (year, band) in [
      (2008, AgeBand.minor),
      (2007, AgeBand.adult),
      (1961, AgeBand.senior),
      (1962, AgeBand.adult),
    ]) {
      test('birthYear $year -> $band', () {
        expect(safetyContextFor(_profile(year), now: now).ageBand, band);
      });
    }
  });

  group('programmeDaysPerWeek(5) at 2026-01-01', () {
    final now = DateTime(2026, 1, 1);
    for (final (year, days) in [(2008, 4), (2007, 5), (1961, 3), (1962, 5)]) {
      test('birthYear $year -> $days days', () {
        expect(programmeDaysPerWeek(5, _profile(year), now: now), days);
      });
    }
  });

  group('buildSuggestions senior balance/mobility follows the same rule', () {
    // squat comes first in catalogue order and scores 0 for everyone; the
    // stretch scores +2 only for the senior band, which moves it to the front.
    List<String> order(int birthYear, DateTime now) => [
          for (final s in buildSuggestions(
            candidates: [
              _ex('squat', 'quads'),
              _ex('stretch', 'hamstrings', stretch: true),
            ],
            profile: _profile(birthYear),
            recentLogs: const [],
            now: now,
          ))
            s.exerciseId
        ];

    test('birthYear 1961 at 2026-01-01 (difference 65) is senior: mobility first',
        () {
      expect(order(1961, DateTime(2026, 1, 1)), ['stretch', 'squat']);
    });
    test('birthYear 1961 at 2025-12-31 (difference 64) is adult: catalogue order',
        () {
      expect(order(1961, DateTime(2025, 12, 31)), ['squat', 'stretch']);
    });
    test('birthYear 1962 at 2026-12-31 (difference 64) is adult', () {
      expect(order(1962, DateTime(2026, 12, 31)), ['squat', 'stretch']);
    });
    test('the senior result is identical on all three clock days of 2026', () {
      for (final c in _clocks) {
        expect(order(1961, c), ['stretch', 'squat'], reason: '$c');
      }
    });
  });
}
