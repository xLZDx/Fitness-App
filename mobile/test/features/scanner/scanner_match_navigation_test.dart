import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
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

/// Reported defect (operator, real phone): what the Scan list named and the
/// equipment page that opened did not match. These tests drive the real
/// ScannerPage, the real GoRouter `/equipment/:id` route, the real
/// EquipmentDetailPage and the real (Russian) catalogue asset, with only the
/// recogniser faked, and assert the tapped row's machine is the machine whose
/// page opens -- on the alternatives path, the remembered "My machines" path
/// and across consecutive scans.
class _Picker extends ImagePickerPlatform {
  int calls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls++;
    return XFile('/tmp/picked-$calls.jpg');
  }
}

/// Answers the Nth classification with the Nth scripted list.
class _ScriptedService implements VisualEquipmentService {
  _ScriptedService(this.script);
  final List<List<VisualMatch>> script;
  int calls = 0;

  @override
  Future<List<VisualMatch>> classifyFile(
      {required String path, int topK = 3}) async {
    return script[calls++];
  }
}

const _chest = 'Жим от груди (тренажёр)';
const _pec = 'Бабочка (пек-дек)';
const _legPress = 'Жим ногами';
const _elliptical = 'Эллиптический тренажёр';

/// The Scan page animates forever (viewfinder pulse), so `pumpAndSettle`
/// never settles; a bounded run of frames is enough here. Real asset reads go
/// through `runAsync` so the catalogue JSON actually arrives.
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
  _Harness(this.tester, this.router, this.landed, this.history);
  final WidgetTester tester;
  final GoRouter router;
  final List<String> landed;
  final MockRecognitionHistoryRepository history;

  Future<void> scanViaGallery() async {
    final gallery = find.byKey(const Key('scan-recognise-gallery'));
    await _reveal(tester, gallery);
    await tester.tap(gallery);
    await tester.pump();
    await tester.pump();
    await _settle(tester);
  }

  Future<void> tapAndBack(Finder target, String expectedTitle) async {
    await _reveal(tester, target);
    await tester.tap(target);
    await _settle(tester);
    expect(find.byType(EquipmentDetailPage), findsOneWidget);
    expect(find.text(expectedTitle), findsWidgets,
        reason: 'the opened page must be the tapped machine\'s page');
    router.pop();
    await _settle(tester);
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required List<List<VisualMatch>> script,
  List<String> seededHistory = const [],
}) async {
  final picker = _Picker();
  final previous = ImagePickerPlatform.instance;
  ImagePickerPlatform.instance = picker;
  addTearDown(() => ImagePickerPlatform.instance = previous);

  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final history = MockRecognitionHistoryRepository();
  for (final id in seededHistory) {
    await history.record(RecognitionEntry(
      equipmentId: id,
      recognisedAt: DateTime.utc(2026, 1, 1),
      confidence: 0.5,
      source: RecognitionSource.photo,
    ));
  }

  // Load the real catalogue up front (outside fake async) so row names are the
  // catalogue's own, not the prettified-id fallback shown while it loads.
  final repo = AssetEquipmentRepository(languageCode: 'ru');
  await tester.runAsync(() => repo.listEquipment());

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
      recommendedExercisesProvider.overrideWith(
        (ref, id) async =>
            const RecommendedExercises(items: [], hiddenForInjury: 0),
      ),
      equipmentHeroImageProvider.overrideWith((ref, id) async => null),
      safetyContextProvider.overrideWith(
        (_) async => SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}),
        ),
      ),
      recognitionHistoryRepositoryProvider.overrideWithValue(history),
      visualEquipmentServiceProvider
          .overrideWithValue(_ScriptedService(script)),
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
  return _Harness(tester, router, landed, history);
}

VisualMatch _m(String id, double c) =>
    VisualMatch(equipmentId: id, confidence: c, labelHint: id);

