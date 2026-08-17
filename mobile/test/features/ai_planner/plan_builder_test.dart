import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/cycle_aware/data/cycle_phase.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
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
final _cleared = SafetyContext(
    screening: screen({for (final q in ParQQuestion.values) q: false}));

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
        safety: SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}),
          injuries: const [Injury(bodyPart: 'shoulder', type: 'impingement')],
        ),
        deficit: const <String, double>{},
        deload: _noDeload,
      ));
      expect(plan.exercises.map((e) => e.id), ['squat']);
      expect(
          plan.reasons,
          contains(isA<InjuryFilterReason>()
              .having((r) => r.count, 'count', 1)));
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
        safety: SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}),
          injuries: const [Injury(bodyPart: 'shoulder', type: 'strain')],
        ),
        deficit: const <String, double>{},
        deload: _noDeload,
      ));
      // F027: the claim now lives in the ARB, so the code asserts the
      // CODE and `plan_reason_text_test.dart` asserts the wording. Both
      // halves still have to hold; what changed is that the wording half
      // is now checked in Russian too, where it previously could not be.
      expect(plan.reasons, contains(isA<InjuryFilterReason>()));
    });

    test('respects target minutes (greedy fill)', () {
      final pool = [
        _ex('a', minutes: 25),
        _ex('b', minutes: 25),
        _ex('c', minutes: 25),
      ];
      final plan = _plan(buildPlan(
        candidatePool: pool,
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
        reasons: [const HardSessionsSignal(7)],
        suggestedVolumeFactor: 0.5,
      );
      final plan = _plan(buildPlan(
        candidatePool: [_ex('squat', muscles: ['quads'])],
        deficit: const <String, double>{},
        deload: deload,
        safety: _cleared,
      ));
      expect(plan.title, PlanTitle.deload);
      expect(plan.intensityFactor, closeTo(0.5, 0.0001));
      expect(plan.reasons, contains(isA<DeloadReason>()));
    });

    test('the factor shortens the session it is printed over', () {
      // The defect this replaces: the factor was computed after the greedy
      // fill, so the screen said "intensity 50%" above exactly the session a
      // well-recovered user was handed. A number about a prescription has to
      // be a property of the prescription.
      final pool = [
        for (var i = 0; i < 8; i++) _ex('e$i', muscles: ['m$i'], minutes: 10),
      ];
      const halved = DeloadVerdict(
        shouldDeload: true,
        reasons: [const HardSessionsSignal(7)],
        suggestedVolumeFactor: 0.5,
      );

      final full = _plan(buildPlan(
        candidatePool: pool,
        deficit: const <String, double>{},
        deload: _noDeload,
        safety: _cleared,
        targetMinutes: 60,
      ));
      final reduced = _plan(buildPlan(
        candidatePool: pool,
        deficit: const <String, double>{},
        deload: halved,
        safety: _cleared,
        targetMinutes: 60,
      ));

      expect(reduced.intensityFactor, closeTo(0.5, 0.0001));
      expect(reduced.estimatedMinutes, lessThan(full.estimatedMinutes),
          reason: 'half the volume has to be half the session');
      expect(reduced.exercises.length, lessThan(full.exercises.length));
      expect(reduced.estimatedMinutes,
          lessThanOrEqualTo((full.estimatedMinutes * 0.6).ceil()));
    });

    test('a low factor over a short target still produces a session', () {
      // The floor. Scaling a 15-minute target by 0.5 without one leaves 8
      // minutes, which no exercise fits into — an empty plan with no reason
      // attached, which is the shape Gate M exists to prevent.
      final plan = _plan(buildPlan(
        candidatePool: [_ex('squat', muscles: ['quads'], minutes: 10)],
        deficit: const <String, double>{},
        deload: const DeloadVerdict(
          shouldDeload: true,
          reasons: [const HardSessionsSignal(7)],
          suggestedVolumeFactor: 0.5,
        ),
        safety: _cleared,
        targetMinutes: 15,
      ));
      expect(plan.exercises, isNotEmpty);
    });

    test('a cycle self-report caps, and the calendar phase does not', () {
      // Rewritten in Gate O. This case asserted `0.7 * 0.9 = 0.63` — the deload
      // factor MULTIPLIED by the luteal phase's multiplier, which is exactly
      // the behaviour that turned a calendar day into a prescription. The phase
      // no longer multiplies anything.
      const deload = DeloadVerdict(
        shouldDeload: true,
        reasons: [],
        suggestedVolumeFactor: 0.7,
      );
      final withPhaseOnly = _plan(buildPlan(
        candidatePool: [_ex('squat', muscles: ['quads'])],
        deficit: const <String, double>{},
        deload: deload,
        safety: _cleared,
        cycle: const CycleEstimated(CyclePhase.luteal),
      ));
      expect(withPhaseOnly.intensityFactor, closeTo(0.7, 0.0001),
          reason: 'the deload factor, untouched by the calendar');
      expect(
          withPhaseOnly.reasons,
          contains(isA<CyclePhaseReason>()
              .having((r) => r.phase, 'phase', CyclePhase.luteal)),
          reason: 'the estimate is still SAID, it just decides nothing');

      final withReport = _plan(buildPlan(
        candidatePool: [_ex('squat', muscles: ['quads'])],
        deficit: const <String, double>{},
        deload: _noDeload,
        safety: _cleared,
        cycle: const CycleEstimated(CyclePhase.luteal),
        cycleSelfReport: CycleSelfReport.significantSymptoms,
      ));
      expect(withReport.intensityFactor, closeTo(0.7, 0.0001));
      expect(withReport.title, PlanTitle.easy);
    });

    test('the calendar cannot raise the factor in any phase', () {
      // The mutation that matters. Before Gate O, ovulatory multiplied by 1.10.
      const hot = DeloadVerdict(
        shouldDeload: false,
        reasons: [],
        suggestedVolumeFactor: 1.0,
      );
      for (final phase in CyclePhase.values) {
        final plan = _plan(buildPlan(
          candidatePool: [_ex('squat', muscles: ['quads'])],
          deficit: const <String, double>{},
          deload: hot,
          safety: _cleared,
          cycle: CycleEstimated(phase),
        ));
        expect(plan.intensityFactor, closeTo(1.0, 0.0001), reason: phase.name);
      }
    });

    test('caps at 6 exercises even if duration allows more', () {
      final pool = [
        for (var i = 0; i < 12; i++) _ex('e$i', minutes: 5),
      ];
      final plan = _plan(buildPlan(
        candidatePool: pool,
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
        deficit: const {},
        deload: _noDeload,
        safety: _cleared,
      ));
      final warm = _plan(buildPlan(
        candidatePool: [_ex('a', primary: ['chest'])],
        deficit: const {'chest': 0.8},
        deload: _noDeload,
        safety: _cleared,
      ));

      expect(cold.reasons, contains(isA<NoHistoryReason>()));
      expect(warm.reasons, contains(isA<DeficitOrderReason>()));
      // The claim this replaces -- the builder never read a rating to
      // order anything, and "weakest" is a statement about strength that
      // nothing here measures -- is now a property of the copy rather
      // than of this function, and is asserted against both ARB files in
      // `plan_reason_text_test.dart`. It cannot be checked here any more
      // because there is no English in reach of this test, which is the
      // point of the change.
    });
  });
}
