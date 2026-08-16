import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/widgets/safety_refusal_card.dart';

import '../../helpers/test_app.dart';

void main() {
  group('SafetyRefusalCard', () {
    // F017: chest pain is the one PAR-Q+ answer this app treats as urgent
    // (kBlockingQuestions' own doc comment). Before this fix every blocking
    // answer rendered the identical routine "talk to a doctor first" wording,
    // which is the wrong message for a person who just reported chest pain.
    testWidgets('a chest-pain answer renders urgent wording, not the routine referral',
        (tester) async {
      await tester.pumpWidget(testHarness(
        child: Builder(
          builder: (context) => SafetyRefusalCard(
            reasons: const [SafetyReason.question(ParQQuestion.chestPain)],
          ),
        ),
      ));

      final l10n = AppLocalizations.of(
          tester.element(find.byType(SafetyRefusalCard)));

      expect(find.text(l10n.safetyBlockedUrgentTitle), findsOneWidget);
      expect(find.text(l10n.safetyBlockedTitle), findsNothing);
      expect(find.textContaining('emergency'), findsOneWidget);
    });

    // Mutation check for the branch itself: a DIFFERENT blocking answer must
    // still get the routine referral, not the urgent copy — the fix must
    // discriminate on chest pain specifically, not on "any blocking answer".
    testWidgets(
        'a non-chest-pain blocking answer keeps the routine referral wording',
        (tester) async {
      await tester.pumpWidget(testHarness(
        child: Builder(
          builder: (context) => SafetyRefusalCard(
            reasons: const [
              SafetyReason.question(ParQQuestion.medicallySupervisedOnly)
            ],
          ),
        ),
      ));

      final l10n = AppLocalizations.of(
          tester.element(find.byType(SafetyRefusalCard)));

      expect(find.text(l10n.safetyBlockedTitle), findsOneWidget);
      expect(find.text(l10n.safetyBlockedUrgentTitle), findsNothing);
    });
  });
}
