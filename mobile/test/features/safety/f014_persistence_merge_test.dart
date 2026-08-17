import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/profile/data/device_health_profile_repository.dart';
import 'package:fitness_app/features/profile/data/local_sensitive_store.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/data/sensitive_profile.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

/// F014b — the block must survive the trip through storage, not just the trip
/// through `toJson`.
///
/// `f014_professional_guidance_test.dart` already covers serialisation. Every
/// test in it builds a [HealthFlags] or a [SafetyContext] directly, so none of
/// them crosses `mergeSensitive` — and that is where the answer was being lost.
///
/// The chain that loses it:
///
/// ```text
/// HealthFlags.operator ==   omits professionalGuidance
///   -> HealthFlags(reported) == HealthFlags.empty      is true
///   -> HealthHistory.isEmpty                            is true
///   -> SensitiveProfile.isEmpty                         is true
///   -> mergeSensitive returns the SERVER profile
///   -> the locally stored answer is discarded
/// ```
///
/// The user this hits hardest is the one who answered the single question that
/// blocks them and nothing else: their health block contains exactly one fact,
/// and one fact is what the equality cannot see. That is the opposite of
/// fail-closed, which is why it is a defect rather than a tidiness complaint.

class _RecordingRepository implements ProfileRepository {
  UserProfile? stored;

  @override
  Stream<UserProfile?> watch(String uid) => Stream.value(stored);

  @override
  UserProfile? cached(String uid) => stored;

  @override
  Future<UserProfile?> load(String uid) async => stored;

  @override
  Future<void> save(UserProfile profile) async => stored = profile;

  @override
  Future<void> delete(String uid) async => stored = null;
}

/// A profile whose ONLY health answer is the F014 chip.
///
/// Deliberately minimal. Adding any second answer — one injury, one condition,
/// a blood-pressure value — makes `isEmpty` false through a field the equality
/// does check, and the bug disappears. The test is only load-bearing while this
/// profile stays this bare.
UserProfile _onlyGuidance(String uid) => UserProfile(
      uid: uid,
      personal: const PersonalInfo(age: 34, heightCm: 181),
      health: const HealthHistory(
        flags: HealthFlags(
          professionalGuidance: ProfessionalGuidanceNeed.reported,
        ),
      ),
    );

void main() {
  group('F014 answer survives storage', () {
    test('a reported need is not equal to no answer at all', () {
      const reported = HealthFlags(
        professionalGuidance: ProfessionalGuidanceNeed.reported,
      );
      const declined = HealthFlags(
        professionalGuidance: ProfessionalGuidanceNeed.none,
      );

      // The three states must be mutually distinguishable by ==, because
      // downstream code asks "is anything stored?" by comparing to empty.
      expect(reported, isNot(equals(HealthFlags.empty)));
      expect(declined, isNot(equals(HealthFlags.empty)));
      expect(reported, isNot(equals(declined)));
    });

    test('and hashCode agrees, so a set or map cannot collapse them', () {
      const reported = HealthFlags(
        professionalGuidance: ProfessionalGuidanceNeed.reported,
      );
      // Not strictly required by the == contract, but a hashCode that ignores
      // a field == looks at makes Set/Map behaviour depend on bucket order.
      expect(reported.hashCode, isNot(equals(HealthFlags.empty.hashCode)));
      expect({reported, HealthFlags.empty}, hasLength(2));
    });

    test('a health block holding only the F014 answer is not empty', () {
      const h = HealthHistory(
        flags: HealthFlags(
          professionalGuidance: ProfessionalGuidanceNeed.reported,
        ),
      );
      expect(h.isEmpty, isFalse);
      expect(SensitiveProfile(health: h).isEmpty, isFalse);
    });

    test('the merge keeps it instead of falling back to the server copy', () {
      final local = _onlyGuidance('u1');
      final server = stripSensitive(local);

      final merged = mergeSensitive(server, extractSensitive(local));

      expect(
        merged.health.flags.professionalGuidance,
        ProfessionalGuidanceNeed.reported,
      );
    });

    test('it is still there after a save/load round trip', () async {
      final inner = _RecordingRepository();
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      await repo.save(_onlyGuidance('u1'));
      final back = (await repo.load('u1'))!;

      expect(
        back.health.flags.professionalGuidance,
        ProfessionalGuidanceNeed.reported,
      );
      // And the server copy still must not carry it.
      expect(inner.stored!.health.flags.professionalGuidance, isNull);
    });

    /// The consequence, stated as the bypass it is.
    ///
    /// A clear PAR-Q is what makes this the whole bypass rather than half of
    /// one. While the user is unscreened the app refuses anyway, so losing the
    /// F014 answer changes only which surfaces hide. Once they screen clean —
    /// which the app actively asks them to do — the screening no longer
    /// refuses, and the one answer that should still refuse is no longer
    /// there. Training is authorised for a user who said they need
    /// professional guidance first.
    test('a clean screening does not authorise training after the round trip',
        () async {
      final inner = _RecordingRepository();
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      await repo.save(_onlyGuidance('u1'));
      final back = (await repo.load('u1'))!;

      final safety = SafetyContext(
        screening: screen({for (final q in ParQQuestion.values) q: false}),
        health: back.health.flags,
      );

      // The gate is not "the field is present" but "the app still refuses",
      // and those are different claims.
      expect(safety.allowsAnyTraining, isFalse);
      expect(safety.blockedByAStatedAnswer, isTrue);
      expect(
        safety.wholePersonBlocks.map((r) => r.reason),
        contains(BlockReason.professionalGuidance),
      );
    });
  });
}
