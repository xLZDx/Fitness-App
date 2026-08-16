import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/test_app.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_card.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_card_repository.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_describer.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/machine_card_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/widgets/machine_card_view.dart';

/// The scan, end to end, for a machine the catalog does not have.
///
/// Operator: *"если есть в каталоге то показывать из каталога сразу, а если нет
/// — объяснить человеку, что за железка перед ним и что на нем можно делать и
/// сохранить карточку тренажера"*, and *"пользователю тоже видна как «контент
/// готовится»"*. Both halves are load-bearing and both are checked here: what
/// the user is shown, and what we are left holding afterwards.
///
/// Counts the describer's calls too — the second question costs money, and
/// asking it for a machine the catalog already answered would be paying to
/// duplicate an answer we had for free.
class _CountingDescriber implements MachineDescriber {
  _CountingDescriber(this.card);
  final MachineCard? card;
  int calls = 0;

  @override
  Future<MachineCard?> describe({
    required String path,
    String languageCode = 'ru',
    String? recognisedAs,
    double? confidence,
    DateTime? now,
  }) async {
    calls++;
    return card;
  }
}

void main() {
  MachineCard aCard({String name = 'Belt Squat Machine'}) => MachineCard(
        id: machineCardId(name),
        name: name,
        summary: 'A hip-belt loaded squat machine, easy on the spine.',
        uses: const ['Belt squats', 'Calf raises'],
        firstSeenAt: DateTime(2026, 8, 3, 10),
        lastSeenAt: DateTime(2026, 8, 3, 10),
      );

  Future<ProviderContainer> pumpScan(
    WidgetTester tester, {
    required List<Override> overrides,
  }) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/scan',
      routes: [GoRoute(path: '/scan', builder: (_, __) => const ScannerPage())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(ScannerPage)));
  }

  group('a machine the catalog has no page for', () {
    testWidgets('is explained instead of shrugged at', (tester) async {
      // The old answer was "Couldn't tell what that is" and nothing else,
      // which stops being true the moment the second question can name it.
      final repo = MockMachineCardRepository();
      addTearDown(repo.dispose);
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(_NoMatch()),
        machineDescriberProvider
            .overrideWithValue(MockMachineDescriber(card: aCard())),
        machineCardRepositoryProvider.overrideWithValue(repo),
      ]);

      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/unknown.jpg');
      // Two pumps rather than one: F016 made the `uses` list wait on
      // `safetyContextProvider`, which is a FutureProvider, and the card
      // deliberately withholds the list until it resolves rather than showing
      // unscreened movements for the frame in between. The name and the
      // summary -- what this test is actually about -- appear on the first
      // pump either way. `pumpAndSettle` is not an option here: the scan
      // screen animates continuously and it times out.
      await tester.pump();
      await tester.pump();

      expect(find.byType(MachineCardView), findsWidgets);
      expect(find.text('Belt Squat Machine'), findsWidgets);
      expect(find.text('Belt squats'), findsWidgets);
      expect(find.text('Point at a machine and tap Recognise'), findsNothing);
    });

    testWidgets('says plainly that the demonstration is not ready',
        (tester) async {
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(_NoMatch()),
        machineDescriberProvider
            .overrideWithValue(MockMachineDescriber(card: aCard())),
      ]);
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/unknown.jpg');
      await tester.pump();

      expect(find.text('Content being prepared'), findsWidgets);
    });

    testWidgets('is kept, so we know what to film', (tester) async {
      final repo = MockMachineCardRepository();
      addTearDown(repo.dispose);
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(_NoMatch()),
        machineDescriberProvider
            .overrideWithValue(MockMachineDescriber(card: aCard())),
        machineCardRepositoryProvider.overrideWithValue(repo),
      ]);
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/unknown.jpg');
      await tester.pump();

      final stored = await repo.list();
      expect(stored, hasLength(1));
      expect(stored.single.name, 'Belt Squat Machine');
    });

    testWidgets('appears in the "being prepared" list', (tester) async {
      final repo = MockMachineCardRepository();
      addTearDown(repo.dispose);
      await repo.save(aCard(name: 'Pendulum Squat'));
      await pumpScan(tester, overrides: [
        machineCardRepositoryProvider.overrideWithValue(repo),
      ]);
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Being prepared'), 200);
      expect(find.text('Pendulum Squat'), findsOneWidget);
      expect(find.textContaining('Not in the catalog yet'), findsOneWidget);
    });

    testWidgets('a machine we have since added leaves that list',
        (tester) async {
      // Otherwise a machine that already ships a clip keeps telling the user
      // its content is being prepared.
      final repo = MockMachineCardRepository();
      addTearDown(repo.dispose);
      final card = aCard(name: 'Pendulum Squat');
      await repo.save(MachineCard(
        id: card.id,
        name: card.name,
        summary: card.summary,
        uses: card.uses,
        firstSeenAt: card.firstSeenAt,
        lastSeenAt: card.lastSeenAt,
        status: MachineCardStatus.inCatalog,
      ));
      await pumpScan(tester, overrides: [
        machineCardRepositoryProvider.overrideWithValue(repo),
      ]);
      await tester.pump();

      expect(find.text('Being prepared'), findsNothing);
      expect(find.text('Pendulum Squat'), findsNothing);
    });
  });

  group('a machine the catalog DOES have', () {
    testWidgets('answers from the catalog and is never described',
        (tester) async {
      // Operator: "если есть в каталоге то показывать из каталога сразу". The
      // second question is a second billed call; asking it here would be
      // paying to duplicate an answer we already had.
      final describer = _CountingDescriber(aCard());
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
          ]),
        ),
        machineDescriberProvider.overrideWithValue(describer),
      ]);
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/known.jpg');
      await tester.pump();

      expect(describer.calls, 0);
      expect(find.byType(MachineCardView), findsNothing);
      expect(find.text('leg press'), findsOneWidget);
    });
  });

  group('when the second question has nothing to say either', () {
    testWidgets('the honest empty answer comes back', (tester) async {
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(_NoMatch()),
        machineDescriberProvider.overrideWithValue(MockMachineDescriber()),
      ]);
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/dog.jpg');
      await tester.pump();

      expect(find.byType(MachineCardView), findsNothing);
      // Back to the plain hint: nothing was recognised and nothing could be
      // explained, and the screen says so rather than showing a blank.
      expect(find.text('Point at a machine and tap Recognise'), findsOneWidget);
    });

    testWidgets('a failing store does not take the answer off the screen',
        (tester) async {
      // The user is reading the card either way; losing one row of "what
      // people photograph" is our problem, not theirs.
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(_NoMatch()),
        machineDescriberProvider
            .overrideWithValue(MockMachineDescriber(card: aCard())),
        machineCardRepositoryProvider.overrideWithValue(_BrokenStore()),
      ]);
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/unknown.jpg');
      await tester.pump();

      expect(find.text('Belt Squat Machine'), findsWidgets);
    });

    testWidgets('a new scan clears the previous machine', (tester) async {
      // Otherwise the card from the last photo sits under the results of the
      // next one, describing a machine the user has walked away from.
      final container = await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(_NoMatch()),
        machineDescriberProvider
            .overrideWithValue(MockMachineDescriber(card: aCard())),
      ]);
      await container
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/a.jpg');
      await tester.pump();
      expect(container.read(lastMachineCardProvider), isNotNull);

      container.read(lastMachineCardProvider.notifier).clear();
      await tester.pump();
      expect(find.byType(MachineCardView), findsNothing);
    });
  });

  group('the way out to a video that does exist', () {
    testWidgets('searches for the machine by name', (tester) async {
      // Operator: "а клиенту посоветовать ролик на ютюбе или еще где пока мы
      // не добавим новый контент".
      Uri? opened;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MachineCardView(
              card: aCard(),
              onWatchElsewhere: (u) async {
                opened = u;
                return true;
              },
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('machine-card-watch')));
      await tester.pump();

      expect(opened, isNotNull);
      expect(opened!.host, contains('youtube'));
      expect(opened!.queryParameters['search_query'],
          contains('Belt Squat Machine'));
    });
  });

  group('F016: model-written "what you can do on it" is not shown unscreened',
      () {
    /// The card on its own, under whatever safety context the test supplies.
    Future<void> pumpCard(
      WidgetTester tester, {
      required List<Override> overrides,
    }) async {
      await tester.pumpWidget(ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MachineCardView(card: aCard())),
        ),
      ));
      await tester.pumpAndSettle();
    }

    final cleared = SafetyContext(
      screening: screen({for (final q in ParQQuestion.values) q: false}),
    );

    testWidgets('a user with nothing to screen against still sees the list',
        (tester) async {
      // The feature must survive its own safety fix: withholding from
      // everybody would delete it rather than make it safe.
      await pumpCard(tester, overrides: [
        safetyContextProvider.overrideWith((_) async => cleared),
      ]);

      expect(find.text('Belt squats'), findsOneWidget);
      expect(find.byKey(const Key('machine-card.uses-withheld')), findsNothing);
    });

    testWidgets('an injured user gets the reason, not the movements',
        (tester) async {
      // The finding itself. `uses` is free text with no contraindication
      // tags, so nothing screens it -- the same reason `ai::` exercises are
      // excluded for injured users in equipment_providers.dart:481-482.
      await pumpCard(tester, overrides: [
        safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening: cleared.screening,
              injuries: const [Injury(bodyPart: 'lower back', type: 'strain')],
            )),
      ]);

      expect(find.text('Belt squats'), findsNothing);
      expect(find.text('Calf raises'), findsNothing);
      expect(
          find.byKey(const Key('machine-card.uses-withheld')), findsOneWidget);
    });

    testWidgets('an ANSWERED whole-person block withholds them too',
        (tester) async {
      // Someone the app is refusing to train at all must not be handed a
      // list of movements to try -- the same error G-A removed from five
      // other surfaces.
      await pumpCard(tester, overrides: [
        safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening: screen({
                for (final q in ParQQuestion.values)
                  q: q == ParQQuestion.chestPain,
              }),
            )),
      ]);

      expect(find.text('Belt squats'), findsNothing);
      expect(
          find.byKey(const Key('machine-card.uses-withheld')), findsOneWidget);
    });

    testWidgets('an UNANSWERED screen does not withhold them', (tester) async {
      // `screen()` is fail-closed, so an un-onboarded user is "blocked" for
      // having answered nothing at all. Gating on that would withhold from
      // most people who ever open the scanner and delete the feature rather
      // than make it safe -- the same failure mode as requiring a catalogue
      // match. Nothing has been told to us, so there is nothing to screen
      // against, and SafetyDisclosure is what states that honestly.
      await pumpCard(tester, overrides: [
        safetyContextProvider
            .overrideWith((_) async => SafetyContext(screening: kUnscreened)),
      ]);

      expect(find.text('Belt squats'), findsOneWidget);
      expect(find.byKey(const Key('machine-card.uses-withheld')), findsNothing);
    });

    testWidgets('a movement restriction withholds them too', (tester) async {
      // A restriction is exactly a statement about which movements are
      // unsafe, and this list is movements. Nothing here can honour it.
      await pumpCard(tester, overrides: [
        safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening: cleared.screening,
              health: const HealthFlags(
                restrictions: {MovementRestriction.overhead},
              ),
            )),
      ]);

      expect(find.text('Belt squats'), findsNothing);
      expect(
          find.byKey(const Key('machine-card.uses-withheld')), findsOneWidget);
    });

    testWidgets('the card still names the machine and says what it is',
        (tester) async {
      // Withholding the movements must not withhold the answer. The user
      // photographed a real machine and is owed what it is.
      await pumpCard(tester, overrides: [
        safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening: cleared.screening,
              injuries: const [Injury(bodyPart: 'lower back', type: 'strain')],
            )),
      ]);

      expect(find.text('Belt Squat Machine'), findsOneWidget);
      expect(find.textContaining('hip-belt loaded squat machine'),
          findsOneWidget);
    });
  });
}

/// Recognises nothing at all.
///
/// [MockVisualEquipmentService] cannot stand in here: given an empty
/// `fixedResults` it falls through to a deterministic seeded answer and returns
/// three matches, which is the opposite of the case under test.
class _NoMatch implements VisualEquipmentService {
  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async =>
      const [];
}

/// A store whose every write fails, to prove the user still gets their answer.
class _BrokenStore implements MachineCardRepository {
  @override
  Future<void> save(MachineCard card) async => throw StateError('offline');

  @override
  Stream<List<MachineCard>> watch() => Stream.value(const []);

  @override
  Future<List<MachineCard>> list() async => const [];

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> clear() async {}
}
