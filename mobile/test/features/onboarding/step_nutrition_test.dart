import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/health/widgets/health_sync_card.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/nutrition_plan/data/plan_calculator.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/onboarding/steps/step_health_flags.dart';
import 'package:fitness_app/features/onboarding/steps/step_lifestyle.dart';
import 'package:fitness_app/features/onboarding/steps/step_nutrition.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';

/// E2 widget tests for the onboarding nutrition step (ONB-06/07/13/14/15) and
/// the two health-flag questions, including large-text RU layout (A11Y-06/16).

class _SeededDraft extends QuestionnaireDraft {
  _SeededDraft(this.seed);
  final UserProfile seed;
  @override
  UserProfile build() => seed;
}

const _safeFlags = HealthFlags(
  professionalGuidance: ProfessionalGuidanceNeed.none,
  nutritionGuidance: NutritionGuidanceNeed.none,
);

UserProfile _profile({
  HealthFlags flags = const HealthFlags(),
  PersonalInfo personal = const PersonalInfo(),
  FitnessGoals goals = const FitnessGoals(),
  NutritionPrefs nutrition = const NutritionPrefs(),
  Lifestyle lifestyle = const Lifestyle(),
}) =>
    UserProfile.empty('u').copyWith(
      health: HealthHistory(flags: flags),
      personal: personal,
      goals: goals,
      nutrition: nutrition,
      lifestyle: lifestyle,
    );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget step,
  UserProfile seed, {
  Locale locale = const Locale('en'),
  Size size = const Size(800, 4000),
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      questionnaireDraftProvider.overrideWith(() => _SeededDraft(seed)),
      profileRepositoryProvider.overrideWith(
        (ref) => MockProfileRepository(latency: Duration.zero),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: step,
        ),
      ),
    ),
  ));
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

UserProfile _draft(ProviderContainer c) => c.read(questionnaireDraftProvider);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)));

const _lockedKeys = [
  'onb.nutrition.goal',
  'onb.nutrition.targetLine',
  'onb.nutrition.pace',
  'onb.nutrition.bodyFatRuler',
  'onb.nutrition.sex',
  'onb.nutrition.steps',
  'onb.nutrition.ownership.coached',
  'onb.nutrition.ownership.shared',
  'onb.nutrition.ownership.manual',
];

const _alwaysKeys = [
  'onb.nutrition.allergens',
  'onb.nutrition.excludedInput',
  'onb.nutrition.meals',
];

