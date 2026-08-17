import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
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

SafetyContext _ctx(Map<ParQQuestion, bool> answers,
        {HealthFlags health = HealthFlags.empty}) =>
    SafetyContext(screening: screen(answers), health: health);

SafetyContext _clear() =>
    _ctx({for (final q in ParQQuestion.values) q: false});

SafetyContext _restricted() => _ctx({
      for (final q in ParQQuestion.values) q: false,
      ParQQuestion.otherChronicCondition: true,
    });

SafetyContext _blocked() => _ctx({
      for (final q in ParQQuestion.values) q: false,
      ParQQuestion.medicallySupervisedOnly: true,
    });

/// Gate N: refused for a reason with no PAR-Q+ question behind it.
SafetyContext _postSurgical() => _ctx(
      {for (final q in ParQQuestion.values) q: false},
      health: const HealthFlags(surgery: SurgeryStatus.underRestrictions),
    );

PlanOutcome _build({
  required SafetyContext safety,
  DeloadVerdict deload = _noDeload,
  List<ExerciseItem>? pool,
}) =>
    buildPlan(
      candidatePool: pool ?? [_ex('a'), _ex('b'), _ex('c')],
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
      expect(
          out.reasons,
          contains(const EligibilityReason(BlockReason.screening,
              question: ParQQuestion.medicallySupervisedOnly)));
    });

    test('a Gate N refusal names itself, and is not called a screening one',
        () {
      // Post-operative restrictions have no PAR-Q+ question behind them. While
      // `PlanRefused` carried Gate M's narrower `SafetyReason` this refusal
      // could only have come back with an empty reason list — a card with a
      // heading and no explanation.
      final out = _build(safety: _postSurgical());
      expect(out, isA<PlanRefused>());
      expect((out as PlanRefused).reasons,
          [const EligibilityReason(BlockReason.postSurgical)]);
    });

    test('an unscreened user is refused, not quietly cleared', () {
      final out = _build(safety: SafetyContext(screening: kUnscreened));
      expect(out, isA<PlanRefused>());
      expect((out as PlanRefused).reasons.every((r) => r.unanswered), isTrue);
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

    test('a factor that is not a real number does not become the maximum', () {
      // Traced first, and NOT reachable today: both `buildPlan` call sites
      // take their verdict from `deloadVerdictProvider` -> `detectDeload`,
      // which returns 0.5 or 1.0 and nothing else. This is about the SHAPE of
      // the failure if a second producer ever appears — the same argument
      // R-03 made about a terminal mutation with one gated caller.
      //
      // The direction is what makes it worth a case, and it was measured
      // rather than assumed. The first version of this reasoning predicted a
      // crash: `clamp` propagating NaN into `.round()`. Measured, Dart does
      // not propagate it — `double.nan.clamp(0.5, 1.10)` returns **1.10**, the
      // upper limit. So an unusable factor came out of the clamp as the
      // planner's MAXIMUM intensity, and "we could not work out a recovery
      // factor" read as "train ten per cent harder than baseline".
      final unusable = DeloadVerdict(
        shouldDeload: false,
        reasons: const [],
        // Computed, not a literal: `double.nan` as a const would be folded and
        // the point is a value arriving at runtime.
        suggestedVolumeFactor: double.nan * 1,
      );
      final out = (_build(safety: _clear(), deload: unusable) as PlanReady).plan;

      expect(out.intensityFactor.isFinite, isTrue);
      expect(out.intensityFactor, lessThanOrEqualTo(1.0),
          reason: 'an unusable recovery factor must not resolve to more work '
              'than an unremarkable week');
    });

    test('an unusable factor is still subject to the screening ceiling', () {
      // The substitute value is not exempt from the gate that outranks it.
      final unusable = DeloadVerdict(
        shouldDeload: false,
        reasons: const [],
        suggestedVolumeFactor: double.nan * 1,
      );
      final out =
          (_build(safety: _restricted(), deload: unusable) as PlanReady).plan;
      expect(out.intensityFactor,
          closeTo(_restricted().intensityCeiling!, 0.0001));
    });

    test('the cap never raises a factor that was already lower', () {
      // `clamp(0.5, ceiling)` with a deload of 0.6 must leave 0.6 alone. A cap
      // that becomes a floor would turn a recovery signal into a prescription
      // to train harder.
      const deloading = DeloadVerdict(
        shouldDeload: true,
        reasons: [const HardSessionsSignal(7)],
        suggestedVolumeFactor: 0.6,
      );
      final out =
          (_build(safety: _restricted(), deload: deloading) as PlanReady).plan;
      expect(out.intensityFactor, closeTo(0.6, 0.0001));
    });

    test('the user is told, in the rationale, before anything else', () {
      const deloading = DeloadVerdict(
        shouldDeload: true,
        reasons: [const HardSessionsSignal(7)],
        suggestedVolumeFactor: 0.6,
      );
      final out =
          (_build(safety: _restricted(), deload: deloading) as PlanReady).plan;

      expect(out.reasons.first, isA<ScreeningCeilingReason>(),
          reason: 'a user the app has not cleared must not have to read past '
              'a deload note to find that out');
      // Order is the assertion. `first` rather than `contains` because a
      // ceiling that is merely PRESENT, below a deload note, is the defect
      // this case was written for -- and a list of codes makes the
      // position checkable, which a joined paragraph did not.
      expect(out.reasons.whereType<DeloadReason>(), isNotEmpty,
          reason: 'the deload note is still made, just not first');
    });
  });

  group('a clear screen changes nothing', () {
    test('the plan is the one that was built before the gate existed', () {
      final out = (_build(safety: _clear()) as PlanReady).plan;
      expect(out.exercises, isNotEmpty);
      expect(out.intensityFactor, closeTo(1.0, 0.0001));
      expect(out.reasons.whereType<ScreeningCeilingReason>(), isEmpty);
    });
  });
}
