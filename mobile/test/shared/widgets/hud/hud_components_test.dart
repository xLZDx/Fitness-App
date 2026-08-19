import 'package:flutter/semantics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/core/theme/hud_tokens.dart';
import 'package:fitness_app/core/theme/hud_typography.dart';
import 'package:fitness_app/shared/widgets/hud/hud_metric.dart';
import 'package:fitness_app/shared/widgets/hud/hud_scaffold.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

/// The decoration that actually carries the fill and the hairline.
BoxDecoration _fillDecoration(WidgetTester t) {
  final Iterable<DecoratedBox> boxes =
      t.widgetList<DecoratedBox>(find.descendant(
    of: find.byType(HudSurface),
    matching: find.byType(DecoratedBox),
  ));
  return boxes
      .map((DecoratedBox b) => b.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((BoxDecoration d) => d.border != null);
}

/// The outer decoration that carries the shadows.
BoxDecoration _shadowDecoration(WidgetTester t) {
  final DecoratedBox outer = t.widget<DecoratedBox>(find
      .descendant(
        of: find.byType(HudSurface),
        matching: find.byType(DecoratedBox),
        matchRoot: true,
      )
      .first);
  return outer.decoration as BoxDecoration;
}

void main() {
  group('HudSurface paints CSS box-shadows as the three different things', () {
    testWidgets('inset 0 0 0 1px is a Border, not a shadow', (t) async {
      await t.pumpWidget(_host(
        const SizedBox(
            width: 200, height: 100, child: HudPanel(child: Text('x'))),
      ));

      final BoxDecoration fill = _fillDecoration(t);
      expect(fill.border, isNotNull);
      expect(fill.border!.top.width, 1);
      expect(fill.border!.top.color, HudTokens.dark.panel.innerBorder);

      // And the same colour is NOT also emitted as a shadow — which is the
      // mistake being guarded. A `BoxShadow` there would grow the panel by 2px
      // and round its corners on the wrong radius.
      final BoxDecoration shadows = _shadowDecoration(t);
      expect(
        shadows.boxShadow?.where(
            (BoxShadow s) => s.color == HudTokens.dark.panel.innerBorder),
        anyOf(isNull, isEmpty),
      );
    });

    testWidgets('the dark halo reaches the canvas with its own numbers',
        (t) async {
      await t.pumpWidget(_host(
        const SizedBox(
            width: 200, height: 100, child: HudPanel(child: Text('x'))),
      ));
      final List<BoxShadow> shadows = _shadowDecoration(t).boxShadow!;
      expect(shadows, hasLength(1));
      expect(shadows.single.blurRadius, 26);
      expect(shadows.single.spreadRadius, -6);
    });

    testWidgets('light adds a 1px outer ink ring as spread-1, blur-0',
        (t) async {
      await t.pumpWidget(_host(
        const SizedBox(
            width: 200, height: 100, child: HudPanel(child: Text('x'))),
        brightness: Brightness.light,
      ));
      final List<BoxShadow> shadows = _shadowDecoration(t).boxShadow!;
      final Iterable<BoxShadow> rings = shadows
          .where((BoxShadow s) => s.blurRadius == 0 && s.spreadRadius == 1);
      expect(rings, hasLength(1),
          reason: '`0 0 0 1px` is a hard ring, not a blurred shadow');
      expect(rings.single.color, HudTokens.light.panel.outerBorder);
      // and the drop shadow is still there beside it
      expect(shadows.where((BoxShadow s) => s.blurRadius > 0), hasLength(1));
    });

    testWidgets('dark emits no outer ring at all', (t) async {
      await t.pumpWidget(_host(
        const SizedBox(
            width: 200, height: 100, child: HudPanel(child: Text('x'))),
      ));
      final List<BoxShadow> shadows = _shadowDecoration(t).boxShadow!;
      expect(
        shadows.where((BoxShadow s) => s.blurRadius == 0),
        isEmpty,
      );
    });

    Color? topHighlightOf(WidgetTester t, Finder of) {
      final Iterable<Container> lines = t.widgetList<Container>(
        find.descendant(of: of, matching: find.byType(Container)),
      );
      final Iterable<Container> coloured =
          lines.where((Container c) => c.color != null);
      return coloured.isEmpty ? null : coloured.single.color;
    }

    testWidgets(
        'inset 0 1px 0 is a top-only line, distinct from selected/unselected',
        (t) async {
      // `chipOff`'s box-shadow already carries `inset 0 1px 0 rgba(255,255,255,.3)`
      // alongside its ring; `chipOn`'s is `.5`. Both were missing from
      // HudSurface entirely for one gate — this is the fourth shadow kind the
      // class doc names, not the all-round hairline `HudSurface` already drew.
      await t
          .pumpWidget(_host(const HudChip(label: 'Strength', selected: false)));
      expect(topHighlightOf(t, find.byType(HudChip)),
          HudTokens.dark.chip.topHighlight);

      await t
          .pumpWidget(_host(const HudChip(label: 'Strength', selected: true)));
      expect(topHighlightOf(t, find.byType(HudChip)),
          HudTokens.dark.accentChipTopHighlight);
      expect(HudTokens.dark.accentChipTopHighlight,
          isNot(HudTokens.dark.chip.topHighlight),
          reason: 'selected must read as a distinct, stronger highlight');
    });
  });

  group('HudQuality', () {
    testWidgets('frost is on by default', (t) async {
      await t.pumpWidget(_host(const HudPanel(child: Text('x'))));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('turning frost off removes the filter but keeps the surface',
        (t) async {
      // The failure to avoid is a quality switch that also deletes the fill and
      // the hairline, leaving invisible panels on a low-end device.
      await t.pumpWidget(_host(
        const HudQuality(
          frostedGlass: false,
          child: HudPanel(child: Text('x')),
        ),
      ));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('x'), findsOneWidget);
      expect(_fillDecoration(t).border, isNotNull);
      expect(_fillDecoration(t).color, HudTokens.dark.panel.fill);
    });

    testWidgets('it scopes to a subtree rather than the whole app', (t) async {
      await t.pumpWidget(_host(
        const Column(
          children: <Widget>[
            HudQuality(frostedGlass: false, child: HudPanel(child: Text('a'))),
            HudPanel(child: Text('b')),
          ],
        ),
      ));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('HudButton', () {
    testWidgets('meets the 44pt tap target the handoff states', (t) async {
      await t.pumpWidget(_host(
        SizedBox(
          width: 300,
          child: HudButton(label: 'Go', onPressed: () {}),
        ),
      ));
      expect(t.getSize(find.byType(HudButton)).height,
          greaterThanOrEqualTo(HudTokens.minTapTarget));
    });

    testWidgets('a tap fires once and a disabled one never fires', (t) async {
      int hits = 0;
      await t.pumpWidget(_host(
        SizedBox(
          width: 300,
          child: HudButton(label: 'Go', onPressed: () => hits++),
        ),
      ));
      await t.tap(find.byType(HudButton));
      expect(hits, 1);

      await t.pumpWidget(_host(
        SizedBox(
          width: 300,
          child: HudButton(
            label: 'Go',
            enabled: false,
            onPressed: () => hits++,
          ),
        ),
      ));
      await t.tap(find.byType(HudButton));
      expect(hits, 1);
    });

    testWidgets('pressing lifts it, releasing puts it back', (t) async {
      // The handoff's only tap feedback. It animates on :hover in the browser,
      // which a phone does not have, so it is bound to the press instead.
      await t.pumpWidget(_host(
        SizedBox(width: 300, child: HudButton(label: 'Go', onPressed: () {})),
      ));
      double offsetOf() =>
          t.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset.dy;
      expect(offsetOf(), 0);

      final TestGesture g =
          await t.startGesture(t.getCenter(find.byType(HudButton)));
      await t.pump();
      expect(offsetOf(), lessThan(0));

      await g.up();
      await t.pump();
      expect(offsetOf(), 0);
    });

    testWidgets('the accent tone washes the surface in the accent', (t) async {
      await t.pumpWidget(_host(
        SizedBox(
          width: 300,
          child: HudButton(
            label: 'Log set',
            tone: HudButtonTone.accent,
            onPressed: () {},
          ),
        ),
      ));
      final BoxDecoration fill = _fillDecoration(t);
      expect(fill.gradient, isA<LinearGradient>());
      final LinearGradient g = fill.gradient! as LinearGradient;
      expect(g.colors.first.g, HudTokens.dark.accent.g);
      expect(fill.border!.top.color.g, HudTokens.dark.accent.g);
      // and the plain fill is gone, not layered under it
      expect(fill.color, isNull);
    });

    testWidgets('it announces itself as a button with its label', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(_host(
        SizedBox(
          width: 300,
          child: HudButton(label: 'Start workout', onPressed: () {}),
        ),
      ));
      // Read the node rather than searching by label: `find.bySemanticsLabel`
      // matches an element that OWNS the label, and this one is merged upward
      // out of the Text into the button's own node.
      final SemanticsNode node = t.getSemantics(find.byType(HudButton));
      expect(node.label, 'Start workout');
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
      h.dispose();
    });

    testWidgets('reachable and activatable from a keyboard, not only a tap',
        (t) async {
      // `HudButton` is built on a raw `GestureDetector`, which gets no
      // `FocusNode` and no keyboard activation for free -- a person driving
      // the app with a Bluetooth keyboard or switch control could Tab to it
      // and never be able to press it. `HudKeyboardActivation` closes that
      // gap; this proves the gap stays closed.
      int hits = 0;
      await t.pumpWidget(_host(
        SizedBox(
            width: 300, child: HudButton(label: 'Go', onPressed: () => hits++)),
      ));
      Focus.of(t.element(find.byType(GestureDetector).first)).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(hits, 1);

      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(hits, 2);
    });

    testWidgets('a disabled button carries no Focus node to activate',
        (t) async {
      // `HudKeyboardActivation` returns its child bare when `onActivate` is
      // null, rather than wrapping a `Focus` an assistive keyboard could
      // land on and fire a stale handler from.
      await t.pumpWidget(_host(
        SizedBox(
          width: 300,
          child: HudButton(label: 'Go', enabled: false, onPressed: () {}),
        ),
      ));
      expect(
        find.descendant(
            of: find.byType(HudButton), matching: find.byType(Focus)),
        findsNothing,
      );
    });
  });

  group('HudChip', () {
    testWidgets('selection changes the surface, not just the ink', (t) async {
      await t.pumpWidget(_host(
        const HudChip(label: 'Strength', selected: false),
      ));
      expect(_fillDecoration(t).gradient, isNull);
      expect(_fillDecoration(t).color, HudTokens.dark.chip.fill);

      await t.pumpWidget(_host(
        const HudChip(label: 'Strength', selected: true),
      ));
      expect(_fillDecoration(t).gradient, isNotNull);
      expect(_fillDecoration(t).border!.top.color,
          HudTokens.dark.accentChipBorder);
    });

    testWidgets('selection is exposed to a screen reader', (t) async {
      // Not colour alone: a chip whose only selected signal is a wash is
      // invisible to a screen reader and to anyone who cannot see the accent.
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(_host(
        const HudChip(label: 'Cardio', selected: true),
      ));
      final SemanticsNode node = t.getSemantics(find.byType(HudChip));
      expect(node.label, 'Cardio');
      expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);

      await t.pumpWidget(_host(
        const HudChip(label: 'Cardio', selected: false),
      ));
      expect(
        t.getSemantics(find.byType(HudChip)).hasFlag(SemanticsFlag.isSelected),
        isFalse,
        reason: 'the flag must track the state, not merely be present',
      );
      h.dispose();
    });

    testWidgets('it clears the 44pt floor even at chip padding', (t) async {
      await t.pumpWidget(_host(const HudChip(label: 'Fn', selected: false)));
      expect(t.getSize(find.byType(HudChip)).height,
          greaterThanOrEqualTo(HudTokens.minTapTarget));
    });

    testWidgets('Enter activates it exactly like a tap', (t) async {
      int hits = 0;
      await t.pumpWidget(_host(
        HudChip(label: 'Cardio', selected: false, onTap: () => hits++),
      ));
      Focus.of(t.element(find.byType(GestureDetector).first)).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(hits, 1);
    });
  });

  group('HudToggle', () {
    testWidgets('is 50x29 with a 23pt handle inside a 44pt hit box', (t) async {
      await t.pumpWidget(_host(HudToggle(value: true, onChanged: (_) {})));
      expect(t.getSize(find.byType(HudToggle)).height,
          greaterThanOrEqualTo(HudTokens.minTapTarget));
      final Size track = t.getSize(find.byType(AnimatedContainer));
      expect(track.width, 50);
      expect(track.height, 29);
    });

    testWidgets('tapping reports the opposite of its current value', (t) async {
      bool? got;
      await t.pumpWidget(
          _host(HudToggle(value: false, onChanged: (bool v) => got = v)));
      await t.tap(find.byType(HudToggle));
      expect(got, isTrue);
    });

    testWidgets('a null handler makes it inert, not merely grey', (t) async {
      await t.pumpWidget(_host(const HudToggle(value: false, onChanged: null)));
      await t.tap(find.byType(HudToggle));
      // Nothing to assert but the absence of a crash and of a state change;
      // the point is that the gesture is not wired when there is no handler.
      expect(t.takeException(), isNull);
    });

    testWidgets('Space toggles it exactly like a tap', (t) async {
      bool? got;
      await t.pumpWidget(
          _host(HudToggle(value: false, onChanged: (bool v) => got = v)));
      Focus.of(t.element(find.byType(GestureDetector).first)).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(got, isTrue);
    });
  });

  group('HudRing', () {
    testWidgets('reports its value to a screen reader instead of a bare number',
        (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(_host(
        const HudRing(
          size: 112,
          radius: 49,
          progress: 0.6,
          semanticsLabel: 'Exercises done',
          child: Text('04'),
        ),
      ));
      expect(
        t.getSemantics(find.byType(HudRing)),
        matchesSemantics(label: 'Exercises done', value: '60%'),
      );
      h.dispose();
    });

    testWidgets('progress outside 0..1 is clamped, not wrapped', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(_host(
        const HudRing(
          size: 100,
          radius: 40,
          progress: 1.4,
          semanticsLabel: 'over',
        ),
      ));
      expect(t.getSemantics(find.byType(HudRing)),
          matchesSemantics(label: 'over', value: '100%'));
      h.dispose();
    });

    testWidgets('it renders at the size asked for', (t) async {
      await t.pumpWidget(_host(
        const HudRing(size: 150, radius: 66, progress: 0.25),
      ));
      expect(
        t
            .getSize(find.descendant(
              of: find.byType(HudRing),
              matching: find.byType(CustomPaint),
            ))
            .width,
        150,
      );
    });
  });

  group('HudNavBar', () {
    List<HudNavItem> items() => const <HudNavItem>[
          HudNavItem(icon: Icons.grid_view, label: 'Home'),
          HudNavItem(icon: Icons.fitness_center, label: 'Workouts'),
          HudNavItem(icon: Icons.radio_button_checked, label: 'Scan'),
          HudNavItem(icon: Icons.north_east, label: 'Progress'),
          HudNavItem(icon: Icons.person, label: 'Profile'),
        ];

    testWidgets('five equal tabs, none of them raised', (t) async {
      await t.pumpWidget(_host(
        SizedBox(
          width: 390,
          child: HudNavBar(
            items: items(),
            selectedIndex: 0,
            onSelect: (_) {},
          ),
        ),
      ));
      expect(find.byType(Expanded), findsNWidgets(5));
      // The old bar lifted Scan out of the strip with an OverflowBox; the
      // handoff has no raised tab and no centre affordance at all.
      expect(
        find.descendant(
          of: find.byType(HudNavBar),
          matching: find.byType(OverflowBox),
        ),
        findsNothing,
      );
      expect(t.getSize(find.byType(HudNavBar)).height,
          HudTokens.navBarHeight + HudTokens.navBarBottom);
    });

    testWidgets('exactly one tab is selected, and the dot follows it',
        (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(_host(
        SizedBox(
          width: 390,
          child: HudNavBar(
            items: items(),
            selectedIndex: 2,
            onSelect: (_) {},
          ),
        ),
      ));
      final SemanticsNode scan = t.getSemantics(
        find.ancestor(
            of: find.text('SCAN'), matching: find.byType(InkResponse)),
      );
      expect(scan.label, 'Scan');
      expect(scan.hasFlag(SemanticsFlag.isSelected), isTrue);
      final SemanticsNode home = t.getSemantics(
        find.ancestor(
            of: find.text('HOME'), matching: find.byType(InkResponse)),
      );
      expect(home.hasFlag(SemanticsFlag.isSelected), isFalse);
      // The accent dot is a second, non-chromatic channel for the same fact,
      // so exactly one must be opaque.
      final Iterable<Container> dots = t
          .widgetList<Container>(find.descendant(
            of: find.byType(HudNavBar),
            matching: find.byType(Container),
          ))
          .where((Container c) =>
              (c.decoration as BoxDecoration?)?.shape == BoxShape.circle);
      final Iterable<Container> lit = dots.where((Container c) =>
          (c.decoration! as BoxDecoration).color != Colors.transparent);
      expect(dots, hasLength(5));
      expect(lit, hasLength(1));
      expect((lit.single.decoration! as BoxDecoration).color,
          HudTokens.dark.accent);
      h.dispose();
    });

    testWidgets('index -1 lights nothing', (t) async {
      // The handoff lights no tab while a session overlay is open. Telling the
      // user they are on a section they are not on is worse than telling them
      // nothing.
      await t.pumpWidget(_host(
        SizedBox(
          width: 390,
          child: HudNavBar(
            items: items(),
            selectedIndex: -1,
            onSelect: (_) {},
          ),
        ),
      ));
      final Iterable<Container> lit = t
          .widgetList<Container>(find.descendant(
        of: find.byType(HudNavBar),
        matching: find.byType(Container),
      ))
          .where((Container c) {
        final BoxDecoration? d = c.decoration as BoxDecoration?;
        return d?.shape == BoxShape.circle && d?.color != Colors.transparent;
      });
      expect(lit, isEmpty);
    });

    testWidgets('every tab clears the 44pt floor, not just the bar itself',
        (t) async {
      // `Row` centres its children on the cross axis rather than stretching
      // them, so the bar's own 72px height does not guarantee any one tab's
      // hit area does -- each tab must claim its own floor.
      await t.pumpWidget(_host(
        SizedBox(
          width: 390,
          child: HudNavBar(items: items(), selectedIndex: 0, onSelect: (_) {}),
        ),
      ));
      for (final Size size in t
          .widgetList<InkResponse>(find.byType(InkResponse))
          .map((InkResponse w) => t.getSize(find.byWidget(w)))) {
        expect(size.height, greaterThanOrEqualTo(HudTokens.minTapTarget));
      }
    });

    testWidgets('tapping a tab reports its index', (t) async {
      final List<int> picked = <int>[];
      await t.pumpWidget(_host(
        SizedBox(
          width: 390,
          child: HudNavBar(
            items: items(),
            selectedIndex: 0,
            onSelect: picked.add,
          ),
        ),
      ));
      await t.tap(find.text('PROGRESS'));
      expect(picked, <int>[3]);
    });

    testWidgets('labels are uppercased for display, not in the data',
        (t) async {
      // The handoff sets `text-transform:uppercase`. Uppercasing at the source
      // would corrupt the string a screen reader reads out.
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(_host(
        SizedBox(
          width: 390,
          child: HudNavBar(
            items: items(),
            selectedIndex: 0,
            onSelect: (_) {},
          ),
        ),
      ));
      expect(find.text('WORKOUTS'), findsOneWidget);
      expect(
        t
            .getSemantics(find.ancestor(
              of: find.text('WORKOUTS'),
              matching: find.byType(InkResponse),
            ))
            .label,
        'Workouts',
      );
      h.dispose();
    });
  });

  group('HudSettingRow', () {
    testWidgets('a tappable row announces itself once, not twice', (t) async {
      // The title Text merging upward into the outer Semantics without
      // `ExcludeSemantics` produced a node whose label was the title twice
      // over (once from the outer `Semantics.label`, once from the child
      // `Text` merging in) -- caught by reading the actual node, not by
      // searching for a label that happened to still be found somewhere.
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(_host(
        HudSettingRow(
            icon: Icons.settings, title: 'Notifications', onTap: () {}),
      ));
      final SemanticsNode node = t.getSemantics(find.byType(HudSettingRow));
      expect(node.label, 'Notifications');
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      h.dispose();
    });

    testWidgets('a row with no onTap carries no button semantics at all',
        (t) async {
      await t.pumpWidget(
          _host(const HudSettingRow(icon: Icons.info, title: 'Version 1.0')));
      expect(find.byType(Semantics), findsWidgets);
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('typography', () {
    test('every HUD style names Archivo and falls back to Inter', () {
      final HudTokens t = HudTokens.dark;
      final List<TextStyle> styles = <TextStyle>[
        HudType.screenTitle(t),
        HudType.heroTitle(t),
        HudType.panelHeading(t),
        HudType.panelTitle(t),
        HudType.rowTitle(t),
        HudType.rowMeta(t),
        HudType.body(t),
        HudType.bodyStrong(t),
        HudType.label(t),
        HudType.ringLabel(t),
        HudType.bigNumber(t, size: 54),
      ];
      for (final TextStyle s in styles) {
        expect(s.fontFamily, kHudFont);
        // Archivo has no Cyrillic at all. Without this, every Russian string in
        // an app whose default language IS Russian falls back to the platform
        // font — a different face on every device.
        expect(s.fontFamilyFallback, contains('Inter'));
      }
    });

    test('the mono role is Roboto Mono, and is NOT given the Inter fallback',
        () {
      // Inter is proportional; falling back to it for a glyph Roboto Mono
      // lacks would silently break the digit column the mono role exists for.
      final TextStyle s = HudType.mono(HudTokens.dark);
      expect(s.fontFamily, kHudMonoFont);
      expect(s.fontFamilyFallback, anyOf(isNull, isEmpty));
      expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('large numbers are weight 400 — the design says so twice', () {
      // "Вес крупных чисел — 400, не bold: контраст даёт размер и свечение."
      for (final double size in <double>[34, 40, 52, 72]) {
        final TextStyle s = HudType.bigNumber(HudTokens.dark, size: size);
        expect(s.fontWeight, FontWeight.w400, reason: '$size px');
        expect(s.fontSize, size);
        expect(s.shadows, isNotEmpty, reason: 'the glow carries the contrast');
      }
    });

    test('tracking is proportional to size, not one constant', () {
      // .16em is 1.52 at 9.5px and 3.52 at 22px; a single value that suits one
      // is heavy-handed at the other.
      final TextStyle small = HudType.label(HudTokens.dark, size: 9.5);
      final TextStyle large = HudType.label(HudTokens.dark, size: 22);
      expect(small.letterSpacing, closeTo(9.5 * 0.16, 0.001));
      expect(large.letterSpacing, closeTo(22 * 0.16, 0.001));
    });

    test('the over-photo and in-panel shadows are different, and applied', () {
      final HudTokens t = HudTokens.dark;
      final TextStyle over = HudType.body(t).overPhoto(t);
      final TextStyle within = HudType.body(t).inPanel(t);
      expect(over.shadows, t.readabilityShadow);
      expect(within.shadows, t.panelReadabilityShadow);
      expect(over.shadows, isNot(within.shadows));
    });

    testWidgets('a panel gives its text the softer shadow automatically',
        (t) async {
      await t.pumpWidget(_host(const HudPanel(child: Text('inside'))));
      final DefaultTextStyle style = DefaultTextStyle.of(
        t.element(find.text('inside')),
      );
      expect(style.style.shadows, HudTokens.dark.panelReadabilityShadow);
    });
  });
}
