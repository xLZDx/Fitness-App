import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/cycle_aware/data/cycle_phase.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

ExerciseItem _ex(
  String id, {
  List<String> muscles = const [],
  List<String> primary = const [],
  List<String> contra = const [],
  int minutes = 10,
}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      primaryMuscles: primary,
      muscles: muscles,
      difficulty: ExerciseDifficulty.intermediate,
      durationMinutes: minutes,
      summary: '',
      steps: const [],
      contraindications: contra,
    );

const _noDeload = DeloadVerdict(
  shouldDeload: false,
  reasons: [],
  suggestedVolumeFactor: 1.0,
);

/// A screen that clears the user, so these cases exercise the planning logic
/// rather than the Gate M floor. `plan_refusal_test.dart` owns the floor.
final _cleared = screen({for (final q in ParQQuestion.values) q: false});

/// Unwraps the outcome, failing loudly rather than returning a stand-in.
///
/// `buildPlan` returns a sealed [PlanOutcome] since Gate M. A helper that
/// silently substituted an empty plan for a refusal would let every assertion
/// below pass against a refused build.
GeneratedPlan _plan(PlanOutcome out) {
  expect(out, isA<PlanReady>(),
      reason: 'these cases are about planning, not about the safety floor');
  return (out as PlanReady).plan;
}

