import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/nutrition_plan/nutrition_profile_flow_page.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';

/// E2 widget tests for the "complete your nutrition profile" flow (C11):
/// ONB-09, ONB-13 (live lock-out), completedAt stamping and cancel-writes-
/// nothing. The repository is the in-memory mock, so every "saved" assertion
/// reads what the flow actually handed to `ProfileRepository.save`.

final DateTime _profileDone = DateTime.utc(2026, 9, 1, 12);

class _Harness {
  _Harness(this.tester, this.profiles, this.router, this.uid);
  final WidgetTester tester;
  final MockProfileRepository profiles;
  final GoRouter router;
  final String uid;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  UserProfile get stored => profiles.cached(uid)!;
}

/// A profile that lacks only the nutrition-specific answers.
UserProfile _base(String uid) => UserProfile.empty(uid).copyWith(
      completedAt: _profileDone,
      personal: const PersonalInfo(
        birthYear: 1990,
        heightCm: 175,
        weightCurrentKg: 80,
        activityLevel: ActivityLevel.active,
        gender: Gender.male,
      ),
      goals: const FitnessGoals(weightLoss: true),
    );

Future<_Harness> _open(
  WidgetTester tester, {
  UserProfile Function(String uid)? seed,
  Locale locale = const Locale('en'),
  Size size = const Size(800, 3000),
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final auth = MockAuthRepository(latency: Duration.zero);
  final profiles = MockProfileRepository(latency: Duration.zero);
  // The mocks use real timers, which a fake-async testWidgets zone never fires.
  final user = (await tester.runAsync(() async {
    final u = await auth.signInAnonymously();
    await profiles.save((seed ?? _base)(u.uid));
    return u;
  }))!;

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME-PLACEHOLDER'))),
      GoRoute(
          path: '/nutrition/profile',
          builder: (_, __) => const NutritionProfileFlowPage()),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWith((ref) {
        ref.onDispose(auth.dispose);
        return auth;
      }),
      profileRepositoryProvider.overrideWith((ref) {
        ref.onDispose(profiles.dispose);
        return profiles;
      }),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pump();
  // Make the auth stream deliver, then open the flow like a button would.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
  router.push('/nutrition/profile');
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return _Harness(tester, profiles, router, user.uid);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapText(WidgetTester tester, String text, {String? within}) async {
  final f = within == null
      ? find.text(text)
      : find.descendant(of: find.byKey(Key(within)), matching: find.text(text));
  await tester.tap(f);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

UserProfile _withSafety(UserProfile p,
        {ProfessionalGuidanceNeed? pro, NutritionGuidanceNeed? nut}) =>
    p.copyWith(
        health: HealthHistory(
            flags: HealthFlags(professionalGuidance: pro, nutritionGuidance: nut)));

void main() {
  group('sheet list comes from missingNutritionInputs (ONB-09)', () {
    testWidgets('nothing missing: only the food sheet, Step 1 of 1, Save',
        (tester) async {
      await _open(
          tester,
          seed: (uid) => _withSafety(_base(uid),
              pro: ProfessionalGuidanceNeed.none,
              nut: NutritionGuidanceNeed.none));
      expect(find.text('Step 1 of 1'), findsOneWidget);
      expect(find.text('Nutrition profile'), findsOneWidget);
      expect(find.byKey(const ValueKey('nutProfile.sheet.food')), findsOneWidget);
      expect(find.byKey(const ValueKey('nutProfile.sheet.safety')), findsNothing);
      expect(find.byKey(const ValueKey('nutProfile.sheet.body')), findsNothing);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      // No back button on the first sheet.
      expect(find.byKey(const Key('nutProfile.back')), findsNothing);
    });

    testWidgets('only the safety questions missing: Step 1 of 2, safety first',
        (tester) async {
      await _open(tester);
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('nutProfile.sheet.safety')), findsOneWidget);
      expect(find.text('Two quick questions'), findsOneWidget);
      expect(find.byKey(const Key('onb.flags.guidance')), findsOneWidget);
      expect(find.byKey(const Key('onb.flags.nutritionGuidance')), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      // No numbers or goal fields on the safety sheet.
      expect(find.byKey(const Key('onb.nutrition.goal')), findsNothing);
      expect(find.textContaining('kg per week'), findsNothing);
    });

    testWidgets('an already-answered safety question is not asked again',
        (tester) async {
      await _open(
          tester,
          seed: (uid) =>
              _withSafety(_base(uid), pro: ProfessionalGuidanceNeed.none));
      expect(find.byKey(const Key('onb.flags.guidance')), findsNothing);
      expect(find.byKey(const Key('onb.flags.nutritionGuidance')), findsOneWidget);
    });

    testWidgets('a missing body input adds the body sheet: 3 sheets from an '
        'empty profile', (tester) async {
      await _open(tester, seed: (uid) => UserProfile.empty(uid));
      expect(find.text('Step 1 of 3'), findsOneWidget);
      // Safety -> body -> food, in that order.
      await _tapText(tester, 'None of these');
      await _tapText(tester, 'No', within: 'onb.flags.guidance');
      await _tapKey(tester, 'nutProfile.cta');
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('nutProfile.sheet.body')), findsOneWidget);
      expect(find.byKey(const Key('nutProfile.heightRuler')), findsOneWidget);
      expect(find.byKey(const Key('nutProfile.weightRuler')), findsOneWidget);
      expect(find.byKey(const Key('nutProfile.birthYearRuler')), findsOneWidget);
      expect(find.byKey(const Key('nutProfile.activity')), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.sex')), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.goal')), findsOneWidget);
      await _tapKey(tester, 'nutProfile.cta');
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('nutProfile.sheet.food')), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('only the missing body inputs are shown on the body sheet',
        (tester) async {
      await _open(
          tester,
          seed: (uid) => _withSafety(
              _base(uid).copyWith(
                  personal: const PersonalInfo(
                      birthYear: 1990,
                      weightCurrentKg: 80,
                      activityLevel: ActivityLevel.active,
                      gender: Gender.male)),
              pro: ProfessionalGuidanceNeed.none,
              nut: NutritionGuidanceNeed.none));
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(find.byKey(const Key('nutProfile.heightRuler')), findsOneWidget);
      expect(find.byKey(const Key('nutProfile.weightRuler')), findsNothing);
      expect(find.byKey(const Key('nutProfile.birthYearRuler')), findsNothing);
      expect(find.byKey(const Key('nutProfile.activity')), findsNothing);
      expect(find.byKey(const Key('onb.nutrition.sex')), findsNothing);
      expect(find.byKey(const Key('onb.nutrition.goal')), findsNothing);
    });

    testWidgets('the sheet list is fixed on entry: answering does not change '
        'the step count', (tester) async {
      await _open(tester);
      expect(find.text('Step 1 of 2'), findsOneWidget);
      await _tapText(tester, 'None of these');
      await _tapText(tester, 'No', within: 'onb.flags.guidance');
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('nutProfile.sheet.safety')), findsOneWidget);
    });
  });

  group('ONB-13 live lock-out inside the flow', () {
    testWidgets('answering "reported" on the safety sheet locks the next sheets '
        'at once, with no targets', (tester) async {
      await _open(tester, seed: (uid) => UserProfile.empty(uid));
      await _tapText(tester, 'One or more applies');
      await _tapText(tester, 'No', within: 'onb.flags.guidance');
      await _tapKey(tester, 'nutProfile.cta');
      // Body sheet: lock notice only; no ruler, no goal, no sex.
      expect(find.byKey(const ValueKey('nutProfile.sheet.body')), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.locked')), findsOneWidget);
      expect(find.byKey(const Key('nutProfile.heightRuler')), findsNothing);
      expect(find.byKey(const Key('onb.nutrition.goal')), findsNothing);
      await _tapKey(tester, 'nutProfile.cta');
      // Food sheet: lock notice, no steps/ownership; allergens/foods/meals stay.
      expect(find.byKey(const Key('onb.nutrition.locked')), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.steps')), findsNothing);
      expect(find.byKey(const Key('onb.nutrition.ownership.coached')), findsNothing);
      expect(find.byKey(const Key('onb.nutrition.allergens')), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.excludedInput')), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.meals')), findsOneWidget);
    });

    testWidgets('a profile with a stored "reported" answer sees the lock notice '
        'on the food sheet', (tester) async {
      await _open(
          tester,
          seed: (uid) => _withSafety(_base(uid),
              pro: ProfessionalGuidanceNeed.none,
              nut: NutritionGuidanceNeed.reported));
      expect(find.byKey(const Key('onb.nutrition.locked')), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.steps')), findsNothing);
    });

    testWidgets('safe answers unlock steps and ownership on the food sheet',
        (tester) async {
      await _open(
          tester,
          seed: (uid) => _withSafety(_base(uid),
              pro: ProfessionalGuidanceNeed.none,
              nut: NutritionGuidanceNeed.none));
      expect(find.byKey(const Key('onb.nutrition.locked')), findsNothing);
      expect(find.byKey(const Key('onb.nutrition.steps')), findsOneWidget);
      expect(find.byKey(const Key('onb.nutrition.ownership.coached')), findsOneWidget);
    });
  });

  group('saving and completedAt', () {
    testWidgets('final Save stamps NutritionPrefs.completedAt and keeps the '
        'profile completedAt and unrelated fields', (tester) async {
      final h = await _open(
          tester,
          seed: (uid) => _withSafety(
              _base(uid).copyWith(
                  lifestyle: const Lifestyle(sleepHoursPerNight: 7)),
              pro: ProfessionalGuidanceNeed.none,
              nut: NutritionGuidanceNeed.none));
      expect(h.stored.nutrition.completedAt, isNull);
      await _tapText(tester, '4', within: 'onb.nutrition.meals');
      await _tapText(tester, 'Shared');
      final before = DateTime.now();
      await _tapKey(tester, 'nutProfile.cta');
      final s = h.stored;
      expect(s.completedAt, _profileDone,
          reason: 'the profile completedAt (hasCompletedOnboarding) is carried through');
      expect(s.hasCompletedOnboarding, isTrue);
      expect(s.nutrition.mealsPerDay, 4);
      expect(s.nutrition.planOwnership, PlanOwnership.shared);
      expect(s.nutrition.completedAt, isNotNull);
      expect(s.nutrition.completedAt!.isBefore(before), isFalse,
          reason: 'stamped at the final Save, not earlier');
      expect(s.personal.heightCm, 175);
      expect(s.lifestyle.sleepHoursPerNight, 7);
      expect(s.health.flags.professionalGuidance, ProfessionalGuidanceNeed.none);
      // The flow closed back to where it was opened from.
      expect(find.text('HOME-PLACEHOLDER'), findsOneWidget);
    });

    testWidgets('Next on a non-final sheet saves progress but does NOT stamp '
        'NutritionPrefs.completedAt', (tester) async {
      final h = await _open(tester);
      await _tapText(tester, 'None of these');
      await _tapText(tester, 'No', within: 'onb.flags.guidance');
      await _tapKey(tester, 'nutProfile.cta');
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(h.stored.health.flags.nutritionGuidance, NutritionGuidanceNeed.none);
      expect(h.stored.health.flags.professionalGuidance,
          ProfessionalGuidanceNeed.none);
      expect(h.stored.nutrition.completedAt, isNull);
      expect(h.stored.completedAt, _profileDone);
    });

    testWidgets('a reported answer is saved, and the final Save still stamps '
        'completion', (tester) async {
      final h = await _open(tester);
      await _tapText(tester, 'One or more applies');
      await _tapText(tester, 'Yes', within: 'onb.flags.guidance');
      await _tapKey(tester, 'nutProfile.cta');
      await _tapKey(tester, 'nutProfile.cta');
      expect(h.stored.health.flags.nutritionGuidance,
          NutritionGuidanceNeed.reported);
      expect(h.stored.health.flags.professionalGuidance,
          ProfessionalGuidanceNeed.reported);
      expect(h.stored.nutrition.completedAt, isNotNull);
      // Nothing target-like was written in the locked state.
      expect(h.stored.nutrition.goalDirection, isNull);
      expect(h.stored.nutrition.planOwnership, isNull);
      expect(h.stored.nutrition.typicalDailySteps, isNull);
    });

    testWidgets('Back returns to the previous sheet and keeps what was entered',
        (tester) async {
      final h = await _open(tester);
      await _tapText(tester, 'None of these');
      await _tapText(tester, 'No', within: 'onb.flags.guidance');
      await _tapKey(tester, 'nutProfile.cta');
      expect(find.text('Step 2 of 2'), findsOneWidget);
      await _tapKey(tester, 'nutProfile.back');
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('nutProfile.sheet.safety')), findsOneWidget);
      expect(h.stored.health.flags.nutritionGuidance, NutritionGuidanceNeed.none);
    });
  });

  group('cancel writes nothing', () {
    testWidgets('closing without acting leaves the stored profile untouched '
        'and does not stamp completion', (tester) async {
      final h = await _open(tester);
      final before = h.stored;
      await _tapKey(tester, 'nutProfile.close');
      expect(find.text('HOME-PLACEHOLDER'), findsOneWidget);
      expect(h.stored, before, reason: 'the stored profile is the same value');
      expect(h.stored.nutrition, NutritionPrefs.empty);
      expect(h.stored.nutrition.completedAt, isNull);
      expect(h.stored.completedAt, _profileDone);
      expect(h.stored.health.flags.isUnanswered, isTrue);
    });

    testWidgets('rendering the flow does not mutate the profile', (tester) async {
      final h = await _open(
          tester,
          seed: (uid) => _withSafety(_base(uid),
              pro: ProfessionalGuidanceNeed.none,
              nut: NutritionGuidanceNeed.none));
      expect(h.stored.nutrition, NutritionPrefs.empty);
      // The draft equals the cached profile after entry.
      expect(h.container.read(questionnaireDraftProvider), h.stored);
    });
  });

  group('A11Y-06 / I18N-08 RU at 360x640, text scale 2.0', () {
    testWidgets('every sheet lays out without overflow and the CTA is reachable',
        (tester) async {
      await _open(tester,
          seed: (uid) => UserProfile.empty(uid),
          locale: const Locale('ru'),
          size: const Size(360, 640),
          textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.text('Шаг 1 из 3'), findsOneWidget);
      // Safety sheet.
      expect(find.text('Два коротких вопроса'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The CTA is outside the scroll area and at least 48 dp tall.
      final cta = tester.getSize(find.byKey(const Key('nutProfile.cta')));
      expect(cta.height, greaterThanOrEqualTo(48));
      expect(tester.getRect(find.byKey(const Key('nutProfile.cta'))).bottom,
          lessThanOrEqualTo(640));
      // Close and back controls are 48 dp.
      final close = tester.getSize(find.byKey(const Key('nutProfile.close')));
      expect(close.width, greaterThanOrEqualTo(48));
      expect(close.height, greaterThanOrEqualTo(48));
      // Walk to the end through the real controls.
      await _tapText(tester, 'Ничего из этого');
      await _tapKey(tester, 'nutProfile.cta');
      expect(tester.takeException(), isNull);
      await _tapKey(tester, 'nutProfile.cta');
      expect(tester.takeException(), isNull);
      expect(find.text('Шаг 3 из 3'), findsOneWidget);
    });
  });
}
