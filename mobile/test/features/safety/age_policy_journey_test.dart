// J4: the age policy end to end through the REAL builders (plan builder, home
// suggestions builder, programme builder) on the real bundled catalogue, for
// otherwise-identical healthy profiles aged 15, 17, 18, 64, 65, 70 and one with
// no age. Expectations are LITERAL numbers (0.8 / 4 days, 0.85 / 3 days) and do
// not read the policy constants.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';
import 'package:fitness_app/features/home/data/suggestion_builder.dart';
import 'package:fitness_app/features/personalisation/data/recommendation_hints.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_schedule.dart';
import 'package:fitness_app/features/programmes/data/programme_specs.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/age_policy.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';

final _now = DateTime(2026, 10, 13);
const _noDeload =
    DeloadVerdict(shouldDeload: false, reasons: [], suggestedVolumeFactor: 1.0);

class _Result {
  _Result(this.ctx, this.plan, this.suggestions, this.programme, this.days);
  final SafetyContext ctx;
  final PlanOutcome plan;
  final List<WorkoutSuggestion> suggestions;
  final ProgrammeBuildResult programme;
  final int days;
  Map<String, ExerciseItem> byId = {};

  List<ExerciseItem> get planExercises => (plan as PlanReady).plan.exercises;
  List<ExerciseItem> get suggestionExercises =>
      [for (final s in suggestions) if (byId[s.exerciseId] != null) byId[s.exerciseId]!];
  List<ExerciseItem> get programmeExercises => [
        if (programme case ProgrammeBuilt(:final sessions))
          for (final s in sessions) for (final e in s.exercises) e.exercise,
      ];
  List<ExerciseItem> get all =>
      [...planExercises, ...suggestionExercises, ...programmeExercises];
  String get signature =>
      '${planExercises.map((e) => e.id).join(',')}|${(plan as PlanReady).plan.intensityFactor}|'
      '${suggestions.map((s) => s.exerciseId).join(',')}|'
      '${programmeExercises.map((e) => e.id).join(',')}|$days';
}

