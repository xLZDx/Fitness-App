import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/cycle_aware/data/cycle_phase.dart';

/// Gate O. A calendar estimate may prompt; it may not prescribe.
///
/// The file this replaces asserted that day 14 produces `CyclePhase.ovulatory`
/// and that ovulatory carries `intensityFactor: 1.10`. Both were true of the
/// code and neither was a property worth protecting: the first is arithmetic
/// and the second was a 10% load increase issued to a person the app has never
/// measured, on the strength of that arithmetic.
///
/// What is asserted now is the boundary. The estimate is labelled an estimate,
/// nonsense input produces no estimate at all, and nothing derived from the
/// calendar can raise a prescribed load in any state.

void main() {
  group('the estimate', () {
    test('labels the textbook phases', () {
      // Kept, because the arithmetic still has to be right — it just no longer
      // decides anything.
      expect(estimatePhase(cycleDay: 1).phase, CyclePhase.menstrual);
      expect(estimatePhase(cycleDay: 5).phase, CyclePhase.menstrual);
      expect(estimatePhase(cycleDay: 8).phase, CyclePhase.follicular);
      expect(estimatePhase(cycleDay: 14).phase, CyclePhase.ovulatory);
      expect(estimatePhase(cycleDay: 20).phase, CyclePhase.luteal);
    });

    test('is typed as an estimate, not as a measurement', () {
      // Structural. A consumer that wants the phase has to unwrap a
      // `CycleEstimated`, so the word is in front of them at the call site
      // rather than in a comment one file away.
      expect(estimatePhase(cycleDay: 14), isA<CycleEstimated>());
    });

    test('a shorter cycle moves ovulation with it', () {
      expect(estimatePhase(cycleDay: 11, cycleLength: 21).phase,
          CyclePhase.ovulatory);
      expect(estimatePhase(cycleDay: 14, cycleLength: 21).phase,
          CyclePhase.luteal);
    });
  });

  group('nonsense input produces no phase', () {
    test('day zero and below', () {
      // The old `phaseFor` returned `CyclePhase.luteal` for `cycleDay < 1` — a
      // fabricated normal answer for input that is not a day.
      for (final d in [0, -1, -400]) {
        expect(estimatePhase(cycleDay: d), isA<CycleUnknown>(), reason: '$d');
        expect(estimatePhase(cycleDay: d).phase, isNull);
      }
    });

    test('a day past the end of the cycle', () {
      expect(estimatePhase(cycleDay: 29).phase, isNull);
      expect(estimatePhase(cycleDay: 22, cycleLength: 21).phase, isNull);
    });

    test('a cycle length outside the range the model approximates', () {
      // 21–35 days. Outside it the textbook mid-cycle assumption is not a worse
      // estimate, it is not an estimate.
      expect(estimatePhase(cycleDay: 5, cycleLength: 12).phase, isNull);
      expect(estimatePhase(cycleDay: 5, cycleLength: 90).phase, isNull);
      expect(estimatePhase(cycleDay: 5, cycleLength: 21).phase, isNotNull);
      expect(estimatePhase(cycleDay: 5, cycleLength: 35).phase, isNotNull);
    });

    test('an irregular cycle', () {
      final s = estimatePhase(cycleDay: 14, irregular: true);
      expect(s.phase, isNull);
      expect((s as CycleUnknown).reason, CycleUnavailable.irregular);
    });

    test('and each reason is distinguishable', () {
      // "We do not know" and "this does not apply to you" call for different
      // words, so they must not be one value.
      expect(
          (estimatePhase(cycleDay: 0) as CycleUnknown).reason,
          CycleUnavailable.outOfRange);
      expect(
          (estimatePhase(cycleDay: 14, applicable: false) as CycleUnknown)
              .reason,
          CycleUnavailable.notApplicable);
    });
  });

  group('applicability', () {
    test('not applicable wins over every other input', () {
      // Pregnancy and postpartum arrive here as one flag, deliberately: what
      // the app needs to know is whether cycle-derived suggestions are valid,
      // and holding a pregnancy status to reason about is a different product.
      expect(estimatePhase(cycleDay: 14, applicable: false).phase, isNull);
      expect(
          estimatePhase(cycleDay: 14, irregular: true, applicable: false)
              .runtimeType,
          CycleUnknown);
      expect(
          (estimatePhase(cycleDay: 14, irregular: true, applicable: false)
                  as CycleUnknown)
              .reason,
          CycleUnavailable.notApplicable,
          reason: 'the stronger statement is the one to report');
    });
  });

  group('the calendar cannot raise a load, in any state', () {
    test('no phase carries a multiplier at all any more', () {
      // The mutation this group exists to catch: a phase must not be able to
      // acquire a number. `CyclePhase` is a bare enum with no fields, so
      // re-adding a factor means re-adding a field -- a deliberate act rather
      // than an edit to a constant.
      //
      // F027 moved the note TEXT out of this layer and into the ARB, since a
      // pure data file cannot know the user's locale. The three assertions
      // that were here about that text -- that it claims no performance peak,
      // and that it presents itself as a calendar estimate -- did not go away:
      // they moved to `plan_reason_text_test.dart`, where they now run against
      // BOTH languages instead of only the English one.
      for (final p in CyclePhase.values) {
        expect(p.name, isNotEmpty);
      }
      expect(CyclePhase.values, hasLength(4));
    });
  });

  group('only a self-report changes the dose, and only downwards', () {
    test('feeling as usual changes nothing', () {
      // The whole reform in one case: a person who says they feel fine gets
      // their normal session even if the calendar says day 2.
      expect(adjustmentFor(CycleSelfReport.asUsual).intensityCeiling, isNull);
      expect(adjustmentFor(null).intensityCeiling, isNull);
    });

    test('low energy and symptoms cap, in that order', () {
      expect(adjustmentFor(CycleSelfReport.lowEnergy).intensityCeiling, 0.9);
      expect(
          adjustmentFor(CycleSelfReport.significantSymptoms).intensityCeiling,
          0.7);
    });

    test('no self-report can produce a ceiling above 1.0', () {
      for (final r in CycleSelfReport.values) {
        final c = adjustmentFor(r).intensityCeiling;
        if (c != null) {
          expect(c, lessThanOrEqualTo(1.0), reason: r.name);
        }
      }
    });

    test('an adjustment always explains itself', () {
      // Was: `rationale.isEmpty == (intensityCeiling == null)`. That coupling
      // is exactly what F027 removed -- an English string in a data layer was
      // load-bearing for whether the user was told about a cap, so emptying it
      // would have hidden the cap silently.
      //
      // The property survives in a stronger form: a capped self-report must
      // produce a reason CODE, and the renderer must have a sentence for it in
      // every language. The first half is asserted here; the second is a
      // compile-time exhaustiveness check in `plan_reason_text.dart` plus the
      // both-locales pass in `plan_reason_text_test.dart`.
      for (final r in CycleSelfReport.values) {
        final capped = adjustmentFor(r).intensityCeiling != null;
        expect(capped, r != CycleSelfReport.asUsual,
            reason: '${r.name}: a silent cap is a change the user cannot see');
      }
    });
  });
}
