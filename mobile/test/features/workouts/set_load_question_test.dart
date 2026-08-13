import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/workouts/data/set_capture.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';

/// B8 — when the app is allowed to ask what was lifted.
///
/// Operator, 2026-08-13: *"не спрашивать вес вообще если для упражнения вес не
/// нужен, например для йоги, присида, отжимания, скручивания"*. The question is
/// pure and lives in `set_capture.dart`, so the rule is asserted here rather
/// than inferred from whether a sheet appeared on screen.
void main() {
  group('exerciseUsesLoad', () {
    test('loaded equipment is asked', () {
      for (final id in kLoadedEquipmentIds) {
        expect(exerciseUsesLoad(equipmentId: id), isTrue, reason: id);
      }
    });

    test('the operator\'s own examples are never asked', () {
      // Yoga, squats, press-ups, crunches: bodyweight, so either no equipment
      // id at all or a mat. None of them is in the loaded list.
      for (final id in <String?>[null, '', 'none', 'bodyweight', 'yoga_mat']) {
        expect(exerciseUsesLoad(equipmentId: id), isFalse, reason: '$id');
      }
    });

    test('a stretch is never asked, whatever it is tagged with', () {
      expect(
        exerciseUsesLoad(equipmentId: 'dumbbell', isStretch: true),
        isFalse,
      );
    });

    test('an unknown id fails to the quiet side', () {
      // The catalogue is 1,887 rows and grows. A machine nobody has classified
      // yet must produce no question, not a weight box on a mobility drill.
      expect(exerciseUsesLoad(equipmentId: 'machine_invented_next_year'),
          isFalse);
    });
  });

  group('the rest plan and the weight question read the same list', () {
    ExerciseItem ex(String? equipmentId) => ExerciseItem(
          id: 'e',
          title: 't',
          equipmentId: equipmentId,
          muscles: const ['core'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 5,
          summary: '',
          steps: const [],
        );

    test('loaded work gets the longer rest AND the weight question', () {
      // The two used to be separate copies of the same id list. If they ever
      // drift, an exercise gets a lifter's rest without being asked what it is
      // resting from, or the reverse.
      for (final id in kLoadedEquipmentIds) {
        final plan = planFor(ex(id), FitnessTier.intermediate);
        expect(plan.restSeconds >= 60, isTrue, reason: id);
        expect(exerciseUsesLoad(equipmentId: id), isTrue, reason: id);
      }
    });

    test('bodyweight work gets neither', () {
      final plan = planFor(ex(null), FitnessTier.intermediate);
      final base = planFor(null, FitnessTier.intermediate);
      expect(plan.restSeconds, base.restSeconds);
      expect(exerciseUsesLoad(equipmentId: null), isFalse);
    });
  });
}
