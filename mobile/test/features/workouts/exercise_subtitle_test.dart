import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';

/// B2 — what the line under an exercise's name in a list is allowed to say.
///
/// The recorded finding was "`purpose` is rendered on the exercise card only;
/// neither the programme card nor the player shows it". Half of that is stale:
/// the player renders `ExerciseStepsCard`
/// (`workout_player_page.dart:282`), which is the same widget that draws the
/// purpose block on the detail page. Measured before changing anything.
///
/// What was real is narrower and worse than the finding as written. The list
/// row's subtitle was `exercise.summary`, and `summary` is byte-identical to
/// `steps[0]` by an invariant enforced on all 1,887 rows in both languages
/// (`exercise_translations_test.dart`). So the subtitle was never a
/// description — it was the first INSTRUCTION, shown on the one screen where
/// the user has not chosen yet. "Stand tall with your spine neutral, arms by
/// your side" is a fine first step and tells you nothing about which exercise
/// to pick.
///
/// 403 of the 1,887 rows carry a `purpose` written for exactly that question.
/// The other 1,484 keep the old behaviour, so both fallbacks stay: an
/// instruction is a poor subtitle, and a blank one is worse.

ExerciseItem _ex({
  String? purpose,
  String summary = '',
  List<String> muscles = const [],
}) =>
    ExerciseItem(
      id: 'x',
      title: 'X',
      equipmentId: null,
      muscles: muscles,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 10,
      summary: summary,
      steps: summary.isEmpty ? const [] : [summary],
      purpose: purpose,
    );

String _label(String muscle) => muscle.toUpperCase();

void main() {
  group('exerciseSubtitle', () {
    test('prefers the purpose over the first instruction', () {
      final subtitle = exerciseSubtitle(
        _ex(
          purpose: 'Builds the pull that every row and chin-up depends on.',
          summary: 'Stand tall with your spine neutral, arms by your side',
        ),
        _label,
      );
      expect(subtitle,
          'Builds the pull that every row and chin-up depends on.');
    });

    test('falls back to the summary when no purpose is written', () {
      // 1,484 of 1,887 rows. Still an instruction, and still better than blank.
      final subtitle = exerciseSubtitle(
        _ex(summary: 'Stand tall with your spine neutral'),
        _label,
      );
      expect(subtitle, 'Stand tall with your spine neutral');
    });

    test('falls back to muscles when there is no text at all', () {
      final subtitle = exerciseSubtitle(
        _ex(muscles: const ['chest', 'triceps', 'shoulders', 'core']),
        _label,
      );
      expect(subtitle, 'CHEST · TRICEPS · SHOULDERS',
          reason: 'three at most, so the row keeps its shape');
    });

    test('a blank purpose is treated as absent, not as an empty subtitle', () {
      // A whitespace-only field is what a half-finished authoring pass leaves
      // behind, and it must not blank the row.
      final subtitle = exerciseSubtitle(
        _ex(purpose: '   ', summary: 'Stand tall'),
        _label,
      );
      expect(subtitle, 'Stand tall');
    });

    test('CONTROL: nothing at all still returns a string', () {
      expect(exerciseSubtitle(_ex(), _label), '');
    });
  });
}