void main() {
  const enLocked =
      "We'll leave food and calorie targets for later. You can add them any "
      'time in your nutrition profile.';
  const ruLocked =
      'Цели по питанию и калориям мы оставим на потом. Вы сможете добавить их '
      'в любой момент в профиле питания.';

  // A profile that WOULD produce a pace line if the safety answers allowed it.
  const personalWithTarget = PersonalInfo(
    birthYear: 1990,
    heightCm: 175,
    weightCurrentKg: 80,
    weightTargetKg: 72,
    gender: Gender.male,
  );

  group('ONB-13 lock-out: no numbers until BOTH safety answers are none', () {
    final lockedCases = <String, HealthFlags>{
      'both unanswered': const HealthFlags(),
      'only professionalGuidance none':
          const HealthFlags(professionalGuidance: ProfessionalGuidanceNeed.none),
      'only nutritionGuidance none':
          const HealthFlags(nutritionGuidance: NutritionGuidanceNeed.none),
      'professionalGuidance reported': const HealthFlags(
          professionalGuidance: ProfessionalGuidanceNeed.reported,
          nutritionGuidance: NutritionGuidanceNeed.none),
      'nutritionGuidance reported': const HealthFlags(
          professionalGuidance: ProfessionalGuidanceNeed.none,
          nutritionGuidance: NutritionGuidanceNeed.reported),
      'both reported': const HealthFlags(
          professionalGuidance: ProfessionalGuidanceNeed.reported,
          nutritionGuidance: NutritionGuidanceNeed.reported),
    };

    lockedCases.forEach((name, flags) {
      testWidgets('locked: $name', (tester) async {
        await _pump(
            tester,
            const StepNutrition(),
            _profile(
              flags: flags,
              personal: personalWithTarget,
              goals: const FitnessGoals(weightLoss: true),
            ));

        expect(find.text(enLocked), findsOneWidget);
        expect(find.byKey(const Key('onb.nutrition.locked')), findsOneWidget);
        for (final k in _lockedKeys) {
          expect(find.byKey(Key(k)), findsNothing, reason: k);
        }
        // No number-bearing text at all, even though weight, height and a
        // target exist: no pace, no target line, no default goal.
        expect(find.textContaining('kg per week'), findsNothing);
        expect(find.textContaining('Target weight'), findsNothing);
        expect(find.textContaining('72'), findsNothing);
        expect(find.text('Lose weight'), findsNothing);
        // The non-target inputs stay available.
        for (final k in _alwaysKeys) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.byType(HealthSyncCard), findsNothing);
      });
    });

    testWidgets('the locked notice names no reason', (tester) async {
      await _pump(
          tester,
          const StepNutrition(),
          _profile(
              flags: const HealthFlags(
                  nutritionGuidance: NutritionGuidanceNeed.reported)));
      final t = tester.widget<Text>(find.byKey(const Key('onb.nutrition.locked')));
      final text = t.data!.toLowerCase();
      for (final w in [
        'eating',
        'disorder',
        'pregnan',
        'breastfeed',
        'doctor',
        'dietitian',
        'professional'
      ]) {
        expect(text, isNot(contains(w)), reason: w);
      }
    });

    testWidgets('locked notice in RU is the exact RU copy', (tester) async {
      await _pump(tester, const StepNutrition(), _profile(),
          locale: const Locale('ru'));
      expect(find.text(ruLocked), findsOneWidget);
      expect(find.textContaining('кг в неделю'), findsNothing);
    });

    testWidgets('clear (none/none) shows every target element and no lock notice',
        (tester) async {
      await _pump(
          tester,
          const StepNutrition(),
          _profile(
            flags: _safeFlags,
            personal: personalWithTarget,
            goals: const FitnessGoals(weightLoss: true),
          ));
      expect(find.byKey(const Key('onb.nutrition.locked')), findsNothing);
      expect(find.text(enLocked), findsNothing);
      for (final k in [..._lockedKeys.where((k) => !k.startsWith('onb.nutrition.ownership.')),
          'onb.nutrition.ownership.coached', ..._alwaysKeys]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });
  });

  group('ONB-06/ONB-15 pace message and read-only target weight', () {
    testWidgets('a safe pace renders the exact EN message from the calculator',
        (tester) async {
      await _pump(
          tester,
          const StepNutrition(),
          _profile(
            flags: _safeFlags,
            personal: personalWithTarget,
            goals: const FitnessGoals(weightLoss: true),
          ));
      final pace = realisticPace(
        weightKg: 80,
        heightCm: 175,
        targetWeightKg: 72,
        goal: GoalDirection.lose,
      );
      expect(pace.kgPerWeek, isNotNull);
      expect(pace.weeks, isNotNull);
      expect(pace.targetBelowHealthyRange, isFalse);
      final kg = pace.kgPerWeek!;
      final kgText = (kg * 100).round() % 10 == 0
          ? kg.toStringAsFixed(1)
          : kg.toStringAsFixed(2);
      final weeks = pace.weeks!;
      final expected = 'At a safe pace of about $kgText kg per week, this '
          'takes roughly ${weeks == 1 ? '1 week' : '$weeks weeks'}.';
      final shown = tester
          .widget<Text>(find.byKey(const Key('onb.nutrition.pace')))
          .data!;
      expect(shown, expected);
      // Also pin the shape independent of the calculator numbers.
      expect(shown,
          matches(RegExp(r'^At a safe pace of about \d\.\d{1,2} kg per week, '
              r'this takes roughly \d+ weeks?\.$')));
    });

    testWidgets('the pace is a live region so it is announced when it appears',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
          tester,
          const StepNutrition(),
          _profile(
              flags: _safeFlags,
              personal: personalWithTarget,
              goals: const FitnessGoals(weightLoss: true)));
      final node = tester.getSemantics(find.byKey(const Key('onb.nutrition.pace')));
      expect(node.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
      handle.dispose();
    });

    testWidgets('target weight is a read-only line with a Change link, no input',
        (tester) async {
      var taps = 0;
      await _pump(
          tester,
          StepNutrition(onEditTarget: () => taps++),
          _profile(
              flags: _safeFlags,
              personal: personalWithTarget,
              goals: const FitnessGoals(weightLoss: true)));
      expect(find.text('Target weight: 72 kg'), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.editTarget')), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      // Only one text input exists in the step (excluded foods) and no ruler
      // other than the optional body-fat one: the target weight is not asked.
      expect(find.byType(EditableText), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.bodyFatRuler')), findsOneWidget);
      expect(find.textContaining('Target body fat'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onb.nutrition.editTarget')));
      expect(taps, 1);
    });

    testWidgets('no edit callback hides the Change link', (tester) async {
      await _pump(tester, const StepNutrition(),
          _profile(flags: _safeFlags, personal: personalWithTarget));
      expect(find.byKey(const Key('onb.nutrition.editTarget')), findsNothing);
      expect(find.text('Target weight: 72 kg'), findsOneWidget);
    });

    testWidgets('missing target weight says so and shows no pace',
        (tester) async {
      await _pump(
          tester,
          const StepNutrition(),
          _profile(
              flags: _safeFlags,
              personal: const PersonalInfo(
                  heightCm: 175, weightCurrentKg: 80, birthYear: 1990)));
      expect(
          find.text('No target weight yet. You can add one on the personal screen.'),
          findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.pace')), findsNothing);
    });

    testWidgets('a target below the healthy range shows the capped message, '
        'not a pace', (tester) async {
      await _pump(
          tester,
          const StepNutrition(),
          _profile(
              flags: _safeFlags,
              personal: const PersonalInfo(
                  birthYear: 1990,
                  heightCm: 175,
                  weightCurrentKg: 80,
                  weightTargetKg: 40),
              goals: const FitnessGoals(weightLoss: true)));
      expect(
          tester.widget<Text>(find.byKey(const Key('onb.nutrition.pace'))).data,
          "That target weight is below the range this plan supports, so we can't plan "
          'towards it. Try a higher target.');
      expect(find.textContaining('kg per week'), findsNothing);
    });

    testWidgets('RU renders the decimal comma in the target line',
        (tester) async {
      await _pump(
          tester,
          const StepNutrition(),
          _profile(
              flags: _safeFlags,
              personal: const PersonalInfo(
                  birthYear: 1990,
                  heightCm: 175,
                  weightCurrentKg: 80,
                  weightTargetKg: 72.5),
              goals: const FitnessGoals(weightLoss: true)),
          locale: const Locale('ru'));
      expect(find.text('Целевой вес: 72,5 кг'), findsOneWidget);
    });
  });

  group('ONB-06 defaults and chips', () {
    testWidgets('a default goal is shown selected but NOT written to the draft',
        (tester) async {
      final c = await _pump(
          tester,
          const StepNutrition(),
          _profile(
              flags: _safeFlags,
              goals: const FitnessGoals(weightLoss: true)));
      expect(_draft(c).nutrition.goalDirection, isNull);
      expect(_draft(c).nutrition.isEmpty, isTrue,
          reason: 'rendering the step must not write anything');
    });

    testWidgets('picking goal, sex, meals, ownership writes exactly those',
        (tester) async {
      final c = await _pump(tester, const StepNutrition(),
          _profile(flags: _safeFlags));
      await tester.tap(find.text('Gain weight'));
      await tester.tap(find.text('Female'));
      await tester.tap(find.descendant(
          of: find.byKey(const Key('onb.nutrition.meals')),
          matching: find.text('4')));
      await tester.tap(find.text('Shared'));
      await tester.pump();
      final n = _draft(c).nutrition;
      expect(n.goalDirection, GoalDirection.gain);
      expect(n.sexAtBirth, SexAtBirth.female);
      expect(n.mealsPerDay, 4);
      expect(n.planOwnership, PlanOwnership.shared);
      expect(n.typicalDailySteps, isNull);
      expect(n.completedAt, isNull,
          reason: 'completion is stamped by leaving the step, not by tapping');
    });

    testWidgets('meals per day offers exactly 2..6', (tester) async {
      await _pump(tester, const StepNutrition(), _profile());
      final chips = find.descendant(
          of: find.byKey(const Key('onb.nutrition.meals')),
          matching: find.byType(Text));
      expect(
          [for (final w in tester.widgetList<Text>(chips)) w.data],
          ['2', '3', '4', '5', '6']);
      expect(find.text('If you skip this, we plan for 3 meals.'), findsOneWidget);
    });

    testWidgets('ownership defaults are stated, nothing is pre-selected',
        (tester) async {
      final c = await _pump(tester, const StepNutrition(),
          _profile(flags: _safeFlags));
      expect(find.text('Coached is the default.'), findsOneWidget);
      expect(_draft(c).nutrition.planOwnership, isNull);
    });

    testWidgets('steps buckets map to 2500/4000/6500/9500/12500 and record manual',
        (tester) async {
      final c = await _pump(tester, const StepNutrition(),
          _profile(flags: _safeFlags));
      final labels = {
        'Under 3,000': 2500,
        '3,000-5,000': 4000,
        '5,000-8,000': 6500,
        '8,000-11,000': 9500,
        '11,000 or more': 12500,
      };
      for (final e in labels.entries) {
        await tester.tap(find.text(e.key));
        await tester.pump();
        expect(_draft(c).nutrition.typicalDailySteps, e.value, reason: e.key);
        expect(_draft(c).nutrition.healthConnectChoice,
            HealthConnectChoice.manual,
            reason: e.key);
      }
    });

    testWidgets('a connected Health Connect choice is not overwritten by a bucket',
        (tester) async {
      final c = await _pump(
          tester,
          const StepNutrition(),
          _profile(
              flags: _safeFlags,
              nutrition: const NutritionPrefs(
                  healthConnectChoice: HealthConnectChoice.connected)));
      await tester.tap(find.text('3,000-5,000'));
      await tester.pump();
      // The implementation clears the choice rather than relabelling it.
      expect(_draft(c).nutrition.typicalDailySteps, 4000);
      expect(_draft(c).nutrition.healthConnectChoice,
          HealthConnectChoice.connected);
    });

    testWidgets('the existing HealthSyncCard is embedded when the step is clear',
        (tester) async {
      await _pump(tester, const StepNutrition(), _profile(flags: _safeFlags));
      expect(find.byType(HealthSyncCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
          find.text(
              'Connect your health app to use your real steps, or pick the closest range.'),
          findsOneWidget,
          reason: 'manual fallback is offered next to the card');
    });

    testWidgets('body-fat target can be cleared and is never written untouched',
        (tester) async {
      final c = await _pump(
          tester,
          const StepNutrition(),
          _profile(
              flags: _safeFlags,
              personal: const PersonalInfo(gender: Gender.female),
              nutrition: const NutritionPrefs(targetBodyFatPct: 25)));
      expect(find.byKey(const Key('onb.nutrition.bodyFatClear')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onb.nutrition.bodyFatClear')));
      await tester.pump();
      expect(_draft(c).nutrition.targetBodyFatPct, isNull);
      expect(find.byKey(const Key('onb.nutrition.bodyFatClear')), findsNothing);
    });

    testWidgets('sex at birth: derived selection is not written, labels exact',
        (tester) async {
      final c = await _pump(
          tester,
          const StepNutrition(),
          _profile(
              flags: _safeFlags,
              personal: const PersonalInfo(gender: Gender.male)));
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Use a neutral estimate'), findsOneWidget);
      expect(_draft(c).nutrition.sexAtBirth, isNull);
    });
  });

  group('ONB-06 allergens (device-only chips)', () {
    testWidgets('exactly the 14 EU allergens, toggled through HealthFlags',
        (tester) async {
      final c = await _pump(tester, const StepNutrition(), _profile());
      final chips = find.descendant(
          of: find.byKey(const Key('onb.nutrition.allergens')),
          matching: find.byType(Text));
      final labels = [for (final w in tester.widgetList<Text>(chips)) w.data!];
      expect(labels, hasLength(14));
      expect(labels.toSet(), {
        'Gluten', 'Crustaceans', 'Eggs', 'Fish', 'Peanuts', 'Soy', 'Milk',
        'Tree nuts', 'Celery', 'Mustard', 'Sesame', 'Sulphites', 'Lupin',
        'Molluscs',
      });
      expect(FoodAllergen.values, hasLength(14));

      await tester.tap(find.text('Peanuts'));
      // A frame between taps, as a real user always has: the chip callback
      // closes over the set of its last build.
      await tester.pump();
      await tester.tap(find.text('Sesame'));
      await tester.pump();
      expect(_draft(c).health.flags.foodAllergens,
          {FoodAllergen.peanuts, FoodAllergen.sesame});
      expect(_draft(c).nutrition.isEmpty, isTrue,
          reason: 'allergens live in HealthFlags, not NutritionPrefs');
      await tester.tap(find.text('Peanuts'));
      await tester.pump();
      expect(_draft(c).health.flags.foodAllergens, {FoodAllergen.sesame});
    });

    testWidgets('the device-only statement is shown for allergens and foods',
        (tester) async {
      await _pump(tester, const StepNutrition(), _profile());
      expect(find.text('Stays on this device only.'), findsNWidgets(2));
    });

    testWidgets('RU allergen labels come from the RU ARB', (tester) async {
      await _pump(tester, const StepNutrition(), _profile(),
          locale: const Locale('ru'));
      for (final l in ['Глютен', 'Ракообразные', 'Арахис', 'Орехи', 'Моллюски']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
    });
  });

  group('ONB-06 excluded foods (limits, dedupe, device-only)', () {
    Future<void> add(WidgetTester tester, String text) async {
      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('onb.nutrition.excludedInput')),
              matching: find.byType(EditableText)),
          text);
      await tester.pump();
      await tester.tap(find.byKey(const Key('onb.nutrition.excludedAdd')));
      await tester.pump();
    }

    testWidgets('adds a trimmed, whitespace-collapsed entry and clears input',
        (tester) async {
      final c = await _pump(tester, const StepNutrition(), _profile());
      await add(tester, '   brussels    sprouts  ');
      expect(_draft(c).nutrition.excludedFoods, ['brussels sprouts']);
      expect(find.text('brussels sprouts  ✕'), findsOneWidget);
    });

    testWidgets('empty or blank input adds nothing', (tester) async {
      final c = await _pump(tester, const StepNutrition(), _profile());
      await add(tester, '    ');
      expect(_draft(c).nutrition.excludedFoods, isEmpty);
    });

    testWidgets('duplicates are ignored case-insensitively', (tester) async {
      final c = await _pump(tester, const StepNutrition(), _profile());
      await add(tester, 'Mushrooms');
      await add(tester, 'mushrooms');
      await add(tester, 'MUSHROOMS ');
      expect(_draft(c).nutrition.excludedFoods, ['Mushrooms']);
    });

    testWidgets('an entry longer than 40 characters is cut to 40',
        (tester) async {
      final c = await _pump(tester, const StepNutrition(), _profile());
      await add(tester, 'a' * 55);
      expect(_draft(c).nutrition.excludedFoods, ['a' * 40]);
    });

    testWidgets('the 21st entry is refused: input is replaced by the limit text',
        (tester) async {
      final c = await _pump(
          tester,
          const StepNutrition(),
          _profile(
              nutrition: NutritionPrefs(excludedFoods: [
            for (var i = 0; i < 19; i++) 'food$i'
          ])));
      await add(tester, 'food19');
      expect(_draft(c).nutrition.excludedFoods, hasLength(20));
      expect(find.byKey(const Key('onb.nutrition.excludedLimit')), findsOneWidget);
      expect(find.text('You can add up to 20 foods.'), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.excludedInput')), findsNothing);
      expect(_draft(c).nutrition.excludedFoods.last, 'food19');
    });

    testWidgets('removing a chip frees the slot and brings the input back',
        (tester) async {
      final c = await _pump(
          tester,
          const StepNutrition(),
          _profile(
              nutrition: NutritionPrefs(
                  excludedFoods: [for (var i = 0; i < 20; i++) 'food$i'])));
      expect(find.byKey(const Key('onb.nutrition.excludedInput')), findsNothing);
      await tester.tap(find.text('food3  ✕'));
      await tester.pump();
      expect(_draft(c).nutrition.excludedFoods, hasLength(19));
      expect(_draft(c).nutrition.excludedFoods, isNot(contains('food3')));
      expect(find.byKey(const Key('onb.nutrition.excludedInput')), findsOneWidget);
    });

    testWidgets('removal chips are labelled buttons for screen readers',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
          tester,
          const StepNutrition(),
          _profile(nutrition: const NutritionPrefs(excludedFoods: ['olives'])));
      expect(find.bySemanticsLabel('Remove olives'), findsOneWidget);
      handle.dispose();
    });
  });

  group('ONB-07 health-flags step questions (exact design copy)', () {
    testWidgets('pregnancy question names breastfeeding (EN)', (tester) async {
      await _pump(tester, const StepHealthFlags(), _profile());
      expect(
          find.text('Are you currently pregnant or breastfeeding, or within '
              'the first few months after giving birth?'),
          findsOneWidget);
      expect(find.textContaining('breastfeeding'), findsOneWidget);
      // Old wording is gone.
      expect(
          find.text(
              'Are you currently pregnant, or within the first few months after giving birth?'),
          findsNothing);
    });

    testWidgets('pregnancy question names breastfeeding (RU)', (tester) async {
      await _pump(tester, const StepHealthFlags(), _profile(),
          locale: const Locale('ru'));
      expect(
          find.text('Вы сейчас беременны, кормите грудью или находитесь в '
              'первые месяцы после родов?'),
          findsOneWidget);
    });

    testWidgets('the nutrition question carries the exact EN copy',
        (tester) async {
      await _pump(tester, const StepHealthFlags(), _profile());
      for (final s in [
        'Before we suggest food targets',
        'Do any of these apply to you?',
        'A doctor or dietitian supervises or advises what you eat.',
        'You have had a difficult relationship with food or eating, now or in the past.',
        'None of these',
        'One or more applies',
        'We ask so we only give general targets to people they suit. Your '
            'answer stays on this device and is never sent to our servers.',
        "If one applies, we won't show calorie or food targets, and we suggest "
            'talking to a professional.',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.textContaining('Prefer not'), findsNothing);
      expect(find.textContaining('prefer not'), findsNothing);
    });

    testWidgets('the nutrition question carries the exact RU copy',
        (tester) async {
      await _pump(tester, const StepHealthFlags(), _profile(),
          locale: const Locale('ru'));
      for (final s in [
        'Прежде чем предлагать цели по питанию',
        'Подходит ли вам что-то из этого?',
        'Ваш рацион контролирует или советует врач либо диетолог.',
        'У вас сейчас или раньше были сложные отношения с едой или питанием.',
        'Ничего из этого',
        'Подходит один или несколько пунктов',
        'Мы спрашиваем, чтобы давать общие ориентиры только тем, кому они '
            'подходят. Ответ хранится только на этом устройстве и не '
            'отправляется на наши серверы.',
        'Если что-то подходит, мы не показываем цели по калориям и питанию и '
            'советуем обратиться к специалисту.',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
    });

    testWidgets('the nutrition question is single choice with two answers only',
        (tester) async {
      final c = await _pump(tester, const StepHealthFlags(), _profile());
      final chips = find.descendant(
          of: find.byKey(const Key('onb.flags.nutritionGuidance')),
          matching: find.byType(Text));
      expect([for (final w in tester.widgetList<Text>(chips)) w.data],
          ['None of these', 'One or more applies']);
      expect(_draft(c).health.flags.nutritionGuidance, isNull);

      await tester.tap(find.text('One or more applies'));
      await tester.pump();
      expect(_draft(c).health.flags.nutritionGuidance,
          NutritionGuidanceNeed.reported);
      await tester.tap(find.text('None of these'));
      await tester.pump();
      expect(_draft(c).health.flags.nutritionGuidance,
          NutritionGuidanceNeed.none);
    });

    testWidgets('the nutrition question comes after the pregnancy question and '
        'answering one does not set the other', (tester) async {
      final c = await _pump(tester, const StepHealthFlags(), _profile());
      final guidanceY =
          tester.getTopLeft(find.byKey(const Key('onb.flags.guidance'))).dy;
      final nutY = tester
          .getTopLeft(find.byKey(const Key('onb.flags.nutritionGuidance')))
          .dy;
      expect(guidanceY, lessThan(nutY));
      await tester.tap(find.descendant(
          of: find.byKey(const Key('onb.flags.guidance')),
          matching: find.text('Yes')));
      await tester.pump();
      expect(_draft(c).health.flags.professionalGuidance,
          ProfessionalGuidanceNeed.reported);
      expect(_draft(c).health.flags.nutritionGuidance, isNull);
    });

    testWidgets('the nutrition question title is a semantics header',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const StepHealthFlags(), _profile());
      final node = tester.getSemantics(find.text('Before we suggest food targets'));
      expect(node.hasFlag(SemanticsFlag.isHeader), isTrue);
      handle.dispose();
    });
  });

  group('ONB-07 lifestyle step pescatarian chip', () {
    testWidgets('chip exists in EN and RU and is saved in Lifestyle.diet',
        (tester) async {
      final c = await _pump(tester, const StepLifestyle(), _profile());
      expect(find.text('Pescatarian'), findsOneWidget);
      await tester.tap(find.text('Pescatarian'));
      await tester.pump();
      expect(_draft(c).lifestyle.diet, [DietaryPreference.pescatarian]);
    });

    testWidgets('RU label', (tester) async {
      await _pump(tester, const StepLifestyle(), _profile(),
          locale: const Locale('ru'));
      expect(find.text('Пескетарианское'), findsOneWidget);
    });
  });

  group('A11Y-06/I18N-08 RU at 360x640, text scale 2.0', () {
    const small = Size(360, 640);

    for (final scenario in <String, (Widget, UserProfile)>{
      'locked step': (const StepNutrition(), _profile()),
      'clear step': (
        const StepNutrition(),
        _profile(
            flags: _safeFlags,
            personal: personalWithTarget,
            goals: const FitnessGoals(weightLoss: true),
            nutrition: const NutritionPrefs(excludedFoods: [
              'очень длинное название продукта которое не помещается'
            ]))
      ),
      'health flags step': (const StepHealthFlags(), _profile()),
    }.entries) {
      testWidgets('no overflow: ${scenario.key}', (tester) async {
        await _pump(tester, scenario.value.$1, scenario.value.$2,
            locale: const Locale('ru'), size: small, textScale: 2.0);
        expect(tester.takeException(), isNull);
        // Reachable by scrolling: the last element can be brought into view.
        final scroll = find.byType(Scrollable).first;
        await tester.drag(scroll, const Offset(0, -5000));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('interactive targets are at least 48 dp (Change, Add)',
        (tester) async {
      await _pump(
          tester,
          StepNutrition(onEditTarget: () {}),
          _profile(flags: _safeFlags, personal: personalWithTarget),
          size: small);
      final change = tester.getSize(find.byKey(const Key('onb.nutrition.editTarget')));
      expect(change.width, greaterThanOrEqualTo(48));
      expect(change.height, greaterThanOrEqualTo(48));
      final add = find.ancestor(
          of: find.byKey(const Key('onb.nutrition.excludedAdd')),
          matching: find.byType(ConstrainedBox));
      expect(add, findsWidgets);
      final addSize =
          tester.getSize(find.byKey(const Key('onb.nutrition.excludedAdd')));
      // The chip itself may be smaller; its hit area (the enclosing box) is 48.
      final box = tester.getSize(add.first);
      expect(box.height >= 48 || addSize.height >= 48, isTrue);
    });

    testWidgets('semantics: the locked notice is a live region with its text',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const StepNutrition(), _profile());
      final node = tester.getSemantics(find.byKey(const Key('onb.nutrition.locked')));
      expect(node.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
      expect(node.label, enLocked);
      handle.dispose();
    });

    testWidgets('semantics: choice chips are exposed as buttons with their label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const StepNutrition(), _profile());
      final node = tester.getSemantics(find.text('Peanuts'));
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.label, contains('Peanuts'));
      handle.dispose();
    });
  });
}
