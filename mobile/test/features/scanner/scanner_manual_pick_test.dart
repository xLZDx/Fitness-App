import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/equipment/equipment_detail_page.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/visual_equipment/data/recognition_history.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/recognition_history_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../../helpers/test_app.dart';

/// Scan confirmation experience (2026-10-14): the cloud names the right machine
/// first only about half the time, so every candidate row carries the machine's
/// picture, and "Not it -- choose manually" opens the whole catalogue. These
/// tests drive the real ScannerPage, the real (Russian) catalogue and the real
/// GoRouter `/equipment/:id` route; only the recogniser and the hero images
/// are faked.
class _Picker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile('/tmp/picked.jpg');
}

class _ScriptedService implements VisualEquipmentService {
  _ScriptedService(this.answer);
  final List<VisualMatch> answer;
  int? lastTopK;

  @override
  Future<List<VisualMatch>> classifyFile(
      {required String path, int topK = 3}) async {
    lastTopK = topK;
    return answer;
  }
}

const _chest = 'Жим от груди (тренажёр)';
const _pec = 'Бабочка (пек-дек)';
const _legPress = 'Жим ногами';
const _elliptical = 'Эллиптический тренажёр';
const _bench = 'Жим лёжа (стойка)';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _reveal(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      120,
      scrollable: find
          .descendant(
              of: find.byType(ScannerPage), matching: find.byType(Scrollable))
          .first,
    );

class _Harness {
  _Harness(this.tester, this.landed, this.history, this.service);
  final WidgetTester tester;
  final List<String> landed;
  final MockRecognitionHistoryRepository history;
  final _ScriptedService service;

  Future<void> scanViaGallery() async {
    final gallery = find.byKey(const Key('scan-recognise-gallery'));
    await _reveal(tester, gallery);
    await tester.tap(gallery);
    await tester.pump();
    await tester.pump();
    await _settle(tester);
  }

  Future<void> openPicker() async {
    final button = find.byKey(const Key('scan-pick-manually'));
    await _reveal(tester, button);
    await tester.tap(button);
    await _settle(tester);
  }

