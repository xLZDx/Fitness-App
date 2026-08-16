import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/about/about_page.dart';

/// R9 of the Gate J regulatory review
/// (`core/audit/gate_j_regulatory_review_2026-08-15/`).
///
/// The About page carried a principle headed "Open clinical content" with a
/// medical-information icon, whose own body says the exercise library "has not
/// been reviewed by a physiotherapist"; directly below it, a use-of-funds
/// breakdown gave 25% to "Clinical / physio review". Nothing there was a lie in
/// isolation — the caption said "Approximate, year-1 conservative budget" — but
/// together the heading, the icon and the line implied a clinical review
/// programme that does not exist, next to the sentence saying it does not.
///
/// This is the same defect class as R2, where the About page promised
/// "rehab-grade exercise guidance" against Terms in the same corpus stating the
/// library was unreviewed. R2 was a blocker because the words made a
/// therapeutic claim; R9 is milder because it is an implication rather than a
/// claim. The fix is the same: the honest half is the body, and the heading,
/// the icon and the budget line now agree with it.
///
/// Both locales, because a corrected claim that survives in one language is the
/// exact regression S0b already had to fix once.

String _arb(String lang) =>
    File('lib/l10n/app_$lang.arb').readAsStringSync();

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  group('the use-of-funds breakdown', () {
    /// The line names work nobody has done. It may stay — it is a plan, and a
    /// plan is allowed — but a reader must not be able to read it as spending.
    test('marks the clinical review line as not started, in both locales', () {
      expect(_arb('en'), contains('Clinical / physio review (not started)'));
      expect(_arb('ru'), contains('(не начата)'));
    });

    /// The caption is the only thing framing the whole table. "Approximate,
    /// year-1 conservative budget" describes the numbers' precision, not
    /// whether the money moved, which is the question a reader actually has.
    test('the caption says these are planned funds rather than spend', () {
      expect(_arb('en'), contains('not a record of money spent'));
      expect(_arb('ru'), contains('не отчёт о потраченном'));
    });
  });

  group('the clinical-content principle', () {
    /// A heading is read before the body under it, and this one asserted the
    /// opposite of what its body said.
    test('the heading does not claim a clinical review, in both locales', () {
      expect(_arb('en'), isNot(contains('"Open clinical content"')));
      expect(_arb('ru'), isNot(contains('"Открытый клинический контент"')));
      expect(_arb('en'), contains('not a clinical review'));
      expect(_arb('ru'), contains('а не клиническая проверка'));
    });

    /// CONTROL. Every assertion above is satisfiable by deleting the principle
    /// outright, which would "fix" R9 by removing the disclosure that the
    /// library is unreviewed — strictly worse than the defect. This pins the
    /// honest half in place so the corrections above cannot be achieved that
    /// way.
    testWidgets('the body still says no physiotherapist has reviewed it',
        (tester) async {
      await tester.pumpWidget(_host(const AboutPage()));
      await tester.pumpAndSettle();

      final rendered = StringBuffer();
      for (final w in tester.widgetList<Text>(find.byType(Text))) {
        rendered.writeln(w.data ?? w.textSpan?.toPlainText() ?? '');
      }
      expect(
        rendered.toString(),
        contains('has not been reviewed by a physiotherapist'),
      );
    });
  });
}
