import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsFlag;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_palette.dart';
import 'package:fitness_app/core/theme/app_semantic_colors.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/app_buttons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Inter is bundled, so `AppTheme` resolves it from the asset bundle. This
  // used to disable Google Fonts' runtime fetching, because a test machine has
  // no network and the failure had nothing to do with buttons.

  Future<void> pump(WidgetTester t, Widget child) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    ));
    t.takeException();
  }

  Color spinnerColour(WidgetTester t) => t
      .widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator))
      .valueColor!
      .value!;

  group('loading', () {
    testWidgets('swallows the tap', (t) async {
      var taps = 0;
      await pump(
          t,
          AppPrimaryButton(
              label: 'Save', loading: true, onPressed: () => taps++));
      await t.tap(find.byType(AppPrimaryButton));
      await t.pump();
      expect(taps, 0, reason: 'a working button must not queue a second call');
    });

    testWidgets('taps land when it is not loading', (t) async {
      var taps = 0;
      // The control for the test above: without it, a button that is broken
      // outright would pass that assertion.
      await pump(t, AppPrimaryButton(label: 'Save', onPressed: () => taps++));
      await t.tap(find.byType(AppPrimaryButton));
      await t.pump();
      expect(taps, 1);
    });

    testWidgets('keeps the label visible', (t) async {
      await pump(
          t,
          const AppPrimaryButton(
              label: 'Saving', loading: true, onPressed: null));
      expect(find.text('Saving'), findsOneWidget,
          reason:
              'a button whose text vanishes says nothing about what it does');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('the spinner takes the button\'s own foreground, per tone',
        (t) async {
      // The defect this component exists for. Three call sites painted this
      // spinner `Colors.white`, one of them directly under a
      // `foregroundColor: onError` it contradicted.
      await pump(
          t,
          const AppPrimaryButton(
              label: 'Delete',
              loading: true,
              tone: AppButtonTone.destructive,
              onPressed: null));
      expect(spinnerColour(t), AppTheme.dark().colorScheme.onError);
    });

    testWidgets('a bare spinner would be INVISIBLE on a filled button',
        (t) async {
      // The second defect, and the worse one. Four call sites wrote
      // `CircularProgressIndicator(strokeWidth: 2.4)` with no colour inside a
      // FilledButton. With no colour it takes `colorScheme.primary` — which is
      // exactly what M3 paints the button's BACKGROUND. Same colour, 1:1: the
      // user pressed a button and got no feedback at all, on backup, restore,
      // video upload and injury save.
      late Color background, bare;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Builder(builder: (c) {
          final s = Theme.of(c).colorScheme;
          background = s.primary;
          bare = Theme.of(c).progressIndicatorTheme.color ?? s.primary;
          return const SizedBox.shrink();
        })),
      ));
      t.takeException();
      expect(bare, background, reason: 'this is why `loading` sets the colour');

      // And the component does not do that.
      await pump(
          t,
          const AppPrimaryButton(
              label: 'Back up', loading: true, onPressed: null));
      expect(spinnerColour(t), isNot(background));
      expect(spinnerColour(t), AppTheme.dark().colorScheme.onPrimary);
    });

    testWidgets('and follows the brand tone too', (t) async {
      await pump(
          t,
          const AppPrimaryButton(
              label: 'Support',
              loading: true,
              tone: AppButtonTone.brand,
              onPressed: null));
      expect(spinnerColour(t), AppSemanticColors.onGradientInk);
    });
  });

  group('tone', () {
    testWidgets('destructive paints the scheme error colour', (t) async {
      await pump(
          t,
          const AppPrimaryButton(
              label: 'Delete',
              tone: AppButtonTone.destructive,
              onPressed: null));
      final style = t.widget<FilledButton>(find.byType(FilledButton)).style!;
      expect(style.backgroundColor!.resolve({}),
          AppTheme.dark().colorScheme.error);
      expect(style.foregroundColor!.resolve({}),
          AppTheme.dark().colorScheme.onError);
    });

    testWidgets('brand paints the aurora colour and its ink', (t) async {
      await pump(
          t,
          const AppPrimaryButton(
              label: 'Support', tone: AppButtonTone.brand, onPressed: null));
      final style = t.widget<FilledButton>(find.byType(FilledButton)).style!;
      expect(style.backgroundColor!.resolve({}), AppPalette.auroraPeach);
      expect(
          style.foregroundColor!.resolve({}), AppSemanticColors.onGradientInk);
    });

    testWidgets('normal leaves the theme to decide', (t) async {
      await pump(t, const AppPrimaryButton(label: 'Go', onPressed: null));
      final style = t.widget<FilledButton>(find.byType(FilledButton)).style!;
      expect(style.backgroundColor?.resolve({}), isNull,
          reason: 'a null override is what lets the theme through');
    });
  });

  group('size', () {
    testWidgets('a compact button survives inside a Row', (t) async {
      // The crash class. `AppTheme` gives buttons `minimumSize:
      // Size.fromHeight(54)` — which is `Size(double.infinity, 54)` — and a Row
      // hands unbounded width to its non-flex children. This exact shape threw
      // "BoxConstraints forces an infinite width" in the set-capture sheet, on
      // the workout-logging path.
      await pump(
          t,
          const Row(children: [
            AppPrimaryButton(
                label: 'Save', size: AppButtonSize.compact, onPressed: null),
          ]));
      expect(t.takeException(), isNull);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('a raw themed button in the same Row does NOT', (t) async {
      // The negative control. Without it the assertion above proves nothing
      // about whether `compact` is what saved it.
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Row(children: [
            FilledButton(onPressed: () {}, child: const Text('Save')),
          ]),
        ),
      ));
      // Not `isA<FlutterError>()`: the bad constraint cascades and the binding
      // hands back a summary of six exceptions rather than the first one.
      // What matters is that this shape throws at all and `compact` does not.
      expect(t.takeException(), isNotNull,
          reason: 'this is the shape the component is protecting against');
    });

    testWidgets('a regular button keeps the theme height', (t) async {
      await pump(t, const AppPrimaryButton(label: 'Go', onPressed: null));
      final style = t.widget<FilledButton>(find.byType(FilledButton)).style!;
      expect(style.minimumSize?.resolve({}), isNull,
          reason: 'null is what leaves Size.fromHeight(54) in place');
    });
  });

  group('icon', () {
    testWidgets('renders beside the label', (t) async {
      await pump(
          t,
          const AppPrimaryButton(
              label: 'Scan', icon: Icons.qr_code_scanner, onPressed: null));
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
    });

    testWidgets('gives way to the spinner while loading', (t) async {
      await pump(
          t,
          const AppPrimaryButton(
              label: 'Scan',
              icon: Icons.qr_code_scanner,
              loading: true,
              onPressed: null));
      expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('the other three', () {
    testWidgets('secondary and tertiary carry label, icon and loading',
        (t) async {
      await pump(
          t,
          const Column(children: [
            AppSecondaryButton(
                label: 'Later', icon: Icons.schedule, onPressed: null),
            AppTertiaryButton(label: 'Skip', loading: true, onPressed: null),
          ]));
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('an icon button carries an accessible name', (t) async {
      // `tooltip` is required by the constructor, so this asserts that being
      // required actually reaches the semantics tree — twelve of the app's
      // plain `IconButton`s had no name at all.
      await pump(
          t,
          const AppIconButton(
              icon: Icons.close, tooltip: 'Close', onPressed: null));
      expect(find.byTooltip('Close'), findsOneWidget);
      // The tooltip's semantics live on the `Tooltip` node, not on the
      // `IconButton` one — asserting on the button node reports an empty
      // tooltip and looks like the name is missing when it is not.
      expect(t.getSemantics(find.byTooltip('Close')).tooltip, 'Close');
      expect(
          t
              .getSemantics(find.byType(IconButton))
              .hasFlag(SemanticsFlag.isButton),
          isTrue);
    });

    testWidgets('an icon button shows a spinner in place of its icon',
        (t) async {
      await pump(
          t,
          const AppIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              loading: true,
              onPressed: null));
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('regular tints nothing -- the theme colours the icon',
        (t) async {
      // The default IconButton has no `color:` override, so a null here
      // (rather than a hardcoded onSurface) is what lets a disabled/pressed
      // theme state come through untouched.
      await pump(
          t,
          const AppIconButton(
              icon: Icons.close, tooltip: 'Close', onPressed: null));
      final btn = t.widget<IconButton>(find.byType(IconButton));
      expect(btn.color, isNull);
    });

    testWidgets('destructive paints the scheme error colour', (t) async {
      // The subscription page's copy-error button: one of twelve IconButton
      // call sites, the only one that coloured its icon at all.
      await pump(
          t,
          const AppIconButton(
              icon: Icons.copy_rounded,
              tooltip: 'Copy error',
              tone: AppButtonTone.destructive,
              onPressed: null));
      final btn = t.widget<IconButton>(find.byType(IconButton));
      expect(btn.color, AppTheme.dark().colorScheme.error);
    });

    testWidgets('compact tightens the touch target AND shrinks the glyph',
        (t) async {
      // The shape seven of the twelve call sites already used by hand
      // (VisualDensity.compact + an 18px icon) for controls sitting inline
      // next to text, rather than alone in an app bar.
      await pump(
          t,
          const AppIconButton(
              icon: Icons.add_rounded,
              tooltip: 'Increase',
              size: AppButtonSize.compact,
              onPressed: null));
      final btn = t.widget<IconButton>(find.byType(IconButton));
      expect(btn.visualDensity, VisualDensity.compact);
      expect(btn.iconSize, 18);
    });

    testWidgets('regular leaves both to the theme default', (t) async {
      await pump(
          t,
          const AppIconButton(
              icon: Icons.add_rounded, tooltip: 'Increase', onPressed: null));
      final btn = t.widget<IconButton>(find.byType(IconButton));
      expect(btn.visualDensity, isNull);
      expect(btn.iconSize, isNull);
    });
  });
}
