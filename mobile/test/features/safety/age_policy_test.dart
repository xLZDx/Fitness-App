import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/home/data/suggestion_builder.dart';
import 'package:fitness_app/features/personalisation/data/recommendation_hints.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/data/programme_specs.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/age_policy.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';

/// WS6 part 1: the age policy, the cautious selection and the honest reasons.
ExerciseItem _ex(
  String id, {
  String title = '',
  ExerciseDifficulty difficulty = ExerciseDifficulty.beginner,
  String? group,
  bool stretch = false,
  List<String> contra = const [],
  int minutes = 10,
}) =>
    ExerciseItem(
      id: id,
      title: title.isEmpty ? id : title,
      equipmentId: null,
      muscles: const ['quads'],
      primaryMuscles: const ['quads'],
      difficulty: difficulty,
      durationMinutes: minutes,
      summary: '',
      steps: const [],
      contraindications: contra,
      isStretch: stretch,
      vendorGroup: group,
    );

const _noDeload =
    DeloadVerdict(shouldDeload: false, reasons: [], suggestedVolumeFactor: 1.0);

SafetyContext _ctx({
  AgeBand band = AgeBand.adult,
  bool gentle = false,
  List<Injury> injuries = const [],
}) =>
    SafetyContext(
      screening: screen({for (final q in ParQQuestion.values) q: false}),
      ageBand: band,
      gentleSelection: gentle,
      injuries: injuries,
    );

List<ExerciseItem> _pool() => [
      _ex('squat'),
      _ex('deadlift', group: 'Powerlifting'),
      _ex('crow', difficulty: ExerciseDifficulty.advanced, group: 'Yoga', stretch: true),
      _ex('box', title: 'Box Jump', group: 'Calisthenics-Cardio-Plyo-Functional'),
      _ex('stretch', group: 'Stretching - Mobility', stretch: true),
      _ex('row'),
      _ex('curl'),
    ];

PlanReady _plan(SafetyContext ctx,
        {int minutes = 45,
        RecommendationHints hints = RecommendationHints.none,
        List<ExerciseItem>? pool}) =>
    buildPlan(
      candidatePool: pool ?? _pool(),
      deficit: const {},
      deload: _noDeload,
      safety: ctx,
      targetMinutes: minutes,
      hints: hints,
    ) as PlanReady;

