import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/workouts/widgets/set_capture_sheet.dart';

/// B8 follow-up — the sheet says what moment it is.
///
/// B8 moved this sheet from "mark complete" to the timer's Start button and
/// left its words behind: "Log your set" is past tense, and "Reps" reads as a
/// count of repetitions already performed. Both appeared before a single one
/// had happened.
///
/// The operator chose (2026-08-13) to keep BOTH fields on Start rather than
/// splitting them, so the stored rep count is a plan. That makes the label the
/// only thing standing between the number and being read as a fact — which is
/// exactly why it is asserted rather than eyeballed.
/// `AppTheme.light()`, not a bare `MaterialApp`: the sheet reads
/// `theme.colors`, which is a theme EXTENSION the app installs. Without it that
/// getter null-checks and the whole subtree fails to build — which is what the
/// first draft of this file did, and every assertion then failed with "found 0
/// widgets", including ones about strings this change never touched. A test
/// harness that cannot build the widget reports a fault in the widget.
Widget _host({required bool planning}) => MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SetCaptureSheet(
          exerciseTitle: 'Bench press',
          planning: planning,
        ),
      ),
    );

void main() {
  testWidgets('before the set it does not claim the set has happened',
      (tester) async {
    await tester.pumpWidget(_host(planning: true));
    await tester.pumpAndSettle();

    expect(find.text('Before the set'), findsOneWidget);
    expect(find.text('Log your set'), findsNothing,
        reason: 'past tense on a sheet that opens before the first rep');
    expect(find.text('Target reps'), findsOneWidget);
    expect(find.text('Reps'), findsNothing,
        reason: 'a planned count must not read as a performed one');
  });

  testWidgets('after the set the original wording is unchanged',
      (tester) async {
    // The add-an-exercise path still opens this sheet after the fact, and its
    // words were correct there all along. A fix for one moment that changed
    // the other would be a new defect.
    await tester.pumpWidget(_host(planning: false));
    await tester.pumpAndSettle();

    expect(find.text('Log your set'), findsOneWidget);
    expect(find.text('Reps'), findsOneWidget);
    expect(find.text('Before the set'), findsNothing);
    expect(find.text('Target reps'), findsNothing);
  });

  testWidgets('the weight field is the same question in both moments',
      (tester) async {
    // Only the tense-bearing strings differ. If this starts failing, someone
    // has begun forking the sheet in two, which the `planning` flag exists to
    // avoid.
    for (final planning in [true, false]) {
      await tester.pumpWidget(_host(planning: planning));
      await tester.pumpAndSettle();
      expect(find.text('Weight (kg)'), findsOneWidget,
          reason: 'planning=$planning');
    }
  });
}
