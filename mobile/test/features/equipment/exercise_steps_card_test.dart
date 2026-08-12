import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/widgets/exercise_reference.dart';

import '../../helpers/test_app.dart';

/// The "How to do it" card must never render as a heading over blank space.
///
/// Reported from the operator's phone, 2026-08-12: an exercise whose card
/// showed a title and nothing else. Measured afterwards, it is not one
/// exercise — 403 of the 1,887 vendor rows carry neither `summary` nor
/// `steps`, and they are the SAME 403 rows for both fields, because every
/// catalog builder derives `summary` as `steps[0]`
/// (`build_vendor_catalog.py:291`). The vendor's metadata sheet is ~79%
/// filled and the builder's own header says so; no code change can conjure
/// the missing text, and inventing technique cues for a fitness app is an
/// injury risk rather than a nicer empty state.
///
/// So the invariant this holds is about honesty, not about coverage: when
/// there is nothing to say, the card says that.
ExerciseItem _item({String summary = '', List<String> steps = const []}) {
  return ExerciseItem(
    id: 'ea_test',
    title: 'Test movement',
    equipmentId: 'none',
    muscles: const ['chest'],
    difficulty: ExerciseDifficulty.beginner,
    durationMinutes: 10,
    summary: summary,
    steps: steps,
  );
}

void main() {
  const missingKey = Key('exercise-steps-missing');

  testWidgets('an exercise with no description says so', (tester) async {
    await tester.pumpWidget(testHarness(
      child: Scaffold(
        body: SingleChildScrollView(child: ExerciseStepsCard(exercise: _item())),
      ),
    ));
    await tester.pump();

    expect(find.byKey(missingKey), findsOneWidget,
        reason: 'the card used to draw Text("") and zero steps, which reads '
            'as the app having lost the text rather than never having had it');

    final note = tester.widget<Text>(find.byKey(missingKey));
    expect(note.data, isNotNull);
    expect(note.data!.trim(), isNotEmpty);
  });

  testWidgets('an exercise WITH a description does not show the note',
      (tester) async {
    await tester.pumpWidget(testHarness(
      child: Scaffold(
        body: SingleChildScrollView(
          child: ExerciseStepsCard(
            exercise: _item(
              summary: 'Stand tall with the bar across your shoulders.',
              steps: const [
                'Stand tall with the bar across your shoulders.',
                'Sit back and down until your thighs are parallel.',
                'Drive through the heels to stand.',
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(missingKey), findsNothing);
    expect(find.text('Drive through the heels to stand.'), findsOneWidget);
    // The numbered bullets are what makes it a technique list rather than a
    // paragraph; losing them would still pass a "not blank" assertion.
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('whitespace-only summary counts as missing, not as content',
      (tester) async {
    // `split_steps` strips " .;\t" and drops empties, but the legacy
    // `build_catalog.py` path does not, so a row whose only instruction is a
    // blank line reaches here as "   ". Rendering that is the same blank card
    // with extra steps.
    await tester.pumpWidget(testHarness(
      child: Scaffold(
        body: SingleChildScrollView(
          child: ExerciseStepsCard(exercise: _item(summary: '   ')),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(missingKey), findsOneWidget);
  });
}
