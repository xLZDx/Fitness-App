import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/onboarding/steps/step_goal_and_level.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart'
    show ProgrammeGoal;
import '../../helpers/test_app.dart';

/// O3's screen: one primary goal, one starting level, on one page.
///
/// Asserts on the DRAFT, not on which card looks selected. A card that lights
/// up without writing anything is the failure worth catching — it looks correct
/// on a phone right up until the answers are saved and the goal is missing.

Widget _harness(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: StepGoalAndLevel()),
        ),
      ),
    );

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

/// Scroll to [f], then tap it.
///
/// The screen is taller than the 800x600 test surface — the level cards start
/// below the fold. A bare `tap()` on an off-screen widget does not fail loudly;
/// it warns and dispatches the pointer at an offset that hits nothing, so the
/// assertion afterwards reports a null answer and looks like a wiring bug.
///
/// Scrolling first also asserts something real: every card on this screen is
/// reachable. A control the user cannot scroll to is not a control.
Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

void main() {
  testWidgets('picking a goal writes it as the primary goal', (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    expect(c.read(questionnaireDraftProvider).goals.primary, isNull);

    await _tapVisible(tester, find.byKey(const Key('onb.goal.endurance')));

    expect(c.read(questionnaireDraftProvider).goals.primary,
        ProgrammeGoal.endurance);
  });

  testWidgets('the primary goal is single-select', (tester) async {
    // Six cards, one answer. If a second tap added rather than replaced, the
    // screen would be a multi-select wearing radio buttons.
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.goal.strength')));
    await _tapVisible(tester, find.byKey(const Key('onb.goal.muscle')));

    expect(
        c.read(questionnaireDraftProvider).goals.primary, ProgrammeGoal.muscle);
  });

  testWidgets('picking a level writes the tier, including "never"',
      (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.tier.never')));

    expect(c.read(questionnaireDraftProvider).level.tier, FitnessTier.never);
  });

  testWidgets('the goal does not disturb the level, or the reverse',
      (tester) async {
    // They live in separate models (`FitnessGoals` / `FitnessLevel`) and share
    // only a screen. A `copyWith` wired to the wrong notifier would show up
    // here and nowhere else.
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.goal.form')));
    await _tapVisible(tester, find.byKey(const Key('onb.tier.advanced')));

    final draft = c.read(questionnaireDraftProvider);
    expect(draft.goals.primary, ProgrammeGoal.form);
    expect(draft.level.tier, FitnessTier.advanced);
  });

  testWidgets('the secondary multi-select still works, and is separate',
      (tester) async {
    // The design's single goal did not replace the older "what else interests
    // you" list — "mainly strength, also some weight loss" is a real answer and
    // collapsing it either way throws away half of it.
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.goal.strength')));
    await _tapVisible(tester, find.text('Weight loss'));

    final goals = c.read(questionnaireDraftProvider).goals;
    expect(goals.primary, ProgrammeGoal.strength);
    expect(goals.weightLoss, isTrue);
  });

  testWidgets('every goal and every tier is offered', (tester) async {
    // A card missing from the list is a question the user is never asked, with
    // the field still in the model — nothing else goes red.
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    for (final g in ProgrammeGoal.values) {
      expect(find.byKey(Key('onb.goal.${g.name}')), findsOneWidget,
          reason: g.name);
    }
    for (final t in FitnessTier.values) {
      expect(find.byKey(Key('onb.tier.${t.name}')), findsOneWidget,
          reason: t.name);
    }
  });
}
