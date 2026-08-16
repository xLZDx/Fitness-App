import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/equipment_detail_page.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';

/// N04 (G-B/B4) — the machine page's route to a prescription.
///
/// `AiCoachSheet`'s answer is sets and reps. `exercise_page.dart` cannot serve
/// it to a refused user because its entry point sits inside
/// `ExerciseResolutionView`'s builder, which never runs for one. This page
/// reached the sheet directly and applied no such gate, so a user the app
/// refuses all training could still ask for and receive a prescription.
///
/// This file exists because `EquipmentDetailPage` had no test of any kind, so
/// there was nothing for the gate to be added to.
const _machine = EquipmentItem(
  id: 'leg_press',
  name: 'Leg Press',
  manufacturer: 'Any',
  category: 'strength',
  description: 'd',
);

Widget _page({required SafetyContext safety}) => ProviderScope(
      overrides: [
        equipmentByIdProvider.overrideWith((ref, id) async => _machine),
        recommendedExercisesProvider.overrideWith(
          (ref, id) async =>
              const RecommendedExercises(items: [], hiddenForInjury: 0),
        ),
        safetyContextProvider.overrideWith((_) async => safety),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EquipmentDetailPage(equipmentId: 'leg_press'),
      ),
    );

SafetyContext _cleared() => SafetyContext(
      screening: screen({for (final q in ParQQuestion.values) q: false}),
    );

SafetyContext _chestPain() => SafetyContext(
      screening: screen({
        for (final q in ParQQuestion.values) q: q == ParQQuestion.chestPain,
      }),
    );

void main() {
  Future<void> pump(WidgetTester t, SafetyContext safety) async {
    t.view.physicalSize = const Size(400, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_page(safety: safety));
    await t.pumpAndSettle();
  }

  testWidgets('a cleared user is offered the AI coach', (t) async {
    // The control. The gate must filter, not remove the feature.
    await pump(t, _cleared());
    expect(find.byKey(const Key('equipment-ai-coach')), findsOneWidget);
  });

  testWidgets('N04: a user refused all training is not', (t) async {
    await pump(t, _chestPain());
    expect(find.byKey(const Key('equipment-ai-coach')), findsNothing);
  });

  testWidgets('an unfinished questionnaire still is', (t) async {
    // `screen()` is fail-closed, so an un-onboarded user is `blocked` with
    // every reason marked incomplete. Gating on `allowsAnyTraining` would
    // therefore hide the coach from everyone who has not onboarded -- a far
    // larger change than N04 describes, landing on people who have told us
    // nothing that refuses them. See `SafetyContext.blockedByAStatedAnswer`.
    await pump(t, SafetyContext(screening: kUnscreened));
    expect(find.byKey(const Key('equipment-ai-coach')), findsOneWidget);
  });
}
