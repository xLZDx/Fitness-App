import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

/// The builder's floor.
///
/// `par_q_test.dart` proves the screen reaches the right verdict. This proves
/// the verdict reaches the output — which is the half that was missing, since
/// before Gate M there was a `HealthHistory` full of answers and nothing that
/// read them.

ExerciseItem _ex(String id, {List<String> primary = const ['chest']}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      primaryMuscles: primary,
      muscles: primary,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 10,
      summary: '',
      steps: const [],
    );

const _noDeload = DeloadVerdict(
  shouldDeload: false,
  reasons: [],
  suggestedVolumeFactor: 1.0,
);

SafetyVerdict _clear() =>
    screen({for (final q in ParQQuestion.values) q: false});

SafetyVerdict _restricted() => screen({
      for (final q in ParQQuestion.values) q: false,
      ParQQuestion.otherChronicCondition: true,
    });

SafetyVerdict _blocked() => screen({
      for (final q in ParQQuestion.values) q: false,
      ParQQuestion.medicallySupervisedOnly: true,
    });

PlanOutcome _build({
  required SafetyVerdict safety,
  DeloadVerdict deload = _noDeload,
  List<ExerciseItem>? pool,
}) =>
    buildPlan(
      candidatePool: pool ?? [_ex('a'), _ex('b'), _ex('c')],
      reportedInjuries: const <Injury>[],
      deficit: const {'chest': 0.8},
      deload: deload,
      safety: safety,
    );

void main() {
  group('a blocked screen produces no plan', () {
    test('the outcome is a refusal, not an empty plan', () {
      // An empty `GeneratedPlan` was the shape a refusal would have had to take
      // before the sealed type existed, and every consumer renders that as
      // "your session" with nothing in it.
      final out = _build(safety: _blocked());
      expect(out, isA<PlanRefused>());
    });

    test('the refusal carries the reasons, so the UI need not re-derive them',
        () {
      final out = _build(safety: _blocked()) as PlanRefused;
      expect(out.reasons,
          contains(SafetyReason.question(ParQQuestion.medicallySupervisedOnly)));
    });

    test('an unscreened user is refused, not quietly cleared', () {
      final out = _build(safety: kUnscreened);
      expect(out, isA<PlanRefused>());
      expect((out as PlanRefused).reasons.every((r) => r.incomplete), isTrue);
    });

    test('the refusal does not depend on the catalogue having loaded', () {
      // The check runs before the pool is read. A refusal that needs a
      // non-empty catalogue is one that can be raced by a slow asset load, and
      // "the exercises had not arrived yet" is not a reason to hand somebody a
      // workout OR to hand them a different message.
      final empty = _build(safety: _blocked(), pool: const <ExerciseItem>[]);
      final full = _build(safety: _blocked());
      expect(empty, isA<PlanRefused>());
      expect((empty as PlanRefused).reasons, (full as PlanRefused).reasons);
    });
  });

  group('a restricted screen produces a capped plan', () {
    test('a plan is still produced', () {
      // Restricted is not blocked. Refusing here would make the screen a
      // gate on the whole product rather than on the dose.
      final out = _build(safety: _restricted());
      expect(out, isA<PlanReady>());
      expect((out as PlanReady).plan.exercises, isNotEmpty);
    });

    test('intensity is capped below the unrestricted ceiling', () {
      const hot = DeloadVerdict(
        shouldDeload: false,
        reasons: [],
        suggestedVolumeFactor: 1.10,
      );
      final clear = (_build(safety: _clear(), deload: hot) as PlanReady).plan;
      final capped =
          (_build(safety: _restricted(), deload: hot) as PlanReady).plan;

      expect(clear.intensityFactor, closeTo(1.10, 0.0001));
      expect(capped.intensityFactor, lessThan(clear.intensityFactor));
      expect(capped.intensityFactor,
          closeTo(_restricted().intensityCeiling!, 0.0001));
    });

    test('the cap never raises a factor that was already lower', () {
      // `clamp(0.5, ceiling)` with a deload of 0.6 must leave 0.6 alone. A cap
      // that becomes a floor would turn a recovery signal into a prescription
      // to train harder.
      const deloading = DeloadVerdict(
        shouldDeload: true,
        reasons: ['low'],
        suggestedVolumeFactor: 0.6,
      );
      final out =
          (_build(safety: _restricted(), deload: deloading) as PlanReady).plan;
      expect(out.intensityFactor, closeTo(0.6, 0.0001));
    });

    test('the user is told, in the rationale, before anything else', () {
      const deloading = DeloadVerdict(
        shouldDeload: true,
        reasons: ['low'],
        suggestedVolumeFactor: 0.6,
      );
      final out =
          (_build(safety: _restricted(), deload: deloading) as PlanReady).plan;

      expect(out.rationale, startsWith('Your health screening'),
          reason: 'a user the app has not cleared must not have to read past '
              'a deload note to find that out');
      expect(out.rationale, contains('qualified exercise professional'));
    });
  });

  group('a clear screen changes nothing', () {
    test('the plan is the one that was built before the gate existed', () {
      final out = (_build(safety: _clear()) as PlanReady).plan;
      expect(out.exercises, isNotEmpty);
      expect(out.intensityFactor, closeTo(1.0, 0.0001));
      expect(out.rationale, isNot(contains('screening')));
    });
  });
}
