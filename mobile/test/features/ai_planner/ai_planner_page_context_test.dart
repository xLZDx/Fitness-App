import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/ai_planner_page.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/ai_planner/state/ai_planner_providers.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';

class _FakeTrainingContext extends TrainingContextNotifier {
  _FakeTrainingContext(this.initial);
  final TrainingContextAnswer initial;
  @override
  Future<TrainingContextAnswer> build() async => initial;
  @override
  Future<void> select(TrainingContextAnswer answer) async =>
      state = AsyncData(answer);
}

void main() {
  testWidgets(
      'planner page asks first, generates nothing until answered, and '
      'regenerates for each new choice', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    // Each build of the plan provider records the context it was built under.
    final builtFor = <TrainingContext?>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        trainingContextProvider.overrideWith(
            () => _FakeTrainingContext(TrainingContextAnswer.unanswered)),
        generatedPlanProvider.overrideWith((ref) async {
          final tc = (await ref.watch(trainingContextProvider.future)).context;
          builtFor.add(tc);
          return const PlanRefused([]);
        }),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiPlannerPage(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('training-context.selector')), findsOneWidget);
    expect(find.byKey(const Key('training-context.skip')), findsOneWidget);
    expect(builtFor, isEmpty,
        reason: 'the plan must not be generated before the question is answered');

    await tester.tap(find.byKey(const Key('training-context.gymMachines')));
    await tester.pumpAndSettle();
    expect(builtFor, [TrainingContext.gymMachines]);
    expect(find.byKey(const Key('planner.refused')), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-context.home')));
    await tester.pumpAndSettle();
    expect(builtFor, [TrainingContext.gymMachines, TrainingContext.home],
        reason: 'changing the context regenerates the plan');
  });

  testWidgets('skip generates once with a null context', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final builtFor = <TrainingContext?>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        trainingContextProvider.overrideWith(
            () => _FakeTrainingContext(TrainingContextAnswer.unanswered)),
        generatedPlanProvider.overrideWith((ref) async {
          builtFor.add((await ref.watch(trainingContextProvider.future)).context);
          return const PlanRefused([]);
        }),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiPlannerPage(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-context.skip')));
    await tester.pumpAndSettle();
    expect(builtFor, [null]);
  });
}
