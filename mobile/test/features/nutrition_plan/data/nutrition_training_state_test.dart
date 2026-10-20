// T18 nutrition_training_state_test (PROG-01..PROG-09, PROG-10 function half).
// The nutrition-aware programme advice may only LOWER load, never acts on
// missing data, and every rule is tested on both sides of its boundary.
import 'package:fitness_app/features/nutrition_plan/data/missing_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_training_state.dart';
import 'package:flutter_test/flutter_test.dart';

NutritionTrainingInput _in({
  NutritionEligibility eligibility = const Eligible(),
  EnergyPhase? phase = EnergyPhase.deficit,
  double? deficitPct,
  double? surplusPct,
  double? adherence,
  int logged = 14,
  double? sleep,
  double? rate,
  double? maxRate,
  int sessions = 3,
  bool recovery = false,
  double? kcalMid = 2000,
  double? floor = 1500,
}) =>
    NutritionTrainingInput(
      eligibility: eligibility,
      phase: phase,
      deficitPct: deficitPct,
      surplusPct: surplusPct,
      proteinAdherence: adherence,
      loggedDays14: logged,
      avgSleepHours: sleep,
      weightRatePctPerWeek: rate,
      planMaxRatePctPerWeek: maxRate,
      sessionsPerWeek: sessions,
      recoveryDeloadSignal: recovery,
      kcalMid: kcalMid,
      floorKcal: floor,
    );

TrainingNutritionAdvice _a(NutritionTrainingInput i) =>
    adviseTrainingFromNutrition(i);

