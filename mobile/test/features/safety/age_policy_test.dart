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
