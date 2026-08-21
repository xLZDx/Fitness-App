import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_setup_note.dart';
import 'package:fitness_app/features/equipment/data/equipment_setup_note_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_setup_note_providers.dart';
import 'package:fitness_app/features/equipment/widgets/setup_note_card.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

UserProfile _profileWithGym(String? gymId) => UserProfile.empty('u').copyWith(
      equipment: EquipmentAccess(
        location: TrainingLocation.gym,
        gymId: gymId,
      ),
    );

Widget _harness({
  required UserProfile? profile,
  EquipmentSetupNoteRepository? repo,
  Key? key,
}) =>
    ProviderScope(
      key: key,
      overrides: [
        currentProfileProvider.overrideWith((_) => Stream.value(profile)),
        equipmentSetupNoteRepositoryProvider
            .overrideWithValue(repo ?? MockEquipmentSetupNoteRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(
            width: 360,
            child: SetupNoteCard(equipmentId: 'leg_press'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders nothing when the profile has no gymId set',
      (tester) async {
    await tester.pumpWidget(_harness(profile: _profileWithGym(null)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('equipment.setupNote')), findsNothing);
  });

  testWidgets('renders nothing when gymId is set but blank', (tester) async {
    await tester.pumpWidget(_harness(profile: _profileWithGym('   ')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('equipment.setupNote')), findsNothing);
  });

  testWidgets('renders nothing when there is no signed-in profile at all',
      (tester) async {
    await tester.pumpWidget(_harness(profile: null));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('equipment.setupNote')), findsNothing);
  });

  testWidgets('shows the card, empty, once a gym is set', (tester) async {
    await tester.pumpWidget(_harness(profile: _profileWithGym('Gold\'s Gym')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('equipment.setupNote')), findsOneWidget);
    expect(find.text('At Gold\'s Gym'), findsOneWidget);
  });

  testWidgets('loads and displays a previously saved note', (tester) async {
    final repo = MockEquipmentSetupNoteRepository();
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: 'seat 4, pin 8',
      updatedAt: DateTime(2026, 8, 19),
    ));

    await tester.pumpWidget(
        _harness(profile: _profileWithGym('Gold\'s Gym'), repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('seat 4, pin 8'), findsOneWidget);
  });

  testWidgets('typing and saving writes the note to the repository',
      (tester) async {
    final repo = MockEquipmentSetupNoteRepository();
    await tester.pumpWidget(
        _harness(profile: _profileWithGym('Gold\'s Gym'), repo: repo));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('equipment.setupNote.field')), 'seat 4, pin 8');
    await tester.pump();
    await tester.tap(find.byKey(const Key('equipment.setupNote.save')));
    await tester.pumpAndSettle();

    final saved =
        await repo.get(equipmentId: 'leg_press', gymId: 'Gold\'s Gym');
    expect(saved?.note, 'seat 4, pin 8');
    expect(find.text('Setup note saved'), findsOneWidget);
  });

  testWidgets(
      'two different gyms show two different notes for the same equipment',
      (tester) async {
    final repo = MockEquipmentSetupNoteRepository();
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: 'seat 4',
      updatedAt: DateTime(2026, 8, 19),
    ));
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Planet Fitness',
      note: 'seat 6',
      updatedAt: DateTime(2026, 8, 19),
    ));

    await tester.pumpWidget(_harness(
      profile: _profileWithGym('Gold\'s Gym'),
      repo: repo,
      key: const Key('gold'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('seat 4'), findsOneWidget);

    await tester.pumpWidget(_harness(
      profile: _profileWithGym('Planet Fitness'),
      repo: repo,
      key: const Key('planet'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('seat 6'), findsOneWidget);
  });

  testWidgets(
      'REGRESSION (Gate G flutter-reviewer): revisiting the same equipment '
      "after Save shows the just-saved note, not the pre-save cache -- "
      "equipmentSetupNoteProvider is a plain FutureProvider.family with no "
      "autoDispose, so its resolved value survives disposal of the widget "
      "that watched it unless explicitly invalidated after save()",
      (tester) async {
    final repo = MockEquipmentSetupNoteRepository();
    final container = ProviderContainer(overrides: [
      currentProfileProvider
          .overrideWith((_) => Stream.value(_profileWithGym('Gold\'s Gym'))),
      equipmentSetupNoteRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    Widget page(Key cardKey) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: SetupNoteCard(key: cardKey, equipmentId: 'leg_press'),
              ),
            ),
          ),
        );

    // First visit: nothing saved yet, field starts empty.
    await tester.pumpWidget(page(const Key('visit1')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('equipment.setupNote.field')), 'seat 4, pin 8');
    await tester.pump();
    await tester.tap(find.byKey(const Key('equipment.setupNote.save')));
    await tester.pumpAndSettle();

    // Simulate leaving and reopening the page: a brand new SetupNoteCard
    // State (distinct key), but the same ProviderContainer -- exactly what
    // real navigation does, since providers live in the container, not in
    // any one page's widget tree.
    await tester.pumpWidget(page(const Key('visit2')));
    await tester.pumpAndSettle();

    expect(find.text('seat 4, pin 8'), findsOneWidget,
        reason: 'the provider must be invalidated after save(), or a '
            'revisit re-shows the stale pre-save cache');
  });

  testWidgets(
      'REGRESSION: if the signed-in gym changes while this same card stays '
      'mounted (profile edited elsewhere, e.g. "edit your answers"), it '
      "shows the NEW gym's note, not the previous gym's draft text left over "
      'in local state -- a stale draft here would also make the next Save '
      "write the old gym's text under the new gym's key", (tester) async {
    final repo = MockEquipmentSetupNoteRepository();
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Gold\'s Gym',
      note: 'seat 4',
      updatedAt: DateTime(2026, 8, 19),
    ));
    await repo.save(EquipmentSetupNote(
      equipmentId: 'leg_press',
      gymId: 'Planet Fitness',
      note: 'seat 6',
      updatedAt: DateTime(2026, 8, 19),
    ));

    final profileCtrl = StreamController<UserProfile?>();
    addTearDown(profileCtrl.close);
    profileCtrl.add(_profileWithGym('Gold\'s Gym'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((_) => profileCtrl.stream),
          equipmentSetupNoteRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(
              width: 360,
              child: SetupNoteCard(equipmentId: 'leg_press'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('seat 4'), findsOneWidget);

    // Same widget instance, same State -- only the upstream profile changes,
    // exactly as it would if the user backgrounded this page, edited their
    // gym on the onboarding screen, and returned.
    profileCtrl.add(_profileWithGym('Planet Fitness'));
    await tester.pumpAndSettle();

    expect(find.text('seat 6'), findsOneWidget);
    expect(find.text('seat 4'), findsNothing);
  });
}