void main() {
  group('PROG-01 neutral on missing or ineligible data', () {
    void expectNeutral(TrainingNutritionAdvice a) {
      expect(a.neutral, isTrue);
      expect(a.volumeFactor, 1.0);
      expect(a.intensityCapDelta, 0.0);
      expect(a.deload, DeloadSuggestion.none);
      expect(a.reasons, isEmpty);
      expect(a.showProfessionalLine, isFalse);
    }

    test('every non-eligible verdict gives the neutral advice, whatever the numbers say', () {
      final worst = {
        'referProfessional': const ReferProfessional(ReferReason.guidance),
        'needsAnswer': const NeedsAnswer(NutritionQuestion.nutritionGuidance),
        'needsProfile': const NeedsProfile([NutritionInput.height]),
      };
      worst.forEach((name, e) {
        expectNeutral(_a(_in(
          eligibility: e,
          deficitPct: 0.4,
          adherence: 0.1,
          sleep: 4,
          rate: -3,
          maxRate: 0.5,
          sessions: 7,
          recovery: true,
          kcalMid: 1500,
          floor: 1500,
        )));
      });
    });
    test('unknown kcalMid is neutral', () {
      expectNeutral(_a(_in(kcalMid: null, deficitPct: 0.4, sleep: 4)));
    });
    test('unknown phase is neutral', () {
      expectNeutral(_a(_in(phase: null, deficitPct: 0.4, sleep: 4)));
    });
    test('an eligible user with nothing notable is neutral too', () {
      expectNeutral(_a(_in()));
    });
    test('the static neutral advice object', () {
      expectNeutral(TrainingNutritionAdvice.neutralAdvice);
      expectNeutral(const TrainingNutritionAdvice());
    });
    test('neutral is false as soon as anything is applied', () {
      expect(const TrainingNutritionAdvice(volumeFactor: 0.95).neutral, isFalse);
      expect(const TrainingNutritionAdvice(intensityCapDelta: -0.05).neutral, isFalse);
      expect(const TrainingNutritionAdvice(deload: DeloadSuggestion.consider).neutral,
          isFalse);
      expect(
          const TrainingNutritionAdvice(
              reasons: [TrainingNutritionReason.sleepLow]).neutral,
          isFalse);
    });
  });

  group('PROG-02 deficit depth (V-TRAIN)', () {
    test('0.0999 -> 1.0 (no trim, nothing recorded)', () {
      final a = _a(_in(deficitPct: 0.0999));
      expect(a.volumeFactor, 1.0);
      expect(a.reasons, isEmpty);
      expect(a.neutral, isTrue);
    });
    test('0.10 -> 0.95', () {
      final a = _a(_in(deficitPct: 0.10));
      expect(a.volumeFactor, 0.95);
      expect(a.reasons, [TrainingNutritionReason.deficitVolumeTrim]);
    });
    test('0.1999 -> 0.95', () {
      expect(_a(_in(deficitPct: 0.1999)).volumeFactor, 0.95);
    });
    test('0.20 -> 0.85', () {
      final a = _a(_in(deficitPct: 0.20));
      expect(a.volumeFactor, 0.85);
      expect(a.reasons, [TrainingNutritionReason.deficitVolumeTrim]);
    });
    test('a very deep deficit stays at 0.85 (no further trim from this rule)', () {
      expect(_a(_in(deficitPct: 0.5)).volumeFactor, 0.85);
    });
    test('a deficit alone never lowers intensity or suggests a deload', () {
      for (final d in [0.10, 0.2, 0.4]) {
        final a = _a(_in(deficitPct: d));
        expect(a.intensityCapDelta, 0.0);
        expect(a.deload, DeloadSuggestion.none);
      }
    });
    test('the trim applies only in the deficit phase', () {
      expect(_a(_in(phase: EnergyPhase.maintenance, deficitPct: 0.3)).volumeFactor, 1.0);
      expect(_a(_in(phase: EnergyPhase.surplus, deficitPct: 0.3)).volumeFactor, 1.0);
    });
    test('an unknown deficit percentage trims nothing', () {
      expect(_a(_in()).volumeFactor, 1.0);
    });
  });

  group('PROG-03 surplus boost conditions', () {
    NutritionTrainingInput s(double? sleep, double? adh, {int logged = 14}) =>
        _in(phase: EnergyPhase.surplus, sleep: sleep, adherence: adh, logged: logged);

    test('(6.99 h, 0.70) -> 1.0', () => expect(_a(s(6.99, 0.7)).volumeFactor, 1.0));
    test('(7.0 h, 0.69) -> 1.0', () => expect(_a(s(7.0, 0.69)).volumeFactor, 1.0));
    test('(7.0 h, 0.70) -> 1.05 with the boost reason', () {
      final a = _a(s(7.0, 0.7));
      expect(a.volumeFactor, 1.05);
      expect(a.reasons, [TrainingNutritionReason.surplusVolumeBoost]);
    });
    test('better than the thresholds also boosts, never above 1.05', () {
      expect(_a(s(9, 1.0)).volumeFactor, 1.05);
    });
    test('unknown sleep or unknown adherence -> no boost', () {
      expect(_a(s(null, 0.9)).volumeFactor, 1.0);
      expect(_a(s(8, null)).volumeFactor, 1.0);
    });
    test('adherence needs >= 4 logged days: 3 days -> no boost', () {
      expect(_a(s(8, 0.9, logged: 3)).volumeFactor, 1.0);
      expect(_a(s(8, 0.9, logged: 4)).volumeFactor, 1.05);
    });
    test('the boost applies only in the surplus phase', () {
      for (final p in [EnergyPhase.deficit, EnergyPhase.maintenance]) {
        expect(_a(_in(phase: p, sleep: 8, adherence: 0.9)).volumeFactor,
            lessThanOrEqualTo(1.0));
      }
    });
  });

  group('PROG-04 protein adherence', () {
    test('fewer than 4 logged days -> adherence ignored, no reason, no deload', () {
      final a = _a(_in(adherence: 0.1, logged: 3));
      expect(a.reasons, isEmpty);
      expect(a.deload, DeloadSuggestion.none);
    });
    test('4 logged days with adherence 0.49 in deficit -> proteinLow + consider', () {
      final a = _a(_in(adherence: 0.49, logged: 4));
      expect(a.reasons, [TrainingNutritionReason.proteinLow]);
      expect(a.deload, DeloadSuggestion.consider);
    });
    test('volume is unchanged by the protein rule itself', () {
      expect(_a(_in(adherence: 0.2)).volumeFactor, 1.0);
      expect(_a(_in(adherence: 0.2, deficitPct: 0.15)).volumeFactor, 0.95);
    });
    test('adherence exactly 0.5 -> none', () {
      final a = _a(_in(adherence: 0.5));
      expect(a.reasons, isEmpty);
      expect(a.deload, DeloadSuggestion.none);
    });
    test('only in a deficit: maintenance and surplus ignore low adherence', () {
      expect(_a(_in(phase: EnergyPhase.maintenance, adherence: 0.1)).reasons, isEmpty);
      expect(_a(_in(phase: EnergyPhase.surplus, adherence: 0.1)).reasons, isEmpty);
    });
  });

  group('PROG-05 sleep', () {
    test('6.0 h -> no change', () {
      final a = _a(_in(sleep: 6.0));
      expect(a.intensityCapDelta, 0.0);
      expect(a.reasons, isEmpty);
    });
    test('5.99 h -> intensityCapDelta -0.05 and sleepLow', () {
      final a = _a(_in(sleep: 5.99));
      expect(a.intensityCapDelta, -0.05);
      expect(a.reasons, [TrainingNutritionReason.sleepLow]);
    });
    test('applies in every phase', () {
      for (final p in EnergyPhase.values) {
        expect(_a(_in(phase: p, sleep: 4)).intensityCapDelta, -0.05);
      }
    });
    test('unknown sleep changes nothing; very short sleep is still only -0.05', () {
      expect(_a(_in()).intensityCapDelta, 0.0);
      expect(_a(_in(sleep: 0)).intensityCapDelta, -0.05);
    });
  });

  group('PROG-06 fast loss', () {
    test('rate exactly -1.25 x max (-0.625 at max 0.5) is NOT triggered', () {
      final a = _a(_in(rate: -0.625, maxRate: 0.5));
      expect(a.reasons, isEmpty);
      expect(a.deload, DeloadSuggestion.none);
    });
    test('beyond it: volume 0.90, deload consider, lossTooFast', () {
      final a = _a(_in(rate: -0.63, maxRate: 0.5));
      expect(a.volumeFactor, 0.90);
      expect(a.deload, DeloadSuggestion.consider);
      expect(a.reasons, [TrainingNutritionReason.lossTooFast]);
    });
    test('volume is min(current, 0.90): a deep deficit trim of 0.85 stays; 0.95 drops to 0.90', () {
      expect(_a(_in(rate: -1, maxRate: 0.5, deficitPct: 0.25)).volumeFactor, 0.85);
      expect(_a(_in(rate: -1, maxRate: 0.5, deficitPct: 0.12)).volumeFactor, 0.90);
    });
    test('a weight gain or missing rate/max never triggers it', () {
      expect(_a(_in(rate: 0.5, maxRate: 0.5)).reasons, isEmpty);
      expect(_a(_in(rate: -3, maxRate: null)).reasons, isEmpty);
      expect(_a(_in(rate: null, maxRate: 0.5)).reasons, isEmpty);
    });
  });

  group('PROG-07 low intake with high load', () {
    test('kcalMid = floor x 1.05 with 5 sessions -> recommended + lowIntakeHighLoad + the generic line', () {
      final a = _a(_in(kcalMid: 1890, floor: 1800, sessions: 5));
      expect(a.deload, DeloadSuggestion.recommended);
      expect(a.reasons, [TrainingNutritionReason.lowIntakeHighLoad]);
      expect(a.showProfessionalLine, isTrue);
    });
    test('4 sessions, or floor x 1.06 (1908), are not triggered', () {
      expect(_a(_in(kcalMid: 1890, floor: 1800, sessions: 4)).deload,
          DeloadSuggestion.none);
      final a = _a(_in(kcalMid: 1908, floor: 1800, sessions: 5));
      expect(a.deload, DeloadSuggestion.none);
      expect(a.showProfessionalLine, isFalse);
    });
    test('one kcal over the boundary (1891) is not triggered; far below the floor is', () {
      expect(_a(_in(kcalMid: 1891, floor: 1800, sessions: 5)).deload,
          DeloadSuggestion.none);
      expect(_a(_in(kcalMid: 1500, floor: 1800, sessions: 6)).deload,
          DeloadSuggestion.recommended);
    });
    test('an unknown floor never triggers it', () {
      expect(_a(_in(kcalMid: 1500, floor: null, sessions: 7)).deload,
          DeloadSuggestion.none);
    });
    test('no energy-availability or RED-S wording in any reason code', () {
      for (final r in TrainingNutritionReason.values) {
        final n = r.name.toLowerCase();
        expect(n, isNot(contains('energyavailability')));
        expect(n, isNot(contains('reds')));
        expect(n, isNot(contains('red-s')));
        expect(n, isNot(contains('availability')));
      }
    });
  });

  group('PROG-08 recovery signal preserved', () {
    test('recoveryDeloadSignal -> recommended regardless of nutrition', () {
      final a = _a(_in(recovery: true));
      expect(a.deload, DeloadSuggestion.recommended);
      expect(a.reasons, [TrainingNutritionReason.recoveryDeload]);
    });
    test('it stays recommended in surplus and maintenance too', () {
      for (final p in EnergyPhase.values) {
        expect(_a(_in(phase: p, recovery: true)).deload,
            DeloadSuggestion.recommended);
      }
    });
    test('it never lowers an already stronger suggestion and stacks without losing reasons', () {
      final a = _a(_in(
          recovery: true, kcalMid: 1500, floor: 1800, sessions: 6));
      expect(a.deload, DeloadSuggestion.recommended);
      expect(a.reasons, containsAll([
        TrainingNutritionReason.lowIntakeHighLoad,
        TrainingNutritionReason.recoveryDeload,
      ]));
    });
  });

  group('PROG-09 clamps and no stacking', () {
    test('every rule at once stays inside the clamps', () {
      final a = _a(_in(
        deficitPct: 0.35,
        adherence: 0.1,
        sleep: 4,
        rate: -2,
        maxRate: 0.5,
        sessions: 7,
        recovery: true,
        kcalMid: 1500,
        floor: 1500,
      ));
      expect(a.volumeFactor, inInclusiveRange(0.70, 1.05));
      expect(a.volumeFactor, 0.85); // min of the deep-deficit trim and 0.90
      expect(a.intensityCapDelta, inInclusiveRange(-0.10, 0.0));
      expect(a.intensityCapDelta, -0.05);
      expect(a.deload, DeloadSuggestion.recommended);
      expect(a.reasons.toSet().length, a.reasons.length); // no duplicates
      expect(a.reasons.toSet(), {
        TrainingNutritionReason.deficitVolumeTrim,
        TrainingNutritionReason.proteinLow,
        TrainingNutritionReason.sleepLow,
        TrainingNutritionReason.lossTooFast,
        TrainingNutritionReason.lowIntakeHighLoad,
        TrainingNutritionReason.recoveryDeload,
      });
    });
    test('volumeFactor and delta stay in range over a grid of inputs', () {
      for (final phase in EnergyPhase.values) {
        for (final deficit in [null, 0.05, 0.1, 0.2, 0.4]) {
          for (final sleep in [null, 4.0, 6.0, 7.0, 9.0]) {
            for (final adh in [null, 0.2, 0.5, 0.9]) {
              for (final rate in [null, -2.0, 0.3]) {
                final a = _a(_in(
                  phase: phase,
                  deficitPct: deficit,
                  sleep: sleep,
                  adherence: adh,
                  rate: rate,
                  maxRate: 0.5,
                  sessions: 5,
                  kcalMid: 1500,
                  floor: 1500,
                ));
                expect(a.volumeFactor, inInclusiveRange(0.70, 1.05));
                expect(a.intensityCapDelta, inInclusiveRange(-0.10, 0.0));
              }
            }
          }
        }
      }
    });
    test('nutrition can only LOWER volume in a deficit and never raises intensity', () {
      for (final d in [0.0, 0.1, 0.2, 0.3]) {
        final a = _a(_in(deficitPct: d));
        expect(a.volumeFactor, lessThanOrEqualTo(1.0));
        expect(a.intensityCapDelta, lessThanOrEqualTo(0.0));
      }
    });
    test('limits table constants', () {
      expect(TrainingNutritionLimits.deepDeficitPct, 0.20);
      expect(TrainingNutritionLimits.moderateDeficitPct, 0.10);
      expect(TrainingNutritionLimits.deepDeficitVolume, 0.85);
      expect(TrainingNutritionLimits.moderateDeficitVolume, 0.95);
      expect(TrainingNutritionLimits.surplusVolume, 1.05);
      expect(TrainingNutritionLimits.surplusMinSleepHours, 7.0);
      expect(TrainingNutritionLimits.surplusMinProteinAdherence, 0.7);
      expect(TrainingNutritionLimits.minLoggedDays, 4);
      expect(TrainingNutritionLimits.proteinLowAdherence, 0.5);
      expect(TrainingNutritionLimits.lowSleepHours, 6.0);
      expect(TrainingNutritionLimits.lowSleepIntensityDelta, -0.05);
      expect(TrainingNutritionLimits.fastLossFactor, 1.25);
      expect(TrainingNutritionLimits.fastLossVolume, 0.90);
      expect(TrainingNutritionLimits.lowIntakeFloorFactor, 1.05);
      expect(TrainingNutritionLimits.highLoadSessionsPerWeek, 5);
      expect(TrainingNutritionLimits.volumeMin, 0.70);
      expect(TrainingNutritionLimits.volumeMax, 1.05);
      expect(TrainingNutritionLimits.intensityDeltaMin, -0.10);
    });
    test('DeloadSuggestion.max keeps the stronger of two', () {
      expect(DeloadSuggestion.none.max(DeloadSuggestion.consider),
          DeloadSuggestion.consider);
      expect(DeloadSuggestion.recommended.max(DeloadSuggestion.consider),
          DeloadSuggestion.recommended);
      expect(DeloadSuggestion.consider.max(DeloadSuggestion.consider),
          DeloadSuggestion.consider);
    });
  });

  group('PROG-10 combinedIntensityCeiling: the more conservative cap wins', () {
    test('the minimum of the base, the age cap, the screening ceiling and the hint cap', () {
      expect(
          combinedIntensityCeiling(
              baseCeiling: 1.0, ageCap: 0.8, screeningCeiling: 0.9, hintCap: 0.85),
          0.8);
      expect(
          combinedIntensityCeiling(
              baseCeiling: 1.0, ageCap: 0.9, screeningCeiling: 0.7),
          0.7);
      expect(combinedIntensityCeiling(baseCeiling: 0.9, ageCap: 1.0), 0.9);
    });
    test('the nutrition delta lowers the result: 0.8 - 0.05 = 0.75', () {
      final r = combinedIntensityCeiling(
        baseCeiling: 1.0,
        ageCap: 0.8,
        advice: const TrainingNutritionAdvice(intensityCapDelta: -0.05),
      );
      expect(r, closeTo(0.75, 1e-12));
    });
    test('a POSITIVE delta is ignored: nutrition never raises a cap safety set', () {
      final r = combinedIntensityCeiling(
        baseCeiling: 1.0,
        ageCap: 0.8,
        advice: const TrainingNutritionAdvice(intensityCapDelta: 0.2),
      );
      expect(r, 0.8);
    });
    test('the neutral advice leaves the safety cap exactly as it is', () {
      expect(combinedIntensityCeiling(baseCeiling: 1.0, screeningCeiling: 0.6), 0.6);
    });
    test('the result never goes under the floor 0.5 by nutrition alone, and never above a lower cap', () {
      expect(
          combinedIntensityCeiling(
              baseCeiling: 0.52,
              advice: const TrainingNutritionAdvice(intensityCapDelta: -0.05)),
          0.5);
      // a safety cap already below the floor is kept, not raised to it.
      expect(
          combinedIntensityCeiling(
              baseCeiling: 0.4,
              advice: const TrainingNutritionAdvice(intensityCapDelta: -0.05)),
          0.4);
    });
    test('a custom floor is honoured', () {
      expect(
          combinedIntensityCeiling(
              baseCeiling: 0.7,
              floor: 0.68,
              advice: const TrainingNutritionAdvice(intensityCapDelta: -0.05)),
          0.68);
    });
  });
}
