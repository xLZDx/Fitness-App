import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/workouts/data/set_prescription.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';

/// Timed or repetition based, and with which numbers.
///
/// The mode is derived from the exercise itself (no programme-level
/// prescription yet), so the derivation is the contract: a plank must keep its
/// clock, a squat must lose it, and an unknown row must fail to the
/// behaviour that predates this feature (timed).
ExerciseItem _ex({
  String id = 'e',
  String title = 'Goblet squat',
  String? equipmentId,
  bool isStretch = false,
  String? vendorGroup,
}) =>
    ExerciseItem(
      id: id,
      title: title,
      equipmentId: equipmentId,
      muscles: const ['legs'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 5,
      summary: '',
      steps: const [],
      isStretch: isStretch,
      vendorGroup: vendorGroup,
    );

void main() {
  group('SetPrescription value', () {
    test('defaults to timed with no reps and no load', () {
      const p = SetPrescription();
      expect(p.mode, SetMode.timed);
      expect(p.isReps, isFalse);
      expect(p.targetReps, isNull);
      expect(p.loadKg, isNull);
    });

    test('reps mode reports isReps', () {
      expect(const SetPrescription(mode: SetMode.reps, targetReps: 5).isReps,
          isTrue);
    });

    test('equality and hashCode cover every field', () {
      const a = SetPrescription(mode: SetMode.reps, targetReps: 8, loadKg: 20);
      const same =
          SetPrescription(mode: SetMode.reps, targetReps: 8, loadKg: 20);
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a,
          isNot(const SetPrescription(mode: SetMode.reps, targetReps: 9, loadKg: 20)));
      expect(a,
          isNot(const SetPrescription(mode: SetMode.reps, targetReps: 8, loadKg: 25)));
      expect(a,
          isNot(const SetPrescription(mode: SetMode.timed, targetReps: 8, loadKg: 20)));
    });

    test('SetPlan equality includes the prescription', () {
      const timed = SetPlan(sets: 1, workSeconds: 5, restSeconds: 5);
      final reps = timed.copyWith(
          prescription: const SetPrescription(mode: SetMode.reps, targetReps: 3));
      expect(reps, isNot(timed));
      expect(reps.isRepBased, isTrue);
      expect(timed.isRepBased, isFalse);
      // copyWith without the argument keeps it.
      expect(reps.copyWith(sets: 2).isRepBased, isTrue);
    });
  });

  group('defaultTargetReps', () {
    test('beginner and never 12, intermediate 10, advanced 8', () {
      expect(defaultTargetReps(FitnessTier.beginner), 12);
      expect(defaultTargetReps(FitnessTier.never), 12);
      expect(defaultTargetReps(FitnessTier.intermediate), 10);
      expect(defaultTargetReps(FitnessTier.advanced), 8);
    });

    test('an unanswered questionnaire gets the middle number', () {
      expect(defaultTargetReps(null), 10);
    });
  });

  group('exerciseIsTimed: the structural signals', () {
    test('isStretch is timed whatever the title or equipment says', () {
      expect(
          exerciseIsTimed(
              _ex(title: 'Dumbbell row', equipmentId: 'dumbbell', isStretch: true)),
          isTrue);
    });

    test('every cardio machine id is timed', () {
      for (final id in const [
        'treadmill',
        'rowing_machine',
        'exercise_bike',
        'elliptical',
        'stair_climber',
      ]) {
        expect(exerciseIsTimed(_ex(title: 'Steady effort', equipmentId: id)),
            isTrue,
            reason: id);
      }
    });

    test('vendor groups Stretching - Mobility and Yoga are timed', () {
      expect(
          exerciseIsTimed(
              _ex(title: 'Cat cow', vendorGroup: 'Stretching - Mobility')),
          isTrue);
      expect(exerciseIsTimed(_ex(title: 'Sun salutation', vendorGroup: 'Yoga')),
          isTrue);
    });

    test('vendor group matching ignores case and surrounding blanks', () {
      expect(
          exerciseIsTimed(
              _ex(title: 'Cat cow', vendorGroup: '  stretching - mobility ')),
          isTrue);
      expect(exerciseIsTimed(_ex(title: 'Sun salutation', vendorGroup: 'YOGA')),
          isTrue);
    });

    test('other vendor groups stay rep based', () {
      for (final g in const [
        'Legs',
        'Chest',
        'Back',
        'Abdominals',
        'Powerlifting',
        'Calisthenics-Cardio-Plyo-Functional',
      ]) {
        expect(exerciseIsTimed(_ex(title: 'Goblet squat', vendorGroup: g)),
            isFalse,
            reason: g);
      }
    });
  });

  group('exerciseIsTimed: whole-word titles', () {
    test('holds and cardio drills are timed', () {
      for (final t in const [
        'Plank',
        'Side Plank',
        'Wall Sit',
        'Hollow Hold',
        'Dead Hang',
        'L-Sit',
        'Isometric squat',
        'Hold the top position',
        'Jumping Jacks',
        'Jumping Jack',
        'Mountain Climbers',
        'High Knees',
        'Jog in place',
        'Run',
        'Sprint intervals',
        'Jump Rope',
        'Skipping',
        'Chest stretch',
        'Pilates roll',
        'Mobility flow',
        'Cardio blast',
      ]) {
        expect(exerciseIsTimed(_ex(title: t)), isTrue, reason: t);
      }
    });

    test('matching is case-insensitive', () {
      expect(exerciseIsTimed(_ex(title: 'WALL SIT')), isTrue);
      expect(exerciseIsTimed(_ex(title: 'plank')), isTrue);
    });

    test('strength and bodyweight strength moves are rep based', () {
      for (final t in const [
        'Back squat',
        'Goblet squat',
        'Push-up',
        'Pull-up',
        'Barbell bench press',
        'Crunch',
        'Lunge',
        'Bicep curl',
        'Deadlift',
        'Burpee',
      ]) {
        expect(exerciseIsTimed(_ex(title: t)), isFalse, reason: t);
      }
    });

    test('substrings inside other words do not count', () {
      // "Runner's lunge", "Planker", "Threshold" must not be caught by
      // run / plank / hold.
      for (final t in const [
        "Runner's lunge",
        'Plankton press',
        'Threshold squat',
        'Stretcher carry',
        'Pushing sled',
        'Brunch crunch',
      ]) {
        expect(exerciseIsTimed(_ex(title: t)), isFalse, reason: t);
      }
    });

    test('an unknown equipment id with a strength title is rep based', () {
      expect(
          exerciseIsTimed(
              _ex(title: 'Goblet squat', equipmentId: 'machine_invented')),
          isFalse);
    });
  });

  group('planFor', () {
    test('no exercise stays timed, exactly the tier plan as before', () {
      expect(planFor(null, FitnessTier.beginner), SetPlan.beginner);
      expect(planFor(null, FitnessTier.advanced), SetPlan.advanced);
      expect(planFor(null, null), SetPlan.intermediate);
      expect(planFor(null, FitnessTier.beginner).isRepBased, isFalse);
    });

    test('a timed exercise keeps the tier plan unchanged', () {
      expect(planFor(_ex(title: 'Plank'), FitnessTier.intermediate),
          SetPlan.intermediate);
    });

    test('a strength exercise becomes rep based with tier reps', () {
      final b = planFor(_ex(), FitnessTier.beginner);
      final i = planFor(_ex(), FitnessTier.intermediate);
      final a = planFor(_ex(), FitnessTier.advanced);
      final n = planFor(_ex(), FitnessTier.never);
      final u = planFor(_ex(), null);
      expect(b.isRepBased, isTrue);
      expect(b.prescription.targetReps, 12);
      expect(i.prescription.targetReps, 10);
      expect(a.prescription.targetReps, 8);
      expect(n.prescription.targetReps, 12);
      expect(u.prescription.targetReps, 10);
      expect(b.prescription.loadKg, isNull);
    });

    test('the tier set count and rest survive the switch to reps', () {
      final plan = planFor(_ex(), FitnessTier.advanced);
      expect(plan.sets, SetPlan.advanced.sets);
      expect(plan.restSeconds, SetPlan.advanced.restSeconds);
    });

    test('captured reps and load override the tier default', () {
      final plan =
          planFor(_ex(), FitnessTier.advanced, loadKg: 62.5, capturedReps: 5);
      expect(plan.prescription.targetReps, 5);
      expect(plan.prescription.loadKg, 62.5);
    });

    test('captured numbers do not turn a timed exercise into a rep set', () {
      final plan = planFor(_ex(title: 'Plank'), FitnessTier.beginner,
          loadKg: 10, capturedReps: 5);
      expect(plan.isRepBased, isFalse);
    });

    test('loaded equipment keeps its longer rest and gets reps', () {
      final plan = planFor(_ex(equipmentId: 'barbell'), FitnessTier.intermediate);
      expect(plan.isRepBased, isTrue);
      expect(plan.restSeconds, greaterThanOrEqualTo(60));
    });
  });

  group('setPlanProvider pre-fills from the capture', () {
    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('nothing captured: tier default reps, no load', () {
      final c = container();
      final ex = _ex(id: 'sq');
      final plan = c.read(setPlanProvider(ex));
      expect(plan.isRepBased, isTrue);
      expect(plan.prescription.targetReps, 10,
          reason: 'no profile means the middle tier');
      expect(plan.prescription.loadKg, isNull);
    });

    test('a capture for this exercise id pre-fills load and reps', () {
      final c = container();
      final ex = _ex(id: 'sq');
      c.read(setLoadProvider('sq').notifier).state = (weightKg: 80, reps: 5);
      final plan = c.read(setPlanProvider(ex));
      expect(plan.prescription.targetReps, 5);
      expect(plan.prescription.loadKg, 80);
    });

    test('a capture with only a load keeps default reps', () {
      final c = container();
      final ex = _ex(id: 'sq');
      c.read(setLoadProvider('sq').notifier).state = (weightKg: 40, reps: null);
      final plan = c.read(setPlanProvider(ex));
      expect(plan.prescription.targetReps, 10);
      expect(plan.prescription.loadKg, 40);
    });

    test('a capture for another exercise is not used', () {
      final c = container();
      c.read(setLoadProvider('other').notifier).state = (weightKg: 99, reps: 1);
      final plan = c.read(setPlanProvider(_ex(id: 'sq')));
      expect(plan.prescription.loadKg, isNull);
      expect(plan.prescription.targetReps, 10);
    });

    test('the provider reacts when the capture changes', () {
      final c = container();
      final ex = _ex(id: 'sq');
      final sub = c.listen(setPlanProvider(ex), (_, __) {});
      addTearDown(sub.close);
      expect(c.read(setPlanProvider(ex)).prescription.loadKg, isNull);
      c.read(setLoadProvider('sq').notifier).state = (weightKg: 30, reps: 6);
      expect(c.read(setPlanProvider(ex)).prescription.loadKg, 30);
      expect(c.read(setPlanProvider(ex)).prescription.targetReps, 6);
    });

    test('a null exercise yields the timed tier plan', () {
      final c = container();
      expect(c.read(setPlanProvider(null)), SetPlan.intermediate);
    });

    test('a timed exercise ignores a capture', () {
      final c = container();
      c.read(setLoadProvider('pl').notifier).state = (weightKg: 5, reps: 3);
      final plan = c.read(setPlanProvider(_ex(id: 'pl', title: 'Plank')));
      expect(plan.isRepBased, isFalse);
    });
  });
}
