import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsFlag;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/onboarding/widgets/inputs.dart';
import 'package:fitness_app/features/workouts/widgets/difficulty_rating_sheet.dart';

/// P2b — the tap targets the audit found announcing nothing.
///
/// These are all built on a bare `GestureDetector`, which contributes no
/// semantics of its own. To a screen reader the option pills of the
/// questionnaire were a row of words with no indication that any of them could
/// be pressed or which one was already chosen — and choosing one is the only
/// way to answer the question.
///
/// The failure is invisible in a screenshot and invisible in a normal widget
/// test, which is why it survived to an audit. It is visible in the semantics
/// tree, so that is what these assert.
Widget _host(Widget child) => MaterialApp(
      // `AppTheme.dark()`, not a bare MaterialApp: several of these widgets
      // read `theme.colors`, the app's own semantic-colour extension, and
      // without it they throw a TypeError while building rather than failing
      // an assertion — which reads as a broken test, not a missing theme.
      theme: AppTheme.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('questionnaire option pills', () {
    testWidgets('each pill is a button, and the chosen one says so',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(
        SingleChoiceChips<String>(
          options: const ['Male', 'Female'],
          labelOf: (o) => o,
          value: 'Female',
          onChanged: (_) {},
        ),
      ));

      final chosen = tester.getSemantics(find.text('Female'));
      expect(chosen.label, 'Female');
      expect(chosen.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(chosen.hasFlag(SemanticsFlag.isSelected), isTrue);

      // The unchosen one must be a button too, and must NOT claim selection —
      // "everything is selected" is as useless as "nothing is".
      final other = tester.getSemantics(find.text('Male'));
      expect(other.label, 'Male');
      expect(other.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(other.hasFlag(SemanticsFlag.isSelected), isFalse);
      handle.dispose();
    });

    testWidgets('multi-select reports every chosen pill, not just one',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(
        MultiChoiceChips<String>(
          options: const ['Barbell', 'Dumbbell', 'Bands'],
          labelOf: (o) => o,
          values: const {'Barbell', 'Bands'},
          onChanged: (_) {},
        ),
      ));

      for (final entry in {'Barbell': true, 'Dumbbell': false, 'Bands': true}
          .entries) {
        final node = tester.getSemantics(find.text(entry.key));
        expect(node.hasFlag(SemanticsFlag.isSelected), entry.value,
            reason: '${entry.key} selection is announced wrongly');
        expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      }
      handle.dispose();
    });
  });

  group('difficulty rating', () {
    testWidgets('each rating is one button with one name, not an emoji reading',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          _host(const DifficultyRatingSheet(exerciseTitle: 'Bench press')));
      await tester.pump();

      // `excludeSemantics` is the point: without it the reader announces the
      // emoji's own description before the label, so "Easy" arrives as a
      // sentence about a face.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      for (final label in [
        l10n.workoutsTooEasy,
        l10n.workoutsRight,
        l10n.workoutsTooHard,
      ]) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.hasFlag(SemanticsFlag.isButton), isTrue,
            reason: '$label does not announce itself as a button');
      }
      handle.dispose();
    });
  });
}
