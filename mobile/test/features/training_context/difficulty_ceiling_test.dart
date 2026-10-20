// MAJOR-01: the "nothing above your level" ceiling (SafetyContext.maxDifficulty)
// must survive a chosen training context.
//
// `safetyContextForTrainingContext` once rebuilt the SafetyContext without
// `maxDifficulty`, so a beginner / never-trained user who picked gym, outdoors,
// home or yoga lost the ceiling and the plan and programme builders could hand
// them advanced work. Part (a) pins every field; parts (b) and (c) drive the
// REAL providers (plan, programme enrolment, home suggestions) with a
// catalogue that holds beginner, intermediate AND advanced exercises usable in
// each context, so the ceiling is the only thing keeping the harder work out.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/ai_planner/state/ai_planner_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/home/state/suggestion_providers.dart';
import 'package:fitness_app/features/personalisation/state/personalisation_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/programmes/data/mock_programme_repository.dart';
import 'package:fitness_app/features/programmes/data/programme_templates.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/recovery/state/recovery_providers.dart';
import 'package:fitness_app/features/safety/data/age_policy.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

void main() {
  group('(a) safetyContextForTrainingContext carries every field', () {
    const injuries = [
      Injury(bodyPart: 'knee', type: 'sprain', region: InjuryRegion.knee),
    ];
    const health = HealthFlags(
      restrictions: {MovementRestriction.overhead},
      bloodPressure: BloodPressureStatus.diagnosedLow,
      surgery: SurgeryStatus.none,
      clinicianAdvice: ClinicianExerciseAdvice.noLimitsGiven,
    );
    final screening = screen({for (final q in ParQQuestion.values) q: false});
    const equipment = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.dumbbells, EquipmentKind.bands]);

    SafetyContext base({
      AgeBand band = AgeBand.minor,
      ExerciseDifficulty? max = ExerciseDifficulty.beginner,
    }) =>
        SafetyContext(
          screening: screening,
          injuries: injuries,
          health: health,
          equipment: equipment,
          ageBand: band,
          gentleSelection: true,
          maxDifficulty: max,
        );

    // The expectation is built from the constructor's NAMED PARAMETERS. If
    // SafetyContext gains a field, add it to `expectedFor` AND to the field
    // list below, with a non-default value in `base`: a field that is not
    // copied by safetyContextForTrainingContext must then fail here.
    SafetyContext expectedFor(SafetyContext b) => SafetyContext(
          screening: b.screening,
          injuries: b.injuries,
          health: b.health,
          equipment: null, // the one field that is deliberately dropped
          ageBand: b.ageBand,
          gentleSelection: b.gentleSelection,
          maxDifficulty: b.maxDifficulty,
        );

    void expectSame(SafetyContext got, SafetyContext want, String why) {
      expect(got.screening, same(want.screening), reason: '$why screening');
      expect(got.injuries, same(want.injuries), reason: '$why injuries');
      expect(got.health, same(want.health), reason: '$why health');
      expect(got.equipment, isNull, reason: '$why equipment dropped');
      expect(got.ageBand, want.ageBand, reason: '$why ageBand');
      expect(got.gentleSelection, want.gentleSelection,
          reason: '$why gentleSelection');
      expect(got.maxDifficulty, want.maxDifficulty,
          reason: '$why maxDifficulty');
    }

    test('null context returns the base itself (equipment kept)', () {
      final b = base();
      expect(safetyContextForTrainingContext(b, null), same(b));
      expect(b.equipment, equipment);
    });

    for (final ctx in TrainingContext.values) {
      for (final band in [AgeBand.minor, AgeBand.senior]) {
        test('${ctx.name} / ${band.name}: every field but equipment', () {
          final b = base(band: band);
          final got = safetyContextForTrainingContext(b, ctx);
          expectSame(got, expectedFor(b), '${ctx.name}/${band.name}');
          expect(got.maxDifficulty, ExerciseDifficulty.beginner,
              reason: 'the beginner ceiling must survive the context');
          expect(got.gentleSelection, isTrue);
        });
      }

      test('${ctx.name}: a base without a ceiling stays without one', () {
        final b = base(max: null);
        final got = safetyContextForTrainingContext(b, ctx);
        expect(got.maxDifficulty, isNull);
        expect(got.equipment, isNull);
      });

      test('${ctx.name}: intermediate ceiling is carried unchanged', () {
        final got = safetyContextForTrainingContext(
            base(max: ExerciseDifficulty.intermediate), ctx);
        expect(got.maxDifficulty, ExerciseDifficulty.intermediate);
      });
    }

    test('the test base really has non-default values in every field', () {
      final b = base();
      expect(b.injuries, isNotEmpty);
      expect(b.health.isUnanswered, isFalse);
      expect(b.equipment, isNotNull);
      expect(b.ageBand, isNot(AgeBand.adult));
      expect(b.gentleSelection, isTrue);
      expect(b.maxDifficulty, isNotNull);
    });
  });

  group('(b)/(c) beginner ceiling through the real providers', () {
    // Titles drive movementRoleOf (whole-word match), so a prefix keeps the
    // role while making the tier visible in the title.
    const roleTitles = {
      'sq': 'Bodyweight Squat',
      'sq2': 'Goblet Squat',
      'hi': 'Romanian Deadlift',
      'hi2': 'Glute Bridge',
      'hp': 'Push Up',
      'hp2': 'Bench Press',
      'vp': 'Overhead Press',
      'vp2': 'Push Press',
      'hl': 'Bent Over Row',
      'hl2': 'Seated Row',
      'vl': 'Pull Up',
      'vl2': 'Lat Pulldown',
      'sl': 'Walking Lunge',
      'sl2': 'Bulgarian Split Squat',
      'ce': 'Front Plank',
      'ce2': 'Hollow Hold',
      'cr': 'Russian Twist',
      'cr2': 'Cable Woodchop',
    };

    ExerciseItem ex(String id, String title, ExerciseDifficulty d,
            {String label = 'None (Bodyweight)',
            String? group,
            bool stretch = false}) =>
        ExerciseItem(
          id: id,
          title: title,
          equipmentId: null,
          equipmentLabel: label,
          muscles: const ['quads'],
          primaryMuscles: const ['quads'],
          difficulty: d,
          durationMinutes: 8,
          summary: '',
          steps: const [],
          isStretch: stretch,
          vendorGroup: group,
        );

    const tiers = {
      ExerciseDifficulty.advanced: ('adv', 'Elite'),
      ExerciseDifficulty.intermediate: ('int', 'Tempo'),
      ExerciseDifficulty.beginner: ('beg', 'Easy'),
    };

    // Hardest first, so an un-ceilinged builder reaches for advanced work.
    // Bodyweight strength rows and yoga rows are usable in every context
    // except yoga (strength) / except none (yoga rows pass all four).
    final pool = <ExerciseItem>[
      for (final entry in tiers.entries) ...[
        for (final r in roleTitles.entries)
          ex('${entry.value.$1}_${r.key}', '${entry.value.$2} ${r.value}',
              entry.key),
        for (var i = 0; i < 30; i++)
          ex('${entry.value.$1}_yoga$i', '${entry.value.$2} Flow Pose $i',
              entry.key,
              label: 'Yoga Mat', group: 'Yoga', stretch: true),
      ],
    ];
    final byId = {for (final e in pool) e.id: e};

    UserProfile profile(FitnessTier tier) => UserProfile.empty('u1').copyWith(
          personal: const PersonalInfo(birthYear: 1990),
          health: HealthHistory(
            injuries: const [],
            screening: {for (final q in ParQQuestion.values) q: false},
            flags: HealthFlags(restrictions: const {}),
          ),
          goals: const FitnessGoals(generalFitness: true),
          level: FitnessLevel(
              tier: tier,
              frequencyPerWeek: 3,
              basics: BasicExerciseAbility.yes),
          schedule: TrainingSchedule(
              daysPerWeek: 3, sessionMinutes: 60, preferredWeekdays: const []),
          completedAt: DateTime(2026, 1, 1),
        );

    ProviderContainer container(FitnessTier tier, TrainingContext ctx) {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);
      final p = profile(tier);
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith(
            (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
        currentProfileProvider.overrideWith((_) => Stream.value(p)),
        equipmentRepositoryProvider.overrideWithValue(_Repo(pool)),
        safeCatalogProvider.overrideWith((ref) async {
          final sp = await ref.watch(screeningProfileProvider.future);
          return safeFor(pool, sp);
        }),
        weeklyVolumeDeficitProvider.overrideWith((_) async => const {}),
        deloadVerdictProvider.overrideWithValue(const DeloadVerdict(
            shouldDeload: false, reasons: [], suggestedVolumeFactor: 1.0)),
        workoutSessionHistoryProvider.overrideWithValue(const []),
        programmeRepositoryProvider.overrideWithValue(programmeRepo),
        scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
        trainingContextProvider
            .overrideWith(() => _FixedContext(TrainingContextAnswer.chosen(ctx))),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<Set<String>> planIds(ProviderContainer c) async {
      final out = await c.read(generatedPlanProvider.future);
      return {for (final e in (out! as PlanReady).plan.exercises) e.id};
    }

    Future<(Set<String>, Object?)> programmeIds(ProviderContainer c) async {
      await c.read(authUserProvider.future);
      await c.read(trainingContextProvider.future);
      await c
          .read(programmeActionProvider.notifier)
          .enroll(programmeTemplates.first);
      final sessionRepo = c.read(scheduledSessionRepositoryProvider)
          as MockScheduledSessionRepository;
      return (
        {for (final r in sessionRepo.cached('u1')) r.exerciseId},
        c.read(programmeActionProvider).error
      );
    }

    Future<Set<String>> suggestionIds(ProviderContainer c) async {
      await c.read(trainingContextProvider.future);
      final s = await c.read(suggestionsProvider.future);
      return {for (final x in s) x.exerciseId};
    }

    Set<String> aboveBeginner(Set<String> ids) => {
          for (final id in ids)
            if (byId[id]!.difficulty != ExerciseDifficulty.beginner) id
        };

    test('the catalogue is not vacuous: every tier is usable in every context',
        () {
      for (final ctx in TrainingContext.values) {
        final allowed = [
          for (final e in pool)
            if (allowedInTrainingContext(e, ctx, null)) e
        ];
        for (final d in ExerciseDifficulty.values) {
          expect(allowed.where((e) => e.difficulty == d), isNotEmpty,
              reason: '${ctx.name} must allow $d rows');
        }
      }
    });

    for (final tier in [FitnessTier.beginner, FitnessTier.never]) {
      for (final ctx in TrainingContext.values) {
        test('${tier.name} in ${ctx.name}: plan, programme and suggestions '
            'stay at beginner difficulty', () async {
          final c = container(tier, ctx);
          // The ceiling reaches the context-narrowed safety context.
          final safety = await c.read(safetyContextProvider.future);
          expect(safety.maxDifficulty, ExerciseDifficulty.beginner);
          expect(
              safetyContextForTrainingContext(safety, ctx).maxDifficulty,
              ExerciseDifficulty.beginner);

          final plan = await planIds(c);
          expect(plan, isNotEmpty, reason: 'plan must exist (not vacuous)');
          expect(aboveBeginner(plan), isEmpty,
              reason: 'plan has intermediate/advanced work: $plan');
          expect(plan.every((id) => id.startsWith('beg_')), isTrue);

          final (prog, err) = await programmeIds(c);
          expect(err, isNull, reason: 'programme must build: $err');
          expect(prog, isNotEmpty);
          expect(aboveBeginner(prog), isEmpty,
              reason: 'programme has intermediate/advanced work: $prog');

          final sugg = await suggestionIds(c);
          expect(sugg, isNotEmpty, reason: 'suggestions must exist');
          expect(aboveBeginner(sugg), isEmpty,
              reason: 'suggestions above beginner: $sugg');
        });
      }
    }

    for (final ctx in TrainingContext.values) {
      test('advanced tier in ${ctx.name}: the ceiling is not over-applied',
          () async {
        final c = container(FitnessTier.advanced, ctx);
        final safety = await c.read(safetyContextProvider.future);
        expect(safety.maxDifficulty, isNull);
        final plan = await planIds(c);
        expect(plan, isNotEmpty);
        expect(plan.any((id) => id.startsWith('adv_')), isTrue,
            reason: 'advanced work can reach the plan: $plan');
        final (prog, err) = await programmeIds(c);
        expect(err, isNull, reason: '$err');
        expect(prog.any((id) => id.startsWith('adv_')), isTrue,
            reason: 'advanced work can reach the programme: $prog');
      });
    }
  });
}

class _FixedContext extends TrainingContextNotifier {
  _FixedContext(this.initial);
  final TrainingContextAnswer initial;
  @override
  Future<TrainingContextAnswer> build() async => initial;
}

class _Repo implements EquipmentRepository {
  _Repo(this.pool);
  final List<ExerciseItem> pool;
  @override
  Future<List<EquipmentItem>> listEquipment() async => const [];
  @override
  Future<EquipmentItem?> findEquipment(String id) async => null;
  @override
  Future<List<ExerciseItem>> exercisesFor(String equipmentId) async => const [];
  @override
  Future<List<ExerciseItem>> bodyweightExercises() async => pool;
}