UserProfile _profile({
  int? birthYear,
  FitnessGoals goals = FitnessGoals.empty,
  TrainingSchedule schedule = TrainingSchedule.empty,
  FitnessLevel level = FitnessLevel.empty,
  PersonalInfo? personal,
}) =>
    UserProfile.empty('u').copyWith(
      personal: personal ?? PersonalInfo(birthYear: birthYear),
      goals: goals,
      schedule: schedule,
      level: level,
      completedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('age bands: boundaries, and an unknown age is adult', () {
    expect(ageBandFor(null), AgeBand.adult);
    expect(ageBandFor(17), AgeBand.minor);
    expect(ageBandFor(18), AgeBand.adult);
    expect(ageBandFor(64), AgeBand.adult);
    expect(ageBandFor(65), AgeBand.senior);
  });

  test('age bands: literal edge ages', () {
    expect(ageBandFor(0), AgeBand.minor);
    expect(ageBandFor(-1), AgeBand.minor,
        reason: 'a nonsensical negative age is still the cautious band');
    expect(ageBandFor(17), AgeBand.minor);
    expect(ageBandFor(18), AgeBand.adult);
    expect(ageBandFor(64), AgeBand.adult);
    expect(ageBandFor(65), AgeBand.senior);
    expect(ageBandFor(120), AgeBand.senior);
  });

  test('band policy values are the literal documented numbers', () {
    expect(AgeBand.minor.intensityCap, 0.8);
    expect(AgeBand.minor.maxDaysPerWeek, 4);
    expect(AgeBand.senior.intensityCap, 0.85);
    expect(AgeBand.senior.maxDaysPerWeek, 3);
    expect(AgeBand.adult.intensityCap, isNull);
    expect(AgeBand.adult.maxDaysPerWeek, isNull);
  });

  test('safetyContextFor reads the birth year', () {
    final now = DateTime(2026, 10, 13);
    expect(safetyContextFor(_profile(birthYear: 2011), now: now).ageBand,
        AgeBand.minor);
    expect(safetyContextFor(_profile(birthYear: 1950), now: now).ageBand,
        AgeBand.senior);
    expect(safetyContextFor(_profile(birthYear: 1996), now: now).ageBand,
        AgeBand.adult);
    expect(safetyContextFor(_profile(), now: now).ageBand, AgeBand.adult);
  });

  group('rollover (birthYear has year precision only)', () {
    // The questionnaire stores a birth YEAR, so the age is one of two values:
    // `calendarYear - birthYear` (birthday already passed) or one less. The
    // boundary year is resolved on the cautious side: the minor band lasts
    // while the calendar-year difference is 18 or less, and the senior band
    // starts at a difference of 65.
    SafetyContext at(int birthYear, DateTime now) =>
        safetyContextFor(_profile(birthYear: birthYear), now: now);

    test('minor -> adult flips on 1 Jan of the year AFTER the difference reaches 18',
        () {
      // Born 2008: difference 17 in 2025, 18 in 2026 (could still be 17 until a
      // December birthday), 19 in 2027.
      expect(at(2008, DateTime(2025, 12, 31)).ageBand, AgeBand.minor);
      expect(at(2008, DateTime(2026, 1, 1)).ageBand, AgeBand.minor);
      expect(at(2008, DateTime(2026, 6, 15)).ageBand, AgeBand.minor);
      expect(at(2008, DateTime(2026, 12, 31)).ageBand, AgeBand.minor);
      expect(at(2008, DateTime(2027, 1, 1)).ageBand, AgeBand.adult);
      // The advisory rolls over with the band.
      expect(at(2008, DateTime(2026, 1, 1)).advisories.single.reason,
          BlockReason.ageMinorAdvisory);
      expect(at(2008, DateTime(2026, 12, 31)).advisories.single.reason,
          BlockReason.ageMinorAdvisory);
      expect(at(2008, DateTime(2027, 1, 1)).advisories, isEmpty);
    });

    test('adult -> senior flips on 1 Jan of the year the difference reaches 65',
        () {
      // Born 1961: difference 64 in 2025, 65 in 2026 (conservative: senior).
      expect(at(1961, DateTime(2025, 12, 31)).ageBand, AgeBand.adult);
      expect(at(1961, DateTime(2026, 1, 1)).ageBand, AgeBand.senior);
      expect(at(1961, DateTime(2026, 1, 1)).ageBand,
          at(1961, DateTime(2026, 12, 31)).ageBand);
      expect(at(1961, DateTime(2025, 12, 31)).advisories, isEmpty);
      expect(at(1961, DateTime(2026, 1, 1)).advisories.single.reason,
          BlockReason.ageSeniorAdvisory);
    });

    test('the programme day cap follows the same rollover', () {
      expect(
          programmeDaysPerWeek(5, _profile(birthYear: 1961),
              now: DateTime(2025, 12, 31)),
          5);
      expect(
          programmeDaysPerWeek(5, _profile(birthYear: 1961),
              now: DateTime(2026, 1, 1)),
          3);
      expect(
          programmeDaysPerWeek(5, _profile(birthYear: 2008),
              now: DateTime(2025, 12, 31)),
          4);
      // Difference 18 is still the minor cap (changed by the boundary-year
      // decision; it used to be 5 here).
      expect(
          programmeDaysPerWeek(5, _profile(birthYear: 2008),
              now: DateTime(2026, 1, 1)),
          4);
      expect(
          programmeDaysPerWeek(5, _profile(birthYear: 2008),
              now: DateTime(2026, 12, 31)),
          4);
      expect(
          programmeDaysPerWeek(5, _profile(birthYear: 2008),
              now: DateTime(2027, 1, 1)),
          5);
    });
  });

  group('lowestAgeAt / ageBandForPersonal table', () {
    // Clocks: 1 Jan, mid-year, 31 Dec. The result may only depend on the
    // calendar YEAR, never on the day, so every clock must give the same row.
    final clocks = [
      DateTime(2026, 1, 1),
      DateTime(2026, 6, 15),
      DateTime(2026, 12, 31),
    ];

    // difference -> (lowest age, band). Literal expectations: lowest = diff - 1;
    // minor while lowest < 18 (diff <= 18); senior from diff 65.
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

    for (final clock in clocks) {
      for (final MapEntry(key: diff, value: (lowest, band)) in rows.entries) {
        test('${clock.month}/${clock.day}: year difference $diff', () {
          final p = PersonalInfo(birthYear: clock.year - diff);
          expect(p.lowestAgeAt(clock.year), lowest);
          expect(p.ageAt(clock.year), diff,
              reason: 'ageAt stays the highest possible age');
          expect(ageBandForPersonal(p, clock.year), band);
        });
      }
    }

    test('no birth year and no stored age: unknown, adult', () {
      const p = PersonalInfo();
      expect(p.lowestAgeAt(2026), isNull);
      expect(ageBandForPersonal(p, 2026), AgeBand.adult);
      expect(ageBandForPersonal(null, 2026), AgeBand.adult);
    });

    test('a legacy stored age passes through unchanged and uses the plain bands',
        () {
      const minor = PersonalInfo(age: 17);
      const adult = PersonalInfo(age: 18);
      const senior = PersonalInfo(age: 65);
      for (final year in [2026, 2040]) {
        expect(minor.lowestAgeAt(year), 17);
        expect(adult.lowestAgeAt(year), 18);
        expect(senior.lowestAgeAt(year), 65);
      }
      expect(ageBandForPersonal(minor, 2026), AgeBand.minor);
      expect(ageBandForPersonal(adult, 2026), AgeBand.adult);
      expect(ageBandForPersonal(senior, 2026), AgeBand.senior);
    });

    test('a future birth year is the cautious (minor) band', () {
      final p = const PersonalInfo(birthYear: 2030);
      expect(p.lowestAgeAt(2026), -5);
      expect(ageBandForPersonal(p, 2026), AgeBand.minor);
    });

    test('safetyContextFor and programmeDaysPerWeek use the bracketed rule', () {
      final now = DateTime(2026, 12, 31);
      expect(safetyContextFor(_profile(birthYear: 2008), now: now).ageBand,
          AgeBand.minor);
      expect(safetyContextFor(_profile(birthYear: 2007), now: now).ageBand,
          AgeBand.adult);
      expect(programmeDaysPerWeek(5, _profile(birthYear: 2008), now: now), 4);
      expect(programmeDaysPerWeek(5, _profile(birthYear: 2007), now: now), 5);
    });
  });

  group('age cap and beginner cap together', () {
    final now = DateTime(2026, 10, 13);
    UserProfile beginner(int birthYear, int freq) => _profile(
        birthYear: birthYear,
        level: FitnessLevel(tier: FitnessTier.beginner, frequencyPerWeek: freq));

    test('senior beginner who trains 0x a week: the stricter beginner cap (2) wins',
        () {
      // age cap 3, beginner cap 0 + 2 = 2.
      expect(programmeDaysPerWeek(5, beginner(1950, 0), now: now), 2);
    });

    test('senior beginner who trains 3x a week: the stricter age cap (3) wins', () {
      // age cap 3, beginner cap 3 + 2 = 5.
      expect(programmeDaysPerWeek(5, beginner(1950, 3), now: now), 3);
    });

    test('minor beginner who trains 1x a week: beginner cap (3) beats age cap (4)',
        () {
      expect(programmeDaysPerWeek(5, beginner(2011, 1), now: now), 3);
    });

    test('adult beginner is not touched by the age cap', () {
      expect(programmeDaysPerWeek(5, beginner(1990, 3), now: now), 5);
    });

    test('senior beginner plan: tier ceiling and 0.85 intensity cap both hold', () {
      final p = beginner(1950, 0).copyWith(
          health: HealthHistory(
              injuries: const [],
              screening: {for (final q in ParQQuestion.values) q: false},
              flags: HealthFlags(restrictions: const {})));
      final ctx = safetyContextFor(p, now: now);
      expect(ctx.ageBand, AgeBand.senior);
      expect(ctx.maxDifficulty, ExerciseDifficulty.beginner);
      final pool = [
        _ex('squat'),
        _ex('hard', difficulty: ExerciseDifficulty.intermediate),
        _ex('stretch', group: 'Stretching - Mobility', stretch: true),
        _ex('row'),
        _ex('curl'),
      ];
      final plan = _plan(ctx, pool: pool).plan;
      expect(plan.intensityFactor, lessThanOrEqualTo(0.85));
      expect(plan.exercises.map((e) => e.id), isNot(contains('hard')));
      expect(plan.exercises.any((e) => e.isStretch), isTrue);
    });
  });

  group('selection', () {
    test('a minor gets no max-effort or advanced items; an adult does', () {
      final adult = eligibleExercises(_pool(), _ctx()).map((e) => e.id);
      final minor =
          eligibleExercises(_pool(), _ctx(band: AgeBand.minor)).map((e) => e.id);
      expect(adult, containsAll(['deadlift', 'crow', 'box']));
      expect(minor, isNot(contains('deadlift')));
      expect(minor, isNot(contains('crow')));
      expect(minor, contains('box'), reason: 'impact is only withheld for seniors');
    });

    test('a senior also loses high-impact items', () {
      final ids = eligibleExercises(_pool(), _ctx(band: AgeBand.senior))
          .map((e) => e.id);
      expect(ids, isNot(contains('box')));
      expect(ids, isNot(contains('deadlift')));
      expect(ids, contains('stretch'));
    });

    test('a gentle goal (comeback / flexibility) withholds max-effort work', () {
      final ids = eligibleExercises(_pool(), _ctx(gentle: true)).map((e) => e.id);
      expect(ids, isNot(contains('deadlift')));
      expect(ids, isNot(contains('crow')));
      expect(ids, contains('box'));
    });

    test('the age advisory rides the existing advisory channel', () {
      expect(_ctx(band: AgeBand.minor).advisories.single.reason,
          BlockReason.ageMinorAdvisory);
      expect(_ctx(band: AgeBand.senior).advisories.single.reason,
          BlockReason.ageSeniorAdvisory);
      expect(_ctx().advisories, isEmpty);
    });
  });

  group('plan', () {
    test('minor: warning in reasons, intensity capped, health ceiling untouched',
        () {
      final plan = _plan(_ctx(band: AgeBand.minor)).plan;
      expect(plan.reasons.whereType<SafetyAdvisoryReason>().single.advisory.reason,
          BlockReason.ageMinorAdvisory);
      expect(plan.intensityFactor, lessThanOrEqualTo(0.8));
      expect(plan.reasons.whereType<ScreeningCeilingReason>(), isEmpty,
          reason: 'a healthy minor must not be told the app has not cleared them');
      expect(plan.exercises.map((e) => e.id), isNot(contains('deadlift')));
    });

    test('senior: balance/mobility item is included and said so', () {
      final plan = _plan(_ctx(band: AgeBand.senior)).plan;
      expect(plan.exercises.any((e) => e.isStretch), isTrue);
      expect(plan.reasons.whereType<GoalMixReason>().map((r) => r.mix),
          contains(GoalMix.seniorBalance));
      expect(plan.intensityFactor, lessThanOrEqualTo(0.85));
    });

    test('an adult with the same answers gets a different output', () {
      final adult = _plan(_ctx()).plan;
      final minor = _plan(_ctx(band: AgeBand.minor)).plan;
      expect(adult.reasons.whereType<SafetyAdvisoryReason>(), isEmpty);
      expect(adult.intensityFactor, greaterThan(minor.intensityFactor));
    });

    test('never exceeds the stated minutes', () {
      for (final m in [15, 25, 30, 45, 60]) {
        final plan = _plan(_ctx(), minutes: m).plan;
        expect(plan.estimatedMinutes, lessThanOrEqualTo(m), reason: '$m');
      }
    });

    test('the injury count is injuries only, not equipment or age removals', () {
      final pool = [
        _ex('knee1', contra: ['knee']),
        _ex('knee2', contra: ['knee']),
        _ex('deadlift', group: 'Powerlifting'),
        _ex('a'),
        _ex('b'),
      ];
      final plan = _plan(
              _ctx(band: AgeBand.minor, injuries: [
                const Injury(bodyPart: 'knee', type: 'sprain', region: InjuryRegion.knee)
              ]),
              pool: pool)
          .plan;
      expect(plan.reasons.whereType<InjuryFilterReason>().single.count, 2);
    });

    test('an injury the filter cannot act on is disclosed, not ignored', () {
      final plan = _plan(_ctx(injuries: [
        const Injury(bodyPart: 'rib', type: 'bruise'),
      ])).plan;
      final adv = plan.reasons.whereType<SafetyAdvisoryReason>().single.advisory;
      expect(adv.reason, BlockReason.unscreenableInjury);
      expect(adv.detail, 'rib');
      // A screenable injury produces none.
      final ok = _plan(_ctx(injuries: [
        const Injury(bodyPart: 'Left knee', type: 'sprain'),
      ])).plan;
      expect(ok.reasons.whereType<SafetyAdvisoryReason>(), isEmpty);
    });

    test('goal mix: mobility and conditioning are included when asked and said',
        () {
      final plan = _plan(_ctx(),
              hints: const RecommendationHints(
                  wantsMobility: true, wantsConditioning: true))
          .plan;
      expect(plan.exercises.any((e) => e.isStretch), isTrue);
      expect(plan.exercises.any(isConditioningExercise), isTrue);
      expect(plan.reasons.whereType<GoalMixReason>().map((r) => r.mix),
          containsAll([GoalMix.mobility, GoalMix.conditioning]));
      // No reason when the pool has nothing to include.
      final bare = _plan(_ctx(),
              hints: const RecommendationHints(wantsMobility: true),
              pool: [_ex('squat'), _ex('row')])
          .plan;
      expect(bare.reasons.whereType<GoalMixReason>(), isEmpty);
    });

    test('starting-volume cap lowers the factor and says why, only then', () {
      final p = _plan(_ctx(),
              hints: const RecommendationHints(
                  volumeCap: 0.85, volumeCapCause: VolumeCapCause.lowActivity))
          .plan;
      expect(p.intensityFactor, 0.85);
      expect(p.reasons.whereType<VolumeCapReason>().single.percent, 85);
    });
  });

  group('suggestions: reasons match the exercise', () {
    test('a stretch is never "builds strength" or "builds muscle"', () {
      final out = buildSuggestions(
        candidates: [
          _ex('stretch', group: 'Stretching - Mobility', stretch: true),
          _ex('yoga', group: 'Yoga', stretch: true),
          _ex('squat'),
        ],
        profile: _profile(
            goals: const FitnessGoals(strength: true, muscleGain: true)),
        recentLogs: const [],
        now: DateTime(2026, 10, 13),
      );
      for (final s in out) {
        if (s.exerciseId == 'squat') {
          expect(s.reason, SuggestionReason.buildsStrength);
        } else {
          expect(s.reason, SuggestionReason.buildsMobility);
        }
      }
    });
  });

  group('programme', () {
    test('days: senior and minor caps, beginner frequency cap, only lowers', () {
      final now = DateTime(2026, 10, 13);
      expect(programmeDaysPerWeek(5, _profile(birthYear: 1950), now: now), 3);
      expect(programmeDaysPerWeek(5, _profile(birthYear: 2011), now: now), 4);
      expect(programmeDaysPerWeek(5, _profile(birthYear: 1990), now: now), 5);
      final beginner = _profile(
          birthYear: 1990,
          level: const FitnessLevel(
              tier: FitnessTier.beginner, frequencyPerWeek: 0));
      expect(programmeDaysPerWeek(5, beginner, now: now), 2);
      final advanced = _profile(
          birthYear: 1990,
          level: const FitnessLevel(
              tier: FitnessTier.advanced, frequencyPerWeek: 0));
      expect(programmeDaysPerWeek(5, advanced, now: now), 5);
    });

    test('spec: conservative dose for minors, goal slots added', () {
      final base = programmeSpecFor('strength_base', daysPerWeek: 4)!;
      final minor = programmeSpecFor('strength_base',
          daysPerWeek: 4,
          adaptation: const ProgrammeAdaptation(ageBand: AgeBand.minor))!;
      expect(minor.setsPerSlot, base.setsPerSlot - 1);
      expect(minor.minWeeklySetsPerRole, lessThanOrEqualTo(minor.setsPerSlot));
      final mob = programmeSpecFor('strength_base',
          daysPerWeek: 4,
          adaptation: const ProgrammeAdaptation(mobility: true, conditioning: true))!;
      expect(mob.declaredRoles.map((r) => r.name),
          containsAll(['mobility', 'conditioning']));
      expect(base.declaredRoles.map((r) => r.name), isNot(contains('mobility')));
    });

    test('hints derive from the questionnaire', () {
      final h = RecommendationHints.fromProfile(_profile(
          goals: const FitnessGoals(flexibility: true, endurance: true),
          personal: const PersonalInfo(activityLevel: ActivityLevel.sedentary)));
      expect(h.wantsMobility, isTrue);
      expect(h.wantsConditioning, isTrue);
      expect(h.volumeCap, 0.85);
      expect(h.volumeCapCause, VolumeCapCause.lowActivity);
      expect(RecommendationHints.fromProfile(null).wantsMobility, isFalse);
      expect(
          gentleSelectionFor(_profile(
              goals: const FitnessGoals(primary: ProgrammeGoal.comeback))),
          isTrue);
    });
  });
}
