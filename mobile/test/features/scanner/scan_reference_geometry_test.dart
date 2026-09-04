import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../../helpers/test_app.dart';
import '../../support/golden_fonts.dart';
import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/scanner/state/scan_preview_provider.dart';
import 'package:fitness_app/features/scanner/widgets/scan_frame.dart';
import 'package:fitness_app/features/scanner/widgets/scan_glyph.dart';
import 'package:fitness_app/features/scanner/widgets/scan_match_card.dart';
import 'package:fitness_app/features/scanner/widgets/scan_viewfinder.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';

/// SCAN-G1, R6(b) (core/SCAN_G1_SCOPE.md): every element of the Scan screen
/// sits where the reference's DOM puts it, and is set the way the reference
/// sets it.
///
/// The expected numbers are NOT typed into this file. They are read from
/// `test/golden/reference/scan_anchors.json`, which
/// `tools/design/render_reference_scan.js` extracts from the reference HTML
/// with a real browser (`getBoundingClientRect` + `getComputedStyle`) --
/// so a re-render of a changed reference moves the expectations, and no
/// number here can be "adjusted to pass". Tolerances: 2px for containers,
/// 3px for text (two text engines, one font); identity facts (family,
/// size, weight, tracking, glyph codepoint, colour alpha) are exact.
///
/// Pumped at the reference's own frame: 390x844 logical with a 46px status
/// inset (`inset:46px 0 158px` on the screen, line 181), so the y values
/// compare directly.
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

/// The reference's own fixture: "Lat pulldown / 92 / Strength · Lats,
/// Biceps" (`Sunset.dc.html:206-211`). Two exercises so `lats` outvotes
/// `biceps` and the line reads in the reference's order.
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

Map<String, dynamic> _anchors(String key) {
  final Map<String, dynamic> all = json.decode(
    File('test/golden/reference/scan_anchors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return all[key] as Map<String, dynamic>;
}

Rect _rectOf(Map<String, dynamic> anchors, String name) {
  final Map<String, dynamic> r =
      (anchors[name] as Map<String, dynamic>)['rect'] as Map<String, dynamic>;
  return Rect.fromLTWH(
    (r['x'] as num).toDouble(),
    (r['y'] as num).toDouble(),
    (r['w'] as num).toDouble(),
    (r['h'] as num).toDouble(),
  );
}

Map<String, dynamic> _styleOf(Map<String, dynamic> anchors, String name) =>
    (anchors[name] as Map<String, dynamic>)['style'] as Map<String, dynamic>;

double _px(String css) => double.parse(css.replaceAll('px', ''));

/// `rgba(255, 255, 255, 0.8)` / `rgb(255, 255, 255)` -> Color.
Color _cssColor(String css) {
  final List<String> parts = css
      .replaceAll(RegExp(r'^rgba?\('), '')
      .replaceAll(')', '')
      .split(',')
      .map((s) => s.trim())
      .toList();
  final double a = parts.length > 3 ? double.parse(parts[3]) : 1.0;
  return Color.fromRGBO(
      int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]), a);
}

void _expectRect(Rect actual, Rect expected, double tol, String what,
    {bool width = true, bool height = true}) {
  expect(actual.left, closeTo(expected.left, tol), reason: '$what left');
  expect(actual.top, closeTo(expected.top, tol), reason: '$what top');
  if (width) {
    // A text run's advance differs between the two shapers by up to ~3.5%
    // (measured: "Open exercises" at 700 13.5px is 99.84px in Chrome and
    // 103.35px in Skia -- kerning/hinting, not layout). Widths therefore
    // get one extra pixel over the position tolerance; positions do not.
    expect(actual.width, closeTo(expected.width, tol + 1),
        reason: '$what width');
  }
  if (height) {
    expect(actual.height, closeTo(expected.height, tol),
        reason: '$what height');
  }
}

void _expectColor(Color actual, Color expected, String what) {
  expect(actual.withValues(alpha: 1), expected.withValues(alpha: 1),
      reason: '$what rgb');
  expect(actual.a, closeTo(expected.a, 1.5 / 255), reason: '$what alpha');
}

