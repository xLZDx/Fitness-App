import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/onboarding/data/step_answered.dart';
import 'package:fitness_app/features/onboarding/onboarding_page.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

/// E2 page-level journey through the real `OnboardingPage`: the safety
/// questions are reached BEFORE the nutrition step, no pace text exists on any
/// earlier screen, the nutrition step links back to the personal screen, and
/// leaving it stamps `NutritionPrefs.completedAt` only when something was
/// answered (ONB-01, ONB-13, ONB-15, completedAt stamping).

class _SeededDraft extends QuestionnaireDraft {
  _SeededDraft(this.seed);
  final UserProfile seed;
  @override
  UserProfile build() => seed;
}

late MockProfileRepository _repo;

Future<ProviderContainer> _open(WidgetTester tester, UserProfile seed) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  _repo = MockProfileRepository(latency: Duration.zero);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      questionnaireDraftProvider.overrideWith(() => _SeededDraft(seed)),
      profileRepositoryProvider.overrideWith((ref) => _repo),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AuroraBackground(child: OnboardingPage()),
    ),
  ));
  await _settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(OnboardingPage)));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _cta(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('onboarding.cta')));
  await _settle(tester);
}

int _counter(WidgetTester tester) {
  final counters = [
    for (final w in tester.widgetList<Text>(find.byType(Text)))
      if (RegExp(r'^\d+/\d+$').hasMatch(w.data ?? '')) w.data!
  ];
  expect(counters, hasLength(1), reason: 'exactly one step counter on screen');
  final parts = counters.single.split('/');
  expect(int.parse(parts[1]), kOnboardingOrder.length,
      reason: 'the counter total is derived from the flow');
  return int.parse(parts[0]) - 1;
}

/// Taps the primary button until the page shows [step]. The page resumes at
/// the first unanswered screen, so the start index depends on the seed.
Future<void> _goTo(WidgetTester tester, OnboardingStep step,
    {void Function(int index)? onEach}) async {
  final target = kOnboardingOrder.indexOf(step);
  var guard = 0;
  while (_counter(tester) < target) {
    onEach?.call(_counter(tester));
    await _cta(tester);
    expect(tester.takeException(), isNull);
    expect(guard++, lessThan(20));
  }
  expect(_counter(tester), target);
}

const _pace = Key('onb.nutrition.pace');

