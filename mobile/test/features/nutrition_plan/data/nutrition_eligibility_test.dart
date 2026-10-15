// T15 nutrition_eligibility_test (SAFE-01..SAFE-06, N-01..N-06). Every refusal,
// every boundary, and the first-match-wins order of the nine design rows
// (design s14). The verdict decides who may be shown ANY number, so each row
// has a dedicated fixture proving its position.
import 'package:fitness_app/features/nutrition_plan/data/missing_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_session.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fully valid adult (born 1985) with both safety questions answered "none".
UserProfile _profile({
  int? birthYear = 1985,
  int? storedAge,
  HealthFlags? flags,
  Gender? gender = Gender.male,
  SexAtBirth? sexAtBirth,
  int? heightCm = 180,
  double? weightKg = 80,
  ActivityLevel? activity = ActivityLevel.moderatelyActive,
}) =>
    UserProfile(
      uid: 'u',
      personal: PersonalInfo(
        age: storedAge,
        birthYear: birthYear,
        gender: gender,
        heightCm: heightCm,
        weightCurrentKg: weightKg,
        activityLevel: activity,
      ),
      health: HealthHistory(
        flags: flags ??
            const HealthFlags(
              nutritionGuidance: NutritionGuidanceNeed.none,
              professionalGuidance: ProfessionalGuidanceNeed.none,
            ),
      ),
      nutrition: NutritionPrefs(sexAtBirth: sexAtBirth),
    );

const _clear = HealthFlags(
  nutritionGuidance: NutritionGuidanceNeed.none,
  professionalGuidance: ProfessionalGuidanceNeed.none,
);

NutritionEligibility _eval(UserProfile p, [DateTime? now]) =>
    evaluateNutritionEligibility(p, now ?? DateTime(2026, 10, 15));

void expectRefer(NutritionEligibility v, ReferReason reason) {
  expect(v, isA<ReferProfessional>());
  expect((v as ReferProfessional).reason, reason);
  expect(v.allowsNumbers, isFalse);
}

