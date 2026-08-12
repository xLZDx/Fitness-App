import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/onboarding/onboarding_page.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import '../../helpers/test_app.dart';

/// The redesign's onboarding chrome: back chevron, progress track, `N/M`
/// counter, and one primary button whose label follows whether the step has
/// been answered.
///
/// The draft is seeded by overriding the notifier rather than by driving the
/// auth stream and the repository cache. Those are a different thing to test —
/// `questionnaire_notifier_test.dart` already does — and routing through them
/// here would make every assertion below depend on a two-frame hydration race.

class _SeededDraft extends QuestionnaireDraft {
  _SeededDraft(this.seed);
  final UserProfile seed;

  @override
  UserProfile build() => seed;
}

Widget _harness(UserProfile seed) {
  return ProviderScope(
    overrides: [
      questionnaireDraftProvider.overrideWith(() => _SeededDraft(seed)),
      profileRepositoryProvider.overrideWith(
        (ref) => MockProfileRepository(latency: Duration.zero),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AuroraBackground(child: OnboardingPage()),
    ),
  );
}

void main() {
  final empty = UserProfile.empty('u');

  testWidgets('the counter says 1/7, not 1/9', (tester) async {
    // The design hard-codes `TOTAL_OB_STEPS = 9` (`App.tsx:1202`) for a flow
    // this app does not render yet -- O2 is the gate that renumbers. A bar
    // that fills to 1/9 over seven screens would misreport how much is left,
    // which is the one job a progress bar has.
    await tester.pumpWidget(_harness(empty));
    await tester.pumpAndSettle();

    expect(find.text('1/7'), findsOneWidget);
    expect(find.text('1/9'), findsNothing);
  });

  testWidgets('the first step offers no back chevron', (tester) async {
    // Rendering a disabled one would invite a tap that does nothing. The slot
    // is still occupied, so the bar does not jump sideways on step 2.
    await tester.pumpWidget(_harness(empty));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding.back')), findsNothing);
  });

  testWidgets('an untouched step offers Skip, and it still advances',
      (tester) async {
    await tester.pumpWidget(_harness(empty));
    await tester.pumpAndSettle();

    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsNothing);

    await tester.tap(find.byKey(const Key('onboarding.cta')));
    await tester.pumpAndSettle();

    expect(find.text('2/7'), findsOneWidget,
        reason: 'Skip is a label, not a gate -- every question is optional');
  });

  testWidgets('the label follows the draft as it is edited', (tester) async {
    // The half a static seed cannot prove: the button has to react to the
    // answer, not to what the page was built with.
    await tester.pumpWidget(_harness(empty));
    await tester.pumpAndSettle();
    expect(find.text('Skip'), findsOneWidget);

    final element = tester.element(find.byType(OnboardingPage));
    ProviderScope.containerOf(element)
        .read(questionnaireDraftProvider.notifier)
        .updateGoals((g) => g.copyWith(strength: true));
    await tester.pumpAndSettle();

    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('answering the screen you are on does NOT jump you forward',
      (tester) async {
    // The failure the resume latch is placed to avoid. Resume is armed until
    // auth resolves, not until the target stops being zero -- otherwise the
    // first answer typed on screen one would read as "screen one is done" and
    // throw the user onto screen two while they were still on it.
    await tester.pumpWidget(_harness(empty));
    await tester.pumpAndSettle();
    expect(find.text('1/7'), findsOneWidget);

    final element = tester.element(find.byType(OnboardingPage));
    ProviderScope.containerOf(element)
        .read(questionnaireDraftProvider.notifier)
        .updateGoals((g) => g.copyWith(strength: true));
    await tester.pumpAndSettle();

    expect(find.text('1/7'), findsOneWidget,
        reason: 'the user is still on the screen they were answering');
  });

  testWidgets('the chevron appears on step 2 and walks back', (tester) async {
    await tester.pumpWidget(_harness(empty));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding.cta')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding.back')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding.back')));
    await tester.pumpAndSettle();
    expect(find.text('1/7'), findsOneWidget);
    expect(find.byKey(const Key('onboarding.back')), findsNothing);
  });

  testWidgets('the flow opens on the goal, not on height and weight',
      (tester) async {
    // O2's reorder, asserted where a user would see it. The pre-O2 flow asked
    // a person to measure themselves before telling them what it was for.
    await tester.pumpWidget(_harness(empty));
    await tester.pumpAndSettle();

    expect(find.text('Goals'), findsOneWidget);
  });

  testWidgets('a returning user resumes at the first screen they left empty',
      (tester) async {
    // The draft already survived; their place in it did not. Every reopen
    // restarted at screen one and made them walk past every answer again.
    await tester.pumpWidget(_harness(
      empty.copyWith(
        goals: const FitnessGoals(strength: true),
        level: const FitnessLevel(frequencyPerWeek: 3),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3/7'), findsOneWidget,
        reason: 'goals and level are answered; equipment is the first gap');
    expect(find.byKey(const Key('onboarding.back')), findsOneWidget,
        reason: 'and they can still walk back into what they answered');
  });

  testWidgets('the step counter is announced as words, not as a slash',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_harness(empty));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Step 1 of 7'), findsOneWidget);
    handle.dispose();
  });
}
