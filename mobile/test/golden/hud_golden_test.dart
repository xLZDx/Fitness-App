import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/hud/hud_metric.dart';
import 'package:fitness_app/shared/widgets/hud/hud_scaffold.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';

import '../support/golden_fonts.dart';

/// M8 -- deterministic golden-image coverage for the HUD primitives.
///
/// Scope, deliberately narrow: the small set of low-churn surfaces every HUD
/// screen is built from ([HudPanel], [HudButton], [HudChip], [HudToggle],
/// [HudNavBar]), in both themes. These are the pieces `hud_tokens.dart` and
/// `hud_typography.dart` feed directly, so a token or type-scale regression
/// that breaks pixels shows up here first -- and cheaply, since these widgets
/// change far less often than a full screen composition does. See
/// `test/golden/README.md` for how to run and regenerate these, and for the
/// font-determinism and exact-pixel-comparison decisions this file relies on.
///
/// Deliberately NOT covered here: a full-screen composition (e.g. `HomePage`)
/// -- mid-churn product surface, not a stable primitive, exactly what M8 asks
/// this first slice to avoid. That follow-up now exists as its own file,
/// `composed_screen_golden_test.dart` (see `test/golden/README.md`'s
/// "Composed screens" section) -- Home and Workouts' Programs tab, plus the
/// Scan flow's aiming/found/fidelity states.
void main() {
  setUpAll(loadHudGoldenFonts);

  Future<void> pumpGolden(
    WidgetTester tester,
    Widget child, {
    required Brightness brightness,
    Key? boundaryKey,
  }) async {
    pinGoldenSurface(tester, size: const Size(440, 320));
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(key: boundaryKey, child: child),
          ),
        ),
      ),
    );
    // The frost (`BackdropFilter`) and press/selection animations are all
    // driven by `AnimationController`s that start on the first frame; settle
    // them before capturing so the golden is the resting state, not whichever
    // partial frame the single `pumpWidget` happened to land on.
    await tester.pumpAndSettle();
  }

  group('HudPanel', () {
    const Key key = Key('golden-hud-panel');

    testWidgets('dark', (tester) async {
      await pumpGolden(
        tester,
        const SizedBox(
          width: 260,
          height: 140,
          child: HudPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('Today'),
                Text('Push day -- 6 exercises'),
              ],
            ),
          ),
        ),
        brightness: Brightness.dark,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_panel_dark.png'),
      );
    });

    testWidgets('light', (tester) async {
      await pumpGolden(
        tester,
        const SizedBox(
          width: 260,
          height: 140,
          child: HudPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('Today'),
                Text('Push day -- 6 exercises'),
              ],
            ),
          ),
        ),
        brightness: Brightness.light,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_panel_light.png'),
      );
    });
  });

  group('HudButton', () {
    const Key key = Key('golden-hud-button');

    testWidgets('glass tone, dark', (tester) async {
      await pumpGolden(
        tester,
        SizedBox(
          width: 260,
          child: HudButton(label: 'Log set', onPressed: () {}),
        ),
        brightness: Brightness.dark,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_button_glass_dark.png'),
      );
    });

    testWidgets('accent tone, dark', (tester) async {
      await pumpGolden(
        tester,
        SizedBox(
          width: 260,
          child: HudButton(
            label: 'Start workout',
            tone: HudButtonTone.accent,
            onPressed: () {},
          ),
        ),
        brightness: Brightness.dark,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_button_accent_dark.png'),
      );
    });

    testWidgets('glass tone, light', (tester) async {
      await pumpGolden(
        tester,
        SizedBox(
          width: 260,
          child: HudButton(label: 'Log set', onPressed: () {}),
        ),
        brightness: Brightness.light,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_button_glass_light.png'),
      );
    });
  });

  group('HudChip', () {
    const Key key = Key('golden-hud-chip');

    testWidgets('unselected, dark', (tester) async {
      await pumpGolden(
        tester,
        const HudChip(label: 'Strength', selected: false),
        brightness: Brightness.dark,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_chip_unselected_dark.png'),
      );
    });

    testWidgets('selected, dark', (tester) async {
      await pumpGolden(
        tester,
        const HudChip(label: 'Strength', selected: true),
        brightness: Brightness.dark,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_chip_selected_dark.png'),
      );
    });

    testWidgets('selected, light', (tester) async {
      await pumpGolden(
        tester,
        const HudChip(label: 'Strength', selected: true),
        brightness: Brightness.light,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_chip_selected_light.png'),
      );
    });
  });

  group('HudToggle', () {
    const Key key = Key('golden-hud-toggle');

    testWidgets('off, dark', (tester) async {
      await pumpGolden(
        tester,
        HudToggle(value: false, onChanged: (_) {}),
        brightness: Brightness.dark,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_toggle_off_dark.png'),
      );
    });

    testWidgets('on, dark', (tester) async {
      await pumpGolden(
        tester,
        HudToggle(value: true, onChanged: (_) {}),
        brightness: Brightness.dark,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_toggle_on_dark.png'),
      );
    });

    testWidgets('on, light', (tester) async {
      await pumpGolden(
        tester,
        HudToggle(value: true, onChanged: (_) {}),
        brightness: Brightness.light,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_toggle_on_light.png'),
      );
    });
  });

  group('HudNavBar', () {
    const Key key = Key('golden-hud-nav-bar');
    List<HudNavItem> items() => const <HudNavItem>[
          HudNavItem(icon: Icons.grid_view, label: 'Home'),
          HudNavItem(icon: Icons.fitness_center, label: 'Workouts'),
          HudNavItem(icon: Icons.radio_button_checked, label: 'Scan'),
          HudNavItem(icon: Icons.north_east, label: 'Progress'),
          HudNavItem(icon: Icons.person, label: 'Profile'),
        ];

    testWidgets('dark', (tester) async {
      await pumpGolden(
        tester,
        SizedBox(
          width: 390,
          child: HudNavBar(items: items(), selectedIndex: 1, onSelect: (_) {}),
        ),
        brightness: Brightness.dark,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_nav_bar_dark.png'),
      );
    });

    testWidgets('light', (tester) async {
      await pumpGolden(
        tester,
        SizedBox(
          width: 390,
          child: HudNavBar(items: items(), selectedIndex: 1, onSelect: (_) {}),
        ),
        brightness: Brightness.light,
        boundaryKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/hud_nav_bar_light.png'),
      );
    });
  });
}
