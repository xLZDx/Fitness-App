import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_semantic_colors.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/core/theme/hud_tokens.dart';

/// D1 — the HUD tokens are a transcription, so this is a transcription check.
///
/// Every value below is quoted from `design_handoff_fitness_hud/README.md` or
/// `CLAUDE.md` in the assertion itself. A test that merely read the constant
/// back would pass against any typo; these compare the constant to the number
/// the handoff states, written out here independently.
void main() {
  group('CSS blur IS the Gaussian sigma, not double it', () {
    test('blur(7px) is sigma 7, not 3.5', () {
      // The whole point: CSSWG filter-effects-1 states the length parameter
      // of `blur()`/`drop-shadow()` directly as the standard deviation. A
      // `sigmaX: cssRadius / 2` implementation renders at half the design's
      // blur, and nothing about the result looks wrong enough to notice —
      // this file shipped exactly that bug for one gate.
      expect(blurSigma(7), 7);
      expect(blurSigma(14), 14);
      expect(blurSigma(30), 30);
    });

    test('a glass recipe actually applies the unhalved value', () {
      // Not "the helper is correct" but "the helper is what the recipe uses".
      final ui.ImageFilter filter = HudTokens.dark.panel.backdropFilter;
      expect(
        filter.toString(),
        contains('7.0'),
        reason: 'panel blur must reach ImageFilter as sigma 7, not 3.5',
      );
    });

    test('saturation is only composed in when the recipe asks for it', () {
      // Dark's panel has no `saturate()`; paying for a colour matrix that is
      // the identity would be a per-frame cost for nothing.
      expect(HudTokens.dark.panel.saturate, isNull);
      expect(HudTokens.dark.panel.backdropFilter.toString(),
          startsWith('ImageFilter.blur'));
      // Light's does: `blur(14px) saturate(150%)`.
      expect(HudTokens.light.panel.saturate, 1.5);
      expect(HudTokens.light.panel.backdropFilter.toString(),
          contains('ColorFilter'));
    });
  });

  group('the dark glass formula', () {
    // background:rgba(255,255,255,.014);
    // box-shadow: inset 0 0 0 1px rgba(255,255,255,.34),
    //             0 0 26px -6px rgba(255,255,255,.26);
    final HudGlass panel = HudTokens.dark.panel;

    test('the fill is 1.4% white — almost nothing, on purpose', () {
      expect(panel.fill.r, 1.0);
      expect(panel.fill.g, 1.0);
      expect(panel.fill.b, 1.0);
      // 0.014 * 255 = 3.57 -> 4/255. Asserted as the byte because that is what
      // survives the round trip, with the tolerance the rounding forces.
      expect((panel.fill.a * 255).round(), 4);
    });

    test('the hairline is 34% white and the halo 26%', () {
      expect((panel.innerBorder.a * 100).round(), 34);
      expect((panel.glow!.color.a * 100).round(), 26);
    });

    test('the halo is 26px blurred and pulled in 6', () {
      expect(panel.glow!.blurRadius, 26);
      expect(panel.glow!.spreadRadius, -6);
      expect(panel.glow!.offset, Offset.zero);
    });

    test('dark has no outer ring and no drop shadow; light has both', () {
      expect(panel.outerBorder, isNull);
      expect(panel.dropShadows, isEmpty);
      expect(HudTokens.light.panel.outerBorder, isNotNull);
      expect(HudTokens.light.panel.dropShadows, hasLength(1));
      expect(HudTokens.light.panel.glow, isNull,
          reason: 'a self-luminous halo on a white wash is a smear');
    });

    test('the button is the brightest tier and the chip the dimmest', () {
      // "Кнопка (самый светлый элемент)". Ordering, not absolute values —
      // this is the property the design states.
      final HudTokens t = HudTokens.dark;
      expect(t.button.innerBorder.a, greaterThan(t.panel.innerBorder.a));
      expect(t.panel.innerBorder.a, greaterThan(t.chip.innerBorder.a));
      expect(t.button.fill.a, greaterThan(t.panel.fill.a));
    });
  });

  group('the light theme is authored, not inverted', () {
    test('the accents are different hues, not one lightened', () {
      // #C9FF47 vs #4B7A00 — hue AND lightness differ; a lightness-only
      // relationship would make the light accent a pale lime.
      expect(HudTokens.dark.accent, const Color(0xFFC9FF47));
      expect(HudTokens.light.accent, const Color(0xFF4B7A00));
      expect(HudTokens.light.accent.g, lessThan(HudTokens.dark.accent.g));
    });

    test('light secondary text is HEAVIER than dark, not mirrored', () {
      // Measured from the Light prototype: every secondary tier is ~.06 higher
      // than its dark twin. Mirroring the alphas would under-weight all of it.
      expect((HudTokens.dark.textSecondary.a * 100).round(), 80);
      expect((HudTokens.light.textSecondary.a * 100).round(), 86);
      expect(
        HudTokens.light.textSecondary.a,
        greaterThan(HudTokens.dark.textSecondary.a),
      );
    });

    test('light glass is two orders of magnitude more opaque', () {
      // rgba(255,255,255,.014) vs rgba(255,255,255,.30). The interface is
      // subtractive on dark and additive on light; that is the whole design.
      expect((HudTokens.light.panel.fill.a * 100).round(), 30);
      expect(
        HudTokens.light.panel.fill.a / HudTokens.dark.panel.fill.a,
        greaterThan(10),
      );
    });

    test('the light nav bar reuses panel glass rather than its own recipe', () {
      // The one place the light theme deliberately does LESS than dark: it
      // drops the tinted gradient and the 30px blur.
      expect(HudTokens.light.navBar.fill, HudTokens.light.panel.fill);
      expect(HudTokens.light.navBar.cssBlur, HudTokens.light.panel.cssBlur);
      expect(HudTokens.dark.navBar.cssBlur, 30);
      expect(HudTokens.dark.navBar.fill, isNot(HudTokens.dark.panel.fill));
    });
  });

  group('the veil table', () {
    test('alpha per phase is the handoff table, and is not monotonic', () {
      // {morning:.5, day:.56, golden:.46, dawn:.44, dusk:.44, night:.5}
      expect(HudTokens.darkVeilAlpha, <String, double>{
        'night': 0.50,
        'dawn': 0.44,
        'morning': 0.50,
        'day': 0.56,
        'golden': 0.46,
        'dusk': 0.44,
      });
      // Stated because a "brighter as the day goes on" formula would look
      // right and be wrong: dawn and dusk share a value, night and morning
      // share another.
      expect(HudTokens.darkVeilAlpha['dawn'], HudTokens.darkVeilAlpha['dusk']);
      expect(
          HudTokens.darkVeilAlpha['night'], HudTokens.darkVeilAlpha['morning']);
    });

    test('the four stops are a+.1 / a / a*.74 / a*.9', () {
      final List<Color> day = HudTokens.dark.veilStops['day']!;
      const double a = 0.56;
      expect(day, hasLength(4));
      expect(day[0].a, closeTo(a + 0.1, 0.005));
      expect(day[1].a, closeTo(a, 0.005));
      expect(day[2].a, closeTo(a * 0.74, 0.005));
      expect(day[3].a, closeTo(a * 0.9, 0.005));
      // rgb(10,12,22)
      expect((day[1].r * 255).round(), 10);
      expect((day[1].g * 255).round(), 12);
      expect((day[1].b * 255).round(), 22);
    });

    test('light veils every phase identically', () {
      // The handoff's light branch is a flat #f6f7fc wash with no
      // time-of-day modulation at all. A phase-varying light veil would be an
      // invention.
      final List<List<Color>> all =
          HudTokens.light.veilStops.values.toList(growable: false);
      for (final List<Color> stops in all.skip(1)) {
        expect(stops, all.first);
      }
      expect((all.first.first.r * 255).round(), 246);
      expect((all.first.first.g * 255).round(), 247);
      expect((all.first.first.b * 255).round(), 252);
    });

    test('every phase key has a veil in both themes', () {
      // Non-vacuity for the lookup in `hudVeil`, which uses `!`.
      for (final String phase in HudTokens.darkVeilAlpha.keys) {
        expect(HudTokens.dark.veilStops[phase], isNotNull, reason: phase);
        expect(HudTokens.light.veilStops[phase], isNotNull, reason: phase);
      }
    });
  });

  group('accent derivations follow the handoff arithmetic', () {
    test('the selected-chip wash is accent at 35% over accent at 12%', () {
      // accentSoft = accent+'59' (0x59/255 = .349), accentFaint = accent+'1f'
      final LinearGradient g = HudTokens.dark.accentChipGradient;
      expect((g.colors.first.a * 100).round(), 35);
      expect((g.colors.last.a * 100).round(), 12);
      expect(g.colors.first.r, HudTokens.dark.accent.r);
    });

    test('the chip hairline is accent at 50%', () {
      expect((HudTokens.dark.accentChipBorder.a * 100).round(), 50);
    });

    test('substituting the accent carries the derivations with it', () {
      // The prototype's alternate presets work by substitution; if the wash
      // were stored rather than derived, a preset would leave a lime chip on a
      // cyan interface.
      const Color cyan = Color(0xFF7CE0FF);
      final HudTokens t = HudTokens.dark.copyWith(accent: cyan);
      expect(t.accent, cyan);
      expect(t.accentChipGradient.colors.first.b, cyan.b);
      expect(t.accentChipBorder.b, cyan.b);
      // and nothing else moved
      expect(t.panel.fill, HudTokens.dark.panel.fill);
    });
  });

  group('lerp', () {
    test('brightness snaps rather than interpolating', () {
      // There is no theme half way between light and dark; anything branching
      // on brightness must never see a value that does not exist.
      final HudTokens mid = HudTokens.dark.lerp(HudTokens.light, 0.4);
      expect(mid.brightness, Brightness.dark);
      final HudTokens past = HudTokens.dark.lerp(HudTokens.light, 0.6);
      expect(past.brightness, Brightness.light);
    });

    test('the endpoints are exact', () {
      final HudTokens at1 = HudTokens.dark.lerp(HudTokens.light, 1.0);
      expect(at1.accent, HudTokens.light.accent);
      expect(at1.panel.fill, HudTokens.light.panel.fill);
    });

    test('lerping against a foreign extension returns this, not null', () {
      expect(HudTokens.dark.lerp(null, 0.5), same(HudTokens.dark));
    });
  });

  group('the theme installs the tokens', () {
    testWidgets('the dark theme resolves the dark tokens', (t) async {
      late HudTokens seen;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(builder: (c) {
          seen = c.hud;
          return const SizedBox.shrink();
        }),
      ));
      expect(seen.accent, const Color(0xFFC9FF47));
    });

    testWidgets('the light theme resolves the light tokens', (t) async {
      // A separate test rather than a second pump in the one above, and that
      // is not tidiness. `MaterialApp` wraps its theme in `AnimatedTheme`, so
      // swapping the theme in place makes the first frame read the OLD tokens
      // interpolated toward the new -- and `HudTokens.lerp` snaps brightness
      // at t=.5, so at t=0 a "light" tree genuinely reports the dark accent.
      // Measured here; the first version of this test asserted #4B7A00 and got
      // #C9FF47.
      late HudTokens seen;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(builder: (c) {
          seen = c.hud;
          return const SizedBox.shrink();
        }),
      ));
      expect(seen.accent, const Color(0xFF4B7A00));
    });

    testWidgets('a theme switch animates through lerp rather than snapping',
        (t) async {
      // The behaviour the test above stumbled over, asserted deliberately: a
      // light/dark switch must cross-fade every token, because a HUD panel
      // snapping from 1.4% to 30% fill mid-gesture is a visible flash.
      final List<Color> seen = <Color>[];
      Widget app(ThemeData theme) => MaterialApp(
            theme: theme,
            home: Builder(builder: (c) {
              seen.add(c.hud.panel.fill);
              return const SizedBox.shrink();
            }),
          );
      await t.pumpWidget(app(AppTheme.dark()));
      await t.pumpWidget(app(AppTheme.light()));
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpAndSettle();
      expect(seen.length, greaterThan(2),
          reason: 'the theme change must produce intermediate frames');
      expect(seen.last.a, closeTo(HudTokens.light.panel.fill.a, 0.001));
      expect(
        seen.where((Color c) =>
            c.a > HudTokens.dark.panel.fill.a &&
            c.a < HudTokens.light.panel.fill.a),
        isNotEmpty,
        reason: 'at least one frame must hold a fill between the two themes',
      );
    });

    testWidgets('a bare MaterialApp falls back instead of throwing', (t) async {
      // `GlassCard` shipped the throwing version of this getter once, and it
      // took down every widget test that did not install the app theme. A
      // design token that cannot be read outside one ThemeData makes its own
      // components untestable.
      late HudTokens seen;
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(builder: (c) {
          seen = c.hud;
          return const SizedBox.shrink();
        }),
      ));
      expect(seen.accent, HudTokens.dark.accent);
    });

    test('installing HudTokens did not displace AppSemanticColors', () {
      // The two layers coexist; the migration is screen by screen, and a
      // screen still on the old tokens must keep resolving them.
      final ThemeData dark = AppTheme.dark();
      expect(dark.extension<HudTokens>(), isNotNull);
      expect(dark.extension<AppSemanticColors>(), isNotNull);
    });
  });
}
