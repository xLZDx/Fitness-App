import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/onboarding/state/plan_preview_provider.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/onboarding/steps/step_preview.dart';
import 'package:fitness_app/features/onboarding/steps/step_screening.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import '../../helpers/test_app.dart';

/// The refusal has to reach a person, not just a return type.
///
/// `par_q_test.dart` proves the verdict is right and `plan_refusal_test.dart`
/// proves the builder honours it. Neither would notice if the widget layer
/// rendered a refusal as a spinner, an empty session, or nothing at all —
/// which is the shape the bug took before Gate M, where the answers existed
/// and no screen read them.

class _SeededDraft extends QuestionnaireDraft {
  _SeededDraft(this.seed);
  final UserProfile seed;

  @override
  UserProfile build() => seed;
}

Widget _harness(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWith(
          (ref) => MockProfileRepository(latency: Duration.zero),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AuroraBackground(
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

UserProfile _withAnswers(Map<ParQQuestion, bool> answers) =>
    UserProfile.empty('u').copyWith(
      health: HealthHistory(screening: answers),
    );

void main() {
  group('the screening step', () {
    testWidgets('asks every question in the enum', (tester) async {
      // The failure with no symptom: a question added to the model, read by
      // `screen()`, and never rendered — so every user is blocked by something
      // nobody was asked and there is no control on screen to answer it.
      await tester.pumpWidget(_harness(
        const StepScreening(),
        overrides: [
          questionnaireDraftProvider
              .overrideWith(() => _SeededDraft(UserProfile.empty('u'))),
        ],
      ));
      await tester.pumpAndSettle();

      for (final q in ParQQuestion.values) {
        expect(find.byKey(Key('onb.screening.${q.name}')), findsOneWidget,
            reason: '${q.name} has no control to answer it');
      }
    });

    testWidgets('answering a blocking question says so on the spot',
        (tester) async {
      // Finding out three screens later that a mis-tap closed the door is
      // worse than being told here, where the answer is still on display.
      await tester.pumpWidget(_harness(
        const StepScreening(),
        overrides: [
          questionnaireDraftProvider.overrideWith(() => _SeededDraft(
              _withAnswers({
                for (final q in ParQQuestion.values) q: false,
                ParQQuestion.chestPain: true,
              }))),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onb.screening.blocked')), findsOneWidget);
      expect(find.text('We are not going to hand you a workout'),
          findsOneWidget);
    });

    testWidgets('an incomplete screen is not shouted at', (tester) async {
      // Blocked, but the honest message is "finish the form", and showing a
      // referral to somebody who has simply not scrolled yet trains them to
      // ignore it.
      await tester.pumpWidget(_harness(
        const StepScreening(),
        overrides: [
          questionnaireDraftProvider
              .overrideWith(() => _SeededDraft(UserProfile.empty('u'))),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onb.screening.blocked')), findsNothing);
      expect(find.byKey(const Key('onb.screening.restricted')), findsNothing);
    });

    testWidgets('a restricting answer says the intensity is capped',
        (tester) async {
      await tester.pumpWidget(_harness(
        const StepScreening(),
        overrides: [
          questionnaireDraftProvider.overrideWith(() => _SeededDraft(
              _withAnswers({
                for (final q in ParQQuestion.values) q: false,
                ParQQuestion.otherChronicCondition: true,
              }))),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onb.screening.restricted')), findsOneWidget);
      expect(find.byKey(const Key('onb.screening.blocked')), findsNothing);
    });
  });

  group('the onboarding preview', () {
    testWidgets('renders the refusal instead of a session', (tester) async {
      await tester.pumpWidget(_harness(
        const StepPreview(),
        overrides: [
          questionnaireDraftProvider
              .overrideWith(() => _SeededDraft(UserProfile.empty('u'))),
          onboardingPlanPreviewProvider.overrideWith((ref) async =>
              const PlanRefused([
                SafetyReason.question(ParQQuestion.medicallySupervisedOnly),
              ])),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onb.preview.refused')), findsOneWidget);
      // The states it must NOT be mistaken for. An empty plan and a refusal
      // are different claims, and before the sealed type they had the same
      // shape.
      expect(find.byKey(const Key('onb.preview.plan')), findsNothing);
      expect(find.byKey(const Key('onb.preview.empty')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('names the answer responsible', (tester) async {
      await tester.pumpWidget(_harness(
        const StepPreview(),
        overrides: [
          questionnaireDraftProvider
              .overrideWith(() => _SeededDraft(UserProfile.empty('u'))),
          onboardingPlanPreviewProvider.overrideWith((ref) async =>
              const PlanRefused([
                SafetyReason.question(ParQQuestion.chestPain),
              ])),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('pain in your chest'), findsOneWidget,
          reason: 'a refusal that does not say which answer caused it cannot '
              'be corrected by the person it was about');
    });
  });
}
