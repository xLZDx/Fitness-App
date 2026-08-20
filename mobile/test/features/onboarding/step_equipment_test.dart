import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/onboarding/state/questionnaire_notifier.dart';
import 'package:fitness_app/features/onboarding/steps/step_equipment.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import '../../helpers/test_app.dart';

/// MRD-02, Gate F — the gym-name field is conditional on [TrainingLocation],
/// same as `hasGymAccess` derives from it, and writes to the draft the same
/// way every other field on this screen already does.
Widget _harness(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: StepEquipment()),
        ),
      ),
    );

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

void main() {
  testWidgets('the gym field is absent until a gym-inclusive place is picked',
      (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    expect(find.byKey(const Key('onb.gymId')), findsNothing);
  });

  testWidgets('picking "gym" reveals the field', (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.place.gym')));

    expect(find.byKey(const Key('onb.gymId')), findsOneWidget);
  });

  testWidgets('picking "mixed" also reveals the field', (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.place.mixed')));

    expect(find.byKey(const Key('onb.gymId')), findsOneWidget);
  });

  testWidgets(
      'picking "home" or "outdoor" keeps the field hidden, even after '
      'previously showing it', (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.place.gym')));
    expect(find.byKey(const Key('onb.gymId')), findsOneWidget);

    await _tapVisible(tester, find.byKey(const Key('onb.place.home')));
    expect(find.byKey(const Key('onb.gymId')), findsNothing,
        reason: 'a location with no gym in it must not still show the field');
  });

  testWidgets('typing a gym name writes it to the draft', (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.place.gym')));
    await tester.enterText(
        find.byKey(const Key('onb.gymId')), 'Iron Temple');
    await tester.pump();

    expect(c.read(questionnaireDraftProvider).equipment.gymId, 'Iron Temple');
  });

  testWidgets(
      'REGRESSION: typing a multi-word name character by character keeps '
      'the spaces -- a per-keystroke trim fed back into this controlled '
      "field's value strips the space at every word boundary the moment the "
      'draft rebuild lands, before the next key is pressed',
      (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.place.gym')));

    // Each step appends one character to whatever the field is *actually*
    // displaying right now -- not to an assumed target prefix -- so a
    // resync that silently dropped a character on the previous frame (the
    // failure this test exists to catch) is reflected in what the next
    // keystroke is typed onto, exactly as a real keyboard would.
    const target = 'Iron Temple Gym';
    final fieldFinder = find.byKey(const Key('onb.gymId'));
    for (final ch in target.split('')) {
      final editable = tester.widget<EditableText>(
        find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
      );
      await tester.enterText(fieldFinder, editable.controller.text + ch);
      await tester.pump();
    }

    expect(c.read(questionnaireDraftProvider).equipment.gymId, target);
  });

  testWidgets(
      'REGRESSION shape: an unset gym still reports gymId null, not an '
      'empty-string default that would masquerade as a real (if blank) answer',
      (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.place.gym')));

    expect(c.read(questionnaireDraftProvider).equipment.gymId, isNull);
  });

  testWidgets(
      'BLOCKER (codex review, Gate F cherry-pick, 2026-08-21): switching '
      'away from gym/mixed clears gymId, so a later report cannot be sent '
      "to the user's former gym", (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.place.gym')));
    await tester.enterText(
        find.byKey(const Key('onb.gymId')), 'Iron Temple');
    await tester.pump();
    expect(c.read(questionnaireDraftProvider).equipment.gymId, 'Iron Temple');

    await _tapVisible(tester, find.byKey(const Key('onb.place.home')));

    expect(c.read(questionnaireDraftProvider).equipment.gymId, isNot('Iron Temple'));
    expect(c.read(questionnaireDraftProvider).equipment.hasGymAccess, false);
  });

  testWidgets(
      'switching gym -> mixed keeps the gym name (both are gym access, '
      'not a reason to clear it)', (tester) async {
    final c = _container();
    await tester.pumpWidget(_harness(c));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.place.gym')));
    await tester.enterText(
        find.byKey(const Key('onb.gymId')), 'Iron Temple');
    await tester.pump();

    await _tapVisible(tester, find.byKey(const Key('onb.place.mixed')));

    expect(c.read(questionnaireDraftProvider).equipment.gymId, 'Iron Temple');
  });
}
