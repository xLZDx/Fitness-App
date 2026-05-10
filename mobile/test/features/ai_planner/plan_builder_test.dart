import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/cycle_aware/data/cycle_phase.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/personalisation/data/fitness_model.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';

ExerciseItem _ex(
  String id, {
  List<String> muscles = const [],
  List<String> contra = const [],
  int minutes = 10,
}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
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

void main() {
  group('buildPlan', () {
    test('drops contraindicated exercises from the pool', () {
      final pool = [
        _ex('squat', muscles: ['quads']),
        _ex('overhead-press',
            muscles: ['shoulders'],
            contra: ['shoulder']),
      ];
      final plan = buildPlan(
        candidatePool: pool,
        reportedInjuries: const [
          Injury(bodyPart: 'shoulder', type: 'impingement'),
        ],
        profile: FitnessProfile.empty,
        deload: _noDeload,
      );
      expect(plan.exercises.map((e) => e.id), ['squat']);
      expect(plan.rationale, contains('Filtered out 1'));
    });

    test('respects target minutes (greedy fill)', () {
      final pool = [
        _ex('a', minutes: 25),
        _ex('b', minutes: 25),
        _ex('c', minutes: 25),
      ];
      final plan = buildPlan(
        candidatePool: pool,
        reportedInjuries: const [],
        profile: FitnessProfile.empty,
        deload: _noDeload,
        targetMinutes: 30,
      );
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
      final plan = buildPlan(
        candidatePool: [_ex('squat', muscles: ['quads'])],
        reportedInjuries: const [],
        profile: FitnessProfile.empty,
        deload: deload,
      );
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
      final plan = buildPlan(
        candidatePool: [_ex('squat', muscles: ['quads'])],
        reportedInjuries: const [],
        profile: FitnessProfile.empty,
        deload: deload,
        cyclePhase: CyclePhase.luteal,
      );
      // 0.7 * 0.9 = 0.63 — clamps not exceeded.
      expect(plan.intensityFactor, closeTo(0.63, 0.01));
    });

    test('caps at 6 exercises even if duration allows more', () {
      final pool = [
        for (var i = 0; i < 12; i++) _ex('e$i', minutes: 5),
      ];
      final plan = buildPlan(
        candidatePool: pool,
        reportedInjuries: const [],
        profile: FitnessProfile.empty,
        deload: _noDeload,
        targetMinutes: 999,
      );
      expect(plan.exercises.length, 6);
    });
  });
}
