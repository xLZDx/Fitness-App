import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../helpers/test_app.dart';
import '../support/golden_fonts.dart';
import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/core/theme/hud_tokens.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/scanner/state/scan_preview_provider.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';

/// SCAN-G1, R6(c)/(d) (core/SCAN_G1_SCOPE.md): the Scan screen's pixels.
///
/// Two families of golden, both states (aiming / found), both themes:
///
///  * `composed_scan_fidelity_*` -- the page at the reference's own frame
///    (390x844 @2x, 46px status inset, reduce motion so the sweep is parked
///    at t=0, a transparent camera) over the flat base colour
///    (`HudTokens.<theme>.base`: `#14182C` / `#EEF0F6`, the phone's own
///    background in the reference with its sky import hidden). These are the
///    INPUT to `tools/design/scan_fidelity_check.py`, which diffs them
///    against `test/golden/reference/scan_*_flat.png` -- the reference
///    rendered identically by `tools/design/render_reference_scan.js`.
///    Their job is to exist and be current; the judgement is the script's.
///  * `composed_scan_*` -- the same page over the app's composed sky
///    (`AuroraBackground`, the same backdrop the other composed goldens
///    use), as ordinary regression pins for the screen as shipped.
///
/// Fixture: the reference's own "Lat pulldown / 92 / Strength · Lats,
/// Biceps" (`Sunset.dc.html:206-211`). Goldens are recorded in the project's
/// Linux container (`ghcr.io/cirruslabs/flutter:3.27.1`), never on Windows,
/// so the font rasteriser is the one CI sees.
class _StillSession extends CameraSession {
  @override
  Future<void> start({bool requestPermission = false}) async {}

  @override
  Future<void> stop() async {}
}

class _FakeImagePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile('/tmp/lat_pulldown.jpg');
}

AssetEquipmentRepository _seededRepo() => AssetEquipmentRepository()
  ..seedForTests(
    equipment: const [
      EquipmentItem(
        id: 'lat_pulldown',
        name: 'Lat pulldown',
        manufacturer: 'Any',
        category: 'strength',
        description: '',
      ),
    ],
    exercises: const [
      ExerciseItem(
        id: 'lat_pulldown_wide',
        title: 'Wide-grip pulldown',
        equipmentId: 'lat_pulldown',
        muscles: ['lats', 'biceps'],
        primaryMuscles: ['lats', 'biceps'],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 10,
        summary: 'Pull',
        steps: ['Pull'],
      ),
      ExerciseItem(
        id: 'lat_pulldown_close',
        title: 'Close-grip pulldown',
        equipmentId: 'lat_pulldown',
        muscles: ['lats'],
        primaryMuscles: ['lats'],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 10,
        summary: 'Pull',
        steps: ['Pull'],
      ),
    ],
  );

const Key _rootKey = Key('scan-golden-root');