void main() {
  const personal = PersonalInfo(
    birthYear: 1990,
    heightCm: 175,
    weightCurrentKg: 80,
    weightTargetKg: 72,
    gender: Gender.male,
  );

  UserProfile seed() => UserProfile.empty('flow-user').copyWith(
        personal: personal,
        goals: const FitnessGoals(weightLoss: true),
      );

  testWidgets('the nutrition step is the screen right after the health '
      'questions, and its counter is derived', (tester) async {
    await _open(tester, seed());
    expect(kOnboardingOrder.length, OnboardingStep.values.length);
    await _goTo(tester, OnboardingStep.healthFlags);
    // The two safety questions are on this screen.
    expect(find.byKey(const Key('onb.flags.guidance')), findsOneWidget);
    expect(find.byKey(const Key('onb.flags.nutritionGuidance')), findsOneWidget);
    await _cta(tester);
    expect(_counter(tester), kOnboardingOrder.indexOf(OnboardingStep.nutrition));
    expect(find.byKey(const Key('onb.nutrition.allergens')), findsOneWidget);
  });

  testWidgets('no pace text appears on any screen before the nutrition step, '
      'even with weight, height and target already entered', (tester) async {
    await _open(tester, seed());
    await _goTo(tester, OnboardingStep.nutrition, onEach: (i) {
      expect(find.byKey(_pace), findsNothing, reason: 'screen $i');
      expect(find.textContaining('kg per week'), findsNothing,
          reason: 'screen $i');
    });
    // Safety questions skipped (unanswered): the nutrition step is locked.
    expect(find.byKey(const Key('onb.nutrition.locked')), findsOneWidget);
    expect(find.byKey(_pace), findsNothing);
    expect(find.byKey(const Key('onb.nutrition.targetLine')), findsNothing);
    expect(find.textContaining('kg per week'), findsNothing);
  });

  testWidgets('answering none/none on the health screen unlocks the pace line '
      'on the next screen', (tester) async {
    await _open(tester, seed());
    await _goTo(tester, OnboardingStep.healthFlags);
    await tester.tap(find.descendant(
        of: find.byKey(const Key('onb.flags.guidance')),
        matching: find.text('No')));
    await tester.pump();
    await tester.tap(find.text('None of these'));
    await tester.pump();
    await _cta(tester);
    expect(find.byKey(const Key('onb.nutrition.locked')), findsNothing);
    expect(find.byKey(_pace), findsOneWidget);
    expect(find.text('Target weight: 72 kg'), findsOneWidget);
  });

  testWidgets('answering reported keeps the next screen locked: no pace, no '
      'target, no default goal', (tester) async {
    await _open(tester, seed());
    await _goTo(tester, OnboardingStep.healthFlags);
    await tester.tap(find.descendant(
        of: find.byKey(const Key('onb.flags.guidance')),
        matching: find.text('No')));
    await tester.pump();
    await tester.tap(find.text('One or more applies'));
    await tester.pump();
    await _cta(tester);
    expect(find.byKey(const Key('onb.nutrition.locked')), findsOneWidget);
    expect(find.byKey(_pace), findsNothing);
    expect(find.text('Lose weight'), findsNothing);
    expect(find.textContaining('72'), findsNothing);
  });

  testWidgets('the Change link returns to the personal screen, which owns the '
      'target weight', (tester) async {
    await _open(tester, seed());
    await _goTo(tester, OnboardingStep.healthFlags);
    await tester.tap(find.descendant(
        of: find.byKey(const Key('onb.flags.guidance')),
        matching: find.text('No')));
    await tester.pump();
    await tester.tap(find.text('None of these'));
    await tester.pump();
    await _cta(tester);
    await tester.tap(find.byKey(const Key('onb.nutrition.editTarget')));
    await _settle(tester);
    expect(_counter(tester), kOnboardingOrder.indexOf(OnboardingStep.personal));
    expect(find.byKey(const Key('onb.nutrition.allergens')), findsNothing);
  });

  group('completedAt stamping on leaving the nutrition step', () {
    testWidgets('an untouched (skipped) step leaves NutritionPrefs.completedAt '
        'unset and the button reads Skip', (tester) async {
      final c = await _open(tester, seed());
      await _goTo(tester, OnboardingStep.nutrition);
      expect(find.text('Skip'), findsOneWidget);
      await _cta(tester);
      expect(c.read(questionnaireDraftProvider).nutrition.completedAt, isNull);
      expect(_repo.cached('flow-user')!.nutrition.completedAt, isNull);
    });

    testWidgets('touching one field flips the button to Next and stamps '
        'completion once on leaving, persisted by the same save', (tester) async {
      final c = await _open(tester, seed());
      await _goTo(tester, OnboardingStep.nutrition);
      expect(find.text('Skip'), findsOneWidget);
      await tester.tap(find.text('Peanuts'));
      await tester.pump();
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(c.read(questionnaireDraftProvider).nutrition.completedAt, isNull,
          reason: 'not stamped until the step is left');
      final before = DateTime.now();
      await _cta(tester);
      final stamp = c.read(questionnaireDraftProvider).nutrition.completedAt;
      expect(stamp, isNotNull);
      expect(stamp!.isBefore(before), isFalse);
      final saved = _repo.cached('flow-user')!;
      expect(saved.nutrition.completedAt, stamp,
          reason: 'the stamp is written by the save that precedes advancing');
      expect(saved.completedAt, isNull,
          reason: 'leaving the nutrition step does not complete onboarding');
    });

    testWidgets('going back and forward again keeps the FIRST stamp',
        (tester) async {
      final c = await _open(tester, seed());
      await _goTo(tester, OnboardingStep.nutrition);
      await tester.tap(find.text('Peanuts'));
      await tester.pump();
      await _cta(tester);
      final first = c.read(questionnaireDraftProvider).nutrition.completedAt;
      expect(first, isNotNull);
      // Back to the nutrition screen, then forward again.
      expect(_counter(tester),
          kOnboardingOrder.indexOf(OnboardingStep.nutrition) + 1);
      await tester.tap(find.byKey(const Key('onboarding.back')));
      await _settle(tester);
      expect(_counter(tester),
          kOnboardingOrder.indexOf(OnboardingStep.nutrition));
      await _cta(tester);
      expect(c.read(questionnaireDraftProvider).nutrition.completedAt, first);
    });
  });
}