void main() {
  group('buildPlan', () {
    test('drops contraindicated exercises from the pool', () {
      final pool = [
        _ex('squat', muscles: ['quads']),
        _ex('overhead-press', muscles: ['shoulders'], contra: ['shoulder']),
      ];
      final plan = _plan(buildPlan(
        candidatePool: pool,
        reportedInjuries: const [
          Injury(bodyPart: 'shoulder', type: 'impingement'),
        ],
        deficit: const <String, double>{},
        deload: _noDeload,
        safety: _cleared,
      ));
      expect(plan.exercises.map((e) => e.id), ['squat']);
      expect(plan.rationale, contains('Filtered out 1'));
    });

    test('the filter claim names injuries, which is all it screened', () {
      // `filterContraindicated` is passed the injury list and nothing else.
      // The string used to say "your reported conditions", which told a user
      // who had entered diabetes and hypertension that both had been screened
      // for. `HealthHistory.conditions` reaches no filter at all.
      final plan = _plan(buildPlan(
        candidatePool: [
          _ex('a'),
          _ex('press', contra: ['shoulder']),
        ],
        reportedInjuries: const [Injury(bodyPart: 'shoulder', type: 'strain')],
        deficit: const <String, double>{},
        deload: _noDeload,
        safety: _cleared,
      ));
      expect(plan.rationale, contains('an injury you reported'));
      expect(plan.rationale, isNot(contains('condition')));
    });

    test('respects target minutes (greedy fill)', () {
      final pool = [
        _ex('a', minutes: 25),
        _ex('b', minutes: 25),
        _ex('c', minutes: 25),
      ];
      final plan = _plan(buildPlan(
        candidatePool: pool,
        reportedInjuries: const [],
        deficit: const <String, double>{},
        deload: _noDeload,
        safety: _cleared,
        targetMinutes: 30,
      ));
      // 25 + 25 = 50 > 30+5 buffer; only one fits.
      expect(plan.estimatedMinutes, 25);
      expect(plan.exercises.length, 1);
    });

    test('deload pulls intensity factor', () {
      const deload = DeloadVerdict(
        shouldDeload: true,
        reasons: ['Recovery is low'],
        suggestedVolumeFactor: 0.5,
      );
      final plan = _plan(buildPlan(
        candidatePool: [_ex('squat', muscles: ['quads'])],
        reportedInjuries: const [],
        deficit: const <String, double>{},
        deload: deload,
        safety: _cleared,
      ));
      expect(plan.title, 'Deload day');
      expect(plan.intensityFactor, closeTo(0.5, 0.0001));
      expect(plan.rationale, contains('Recovery'));
    });

    test('cycle phase composes with deload factor', () {
      const deload = DeloadVerdict(
        shouldDeload: true,
        reasons: [],
        suggestedVolumeFactor: 0.7,
      );
      final plan = _plan(buildPlan(
        candidatePool: [_ex('squat', muscles: ['quads'])],
        reportedInjuries: const [],
        deficit: const <String, double>{},
        deload: deload,
        safety: _cleared,
        cyclePhase: CyclePhase.luteal,
      ));
      // 0.7 * 0.9 = 0.63 — clamps not exceeded.
      expect(plan.intensityFactor, closeTo(0.63, 0.01));
    });

    test('caps at 6 exercises even if duration allows more', () {
      final pool = [
        for (var i = 0; i < 12; i++) _ex('e$i', minutes: 5),
      ];
      final plan = _plan(buildPlan(
        candidatePool: pool,
        reportedInjuries: const [],
        deficit: const <String, double>{},
        deload: _noDeload,
        safety: _cleared,
        targetMinutes: 999,
      ));
      expect(plan.exercises.length, 6);
    });
  });

  group('the plan is ordered by what has been trained least', () {
    // Every case above passes an EMPTY deficit, so until this group existed
    // the ordering — the thing the builder is for — had no coverage at all.
    // That is how the previous signal could be inverted without a red test.

    test('the biggest deficit is picked first', () {
      final plan = _plan(buildPlan(
        candidatePool: [
          _ex('bench', primary: ['chest']),
          _ex('row', primary: ['back']),
        ],
        reportedInjuries: const [],
        deficit: const {'chest': 0.1, 'back': 0.9},
        deload: _noDeload,
        safety: _cleared,
        targetMinutes: 10,
      ));
      expect(plan.exercises.map((e) => e.id), ['row']);
    });

    test('and the reverse, so the order is read and not fixed', () {
      final plan = _plan(buildPlan(
        candidatePool: [
          _ex('bench', primary: ['chest']),
          _ex('row', primary: ['back']),
        ],
        reportedInjuries: const [],
        deficit: const {'chest': 0.9, 'back': 0.1},
        deload: _noDeload,
        safety: _cleared,
        targetMinutes: 10,
      ));
      expect(plan.exercises.map((e) => e.id), ['bench']);
    });

    test('an untagged exercise cannot displace a tagged one', () {
      // 182 catalogue rows carry no muscle tag. When they scored mid-range
      // they tied with every untrained muscle and this greedy fill could take
      // the whole session from them, while the rationale claimed the plan came
      // from the user's own history.
      final plan = _plan(buildPlan(
        candidatePool: [
          _ex('untagged-1'),
          _ex('untagged-2'),
          _ex('row', primary: ['back']),
        ],
        reportedInjuries: const [],
        // Deliberately small: even a nearly-met muscle outranks no signal.
        deficit: const {'back': 0.05},
        deload: _noDeload,
        safety: _cleared,
        targetMinutes: 10,
      ));
      expect(plan.exercises.map((e) => e.id), ['row']);
    });

    test('the cold-start rationale does not claim a history it has not got',
        () {
      final cold = _plan(buildPlan(
        candidatePool: [_ex('a', primary: ['chest'])],
        reportedInjuries: const [],
        deficit: const {},
        deload: _noDeload,
        safety: _cleared,
      ));
      final warm = _plan(buildPlan(
        candidatePool: [_ex('a', primary: ['chest'])],
        reportedInjuries: const [],
        deficit: const {'chest': 0.8},
        deload: _noDeload,
        safety: _cleared,
      ));

      expect(cold.rationale, contains('starting session'));
      expect(warm.rationale, contains('trained least'));
      // The claim this replaces. The builder never read a rating to order
      // anything, and "weakest" is a statement about strength that nothing
      // here measures.
      for (final r in [cold.rationale, warm.rationale]) {
        expect(r, isNot(contains('rating')));
        expect(r, isNot(contains('weakest')));
      }
    });
  });
}