FontVariation? _axis(TextStyle s, String tag) =>
    s.fontVariations?.where((v) => v.axis == tag).firstOrNull;

void main() {
  setUpAll(loadHudGoldenFonts);

  Future<ProviderContainer> pumpScan(
    WidgetTester tester, {
    required Brightness brightness,
  }) async {
    pinGoldenSurface(tester,
        size: const Size(390, 844), devicePixelRatio: 2);
    // 46 logical px of status bar, in physical px.
    tester.view.padding = const FakeViewPadding(top: 92);
    addTearDown(tester.view.resetPadding);

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
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
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
      ],
      child: MaterialApp.router(
        theme:
            brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          // Reduce motion: the sweep parks at t=0 (the reference's paused
          // state) and nothing on the page keeps animating.
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(ScannerPage)));
  }

  /// Through the page's own `_classify` (the gallery path), so `_attempted`
  /// flips and the button reads "Scan again" -- the reference's found state.
  Future<void> lockMatch(WidgetTester tester) async {
    final previous = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _FakeImagePicker();
    addTearDown(() => ImagePickerPlatform.instance = previous);
    await tester.tap(find.byKey(const Key('scan-recognise-gallery')));
    await tester.pump();
    await tester.pump();
    // The catalogue-derived subtitle resolves asynchronously.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
  }

  Text textOf(WidgetTester tester, Finder f) => tester.widget<Text>(f);

  group('aiming, dark', () {
    late Map<String, dynamic> a;
    setUpAll(() => a = _anchors('dark_aiming'));

    testWidgets('containers sit on the reference anchors (±2px)',
        (tester) async {
      await pumpScan(tester, brightness: Brightness.dark);

      _expectRect(tester.getRect(find.byType(ScanViewfinder)), _rectOf(a, 'card'),
          2, 'card');
      _expectRect(tester.getRect(find.byKey(const Key('scan-centre-glyph'))),
          _rectOf(a, 'centre_glyph'), 2, 'centre glyph');
      _expectRect(tester.getRect(find.byKey(const Key('scan-recognise-camera'))),
          _rectOf(a, 'primary_button'), 2, 'primary button');
      final Finder glyph = find.descendant(
          of: find.byKey(const Key('scan-recognise-camera')),
          matching: find.byType(ScanGlyph));
      _expectRect(tester.getRect(glyph), _rectOf(a, 'primary_glyph'), 2,
          'primary glyph');
      // The brackets are painted, not laid out: the card's box plus
      // ScanFrame's constants IS their position.
      final Rect card = tester.getRect(find.byType(ScanViewfinder));
      final Rect tl = _rectOf(a, 'bracket_tl');
      final Rect br = _rectOf(a, 'bracket_br');
      expect(card.left + ScanFrame.inset, closeTo(tl.left, 2));
      expect(card.top + ScanFrame.inset, closeTo(tl.top, 2));
      expect(tl.width, ScanFrame.arm);
      expect(card.right - ScanFrame.inset, closeTo(br.right, 2));
      expect(card.bottom - ScanFrame.inset, closeTo(br.bottom, 2));
      final Rect sweep = _rectOf(a, 'sweep');
      expect(card.top + ScanFrame.sweepTop, closeTo(sweep.top, 2));
      expect(card.left + ScanFrame.inset, closeTo(sweep.left, 2));
      expect(card.right - ScanFrame.inset, closeTo(sweep.right, 2));
    });

    testWidgets('text sits on the reference anchors (±3px)', (tester) async {
      await pumpScan(tester, brightness: Brightness.dark);

      _expectRect(tester.getRect(find.text('Scan')), _rectOf(a, 'title'), 3,
          'title',
          width: false);
      _expectRect(
          tester.getRect(find.text('Point the camera at one machine and tap Recognise.')),
          _rectOf(a, 'subtitle'),
          3,
          'subtitle',
          width: false);
      _expectRect(tester.getRect(find.byKey(const Key('scan-hint'))),
          _rectOf(a, 'hint'), 3, 'hint');
      _expectRect(tester.getRect(find.text('Recognise')),
          _rectOf(a, 'primary_label'), 3, 'primary label');
    });

    testWidgets('and is set exactly as the reference sets it', (tester) async {
      await pumpScan(tester, brightness: Brightness.dark);

      final Text title = textOf(tester, find.text('Scan'));
      expect(title.style!.fontFamily, 'Archivo');
      expect(title.style!.fontSize, _px(_styleOf(a, 'title')['fontSize']));
      expect(title.style!.fontWeight, FontWeight.w800);
      final Text subtitle = textOf(tester,
          find.text('Point the camera at one machine and tap Recognise.'));
      expect(subtitle.style!.fontSize, 12.5);
      expect(subtitle.style!.fontWeight, FontWeight.w400);
      _expectColor(subtitle.style!.color!,
          _cssColor(_styleOf(a, 'subtitle')['color']), 'subtitle');

      final Text glyph = textOf(
          tester,
          find.descendant(
              of: find.byKey(const Key('scan-centre-glyph')),
              matching: find.byType(Text)));
      expect(glyph.data, String.fromCharCode(0xE3B5),
          reason: 'center_focus_weak, e3b5');
      expect(glyph.style!.fontFamily, 'Material Symbols Sharp');
      expect(glyph.style!.fontSize, 36);
      expect(_axis(glyph.style!, 'wght')?.value, 300);
      expect(_axis(glyph.style!, 'FILL')?.value, 0);
      expect(_axis(glyph.style!, 'GRAD')?.value, 0);
      _expectColor(glyph.style!.color!,
          _cssColor(_styleOf(a, 'centre_glyph')['color']), 'centre glyph');

      final Text hint = textOf(tester, find.byKey(const Key('scan-hint')));
      final Map<String, dynamic> hs = _styleOf(a, 'hint');
      expect(hint.data, 'ALIGN THE MACHINE IN FRAME');
      expect(hint.data, hint.data!.toUpperCase());
      expect(hint.style!.fontFamily, 'Roboto Mono');
      expect(hint.style!.fontSize, _px(hs['fontSize']));
      expect(hint.style!.fontWeight, FontWeight.w600);
      expect(hint.style!.letterSpacing, closeTo(_px(hs['letterSpacing']), 0.01),
          reason: '.14em at 10px = 1.4px');
      _expectColor(hint.style!.color!, _cssColor(hs['color']), 'hint');

      final Text label = textOf(tester, find.text('Recognise'));
      expect(label.style!.fontFamily, 'Archivo');
      expect(label.style!.fontSize, 14);
      expect(label.style!.fontWeight, FontWeight.w700);
      final Text bglyph = textOf(
          tester,
          find.descendant(
              of: find.descendant(
                  of: find.byKey(const Key('scan-recognise-camera')),
                  matching: find.byType(ScanGlyph)),
              matching: find.byType(Text)));
      expect(bglyph.data, String.fromCharCode(0xE3B4),
          reason: 'center_focus_strong, e3b4');
      expect(bglyph.style!.fontSize, 20);

      final ScanFrame frame = tester.widget<ScanFrame>(find.byType(ScanFrame));
      expect(frame.bracket, const Color(0xE6FFFFFF),
          reason: 'rgba(255,255,255,.9), line 187');
      final HudButton primary = tester.widget<HudButton>(
          find.byKey(const Key('scan-recognise-camera')));
      expect(primary.radius, 24);
      expect(primary.padding, const EdgeInsets.all(16));
    });
  });

  group('found, dark', () {
    late Map<String, dynamic> a;
    setUpAll(() => a = _anchors('dark_found'));

    testWidgets('containers sit on the reference anchors (±2px)',
        (tester) async {
      await pumpScan(tester, brightness: Brightness.dark);
      await lockMatch(tester);

      expect(find.text('MACHINE LOCKED'), findsOneWidget);
      _expectRect(tester.getRect(find.byType(ScanViewfinder)), _rectOf(a, 'card'),
          2, 'card');
      _expectRect(tester.getRect(find.byType(ScanMatchCard)),
          _rectOf(a, 'match_card'), 2, 'match card');
      _expectRect(tester.getRect(find.byKey(const Key('scan-match-ring'))),
          _rectOf(a, 'ring'), 2, 'ring');
      _expectRect(tester.getRect(find.byKey(const Key('scan-open-exercises'))),
          _rectOf(a, 'cta'), 2, 'cta');
      _expectRect(
          tester.getRect(find.descendant(
              of: find.byKey(const Key('scan-open-exercises')),
              matching: find.byType(ScanGlyph))),
          _rectOf(a, 'cta_arrow'),
          2,
          'cta arrow');
      _expectRect(tester.getRect(find.byKey(const Key('scan-recognise-camera'))),
          _rectOf(a, 'primary_button'), 2, 'primary button');
      _expectRect(
          tester.getRect(find.descendant(
              of: find.byKey(const Key('scan-recognise-camera')),
              matching: find.byType(ScanGlyph))),
          _rectOf(a, 'primary_glyph'),
          2,
          'primary glyph');
    });

    testWidgets('text sits on the reference anchors (±3px)', (tester) async {
      await pumpScan(tester, brightness: Brightness.dark);
      await lockMatch(tester);

      _expectRect(tester.getRect(find.byKey(const Key('scan-hint'))),
          _rectOf(a, 'hint'), 3, 'hint');
      // The column's text blocks span the column in the DOM; here a Text
      // is as wide as its glyphs, so left/top/height are what compare.
      _expectRect(tester.getRect(find.byKey(const Key('scan-match-eyebrow'))),
          _rectOf(a, 'eyebrow'), 3, 'eyebrow',
          width: false);
      _expectRect(tester.getRect(find.byKey(const Key('scan-match-name'))),
          _rectOf(a, 'name'), 3, 'name',
          width: false);
      _expectRect(tester.getRect(find.byKey(const Key('scan-match-category'))),
          _rectOf(a, 'category'), 3, 'category',
          width: false);
      _expectRect(tester.getRect(find.text('Open exercises')),
          _rectOf(a, 'cta_label'), 3, 'cta label');
      _expectRect(tester.getRect(find.text('Scan again')),
          _rectOf(a, 'primary_label'), 3, 'primary label');
      // The value is centred in the 78px ring box.
      final Rect value = tester.getRect(find.byKey(const Key('scan-match-value')));
      final Rect ring = _rectOf(a, 'ring_value');
      expect(value.center.dx, closeTo(ring.center.dx, 2));
      expect(value.center.dy, closeTo(ring.center.dy, 2));
    });

    testWidgets('and is set exactly as the reference sets it', (tester) async {
      await pumpScan(tester, brightness: Brightness.dark);
      await lockMatch(tester);

      // By key: the remembered scan also puts the name on a history chip.
      expect(textOf(tester, find.byKey(const Key('scan-match-name'))).data,
          'Lat pulldown');
      expect(textOf(tester, find.byKey(const Key('scan-match-value'))).data,
          '92');
      expect(
          textOf(tester, find.byKey(const Key('scan-match-category'))).data,
          'Strength · Lats, Biceps',
          reason: 'category, then the muscles the exercises are for');

      final Text eyebrow =
          textOf(tester, find.byKey(const Key('scan-match-eyebrow')));
      final Map<String, dynamic> es = _styleOf(a, 'eyebrow');
      expect(eyebrow.data, eyebrow.data!.toUpperCase());
      expect(eyebrow.style!.fontSize, _px(es['fontSize']));
      expect(eyebrow.style!.fontWeight, FontWeight.w600);
      expect(eyebrow.style!.letterSpacing, closeTo(_px(es['letterSpacing']), 0.01),
          reason: '.16em at 9px = 1.44px');
      _expectColor(eyebrow.style!.color!, _cssColor(es['color']), 'eyebrow');

      final Text name = textOf(tester, find.byKey(const Key('scan-match-name')));
      expect(name.style!.fontSize, 19);
      expect(name.style!.fontWeight, FontWeight.w800);
      expect(name.style!.height, closeTo(1.15, 1e-9));

      final Text category =
          textOf(tester, find.byKey(const Key('scan-match-category')));
      expect(category.style!.fontSize, 11.5);
      expect(category.style!.fontWeight, FontWeight.w400);
      _expectColor(category.style!.color!,
          _cssColor(_styleOf(a, 'category')['color']), 'category');

      final Text value = textOf(tester, find.byKey(const Key('scan-match-value')));
      expect(value.style!.fontSize, 20);
      expect(value.style!.fontWeight, FontWeight.w400);

      final Text cta = textOf(tester, find.text('Open exercises'));
      expect(cta.style!.fontSize, 13.5);
      expect(cta.style!.fontWeight, FontWeight.w700);
      final Text arrow = textOf(
          tester,
          find.descendant(
              of: find.descendant(
                  of: find.byKey(const Key('scan-open-exercises')),
                  matching: find.byType(ScanGlyph)),
              matching: find.byType(Text)));
      expect(arrow.data, String.fromCharCode(0xE5C8), reason: 'arrow_forward');
      expect(arrow.style!.fontSize, 19);

      final Text hint = textOf(tester, find.byKey(const Key('scan-hint')));
      expect(hint.data, 'MACHINE LOCKED');
      final Text again = textOf(tester, find.text('Scan again'));
      expect(again.style!.fontSize, 14);
      expect(again.style!.fontWeight, FontWeight.w700);
      final Text rglyph = textOf(
          tester,
          find.descendant(
              of: find.descendant(
                  of: find.byKey(const Key('scan-recognise-camera')),
                  matching: find.byType(ScanGlyph)),
              matching: find.byType(Text)));
      expect(rglyph.data, String.fromCharCode(0xE5D5), reason: 'refresh');

      final HudButton ctaButton =
          tester.widget<HudButton>(find.byKey(const Key('scan-open-exercises')));
      expect(ctaButton.radius, 22);
      expect(ctaButton.padding, const EdgeInsets.fromLTRB(16, 14, 16, 14));
    });
  });

  group('light', () {
    testWidgets('the same geometry, the light inks', (tester) async {
      final Map<String, dynamic> a = _anchors('light_found');
      await pumpScan(tester, brightness: Brightness.light);
      await lockMatch(tester);

      _expectRect(tester.getRect(find.byType(ScanViewfinder)), _rectOf(a, 'card'),
          2, 'card');
      _expectRect(tester.getRect(find.byType(ScanMatchCard)),
          _rectOf(a, 'match_card'), 2, 'match card');
      _expectRect(tester.getRect(find.byKey(const Key('scan-recognise-camera'))),
          _rectOf(a, 'primary_button'), 2, 'primary button');

      final ScanFrame frame = tester.widget<ScanFrame>(find.byType(ScanFrame));
      expect(frame.bracket, const Color(0x6B1B2030),
          reason: 'rgba(27,32,48,.42), Light.dc.html:187');
      final Text glyph = textOf(
          tester,
          find.descendant(
              of: find.byKey(const Key('scan-centre-glyph')),
              matching: find.byType(Text)));
      _expectColor(glyph.style!.color!,
          _cssColor(_styleOf(a, 'centre_glyph')['color']), 'centre glyph');
      final Text hint = textOf(tester, find.byKey(const Key('scan-hint')));
      _expectColor(hint.style!.color!, _cssColor(_styleOf(a, 'hint')['color']),
          'hint');
      final Text eyebrow =
          textOf(tester, find.byKey(const Key('scan-match-eyebrow')));
      _expectColor(eyebrow.style!.color!,
          _cssColor(_styleOf(a, 'eyebrow')['color']), 'eyebrow');
      final Text category =
          textOf(tester, find.byKey(const Key('scan-match-category')));
      _expectColor(category.style!.color!,
          _cssColor(_styleOf(a, 'category')['color']), 'category');
      final Text cta = textOf(tester, find.text('Open exercises'));
      _expectColor(cta.style!.color!, _cssColor(_styleOf(a, 'cta_label')['color']),
          'cta label');
    });
  });
}
