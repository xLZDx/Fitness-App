import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/profile/data/profile_models.dart';

/// O4 turned `hasGymAccess` from a stored answer into a derived one.
///
/// That is the change with real risk attached, and none of it is visible on
/// screen: every profile written before O4 carries `hasGymAccess` and no
/// `location`. Had the field simply been replaced, those users would have
/// silently reverted to "equipment question unanswered" — no crash, no red
/// test, just a getter returning null where it used to return an answer.
void main() {
  group('a profile written before O4', () {
    test('keeps the gym answer it already had', () {
      const legacy = EquipmentAccess(hasGymAccess: true);
      expect(legacy.location, isNull);
      expect(legacy.hasGymAccess, isTrue);
    });

    test('keeps a negative answer too, which is the easier one to lose', () {
      // `false` and "never answered" are both falsy in a careless
      // implementation. They mean opposite things to a plan generator.
      const legacy = EquipmentAccess(hasGymAccess: false);
      expect(legacy.hasGymAccess, isFalse);
      expect(legacy.hasGymAccess, isNotNull);
    });

    test('is still distinguishable from a profile that answered nothing', () {
      expect(const EquipmentAccess().hasGymAccess, isNull);
    });
  });

  group('a place answered on the new screen', () {
    test('derives gym access, and wins over any stored legacy value', () {
      // The case that decides whether the getter is honest: an old profile said
      // "no gym", the user has now picked "at a gym". The new answer is the
      // true one; preferring the stored value would show them a plan built for
      // a living room.
      const updated = EquipmentAccess(
        location: TrainingLocation.gym,
        hasGymAccess: false,
      );
      expect(updated.hasGymAccess, isTrue);
    });

    test('mixed counts as gym access — it is half the week', () {
      const mixed = EquipmentAccess(location: TrainingLocation.mixed);
      expect(mixed.hasGymAccess, isTrue);
    });

    test('outdoor does not', () {
      const outdoor = EquipmentAccess(location: TrainingLocation.outdoor);
      expect(outdoor.hasGymAccess, isFalse);
    });

    test('every location maps to a definite answer', () {
      // A location that mapped to null would read as "unanswered" on a screen
      // the user had just answered.
      for (final loc in TrainingLocation.values) {
        expect(EquipmentAccess(location: loc).hasGymAccess, isNotNull,
            reason: loc.name);
      }
    });
  });

  group('copyWith', () {
    test('does not resurrect a legacy value over a chosen location', () {
      const legacy = EquipmentAccess(hasGymAccess: false);
      final updated = legacy.copyWith(location: TrainingLocation.gym);
      expect(updated.hasGymAccess, isTrue);
    });

    test('carries the legacy value through an unrelated edit', () {
      // Editing the free-text box must not wipe an answer the user gave months
      // ago on a screen that no longer exists.
      const legacy = EquipmentAccess(hasGymAccess: true);
      final updated = legacy.copyWith(homeEquipment: const ['резинки']);
      expect(updated.hasGymAccess, isTrue);
    });
  });

  group('gymId (MRD-02, Gate F)', () {
    test('unset by default, distinguishable from an empty answer', () {
      expect(const EquipmentAccess().gymId, isNull);
    });

    test('copyWith sets it without disturbing other fields', () {
      const before = EquipmentAccess(
        location: TrainingLocation.gym,
        available: [EquipmentKind.barbell],
      );
      final after = before.copyWith(gymId: 'Planet Fitness Downtown');
      expect(after.gymId, 'Planet Fitness Downtown');
      expect(after.location, TrainingLocation.gym,
          reason: 'copyWith must not disturb fields it was not given');
      expect(after.available, [EquipmentKind.barbell]);
    });

    test('copyWith can clear it to empty string (the onboarding field\'s '
        'own clear-the-text-box case), distinct from never having been set',
        () {
      const before = EquipmentAccess(gymId: 'Old Gym');
      final cleared = before.copyWith(gymId: '');
      expect(cleared.gymId, '',
          reason: 'an explicit empty string must stick, not fall back to '
              'the previous value — this is how the onboarding text field '
              'expresses "the user deleted what they typed"');
    });
  });

  group('serialisation', () {
    test('writes the derived answer, not the stored one', () {
      // Anything still reading `hasGymAccess` — an old export, a Cloud Function
      // — gets a true answer rather than a stale one.
      final p = UserProfile.empty('u').copyWith(
        equipment: const EquipmentAccess(
          location: TrainingLocation.home,
          hasGymAccess: true,
          available: [EquipmentKind.dumbbells, EquipmentKind.bands],
        ),
      );
      final eq = p.toJson()['equipment'] as Map<String, dynamic>;

      expect(eq['location'], 'home');
      expect(eq['hasGymAccess'], isFalse, reason: 'derived from home, not the '
          'stale stored true');
      expect(eq['available'], ['dumbbells', 'bands']);
    });

    test('an untouched profile writes nulls, not invented defaults', () {
      final eq =
          UserProfile.empty('u').toJson()['equipment'] as Map<String, dynamic>;
      expect(eq['location'], isNull);
      expect(eq['hasGymAccess'], isNull);
      expect(eq['available'], isEmpty);
      expect(eq['gymId'], isNull);
    });

    test('gymId round-trips through toJson (MRD-02, Gate F)', () {
      final p = UserProfile.empty('u').copyWith(
        equipment: const EquipmentAccess(
          location: TrainingLocation.gym,
          gymId: 'Iron Temple',
        ),
      );
      final eq = p.toJson()['equipment'] as Map<String, dynamic>;
      expect(eq['gymId'], 'Iron Temple');
    });
  });
}