void main() {
  late List<ExerciseItem> all;
  late List<ExerciseItem> planPool;
  late List<ExerciseItem> demo;

  setUpAll(() {
    final quarantine = (jsonDecode(
                File('assets/data/exercises_quarantine.json').readAsStringSync())
            as List)
        .map((e) => (e as Map)['id'] as String)
        .toSet();
    final eqIds =
        (jsonDecode(File('assets/data/equipment.json').readAsStringSync()) as List)
            .map((e) => (e as Map)['id'] as String)
            .toSet();
    all = (jsonDecode(File('assets/data/exercises_vendor.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>()
        .map(ExerciseItem.fromJson)
        .where((e) => !quarantine.contains(e.id))
        .toList(growable: false);
    planPool = [
      for (final e in all)
        if (e.equipmentId == null || eqIds.contains(e.equipmentId)) e
    ];
    demo = withDemonstration(all);
  });

  UserProfile profile(int? age) => UserProfile.empty('age_$age').copyWith(
        personal: PersonalInfo(birthYear: age == null ? null : 2026 - age),
        health: HealthHistory(
          injuries: const [],
          screening: {for (final q in ParQQuestion.values) q: false},
          flags: HealthFlags(restrictions: const {}),
        ),
        goals: const FitnessGoals(primary: ProgrammeGoal.strength, strength: true),
        level: const FitnessLevel(
            tier: FitnessTier.advanced,
            frequencyPerWeek: 3,
            basics: BasicExerciseAbility.yes),
        equipment: const EquipmentAccess(location: TrainingLocation.gym),
        schedule: TrainingSchedule(
            daysPerWeek: 5, sessionMinutes: 45, preferredWeekdays: const []),
        completedAt: DateTime(2026, 1, 1),
      );

  _Result run(int? age) {
    final p = profile(age);
    final ctx = safetyContextFor(p, now: _now);
    final hints = RecommendationHints.fromProfile(p);
    final plan = buildPlan(
      candidatePool: planPool,
      deficit: const {},
      deload: _noDeload,
      safety: ctx,
      targetMinutes: 45,
      hints: hints,
    );
    final safe = safeFor(demo, p);
    final suggestions = buildSuggestions(
      candidates: sortByTierFit(eligibleExercises(safe, ctx), p.level.tier),
      profile: p,
      recentLogs: const [],
      now: _now,
    );
    final tpl = programmeFromProfile(p);
    final days = programmeScheduledDays(
        daysPerWeek: programmeDaysPerWeek(tpl.daysPerWeek, p, now: _now),
        preferredWeekdays: p.schedule.preferredWeekdays);
    final spec = programmeSpecFor(tpl.id,
        daysPerWeek: days, adaptation: programmeAdaptationFor(ctx, hints))!;
    final focus = programmeMuscles(tpl, p).toSet();
    final programme = buildProgramme(ProgrammeBuildRequest(
      spec: spec,
      catalogue: safe,
      safety: ctx,
      weeks: tpl.weeks,
      daysPerWeek: days,
      rank: focus.isEmpty
          ? null
          : (role, pool) => [
                ...pool.where((e) =>
                    e.primaryMuscles.any(focus.contains) ||
                    e.muscles.any(focus.contains)),
                ...pool.where((e) => !(e.primaryMuscles.any(focus.contains) ||
                    e.muscles.any(focus.contains))),
              ],
    ));
    return _Result(ctx, plan, suggestions, programme, days)
      ..byId = {for (final e in all) e.id: e};
  }

  bool maxEffort(ExerciseItem e) =>
      e.vendorGroup == 'Powerlifting' || e.difficulty == ExerciseDifficulty.advanced;
  final impact = RegExp(r'jump|\bhop|burpee|sprint', caseSensitive: false);
  bool balanceOrMobility(ExerciseItem e) =>
      e.isStretch ||
      e.vendorGroup == 'Yoga' ||
      e.vendorGroup == 'Stretching - Mobility' ||
      RegExp(r'balance', caseSensitive: false).hasMatch(e.title);
  Set<BlockReason> ageWarnings(_Result r) => {
        for (final r in (r.plan as PlanReady).plan.reasons)
          if (r is SafetyAdvisoryReason) r.advisory.reason,
      }..removeWhere((x) =>
          x != BlockReason.ageMinorAdvisory && x != BlockReason.ageSeniorAdvisory);

  for (final age in [15, 17]) {
    test('minor aged $age: no max-effort work, intensity <= 0.8, <= 4 days, warning shown',
        () {
      final r = run(age);
      expect(r.plan, isA<PlanReady>());
      expect(r.planExercises, isNotEmpty);
      expect(r.suggestionExercises, isNotEmpty);
      expect(r.programme, isA<ProgrammeBuilt>());
      expect(r.programmeExercises, isNotEmpty);
      for (final e in r.all) {
        expect(maxEffort(e), isFalse, reason: '${e.id} (${e.vendorGroup}, ${e.difficulty})');
      }
      expect((r.plan as PlanReady).plan.intensityFactor, lessThanOrEqualTo(0.8));
      expect(r.days, lessThanOrEqualTo(4));
      expect(r.days, 4, reason: 'asked for 5 days: the minor cap lowers it to exactly 4');
      expect(ageWarnings(r), {BlockReason.ageMinorAdvisory});
      expect(r.ctx.advisories.map((a) => a.reason), contains(BlockReason.ageMinorAdvisory));
    });
  }

  for (final age in [65, 70]) {
    test('senior aged $age: no max-effort or impact titles, intensity <= 0.85, 3 days, '
        'balance/mobility present, warning shown', () {
      final r = run(age);
      expect(r.plan, isA<PlanReady>());
      expect(r.suggestionExercises, isNotEmpty);
      expect(r.programmeExercises, isNotEmpty);
      for (final e in r.all) {
        expect(maxEffort(e), isFalse, reason: '${e.id} max-effort');
        expect(impact.hasMatch(e.title), isFalse, reason: 'impact title: ${e.title}');
      }
      expect((r.plan as PlanReady).plan.intensityFactor, lessThanOrEqualTo(0.85));
      expect(r.days, 3, reason: 'asked for 5 days: the senior cap is exactly 3');
      expect(r.planExercises.any(balanceOrMobility), isTrue,
          reason: 'senior plan needs a balance or mobility exercise');
      expect(ageWarnings(r), {BlockReason.ageSeniorAdvisory});
    });
  }

  for (final age in [18, 64, null]) {
    test('adult (age ${age ?? "unknown"}): no age warning, no age cap on days or intensity', () {
      final r = run(age);
      expect(r.plan, isA<PlanReady>());
      expect(ageWarnings(r), isEmpty);
      expect(r.ctx.advisories.map((a) => a.reason),
          isNot(contains(BlockReason.ageMinorAdvisory)));
      expect(r.ctx.advisories.map((a) => a.reason),
          isNot(contains(BlockReason.ageSeniorAdvisory)));
      expect((r.plan as PlanReady).plan.intensityFactor, greaterThan(0.85));
      expect(r.days, 5);
    });
  }

  test('17 and 18 (identical otherwise) produce different outputs; 64 and 65 too', () {
    expect(run(17).signature, isNot(run(18).signature));
    expect(run(64).signature, isNot(run(65).signature));
  });
}
