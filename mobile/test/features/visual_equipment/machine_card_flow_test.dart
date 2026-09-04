import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../../helpers/test_app.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/exercise_name_matcher.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
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

/// Routes a gallery pick to a fixed path, so the ScannerPage's own Recognise
/// flow can be driven from a test without a real picker or camera.
class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker(this.path);
  final String path;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile(path);
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
      overrides: [
        // G-C/F016: this whole file's fixture (`aCard()`) writes exercise
        // names the real bundled catalogue has no reason to contain — this
        // is what a real, current-language catalogue would look like for
        // exactly those two lines, so every test in this group keeps
        // exercising the safety-answer/persistence behaviour it was written
        // for, independent of the separate content-validation concern
        // covered by scan_controller_test.dart and
        // exercise_name_matcher_test.dart. A test that wants to exercise
        // filtering itself overrides this again, after it in the list.
        exerciseNameMatcherProvider.overrideWithValue(
          ExerciseNameMatcher(const ['Belt squats', 'Calf raises']),
        ),
        ...overrides,
      ],
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

  /// Drives a scan through the real Recognise-from-gallery flow (a fake
  /// picker + a tap), instead of poking `classifyFilePath` on the provider
  /// directly. `ScannerPage` gates its "nothing to see" hint on its own
  /// `_attempted` flag -- deliberately, since a fresh scan and a genuine
  /// no-match both resolve to the identical `ScanOutcome.noEquipment` at the
  /// provider level, and only a real Recognise action tells them apart. A
  /// test that wants to observe that hint has to go through the flow that
  /// sets the flag, not the provider that cannot.
  Future<void> tapGalleryRecognise(WidgetTester tester,
      {String path = '/tmp/dog.jpg'}) async {
    final previous = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _FakeImagePicker(path);
    addTearDown(() => ImagePickerPlatform.instance = previous);
    await tester.tap(find.byKey(const Key('scan-recognise-gallery')));
    await tester.pump();
    await tester.pump();
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
      // A `findsNothing` for the pristine "Point at a machine..." hint used
      // to sit here. Dropped (SCAN-G1 functional-test review): `_HintCard`
      // is only ever instantiated with `noMatch: true` in production now, so
      // that string is unreachable from any code path -- the assertion could
      // never fail and was proving nothing beyond what the three lines above
      // already do.
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
      await pumpScan(tester, overrides: [
        visualEquipmentServiceProvider.overrideWithValue(_NoMatch()),
        machineDescriberProvider.overrideWithValue(MockMachineDescriber()),
      ]);
      await tapGalleryRecognise(tester);

      expect(find.byType(MachineCardView), findsNothing);
      // The screen says so rather than showing a blank -- the honest
      // "couldn't tell" hint, not the pristine "point at a machine" prompt.
      // `_HintCard` (`scanner_page.dart`) always passes `noMatch: true` on a
      // genuinely attempted, empty result, and reserves the pristine prompt
      // for the state before any scan; `_attempted` (SCAN-G1) is exactly
      // what tells the two apart, since both resolve to the identical
      // `ScanOutcome.noEquipment` at the provider level.
      expect(find.text("Couldn't tell what that is"), findsOneWidget);
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
      MachineCard? card,
    }) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          // MachineCardView now re-validates `card.uses` against the real
          // catalogue on every render (see its own doc comment) — this
          // group is about the SEPARATE safety-answer gate, so give it a
          // catalogue that recognises this file's fixture content, same as
          // `pumpScan` above. A test about the validation gate itself
          // overrides this again, after it, in its own `overrides`.
          exerciseNameMatcherProvider.overrideWithValue(
            ExerciseNameMatcher(const ['Belt squats', 'Calf raises']),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MachineCardView(card: card ?? aCard())),
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

    testWidgets(
        'G-C/F016: a line with no catalogue match never renders, even for '
        'a card this widget did not just receive from _describeInstead',
        (tester) async {
      // The regression two independent reviews caught in the first version
      // of this fix: filtering only at the point `_describeInstead` first
      // saves a card protects that one write path, but says nothing about a
      // card streamed in from storage by any other path (the saved-machines
      // list, a card written before this fix shipped, a future write path
      // that forgets to filter). This pumps a card DIRECTLY, the same way a
      // list render would, with content the override below never validated
      // — proving the widget itself is now the actual safety boundary,
      // independent of how or when the card was written.
      await pumpCard(
        tester,
        card: MachineCard(
          id: 'unknown_2',
          name: 'Old Unvalidated Machine',
          summary: 'A card as if it had been saved before this fix shipped.',
          uses: const ['Genuinely Invented Exercise'],
          firstSeenAt: DateTime(2025, 1, 1),
        ),
        overrides: [
          safetyContextProvider.overrideWith((_) async => cleared),
          // Deliberately does NOT recognise "Genuinely Invented Exercise" —
          // this is what an un-migrated, pre-fix stored card looks like
          // against today's real catalogue.
          exerciseNameMatcherProvider
              .overrideWithValue(ExerciseNameMatcher(const ['Leg Press'])),
        ],
      );

      expect(find.text('Genuinely Invented Exercise'), findsNothing);
      // Not "withheld" either — there was never anything validated to
      // withhold, which is a different, more honest state than "hidden for
      // your safety".
      expect(find.byKey(const Key('machine-card.uses-withheld')), findsNothing);
      expect(find.text('Old Unvalidated Machine'), findsOneWidget);
    });

    testWidgets(
        'G-C/F016 (GPT-PM round 19): a legitimate suggestion reappears once '
        'a still-loading catalogue resolves — no rescan needed', (tester) async {
      // The specific defect round 19 found in the first fix: a write-time
      // filter, reading the matcher once while the catalogue was still
      // loading, destroyed the raw text before anything could recover it.
      // This proves the actual (render-time, read-nothing-destructively)
      // design: the SAME card, never rewritten, shows nothing while the
      // catalogue is empty and then shows the real suggestion the moment the
      // catalogue provider updates — without the card being touched again.
      final card = MachineCard(
        id: 'unknown_3',
        name: 'Cold Start Machine',
        summary: 'Scanned before the catalogue had loaded.',
        uses: const ['Leg Press for quads'],
        firstSeenAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          safetyContextProvider.overrideWith((_) async => cleared),
          // Starts empty — "the catalogue is still loading" — and is
          // watched, not fixed, so updating it mid-test is exactly what a
          // real FutureProvider resolving later looks like to this widget.
          exerciseNameMatcherProvider.overrideWith(
            (ref) => ExerciseNameMatcher(ref.watch(_catalogueLoadStub)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MachineCardView(card: card)),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Leg Press for quads'), findsNothing);

      final container =
          ProviderScope.containerOf(tester.element(find.byType(MachineCardView)));
      container.read(_catalogueLoadStub.notifier).state = ['Leg Press'];
      await tester.pump();

      // The catalogue title, not the model's original elaborated line —
      // resolve() returns the canonical value, per the round-19 fix.
      expect(find.text('Leg Press'), findsOneWidget);
      expect(find.text('Leg Press for quads'), findsNothing);
    });
  });
}

/// Drives the simulated "catalogue still loading, then resolves" transition
/// in the cold-start recovery test above — stands in for the real
/// [exerciseTitlesProvider]'s own dependency on a [FutureProvider] that has
/// not necessarily resolved yet when a scan happens.
final _catalogueLoadStub = StateProvider<List<String>>((_) => const []);

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
