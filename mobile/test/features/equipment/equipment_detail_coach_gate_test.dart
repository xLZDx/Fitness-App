import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/equipment_detail_page.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
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

  /// R-07 — the health half of the gate, which nothing here reached.
  ///
  /// Every case above blocks through `screening`. `wholePersonBlocks` has four
  /// arms and three of them come from [HealthFlags]: a clinician who advised
  /// against exercise, unexpired post-operative restrictions, and F014's
  /// professional-guidance answer. A regression that dropped the health arms
  /// entirely — which is the exact shape F014 failed in twice, a field that
  /// reaches the model and the serialiser but not the guard — would have left
  /// all three tests above green.
  ///
  /// So each arm gets a case, with the questionnaire fully CLEARED, so that
  /// the health answer is the only thing that can be doing the blocking. The
  /// control at the top of the group is what makes them non-vacuous: the same
  /// cleared screening, the same page, and the coach IS offered.
  group('R-07: a stated health answer withholds the coach on its own', () {
    SafetyContext clearedWith(HealthFlags health) => SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}),
          health: health,
        );

    testWidgets('the control: cleared screening, nothing stated, coach shown',
        (t) async {
      // Deliberately duplicated from the top of the file, with the health
      // object made explicit. Without it every case below could pass because
      // the page stopped rendering the entry at all.
      await pump(t, clearedWith(HealthFlags.empty));
      expect(find.byKey(const Key('equipment-ai-coach')), findsOneWidget);
    });

    testWidgets('F014: professional guidance reported', (t) async {
      await pump(
        t,
        clearedWith(const HealthFlags(
          professionalGuidance: ProfessionalGuidanceNeed.reported,
        )),
      );
      expect(find.byKey(const Key('equipment-ai-coach')), findsNothing,
          reason: 'F014. The app holds no validated prescription policy for '
              'this state, and the coach\'s answer is a prescription');
    });

    testWidgets('F014: the same field answered NO does not withhold it',
        (t) async {
      // The three-state semantics, at the surface. `null` is never asked,
      // `.none` is answered no, `.reported` is answered yes -- and only the
      // last blocks. A guard that treated "answered" as "blocked" would refuse
      // every user who completed the questionnaire honestly.
      await pump(
        t,
        clearedWith(const HealthFlags(
          professionalGuidance: ProfessionalGuidanceNeed.none,
        )),
      );
      expect(find.byKey(const Key('equipment-ai-coach')), findsOneWidget);
    });

    testWidgets('a clinician advised against exercise', (t) async {
      await pump(
        t,
        clearedWith(const HealthFlags(
          clinicianAdvice: ClinicianExerciseAdvice.advisedAgainstExercise,
        )),
      );
      expect(find.byKey(const Key('equipment-ai-coach')), findsNothing);
    });

    testWidgets('post-operative restrictions are still in force', (t) async {
      await pump(
        t,
        clearedWith(const HealthFlags(surgery: SurgeryStatus.underRestrictions)),
      );
      expect(find.byKey(const Key('equipment-ai-coach')), findsNothing);
    });

    testWidgets('discharged back to normal exercise does not withhold it',
        (t) async {
      await pump(
        t,
        clearedWith(
            const HealthFlags(surgery: SurgeryStatus.clearedForNormalExercise)),
      );
      expect(find.byKey(const Key('equipment-ai-coach')), findsOneWidget);
    });
  });
}
