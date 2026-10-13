// J5: training-context journeys through the planner and home screens with the
// REAL providers (trainingContextProvider, generatedPlanProvider,
// suggestionsProvider, forYouExercisesInContextProvider, safetyContextProvider,
// the eligibility layer). Fakes sit only at the edge: auth stream, profile
// stream, equipment repository, the injury-screened catalogue, workout history.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/ai_planner/ai_planner_page.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/ai_planner/state/ai_planner_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/home/state/suggestion_providers.dart';
import 'package:fitness_app/features/personalisation/state/personalisation_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/recovery/state/recovery_providers.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

import '../../helpers/test_app.dart';

ExerciseItem _ex(String id,
        {String? equipmentId,
        String label = 'None (Bodyweight)',
        String? group,
        bool stretch = false,
        List<String> contra = const []}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: equipmentId,
      equipmentLabel: label,
      muscles: const ['quads'],
      primaryMuscles: const ['quads'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 8,
      summary: '',
      steps: const [],
      isStretch: stretch,
      vendorGroup: group,
      contraindications: contra,
    );

final _pool = <ExerciseItem>[
  _ex('pushup'),
  _ex('squat_bw'),
  _ex('lunge_knee', contra: const ['knee']),
  _ex('leg_press', equipmentId: 'leg_press', label: 'Leg Press Machine'),
  _ex('bb_squat', label: 'Barbell'),
  _ex('db_curl', label: 'Dumbbells'),
  _ex('band_row', label: 'Resistance Band'),
  _ex('rope', label: 'Jump rope'),
  _ex('cobra', label: 'Yoga Mat', group: 'Yoga', stretch: true),
  _ex('fold', label: 'None', group: 'Stretching - Mobility', stretch: true),
  _ex('pigeon',
      label: 'Yoga Mat', group: 'Yoga', stretch: true, contra: const ['knee']),
];

Set<String> _ids(Iterable<ExerciseItem> l) => {for (final e in l) e.id};

/// Every id a context may show for a profile with NO equipment answers.
const _gym = {
  'pushup', 'squat_bw', 'lunge_knee', 'leg_press', 'bb_squat', 'db_curl',
  'band_row', 'rope', 'cobra', 'fold', 'pigeon'
};
const _home = {'pushup', 'squat_bw', 'lunge_knee', 'cobra', 'fold', 'pigeon'};
const _outdoors = {
  'pushup', 'squat_bw', 'lunge_knee', 'band_row', 'rope', 'cobra', 'fold',
  'pigeon'
};
const _yoga = {'cobra', 'fold', 'pigeon'};
const _machineOnly = {'leg_press', 'bb_squat', 'db_curl'};

class _FakeRepo implements EquipmentRepository {
  int poolReads = 0;
  @override
  Future<List<EquipmentItem>> listEquipment() async => const [];
  @override
  Future<EquipmentItem?> findEquipment(String id) async => null;
  @override
  Future<List<ExerciseItem>> exercisesFor(String equipmentId) async => const [];
  @override
  Future<List<ExerciseItem>> bodyweightExercises() async {
    poolReads++;
    return _pool;
  }
}

const _noDeload =
    DeloadVerdict(shouldDeload: false, reasons: [], suggestedVolumeFactor: 1.0);

UserProfile _profile({bool kneeInjury = false}) =>
    UserProfile.empty('u1').copyWith(
      personal: const PersonalInfo(birthYear: 1990),
      health: HealthHistory(
        injuries: kneeInjury
            ? const [
                Injury(bodyPart: 'knee', type: 'sprain', region: InjuryRegion.knee)
              ]
            : const [],
        screening: {for (final q in ParQQuestion.values) q: false},
        flags: HealthFlags(restrictions: const {}),
      ),
      goals: const FitnessGoals(generalFitness: true),
      level: const FitnessLevel(
          tier: FitnessTier.intermediate,
          frequencyPerWeek: 3,
          basics: BasicExerciseAbility.yes),
      schedule: TrainingSchedule(
          daysPerWeek: 3, sessionMinutes: 45, preferredWeekdays: const []),
      completedAt: DateTime(2026, 1, 1),
    );

List<Override> _overrides(_FakeRepo repo, UserProfile profile) => [
      authUserProvider.overrideWith(
          (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
      currentProfileProvider.overrideWith((_) => Stream.value(profile)),
      equipmentRepositoryProvider.overrideWithValue(repo),
      safeCatalogProvider.overrideWith((ref) async {
        final p = await ref.watch(screeningProfileProvider.future);
        return safeFor(_pool, p);
      }),
      weeklyVolumeDeficitProvider.overrideWith((_) async => const {}),
      deloadVerdictProvider.overrideWithValue(_noDeload),
      workoutSessionHistoryProvider.overrideWithValue(const []),
    ];

ProviderContainer _container(_FakeRepo repo, UserProfile profile) {
  final c = ProviderContainer(overrides: _overrides(repo, profile));
  addTearDown(c.dispose);
  // Keep the notifier alive and loaded before the journey starts.
  c.listen(trainingContextProvider, (_, __) {});
  c.listen(activeTrainingContextProvider, (_, __) {});
  return c;
}

Future<void> _settle(ProviderContainer c) async {
  await c.read(trainingContextProvider.future);
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _choose(ProviderContainer c, TrainingContext ctx) async {
  await c.read(trainingContextProvider.notifier).choose(ctx);
  await _settle(c);
}

Future<Set<String>> _planIds(ProviderContainer c) async {
  final out = await c.read(generatedPlanProvider.future);
  return _ids((out! as PlanReady).plan.exercises);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unanswered: nothing is generated by the screens (pool never read)', () async {
    final repo = _FakeRepo();
    final c = _container(repo, _profile());
    await _settle(c);
    expect(c.read(trainingContextProvider).value, TrainingContextAnswer.unanswered);
    expect(c.read(activeTrainingContextProvider), isNull);
    expect(repo.poolReads, 0);
  });

  const cases = <(TrainingContext, Set<String>)>[
    (TrainingContext.gymMachines, _gym),
    (TrainingContext.home, _home),
    (TrainingContext.outdoorMinimal, _outdoors),
    (TrainingContext.yoga, _yoga),
  ];
  for (final (ctx, allowed) in cases) {
    test('${ctx.name}: feed is exactly the allowed set; plan and suggestions stay inside it',
        () async {
      final c = _container(_FakeRepo(), _profile());
      await _settle(c);
      await _choose(c, ctx);
      final feed = await c.read(forYouExercisesInContextProvider(ctx).future);
      expect(_ids(feed), allowed);
      final plan = await _planIds(c);
      expect(plan, isNotEmpty);
      expect(allowed, containsAll(plan));
      final built = (await c.read(generatedPlanProvider.future))! as PlanReady;
      expect(built.plan.reasons.whereType<TrainingContextReason>().single.context, ctx);
      final sugg = await c.read(suggestionsProvider.future);
      expect(sugg, isNotEmpty);
      expect(allowed, containsAll(sugg.map((s) => s.exerciseId)));
      expect(sugg.every((s) => s.trainingContext == ctx), isTrue);
      if (ctx != TrainingContext.gymMachines) {
        expect(plan.intersection(_machineOnly), isEmpty,
            reason: '${ctx.name} must never plan machine/barbell/unowned dumbbell rows');
        expect(sugg.map((s) => s.exerciseId).toSet().intersection(_machineOnly), isEmpty);
      }
    });
  }

  test('home: a profile without equipment gets no machine-only row in plan or suggestions',
      () async {
    final c = _container(_FakeRepo(), _profile());
    await _settle(c);
    await _choose(c, TrainingContext.home);
    expect(await _planIds(c), isNot(anyOf(contains('leg_press'), contains('bb_squat'))));
    final s = (await c.read(suggestionsProvider.future)).map((x) => x.exerciseId);
    expect(s, isNot(contains('leg_press')));
    expect(s, isNot(contains('bb_squat')));
  });

  test('skip behaves as before the question existed (plain feed, no context line)',
      () async {
    final c = _container(_FakeRepo(), _profile());
    await _settle(c);
    await c.read(trainingContextProvider.notifier).skip();
    await _settle(c);
    expect(c.read(trainingContextProvider).value, TrainingContextAnswer.skipped);
    expect(c.read(activeTrainingContextProvider), isNull);
    final plain = await c.read(forYouExercisesProvider.future);
    final viaContext = await c.read(forYouExercisesInContextProvider(null).future);
    expect(_ids(viaContext), _ids(plain));
    final built = (await c.read(generatedPlanProvider.future))! as PlanReady;
    expect(built.plan.reasons.whereType<TrainingContextReason>(), isEmpty);
    final sugg = await c.read(suggestionsProvider.future);
    expect(sugg, isNotEmpty);
    expect(sugg.every((s) => s.trainingContext == null), isTrue);
    expect(_ids(plain).containsAll({'leg_press', 'bb_squat'}), isTrue,
        reason: 'no equipment answers: nothing is withheld, exactly as before');
  });

  test('switching context regenerates plan and suggestions for the new context', () async {
    final c = _container(_FakeRepo(), _profile());
    await _settle(c);
    await _choose(c, TrainingContext.gymMachines);
    final gymSugg = (await c.read(suggestionsProvider.future)).map((s) => s.exerciseId).toSet();
    expect(gymSugg, isNotEmpty);
    await _choose(c, TrainingContext.yoga);
    final yogaPlan = await _planIds(c);
    final yogaSugg = (await c.read(suggestionsProvider.future)).map((s) => s.exerciseId).toSet();
    expect(_yoga, containsAll(yogaPlan));
    expect(_yoga, containsAll(yogaSugg));
    expect(yogaSugg, isNot(gymSugg));
    await _choose(c, TrainingContext.home);
    expect(_home, containsAll(await _planIds(c)));
    expect(_home, containsAll((await c.read(suggestionsProvider.future)).map((s) => s.exerciseId)));
  });

  for (final (ctx, allowed) in cases) {
    test('knee injury screens the knee rows out in ${ctx.name}', () async {
      final c = _container(_FakeRepo(), _profile(kneeInjury: true));
      await _settle(c);
      await _choose(c, ctx);
      final feed = _ids(await c.read(forYouExercisesInContextProvider(ctx).future));
      expect(feed, allowed.difference({'lunge_knee', 'pigeon'}));
      expect(await _planIds(c), isNot(anyOf(contains('lunge_knee'), contains('pigeon'))));
      final s = (await c.read(suggestionsProvider.future)).map((x) => x.exerciseId);
      expect(s, isNot(contains('lunge_knee')));
      expect(s, isNot(contains('pigeon')));
    });
  }

  Future<void> bigSurface(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
  }

  Set<String> shownIds(WidgetTester t) => {
        for (final e in _pool)
          if (find.text(e.id).evaluate().isNotEmpty) e.id
      };

  testWidgets('planner screen: chooser first, then plan per context, regenerated on switch',
      (t) async {
    await bigSurface(t);
    final repo = _FakeRepo();
    await t.pumpWidget(ProviderScope(
      overrides: _overrides(repo, _profile()),
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AiPlannerPage(),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('training-context.selector')), findsOneWidget);
    expect(shownIds(t), isEmpty, reason: 'no plan before the question is answered');
    expect(repo.poolReads, 0);

    await t.tap(find.byKey(const Key('training-context.home')));
    await t.pumpAndSettle();
    var shown = shownIds(t);
    expect(shown, isNotEmpty);
    expect(_home, containsAll(shown));

    await t.tap(find.byKey(const Key('training-context.yoga')));
    await t.pumpAndSettle();
    shown = shownIds(t);
    expect(shown, isNotEmpty);
    expect(_yoga, containsAll(shown), reason: 'yoga shows only yoga/stretch rows');
  });

  testWidgets('planner screen: skip generates the plain plan', (t) async {
    await bigSurface(t);
    final repo = _FakeRepo();
    await t.pumpWidget(ProviderScope(
      overrides: _overrides(repo, _profile()),
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AiPlannerPage(),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('training-context.skip')));
    await t.pumpAndSettle();
    expect(shownIds(t), isNotEmpty);
    expect(repo.poolReads, greaterThan(0));
  });

  testWidgets('home screen: chooser first, no suggestion cards until chosen, then per context',
      (t) async {
    await bigSurface(t);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [GoRoute(path: '/home', builder: (_, __) => const HomePage())],
    );
    await t.pumpWidget(ProviderScope(
      overrides: _overrides(_FakeRepo(), _profile()),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => Material(
            type: MaterialType.transparency,
            child: AuroraBackground(child: child ?? const SizedBox.shrink())),
      ),
    ));
    await t.pumpAndSettle();
    final scroll = find.byType(Scrollable).first;
    await t.scrollUntilVisible(find.byKey(const Key('training-context.selector')), 300,
        scrollable: scroll);
    Set<String> cards() => {
          for (final e in _pool)
            if (find.byKey(Key('suggestion-${e.id}')).evaluate().isNotEmpty) e.id
        };
    expect(cards(), isEmpty, reason: 'no suggestions before the question is answered');
    expect(find.byKey(const Key('suggestions-empty')), findsNothing);

    await t.tap(find.byKey(const Key('training-context.home')));
    await t.pumpAndSettle();
    for (var i = 0; i < 12 && cards().isEmpty; i++) {
      await t.drag(scroll, const Offset(0, -300));
      await t.pumpAndSettle();
    }
    expect(cards(), isNotEmpty);
    expect(_home, containsAll(cards()));
    expect(cards().intersection(_machineOnly), isEmpty);
  });
}
