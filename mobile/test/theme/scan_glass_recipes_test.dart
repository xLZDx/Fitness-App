import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/hud_tokens.dart';

/// SCAN-G1, R5 (core/SCAN_G1_SCOPE.md): the Scan screen's two glass recipes
/// are the reference's, number for number.
///
/// Every expected value below is read from the reference CSS, not from the
/// token file: `Fitness Glass Phone v1 - Sunset.dc.html:221` (primary
/// button, dark), `:214` (CTA, dark); `Light.dc.html:221` / `:214`.
/// `accentSoft`/`accentFaint`/`accentLine` are `accent + '59'/'1f'/'66'`
/// (accent @ .35 / .12 / .40, lines 702-704). Alphas are compared after the
/// 8-bit round trip a `Color` literal implies.
void main() {
  double a(Color c) => c.a;
  Color rgb(Color c) => c.withValues(alpha: 1);

  group('dark scanPrimaryButton == Sunset.dc.html:221', () {
    final HudGlass g = HudTokens.dark.scanPrimaryButton;

    test('linear-gradient(180deg, rgba(26,15,34,.5), rgba(26,15,34,.3))', () {
      final LinearGradient grad = g.fillGradient! as LinearGradient;
      expect(grad.begin, Alignment.topCenter);
      expect(grad.end, Alignment.bottomCenter);
      expect(grad.colors, hasLength(2));
      expect(rgb(grad.colors[0]), const Color(0xFF1A0F22));
      expect(a(grad.colors[0]), closeTo(0.5, 1 / 255));
      expect(rgb(grad.colors[1]), const Color(0xFF1A0F22));
      expect(a(grad.colors[1]), closeTo(0.3, 1 / 255));
    });

    test('backdrop-filter: blur(22px), no saturate', () {
      expect(g.cssBlur, 22);
      expect(g.saturate, isNull);
    });

    test('inset 0 1px 0 rgba(255,255,255,.4); inset ring rgba(255,255,255,.2)',
        () {
      expect(rgb(g.topHighlight!), const Color(0xFFFFFFFF));
      expect(a(g.topHighlight!), closeTo(0.4, 1 / 255));
      expect(rgb(g.innerBorder), const Color(0xFFFFFFFF));
      expect(a(g.innerBorder), closeTo(0.2, 1 / 255));
      expect(g.outerBorder, isNull, reason: 'no outer ring on dark');
      expect(g.glow, isNull);
    });

    test('0 20px 36px -16px rgba(12,7,24,.85) + 0 6px 14px -8px rgba(12,7,24,.5)',
        () {
      expect(g.dropShadows, hasLength(2));
      final BoxShadow s1 = g.dropShadows[0];
      expect(s1.offset, const Offset(0, 20));
      expect(s1.blurRadius, 36);
      expect(s1.spreadRadius, -16);
      expect(rgb(s1.color), const Color(0xFF0C0718));
      expect(a(s1.color), closeTo(0.85, 1 / 255));
      final BoxShadow s2 = g.dropShadows[1];
      expect(s2.offset, const Offset(0, 6));
      expect(s2.blurRadius, 14);
      expect(s2.spreadRadius, -8);
      expect(rgb(s2.color), const Color(0xFF0C0718));
      expect(a(s2.color), closeTo(0.5, 1 / 255));
    });

    test('is NOT the panel-family button every other screen uses', () {
      final HudGlass b = HudTokens.dark.button;
      expect(g.cssBlur, isNot(b.cssBlur));
      expect(g.fillGradient, isNotNull);
      expect(b.fillGradient, isNull);
    });
  });

  group('light scanPrimaryButton == Light.dc.html:221 (the light panel recipe)',
      () {
    final HudGlass g = HudTokens.light.scanPrimaryButton;

    test('rgba(255,255,255,.3); blur(14px) saturate(150%)', () {
      expect(g.fillGradient, isNull);
      expect(rgb(g.fill), const Color(0xFFFFFFFF));
      expect(a(g.fill), closeTo(0.3, 1 / 255));
      expect(g.cssBlur, 14);
      expect(g.saturate, 1.5);
    });

    test('inset ring rgba(255,255,255,.85); outer ring rgba(27,32,48,.16)', () {
      expect(rgb(g.innerBorder), const Color(0xFFFFFFFF));
      expect(a(g.innerBorder), closeTo(0.85, 1 / 255));
      expect(rgb(g.outerBorder!), const Color(0xFF1B2030));
      expect(a(g.outerBorder!), closeTo(0.16, 1 / 255));
      expect(g.topHighlight, isNull, reason: 'line 221 has no top highlight');
    });

    test('0 18px 34px -22px rgba(42,52,74,.35)', () {
      expect(g.dropShadows, hasLength(1));
      final BoxShadow s = g.dropShadows[0];
      expect(s.offset, const Offset(0, 18));
      expect(s.blurRadius, 34);
      expect(s.spreadRadius, -22);
      expect(rgb(s.color), const Color(0xFF2A344A));
      expect(a(s.color), closeTo(0.35, 1 / 255));
    });

    test('and it equals the light panel, field for field', () {
      final HudGlass p = HudTokens.light.panel;
      expect(g.fill, p.fill);
      expect(g.cssBlur, p.cssBlur);
      expect(g.saturate, p.saturate);
      expect(g.innerBorder, p.innerBorder);
      expect(g.outerBorder, p.outerBorder);
      expect(g.dropShadows, p.dropShadows);
    });
  });

  for (final (String theme, HudTokens t, Color accent, Color ink1, Color ink2)
      in <(String, HudTokens, Color, Color, Color)>[
    (
      'dark',
      HudTokens.dark,
      const Color(0xFFC9FF47),
      const Color(0xD90C0718), // rgba(12,7,24,.85)
      const Color(0x800C0718), // rgba(12,7,24,.5)
    ),
    (
      'light',
      HudTokens.light,
      const Color(0xFF4B7A00),
      const Color(0x2E2A344A), // rgba(42,52,74,.18)
      const Color(0x2E2A344A), // rgba(42,52,74,.18)
    ),
  ]) {
    group('$theme scanCta == line 214', () {
      final HudGlass g = t.scanCta;

      test('accent is the theme default (line 461)', () {
        expect(t.accent, accent);
      });

      test('linear-gradient(180deg, accentSoft, accentFaint) = accent @ .35 -> .12',
          () {
        final LinearGradient grad = g.fillGradient! as LinearGradient;
        expect(grad.begin, Alignment.topCenter);
        expect(grad.end, Alignment.bottomCenter);
        expect(rgb(grad.colors[0]), accent);
        expect(a(grad.colors[0]), closeTo(0.35, 1 / 255));
        expect(rgb(grad.colors[1]), accent);
        expect(a(grad.colors[1]), closeTo(0.12, 1 / 255));
      });

      test('blur(18px) saturate(160%)', () {
        expect(g.cssBlur, 18);
        expect(g.saturate, 1.6);
      });

      test('inset 0 1px 0 rgba(255,255,255,.55); inset ring accentLine (.40)',
          () {
        expect(rgb(g.topHighlight!), const Color(0xFFFFFFFF));
        expect(a(g.topHighlight!), closeTo(0.55, 1 / 255));
        expect(rgb(g.innerBorder), accent);
        expect(a(g.innerBorder), closeTo(0.40, 1 / 255));
        expect(g.outerBorder, isNull);
      });

      test('0 20px 34px -16px + 0 6px 14px -8px, theme ink', () {
        expect(g.dropShadows, hasLength(2));
        expect(g.dropShadows[0].offset, const Offset(0, 20));
        expect(g.dropShadows[0].blurRadius, 34);
        expect(g.dropShadows[0].spreadRadius, -16);
        expect(g.dropShadows[0].color, ink1);
        expect(g.dropShadows[1].offset, const Offset(0, 6));
        expect(g.dropShadows[1].blurRadius, 14);
        expect(g.dropShadows[1].spreadRadius, -8);
        expect(g.dropShadows[1].color, ink2);
      });
    });
  }

  test('an accent preset carries the CTA with it', () {
    // `_withAccent` rebuilds scanCta from the new accent, the way the CSS
    // variables do; the primary button does not depend on the accent.
    const Color custom = Color(0xFF00E5FF);
    final HudTokens t = HudTokens.dark.copyWith(accent: custom);
    final LinearGradient grad = t.scanCta.fillGradient! as LinearGradient;
    expect(rgb(grad.colors[0]), custom);
    expect(rgb(t.scanCta.innerBorder), custom);
    expect(t.scanPrimaryButton, HudTokens.dark.scanPrimaryButton);
  });

  test('lerp reaches both ends', () {
    final HudTokens mid = HudTokens.dark.lerp(HudTokens.light, 0.0);
    expect(mid.scanPrimaryButton.cssBlur, 22);
    final HudTokens end = HudTokens.dark.lerp(HudTokens.light, 1.0);
    expect(end.scanPrimaryButton.cssBlur, 14);
    expect(end.scanCta.dropShadows[0].color, const Color(0x2E2A344A));
  });
}
