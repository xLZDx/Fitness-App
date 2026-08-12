import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/glass_nav_bar.dart';
import 'package:fitness_app/shared/widgets/shell_insets.dart';

/// The invariant behind the operator's device report, held as a RULE rather
/// than as a test of one screen.
///
/// Reported 2026-08-12, on a real phone: the scan sheet sat so low that its
/// shutter could not be tapped, and once dragged down "контроль вообще
/// теряется" — the sheet could not be brought back at all. Measured cause:
/// `MainShell` sets `extendBody: true`, so a tab's body is laid out against
/// the full height and the nav bar is painted over its bottom ~110-130px,
/// while the sheet's `minChildSize: 0.24` was a fraction of the SCREEN and
/// knew nothing about the bar. On a 780px phone that left 51px for a 68px
/// shutter plus the scrollable strip — and the strip is the only surface a
/// drag can reach, which is why the sheet became unrecoverable rather than
/// merely cramped.
///
/// These tests deliberately do not pump `ScannerPage`. The scanner needs a
/// camera; the RULE does not, and the rule is what the other sheet-bearing
/// surfaces need to obey too.
void main() {
  const items = [
    GlassNavItem(icon: Icons.grid_view_outlined, label: 'A'),
    GlassNavItem(icon: Icons.radio_button_checked, label: 'B', raised: true),
    GlassNavItem(icon: Icons.fitness_center, label: 'C'),
  ];

  const headKey = Key('sheet-head');
  const maxFrac = 0.92;

  /// A shell tab, as `MainShell` builds one: body extended under the bar, a
  /// real [GlassNavBar], and a sheet sized through [sheetMinChildSize].
  Widget harness({
    required Size size,
    required double gestureInset,
    required double headHeight,
    bool nested = false,
  }) {
    final insets = EdgeInsets.only(bottom: gestureInset);
    Widget wrap(Widget child) => nested
        // What `FrostedScaffold` expands to (`glass.dart:206-213`): a second,
        // transparent Scaffold with `extendBody: true` and NO bottom bar of
        // its own. Every shell tab is built this way, so the obstruction has
        // to survive one more Scaffold to be usable at the call sites.
        ? Scaffold(
            backgroundColor: const Color(0x00000000),
            extendBody: true,
            extendBodyBehindAppBar: true,
            body: child,
          )
        : child;
    return MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: insets,
          viewPadding: insets,
        ),
        child: Scaffold(
          extendBody: true,
          bottomNavigationBar: GlassNavBar(
            items: items,
            selectedIndex: 0,
            onSelect: (_) {},
          ),
          body: wrap(Stack(
            children: [
              LayoutBuilder(builder: (context, box) {
                final obstruction = shellBottomObstruction(context);
                final min = sheetMinChildSize(
                  viewportHeight: box.maxHeight,
                  obstruction: obstruction,
                  visibleContentNeeded: headHeight,
                  ceiling: maxFrac,
                );
                return DraggableScrollableSheet(
                  initialChildSize: min,
                  minChildSize: min,
                  maxChildSize: maxFrac,
                  builder: (context, controller) => ColoredBox(
                    color: const Color(0xFF101010),
                    child: Column(
                      children: [
                        SizedBox(key: headKey, height: headHeight),
                        Expanded(
                          child: ListView(
                            controller: controller,
                            children: const [SizedBox(height: 2000)],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          )),
        ),
      ),
    );
  }

  // 640 is a small modern phone, 780 the operator's own report, 891 a large
  // one. Insets: 0 (none), 24 (three-button), 48 (gesture bar on a tall
  // Samsung) — the last is what makes the fraction-based sizing worst.
  for (final height in const [640.0, 780.0, 891.0]) {
    for (final inset in const [0.0, 24.0, 48.0]) {
      testWidgets(
          'sheet head clears the nav bar at ${height.toInt()}px, '
          'inset ${inset.toInt()}', (tester) async {
        const head = 200.0;
        tester.view.physicalSize = Size(400, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness(
          size: Size(400, height),
          gestureInset: inset,
          headHeight: head,
        ));
        await tester.pumpAndSettle();

        final barTop = height - GlassNavBar.barHeight - inset;
        final headRect = tester.getRect(find.byKey(headKey));

        expect(headRect.bottom, lessThanOrEqualTo(barTop + 0.5),
            reason: 'at its lowest the sheet must keep its whole head — '
                'shutter, caption and the strip that drags it back up — '
                'above the bar. Head bottom ${headRect.bottom}, '
                'bar top $barTop.');
      });
    }
  }

  testWidgets('the obstruction survives the page\'s own nested Scaffold',
      (tester) async {
    // Every tab wraps its content in `FrostedScaffold`, so the number read at
    // the sheet's call site has passed through TWO Scaffolds. The inner one
    // has `extendBody: true` and no bottom bar, so its `_BodyBuilder` computes
    // `max(inherited padding, 0)` and hands the shell's number straight on —
    // asserted here rather than reasoned about, because a nested Scaffold
    // zeroing it would put every sheet back under the bar with nothing in the
    // suite noticing.
    const head = 200.0;
    tester.view.physicalSize = const Size(400, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(
      size: const Size(400, 780),
      gestureInset: 48,
      headHeight: head,
      nested: true,
    ));
    await tester.pumpAndSettle();

    final barTop = 780 - GlassNavBar.barHeight - 48;
    expect(tester.getRect(find.byKey(headKey)).bottom,
        lessThanOrEqualTo(barTop + 0.5));
  });

  testWidgets('a sheet taller than the ceiling is clamped, not asserted',
      (tester) async {
    // A short screen with a tall bar can want more than `maxChildSize`.
    // `DraggableScrollableSheet` asserts `minChildSize <= maxChildSize`, so an
    // unclamped result turns a tight layout into a crash.
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(
      size: const Size(400, 400),
      gestureInset: 48,
      // 128 of obstruction + 300 of head is 428 on a 400px screen: over 1.0,
      // let alone over the 0.92 ceiling. Chosen to overflow the FRACTION
      // without overflowing the harness's own Column, so the assertion is
      // about the sheet and not about this file's stub.
      headHeight: 300,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('sheetBottomInset', () {
    /// Reads the helper against a chosen MediaQuery, which is the only thing
    /// worth testing here — the callers just add it to a Padding.
    Future<double> read(
      WidgetTester tester, {
      required double keyboard,
      required double system,
      double base = 24,
    }) async {
      late double value;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: keyboard),
          padding: EdgeInsets.only(bottom: system),
        ),
        child: Builder(builder: (context) {
          value = sheetBottomInset(context, base: base);
          return const SizedBox();
        }),
      ));
      return value;
    }

    testWidgets('clears the gesture indicator when the keyboard is down',
        (tester) async {
      // The reported case. A flat `24` left the Cancel/Confirm row inside the
      // system's own swipe band on a gesture-navigation phone.
      expect(await read(tester, keyboard: 0, system: 48), 72);
    });

    testWidgets('a raised keyboard wins over the indicator, and is not added to it',
        (tester) async {
      // Summing the two would leave a visible dead band above the keyboard —
      // the keyboard already covers the indicator.
      expect(await read(tester, keyboard: 300, system: 48), 324);
    });

    testWidgets('with neither, it is just the base', (tester) async {
      expect(await read(tester, keyboard: 0, system: 0), 24);
    });
  });

  group('sheetMinChildSize', () {
    test('returns the fraction that clears the obstruction', () {
      expect(
        sheetMinChildSize(
          viewportHeight: 800,
          obstruction: 128,
          visibleContentNeeded: 272,
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('keeps the designed fraction when the screen is tall enough', () {
      // The half a pixel budget alone gets wrong. On a 2,200px surface the
      // controls need 328px — 15% — but the design asks for 34%, and honouring
      // only the pixels shrank the sheet to a twelfth of the screen. Caught by
      // `scanner_page_test.dart`, not by reasoning: a row landed below the
      // fold, the tap missed, and the page sat spinning.
      expect(
        sheetMinChildSize(
          viewportHeight: 2200,
          obstruction: 0,
          visibleContentNeeded: 328,
          floor: 0.34,
        ),
        0.34,
      );
    });

    test('the pixel budget wins where the designed fraction is too small', () {
      expect(
        sheetMinChildSize(
          viewportHeight: 800,
          obstruction: 128,
          visibleContentNeeded: 272,
          floor: 0.24,
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('a floor above the ceiling is clamped rather than asserted', () {
      // `clamp` asserts when its lower bound exceeds its upper one, so a
      // caller passing a designed fraction larger than `maxChildSize` would
      // crash instead of laying out.
      expect(
        sheetMinChildSize(
          viewportHeight: 800,
          obstruction: 0,
          visibleContentNeeded: 10,
          floor: 0.99,
          ceiling: 0.92,
        ),
        0.92,
      );
    });

    test('never exceeds the ceiling it is given', () {
      expect(
        sheetMinChildSize(
          viewportHeight: 400,
          obstruction: 128,
          visibleContentNeeded: 600,
          ceiling: 0.92,
        ),
        0.92,
      );
    });

    test('a zero viewport yields zero rather than a division by zero', () {
      // Reachable: LayoutBuilder runs before the first real constraint in
      // some route transitions, and `Infinity` here would assert inside the
      // sheet rather than at the call site.
      expect(
        sheetMinChildSize(
          viewportHeight: 0,
          obstruction: 128,
          visibleContentNeeded: 200,
        ),
        0,
      );
    });
  });
}