  Future<void> search(String text) async {
    await tester.enterText(find.byKey(const Key('scan-manual-search')), text);
    await _settle(tester);
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required List<VisualMatch> answer,
  Map<String, String> heroes = const {},
}) async {
  final previous = ImagePickerPlatform.instance;
  ImagePickerPlatform.instance = _Picker();
  addTearDown(() => ImagePickerPlatform.instance = previous);

  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final history = MockRecognitionHistoryRepository();
  final repo = AssetEquipmentRepository(languageCode: 'ru');
  await tester.runAsync(() => repo.listEquipment());
  // The alias index is read from the real bundled asset, outside fake async.
  final aliases = await tester.runAsync(EquipmentAliasIndex.load);

  final service = _ScriptedService(answer);
  final landed = <String>[];
  final router = GoRouter(
    initialLocation: '/scan',
    routes: [
      GoRoute(
        path: '/scan',
        builder: (_, __) => const Scaffold(
          backgroundColor: Colors.transparent,
          body: ScannerPage(),
        ),
      ),
      GoRoute(
        path: '/equipment/:id',
        builder: (_, state) {
          landed.add(state.uri.toString());
          return EquipmentDetailPage(
            equipmentId: state.pathParameters['id']!,
            scanId: state.uri.queryParameters['scanId'],
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      equipmentRepositoryProvider.overrideWithValue(repo),
      equipmentAliasIndexProvider.overrideWith((ref) async => aliases!),
      recommendedExercisesProvider.overrideWith(
        (ref, id) async =>
            const RecommendedExercises(items: [], hiddenForInjury: 0),
      ),
      equipmentHeroImageProvider.overrideWith((ref, id) async => heroes[id]),
      safetyContextProvider.overrideWith(
        (_) async => SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}),
        ),
      ),
      recognitionHistoryRepositoryProvider.overrideWithValue(history),
      visualEquipmentServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await _settle(tester);
  return _Harness(tester, landed, history, service);
}

VisualMatch _m(String id, double c) =>
    VisualMatch(equipmentId: id, confidence: c, labelHint: id);

final _four = <VisualMatch>[
  _m('chest_press_machine', 0.62),
  _m('pec_deck', 0.41),
  _m('leg_press', 0.22),
  _m('elliptical', 0.12),
];

void main() {
  testWidgets(
      'candidate rows show the machine picture where one exists, a neutral '
      'tile where not, plus name and confidence; the scan asks for 4',
      (tester) async {
    final h = await _pump(
      tester,
      answer: _four,
      // Only the chest press has a hero image; the asset need not decode --
      // what is asserted is that the row asks for the picture.
      heroes: {'chest_press_machine': 'assets/posters/men/ea_180_jump_turns.jpg'},
    );
    await h.scanViaGallery();

    expect(h.service.lastTopK, 4, reason: 'best + 3 alternatives');
    for (final name in [_chest, _pec, _legPress, _elliptical]) {
      expect(find.text(name), findsOneWidget);
    }
    // Every row has a thumbnail tile ...
    for (final id in ['chest_press_machine', 'pec_deck', 'leg_press', 'elliptical']) {
      expect(find.byKey(Key('machine-thumb-$id')), findsOneWidget,
          reason: 'row for $id lost its thumbnail');
    }
    // ... a real picture only where the hero image exists ...
    expect(find.byKey(const Key('machine-thumb-image-chest_press_machine')),
        findsOneWidget);
    expect(find.byKey(const Key('machine-thumb-image-pec_deck')), findsNothing,
        reason: 'a machine without a hero must show the neutral icon tile');
    expect(
        find.descendant(
            of: find.byKey(const Key('machine-thumb-pec_deck')),
            matching: find.byIcon(Icons.fitness_center_rounded)),
        findsOneWidget);
    // ... and the confidence of each candidate.
    expect(find.text('62% confidence'), findsOneWidget);
    expect(find.text('12% confidence'), findsOneWidget);
  });

  testWidgets('with 4 candidates the model order is preserved top to bottom',
      (tester) async {
    final h = await _pump(tester, answer: _four);
    await h.scanViaGallery();
    await _reveal(tester, find.byKey(const Key('scan-pick-manually')));

    final ys = [_chest, _pec, _legPress, _elliptical]
        .map((n) => tester.getTopLeft(find.text(n)).dy)
        .toList();
    expect(ys, orderedEquals([...ys]..sort()),
        reason: 'rows must follow the confidence order given by the model');
    expect(ys.toSet().length, 4);
    // The manual exit is the LAST row, below every candidate.
    expect(tester.getTopLeft(find.byKey(const Key('scan-pick-manually'))).dy,
        greaterThan(ys.last));
  });

  testWidgets(
      'manual picker: typing "жим" finds the bench press, tapping it opens '
      '/equipment/bench_press without this scan\'s id and remembers it as a '
      'manual pick with confidence 1.0', (tester) async {
    final h = await _pump(tester, answer: _four);
    await h.scanViaGallery();
    expect(await h.history.list(), isEmpty,
        reason: 'nothing may be filed before the user picks');

    await h.openPicker();
    final picker = find.byKey(const Key('scan-manual-picker'));
    expect(picker, findsOneWidget);
    // The whole catalogue is offered, not only the scan's candidates.
    expect(find.byKey(const Key('scan-manual-pick-bench_press')),
        findsOneWidget);

    await h.search('жим');
    final benchRow = find.descendant(
        of: picker, matching: find.byKey(const Key('scan-manual-pick-bench_press')));
    expect(benchRow, findsOneWidget);
    expect(find.descendant(of: picker, matching: find.text(_bench)),
        findsOneWidget);
    // A name that does not contain "жим" is filtered out.
    expect(find.descendant(of: picker, matching: find.text(_elliptical)),
        findsNothing);

    await tester.tap(benchRow);
    await _settle(tester);

    expect(find.byType(EquipmentDetailPage), findsOneWidget);
    expect(h.landed.single, '/equipment/bench_press',
        reason: 'no scanId: the scan described a different machine');

    final remembered = await h.history.list();
    expect(remembered.single.equipmentId, 'bench_press');
    expect(remembered.single.source, RecognitionSource.manual);
    expect(remembered.single.confidence, 1.0);
  });

  testWidgets('manual picker: searches aliases, not just the display name',
      (tester) async {
    final h = await _pump(tester, answer: _four);
    await h.scanViaGallery();
    await h.openPicker();
    final picker = find.byKey(const Key('scan-manual-picker'));

    // "station" is in an English alias ("bench press station") and in no
    // Russian display name of the bench.
    await h.search('station');
    expect(find.descendant(of: picker, matching: find.text(_bench)),
        findsOneWidget);

    // Nothing matches: an explicit empty state, never a blank list.
    await h.search('qqqqzzzz');
    expect(find.byKey(const Key('scan-manual-empty')), findsOneWidget);
    expect(find.byKey(const Key('scan-manual-pick-bench_press')), findsNothing);
  });

  testWidgets('closing the picker without a choice files and opens nothing',
      (tester) async {
    final h = await _pump(tester, answer: _four);
    await h.scanViaGallery();
    await h.openPicker();
    expect(find.byKey(const Key('scan-manual-picker')), findsOneWidget);

    // Dismiss through the barrier.
    await tester.tapAt(const Offset(400, 20));
    await _settle(tester);

    expect(find.byKey(const Key('scan-manual-picker')), findsNothing);
    expect(h.landed, isEmpty);
    expect(await h.history.list(), isEmpty);
  });
}
