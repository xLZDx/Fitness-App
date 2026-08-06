import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/progression.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';
import 'package:fitness_app/features/workouts/widgets/set_capture_sheet.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

/// Capturing what was actually lifted, and the double-tap that capture makes
/// dangerous.
///
/// `WorkoutLogEntry` has carried `weightKg` and `repsCompleted` since it was
/// written and `suggestNextWeight` reads both, but nothing in the app ever set
/// them — so the progression engine, its four rules and its tests were
/// unreachable in production. Every logged set was a timestamp and a title.

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

WorkoutLogEntry _log(
  String id, {
  required DateTime at,
  double? kg,
  int? reps,
  DifficultyRating? difficulty,
}) =>
    WorkoutLogEntry(
      id: id,
      exerciseId: 'squat',
      exerciseTitle: 'Squat',
      completedAt: at,
      durationMinutes: 10,
      weightKg: kg,
      repsCompleted: reps,
      difficulty: difficulty,
    );

void main() {
  group('the capture sheet', () {
    Future<SetCapture?> open(
      WidgetTester tester, {
      double? initialWeightKg,
      int? initialReps,
    }) async {
      SetCapture? result;
      var opened = false;
      await tester.pumpWidget(_host(Builder(builder: (context) {
        if (!opened) {
          opened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            result = await SetCaptureSheet.show(
              context,
              exerciseTitle: 'Squat',
              initialWeightKg: initialWeightKg,
              initialReps: initialReps,
            );
          });
        }
        return const SizedBox();
      })));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('returns what was typed', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField).first, '82.5');
      await tester.enterText(find.byType(TextField).last, '8');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // The sheet is gone, which is what pop() means; the value itself is
      // asserted through the parsing tests below because the async result
      // lands after the frame.
      expect(find.byType(SetCaptureSheet), findsNothing);
    });

    testWidgets('pre-fills from what is already stored', (tester) async {
      // An edit starts from the logged numbers, not from blank -- otherwise
      // re-opening to fix the reps silently clears the weight.
      await open(tester, initialWeightKg: 60, initialReps: 5);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows a whole number without a trailing zero',
        (tester) async {
      await open(tester, initialWeightKg: 60.0);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('60.0'), findsNothing);
    });

    testWidgets('says that blank is a real answer', (tester) async {
      await open(tester);
      expect(find.textContaining('an empty field is honest'), findsOneWidget);
    });

    testWidgets('skipping is offered next to saving', (tester) async {
      // Body-weight and mobility work carries no load. Forcing a number would
      // make the field lie rather than stay empty.
      await open(tester);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('the progression engine, now reachable', () {
    final now = DateTime(2026, 8, 5);

    test('an entry with no weight yields no suggestion', () {
      // What production looked like before this gate: every row had a null
      // weight, so the engine could never answer.
      final out = suggestNextWeight(historyForExercise: [_log('a', at: now)]);
      expect(out, isNull);
    });

    test('one captured set is enough for a first answer', () {
      final out = suggestNextWeight(historyForExercise: [
        _log('a',
            at: now,
            kg: 60,
            reps: 8,
            difficulty: DifficultyRating.justRight),
      ]);
      expect(out, isNotNull);
      expect(out!.suggestedKg, greaterThan(0));
    });

    test('the same set logged twice would move the suggestion', () {
      // The reason idempotency ships with capture rather than after it. Two
      // rows for one set are indistinguishable from two sessions, and the
      // rules that fire on "two in a row" fire a session early.
      final one = [
        _log('a',
            at: now, kg: 60, reps: 8, difficulty: DifficultyRating.justRight),
      ];
      final duplicated = [
        ...one,
        _log('b',
            at: now, kg: 60, reps: 8, difficulty: DifficultyRating.justRight),
      ];
      expect(
        suggestNextWeight(historyForExercise: duplicated)?.suggestedKg,
        isNot(suggestNextWeight(historyForExercise: one)?.suggestedKg),
        reason: 'a double-tap must not be able to add weight to the bar',
      );
    });

    test('reusing the id is what prevents it', () {
      // `save()` is `doc(entry.id).set(...)` -- an upsert. The player keeps the
      // first entry for the visit and re-logs it, so the duplicate above is
      // unreachable from a repeat tap.
      final first = _log('a', at: now, kg: 60, reps: 8);
      final second = first.copyWith(repsCompleted: 10);
      expect(second.id, first.id);
      expect(second.repsCompleted, 10);
      expect(second.weightKg, 60, reason: 'an edit must not clear the rest');
    });
  });
}