void main() {
  setUpAll(loadHudGoldenFonts);

  Widget build({required Brightness brightness, required bool flat}) {
    final HudTokens t =
        brightness == Brightness.dark ? HudTokens.dark : HudTokens.light;
    final router = GoRouter(
      initialLocation: '/scan',
      routes: [
        GoRoute(path: '/scan', builder: (_, __) => const ScannerPage()),
        GoRoute(
          path: '/equipment/:id',
          builder: (_, s) =>
              Scaffold(body: Text('equipment ${s.pathParameters['id']}')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        scanCameraSessionProvider.overrideWithValue(_StillSession()),
        scanPreviewBuilderProvider
            .overrideWithValue((_) => const SizedBox.shrink()),
        equipmentRepositoryProvider.overrideWithValue(_seededRepo()),
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'lat_pulldown', confidence: 0.92),
          ]),
        ),
        safetyContextProvider.overrideWith((_) async => SafetyContext(
            screening:
                screen({for (final q in ParQQuestion.values) q: false}))),
      ],
      child: MaterialApp.router(
        theme:
            brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) {
          final Widget page = MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child ?? const SizedBox.shrink(),
          );
          // Frost off for the fidelity frames: `flutter test` rasterises a
          // `BackdropFilter` against an empty backdrop (see `HudQuality`),
          // which painted a grey slab where each glass surface's child sits
          // -- the blur of nothing, not of the base colour. The reference's
          // own `backdrop-filter: blur()` over a flat colour is the identity
          // (a blurred flat colour is that colour), so nothing real is lost;
          // its `saturate(150%)` tints the flat base by a few units, which
          // the thresholds absorb. The composed frames keep the frost, like
          // every other composed golden.
          return KeyedSubtree(
            key: _rootKey,
            child: HudQuality(
              frostedGlass: !flat,
              child: flat
                  ? ColoredBox(color: t.base, child: page)
                  : AuroraBackground(child: page),
            ),
          );
        },
      ),
    );
  }

  Future<void> pumpScan(WidgetTester tester,
      {required Brightness brightness, required bool flat}) async {
    pinGoldenSurface(tester,
        size: const Size(390, 844), devicePixelRatio: 2);
    tester.view.padding = const FakeViewPadding(top: 92);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(build(brightness: brightness, flat: flat));
    // Explicit pumps rather than pumpAndSettle: the page's own animations
    // are parked by reduce motion, and nothing else here loops.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Runs [body] with real shadows. `flutter test` sets
  /// `debugDisableShadows`, which strips the blur off every `BoxShadow`: a
  /// `0 0 26px -6px` glow then becomes a sharp rectangle 6px INSIDE the
  /// panel, i.e. nothing, and the reference's halos would count as missing
  /// in the fidelity diff. The binding checks the flag is back to `true` as
  /// soon as the test body returns -- before `addTearDown` callbacks -- so
  /// it is restored in a `finally` here, not in a tear-down.
  Future<void> withRealShadows(Future<void> Function() body) async {
    debugDisableShadows = false;
    try {
      await body();
    } finally {
      debugDisableShadows = true;
    }
  }

  Future<void> lockMatch(WidgetTester tester) async {
    final previous = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _FakeImagePicker();
    addTearDown(() => ImagePickerPlatform.instance = previous);
    await tester.tap(find.byKey(const Key('scan-recognise-gallery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('MACHINE LOCKED'), findsOneWidget);
    expect(find.text('Strength · Lats, Biceps'), findsOneWidget);
  }

  for (final (String theme, Brightness brightness) in <(String, Brightness)>[
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    group('fidelity ($theme, flat base)', () {
      testWidgets('aiming', (tester) => withRealShadows(() async {
            await pumpScan(tester, brightness: brightness, flat: true);
            expect(find.text('ALIGN THE MACHINE IN FRAME'), findsOneWidget);
            await expectLater(
              find.byKey(_rootKey),
              matchesGoldenFile(
                  'goldens/composed_scan_fidelity_aiming_$theme.png'),
            );
          }));

      testWidgets('found', (tester) => withRealShadows(() async {
            await pumpScan(tester, brightness: brightness, flat: true);
            await lockMatch(tester);
            await expectLater(
              find.byKey(_rootKey),
              matchesGoldenFile(
                  'goldens/composed_scan_fidelity_found_$theme.png'),
            );
          }));
    });

    group('composed ($theme, sky)', () {
      testWidgets('aiming', (tester) => withRealShadows(() async {
            await pumpScan(tester, brightness: brightness, flat: false);
            await expectLater(
              find.byKey(_rootKey),
              matchesGoldenFile('goldens/composed_scan_aiming_$theme.png'),
            );
          }));

      testWidgets('found', (tester) => withRealShadows(() async {
            await pumpScan(tester, brightness: brightness, flat: false);
            await lockMatch(tester);
            await expectLater(
              find.byKey(_rootKey),
              matchesGoldenFile('goldens/composed_scan_found_$theme.png'),
            );
          }));
    });
  }
}