void main() {
  group('baseline', () {
    test('a complete adult with both safety answers "none" is eligible', () {
      final v = _eval(_profile());
      expect(v, isA<Eligible>());
      expect(v.allowsNumbers, isTrue);
    });
    test('only Eligible allows numbers', () {
      expect(const Eligible().allowsNumbers, isTrue);
      expect(const ReferProfessional(ReferReason.guidance).allowsNumbers,
          isFalse);
      expect(const NeedsAnswer(NutritionQuestion.nutritionGuidance).allowsNumbers,
          isFalse);
      expect(const NeedsProfile([NutritionInput.height]).allowsNumbers,
          isFalse);
    });
  });

  group('SAFE-01 age (rows 1 and 2)', () {
    // PersonalInfo.lowestAgeAt(year) = year - birthYear - 1, so the verdict
    // depends on the CLOCK YEAR only: any day of 2026 gives the same answer.
    final clocks = [
      DateTime(2026, 1, 1),
      DateTime(2026, 6, 15),
      DateTime(2026, 12, 31, 23, 59),
    ];

    for (final now in clocks) {
      test('clock $now: birth year 2007 (lowest age 18) is eligible', () {
        expect(_eval(_profile(birthYear: 2007), now), isA<Eligible>());
      });
      test('clock $now: birth year 2008 (lowest age 17) is underAge', () {
        expectRefer(_eval(_profile(birthYear: 2008), now), ReferReason.underAge);
      });
      test('clock $now: 2009 and 2020 are underAge', () {
        expectRefer(_eval(_profile(birthYear: 2009), now), ReferReason.underAge);
        expectRefer(_eval(_profile(birthYear: 2020), now), ReferReason.underAge);
      });
    }

    test('the boundary moves with the clock YEAR: 2008 is eligible in 2027', () {
      expect(_eval(_profile(birthYear: 2008), DateTime(2027, 1, 1)),
          isA<Eligible>());
      expectRefer(_eval(_profile(birthYear: 2009), DateTime(2027, 1, 1)),
          ReferReason.underAge);
    });

    test('birth year in the future is refused as underAge', () {
      expectRefer(_eval(_profile(birthYear: 2030)), ReferReason.underAge);
    });

    test('N-02: birth year unknown and no stored age -> needsProfile(birthYear)', () {
      final v = _eval(_profile(birthYear: null));
      expect(v, isA<NeedsProfile>());
      expect((v as NeedsProfile).missing, [NutritionInput.birthYear]);
      expect(v.allowsNumbers, isFalse);
    });

    test('legacy stored whole-number age: 17 refused, 18 passes', () {
      expectRefer(_eval(_profile(birthYear: null, storedAge: 17)),
          ReferReason.underAge);
      expect(_eval(_profile(birthYear: null, storedAge: 18)), isA<Eligible>());
      expect(_eval(_profile(birthYear: null, storedAge: 16)), isA<ReferProfessional>());
      expect(_eval(_profile(birthYear: null, storedAge: 40)), isA<Eligible>());
    });

    test('the scan gate boundary agrees: 17 blocked, 18 allowed, null blocked', () {
      expect(scanAllowedForAge(17), isFalse);
      expect(scanAllowedForAge(18), isTrue);
      expect(scanAllowedForAge(null), isFalse);
      // and the nutrition gate on the same lowest-age figure:
      final p17 = _profile(birthYear: 2008);
      final p18 = _profile(birthYear: 2007);
      expect(scanAllowedForAge(p17.personal.lowestAgeAt(2026)), isFalse);
      expect(scanAllowedForAge(p18.personal.lowestAgeAt(2026)), isTrue);
      expect(_eval(p17).allowsNumbers, isFalse);
      expect(_eval(p18).allowsNumbers, isTrue);
    });
  });

  group('SAFE-02 pregnancy / breastfeeding flag (row 3)', () {
    test('professionalGuidance reported -> referProfessional(guidance)', () {
      final v = _eval(_profile(
          flags: const HealthFlags(
        nutritionGuidance: NutritionGuidanceNeed.none,
        professionalGuidance: ProfessionalGuidanceNeed.reported,
      )));
      expectRefer(v, ReferReason.guidance);
    });
    test('also when every other field is valid and the user is 40', () {
      final v = _eval(_profile(
        birthYear: 1986,
        sexAtBirth: SexAtBirth.female,
        flags: const HealthFlags(
          nutritionGuidance: NutritionGuidanceNeed.none,
          professionalGuidance: ProfessionalGuidanceNeed.reported,
          clinicianAdvice: ClinicianExerciseAdvice.noLimitsGiven,
          surgery: SurgeryStatus.none,
        ),
      ));
      expectRefer(v, ReferReason.guidance);
    });
    test('the verdict does not depend on the numeric inputs', () {
      final v = _eval(_profile(
        heightCm: null,
        weightKg: null,
        activity: null,
        gender: null,
        flags: const HealthFlags(
          nutritionGuidance: NutritionGuidanceNeed.none,
          professionalGuidance: ProfessionalGuidanceNeed.reported,
        ),
      ));
      expectRefer(v, ReferReason.guidance);
    });
  });

  group('SAFE-03 eating-disorder history / supervised nutrition (row 4)', () {
    test('nutritionGuidance reported -> referProfessional(guidance)', () {
      final v = _eval(_profile(
          flags: const HealthFlags(
        nutritionGuidance: NutritionGuidanceNeed.reported,
        professionalGuidance: ProfessionalGuidanceNeed.none,
      )));
      expectRefer(v, ReferReason.guidance);
    });
    test('even when the pregnancy answer is none and the user is 40', () {
      final v = _eval(_profile(
        birthYear: 1986,
        flags: const HealthFlags(
          nutritionGuidance: NutritionGuidanceNeed.reported,
          professionalGuidance: ProfessionalGuidanceNeed.none,
        ),
      ));
      expectRefer(v, ReferReason.guidance);
    });
    test('even when the pregnancy question was never answered', () {
      final v = _eval(_profile(
          flags: const HealthFlags(
        nutritionGuidance: NutritionGuidanceNeed.reported,
      )));
      expectRefer(v, ReferReason.guidance); // row 4 before row 7
    });
    test('the reason is a generic closed value that names no condition', () {
      for (final r in ReferReason.values) {
        expect(r.name, isNot(contains('eating')));
        expect(r.name, isNot(contains('pregnan')));
        expect(r.name, isNot(contains('disorder')));
      }
      expect(ReferReason.values.map((e) => e.name).toSet(),
          {'underAge', 'guidance', 'clinician'});
    });
  });

  group('SAFE-04 clinician advice and surgery (row 5)', () {
    test('advisedAgainstExercise -> referProfessional(clinician)', () {
      final v = _eval(_profile(
          flags: _clear.copyWith(
              clinicianAdvice: ClinicianExerciseAdvice.advisedAgainstExercise)));
      expectRefer(v, ReferReason.clinician);
    });
    test('surgery underRestrictions -> referProfessional(clinician)', () {
      final v = _eval(_profile(
          flags: _clear.copyWith(surgery: SurgeryStatus.underRestrictions)));
      expectRefer(v, ReferReason.clinician);
    });
    test('other clinician answers do not refuse', () {
      for (final a in ClinicianExerciseAdvice.values) {
        if (a == ClinicianExerciseAdvice.advisedAgainstExercise) continue;
        expect(_eval(_profile(flags: _clear.copyWith(clinicianAdvice: a))),
            isA<Eligible>(),
            reason: a.name);
      }
    });
    test('other surgery answers do not refuse', () {
      for (final s in SurgeryStatus.values) {
        if (s == SurgeryStatus.underRestrictions) continue;
        expect(_eval(_profile(flags: _clear.copyWith(surgery: s))),
            isA<Eligible>(),
            reason: s.name);
      }
    });
    test('blood pressure and movement restrictions are NOT nutrition exclusions', () {
      for (final b in BloodPressureStatus.values) {
        expect(_eval(_profile(flags: _clear.copyWith(bloodPressure: b))),
            isA<Eligible>(),
            reason: b.name);
      }
      expect(
        _eval(_profile(
            flags: _clear.copyWith(
                restrictions: {MovementRestriction.overhead}))),
        isA<Eligible>(),
      );
    });
    test('food allergens do not exclude', () {
      expect(
        _eval(_profile(
            flags: _clear.copyWith(
                foodAllergens: {FoodAllergen.peanuts, FoodAllergen.gluten}))),
        isA<Eligible>(),
      );
    });
  });

  group('SAFE-05 unanswered safety questions lock the coach (rows 6, 7)', () {
    test('nutritionGuidance null -> needsAnswer(nutritionGuidance), never clear', () {
      final v = _eval(_profile(
          flags: const HealthFlags(
              professionalGuidance: ProfessionalGuidanceNeed.none)));
      expect(v, isA<NeedsAnswer>());
      expect((v as NeedsAnswer).question, NutritionQuestion.nutritionGuidance);
      expect(v.allowsNumbers, isFalse);
    });
    test('professionalGuidance null -> needsAnswer(professionalGuidance)', () {
      final v = _eval(_profile(
          flags: const HealthFlags(
              nutritionGuidance: NutritionGuidanceNeed.none)));
      expect(v, isA<NeedsAnswer>());
      expect((v as NeedsAnswer).question, NutritionQuestion.professionalGuidance);
    });
    test('both null: the nutrition question is asked first (row 6 before 7)', () {
      final v = _eval(_profile(flags: HealthFlags.empty));
      expect((v as NeedsAnswer).question, NutritionQuestion.nutritionGuidance);
    });
    test('an old profile with every OTHER flag answered but the new question null is locked', () {
      final v = _eval(_profile(
        flags: const HealthFlags(
          professionalGuidance: ProfessionalGuidanceNeed.none,
          clinicianAdvice: ClinicianExerciseAdvice.noLimitsGiven,
          surgery: SurgeryStatus.none,
          bloodPressure: BloodPressureStatus.noKnownIssue,
        ),
      ));
      expect(v, isA<NeedsAnswer>());
    });
    test('no number can come out of an unanswered profile (allowsNumbers false)', () {
      expect(_eval(_profile(flags: HealthFlags.empty)).allowsNumbers, isFalse);
    });
  });

  group('row 8 other inputs missing', () {
    test('height missing', () {
      final v = _eval(_profile(heightCm: null));
      expect((v as NeedsProfile).missing, [NutritionInput.height]);
    });
    test('weight missing', () {
      final v = _eval(_profile(weightKg: null));
      expect((v as NeedsProfile).missing, [NutritionInput.weight]);
    });
    test('currentWeightKg supplies a weight the profile lacks', () {
      final v = evaluateNutritionEligibility(
        _profile(weightKg: null),
        DateTime(2026, 10, 15),
        currentWeightKg: 79.5,
      );
      expect(v, isA<Eligible>());
    });
    test('sex basis missing (no gender, no sexAtBirth)', () {
      final v = _eval(_profile(gender: null));
      expect((v as NeedsProfile).missing, [NutritionInput.sexBasis]);
    });
    test('sexAtBirth alone satisfies the sex basis', () {
      expect(_eval(_profile(gender: null, sexAtBirth: SexAtBirth.female)),
          isA<Eligible>());
    });
    test('activity missing', () {
      final v = _eval(_profile(activity: null));
      expect((v as NeedsProfile).missing, [NutritionInput.activity]);
    });
    test('several missing are listed in the flow order', () {
      final v = _eval(_profile(
          heightCm: null, weightKg: null, gender: null, activity: null));
      expect((v as NeedsProfile).missing, [
        NutritionInput.height,
        NutritionInput.weight,
        NutritionInput.sexBasis,
        NutritionInput.activity,
      ]);
    });
  });

  group('SAFE-06 evaluation order, first match wins (one fixture per row)', () {
    test('row 1 beats everything: unknown age + reported guidance + clinician', () {
      final v = _eval(_profile(
        birthYear: null,
        flags: const HealthFlags(
          nutritionGuidance: NutritionGuidanceNeed.reported,
          professionalGuidance: ProfessionalGuidanceNeed.reported,
          clinicianAdvice: ClinicianExerciseAdvice.advisedAgainstExercise,
        ),
      ));
      expect(v, isA<NeedsProfile>());
      expect((v as NeedsProfile).missing, [NutritionInput.birthYear]);
    });
    test('row 2 beats row 3: 17 AND reported guidance -> underAge', () {
      final v = _eval(_profile(
        birthYear: 2008,
        flags: const HealthFlags(
          nutritionGuidance: NutritionGuidanceNeed.reported,
          professionalGuidance: ProfessionalGuidanceNeed.reported,
        ),
      ));
      expectRefer(v, ReferReason.underAge);
    });
    test('row 3 and row 4 give the same generic reason', () {
      expectRefer(
          _eval(_profile(
              flags: _clear.copyWith(
                  professionalGuidance: ProfessionalGuidanceNeed.reported))),
          ReferReason.guidance);
      expectRefer(
          _eval(_profile(
              flags: _clear.copyWith(
                  nutritionGuidance: NutritionGuidanceNeed.reported))),
          ReferReason.guidance);
    });
    test('rows 3-5 beat row 6: guidance reported AND nutrition question unanswered', () {
      final v = _eval(_profile(
          flags: const HealthFlags(
              professionalGuidance: ProfessionalGuidanceNeed.reported)));
      expectRefer(v, ReferReason.guidance);
    });
    test('row 4 beats row 5: guidance reported AND clinician advice -> guidance', () {
      final v = _eval(_profile(
          flags: _clear.copyWith(
        nutritionGuidance: NutritionGuidanceNeed.reported,
        clinicianAdvice: ClinicianExerciseAdvice.advisedAgainstExercise,
      )));
      expectRefer(v, ReferReason.guidance);
    });
    test('row 5 beats row 6: clinician advice AND nutrition question unanswered', () {
      final v = _eval(_profile(
          flags: const HealthFlags(
        professionalGuidance: ProfessionalGuidanceNeed.none,
        surgery: SurgeryStatus.underRestrictions,
      )));
      expectRefer(v, ReferReason.clinician);
    });
    test('row 6 beats row 7 and row 8', () {
      final v = _eval(_profile(
          heightCm: null, flags: HealthFlags.empty));
      expect((v as NeedsAnswer).question, NutritionQuestion.nutritionGuidance);
    });
    test('row 7 beats row 8', () {
      final v = _eval(_profile(
        heightCm: null,
        flags: const HealthFlags(
            nutritionGuidance: NutritionGuidanceNeed.none),
      ));
      expect((v as NeedsAnswer).question, NutritionQuestion.professionalGuidance);
    });
    test('row 8 beats row 9', () {
      expect(_eval(_profile(heightCm: null)), isA<NeedsProfile>());
    });
    test('row 9: eligible', () {
      expect(_eval(_profile()), isA<Eligible>());
    });
    test('the verdict is a pure function of the profile and the clock YEAR', () {
      final p = _profile(birthYear: 2007);
      expect(_eval(p, DateTime(2026, 3, 1)).runtimeType,
          _eval(p, DateTime(2026, 11, 30)).runtimeType);
    });
  });

  group('ReferProfessional.reasons', () {
    test('exposes exactly the first matching reason', () {
      const r = ReferProfessional(ReferReason.clinician);
      expect(r.reasons, [ReferReason.clinician]);
    });
  });
}