String _path(String uri) => Uri.parse(uri).path;
String? _scanId(String uri) => Uri.parse(uri).queryParameters['scanId'];

void main() {
  testWidgets(
      'alternatives: every tapped row opens exactly that machine\'s page',
      (tester) async {
    final h = await _pump(tester, script: [
      [
        _m('chest_press_machine', 0.85),
        _m('pec_deck', 0.60),
        _m('leg_press', 0.30),
      ],
    ]);
    await h.scanViaGallery();

    // The rows the operator saw, in the catalogue's own Russian names.
    expect(find.text(_chest), findsOneWidget);
    expect(find.text(_pec), findsOneWidget);
    expect(find.text(_legPress), findsOneWidget);

    await h.tapAndBack(find.text(_chest), _chest);
    await h.tapAndBack(find.text(_pec), _pec);
    await h.tapAndBack(find.text(_legPress), _legPress);

    expect(h.landed.map(_path).toList(), [
      '/equipment/chest_press_machine',
      '/equipment/pec_deck',
      '/equipment/leg_press',
    ]);
    // None of them may have opened the elliptical.
    expect(h.landed.any((u) => u.contains('elliptical')), isFalse);
    // All three belong to the one scan on screen.
    expect(h.landed.map(_scanId).toSet().length, 1);
    expect(_scanId(h.landed.first), isNotNull);
  });

  testWidgets(
      'My machines: a remembered chip opens its own page and carries no scanId',
      (tester) async {
    final h = await _pump(
      tester,
      seededHistory: ['elliptical'],
      script: [
        [_m('chest_press_machine', 0.85), _m('pec_deck', 0.60)],
      ],
    );
    await h.scanViaGallery();

    // Tapping an alternative remembers it (existing behaviour) ...
    await h.tapAndBack(find.text(_chest), _chest);
    expect(_scanId(h.landed.last), isNotNull);

    // ... and a chip for a DIFFERENT, older machine must open that machine,
    // not the scan's answer, and must not inherit the scan's identity id.
    await h.tapAndBack(
        find.byKey(const Key('scan-history-elliptical')), _elliptical);
    expect(_path(h.landed.last), '/equipment/elliptical');
    expect(_scanId(h.landed.last), isNull,
        reason: 'scan A\'s scanId leaked into another machine\'s navigation');

    // The chip for the machine just picked is remembered and opens it.
    await h.tapAndBack(
        find.byKey(const Key('scan-history-chest_press_machine')), _chest);
    expect(_path(h.landed.last), '/equipment/chest_press_machine');
    expect(_scanId(h.landed.last), isNull);
  });

  testWidgets('an id from one scan never leaks into the next scan',
      (tester) async {
    final h = await _pump(tester, script: [
      [_m('chest_press_machine', 0.85), _m('pec_deck', 0.60)],
      [_m('leg_press', 0.70), _m('elliptical', 0.20)],
    ]);

    await h.scanViaGallery();
    await h.tapAndBack(find.text(_chest), _chest);
    final firstScanId = _scanId(h.landed.last);
    expect(firstScanId, isNotNull);

    // "Scan again", then a second, different scan.
    await tester.tap(find.byKey(const Key('scan-recognise-camera')));
    await _settle(tester);
    await h.scanViaGallery();

    // First scan's machines are gone from the result list.
    expect(find.text(_pec), findsNothing);

    await h.tapAndBack(find.text(_legPress), _legPress);
    expect(_path(h.landed.last), '/equipment/leg_press');
    expect(_scanId(h.landed.last), isNotNull);
    expect(_scanId(h.landed.last), isNot(firstScanId),
        reason: 'the second scan must mint its own scanId');

    await h.tapAndBack(find.text(_elliptical), _elliptical);
    expect(_path(h.landed.last), '/equipment/elliptical');
    // Nothing from scan one was navigated to again.
    expect(
        h.landed.skip(1).map(_path), isNot(contains('/equipment/pec_deck')));
  });
}
