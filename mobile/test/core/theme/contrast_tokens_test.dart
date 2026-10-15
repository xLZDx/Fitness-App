// C26 / D-83: WCAG 2.1 contrast of every semantic token pair used by the body
// scan, nutrition plan, food diary and activity widgets. Pure arithmetic on
// token values: no widget is pumped. Text pairs must reach 4.5:1, graphics
// (icons, chart marks) 3:1. The recorded table lives in
// core/changes/2026-10-15-c26-l10n-a11y-audit.md.
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_semantic_colors.dart';
import 'package:fitness_app/core/theme/hud_tokens.dart';

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// Composites [fg] over the opaque [bg] and returns the WCAG ratio.
double ratio(Color fg, Color bg) {
  final a = fg.a;
  final flat = Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
  final l1 = _luminance(flat);
  final l2 = _luminance(bg);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

Color over(Color fg, Color bg) => Color.from(
      alpha: 1,
      red: fg.r * fg.a + bg.r * (1 - fg.a),
      green: fg.g * fg.a + bg.g * (1 - fg.a),
      blue: fg.b * fg.a + bg.b * (1 - fg.a),
    );

class _Pair {
  const _Pair(this.name, this.fg, this.bg, this.min);
  final String name;
  final Color fg;
  final Color bg;
  final double min;
}

const double kText = 4.5;
const double kGraphic = 3.0;

List<_Pair> _themePairs(
  String theme,
  AppSemanticColors app,
  HudTokens hud,
) {
  final surfaces = <String, Color>{
    'card': app.surfaceElevated, // GlassCard default fill
    'page': app.backgroundPrimary,
  };
  final out = <_Pair>[];
  surfaces.forEach((sName, bg) {
    String n(String t) => '$theme $t on $sName';
    // Text tokens used by the new widgets.
    out.addAll([
      _Pair(n('hud.textPrimary'), hud.textPrimary, bg, kText),
      _Pair(n('hud.textSecondary'), hud.textSecondary, bg, kText),
      _Pair(n('hud.textTertiary'), hud.textTertiary, bg, kText),
      _Pair(n('app.textPrimary'), app.textPrimary, bg, kText),
      _Pair(n('app.textSecondary'), app.textSecondary, bg, kText),
      // Status colours: danger is used as text, warning/success as icons.
      _Pair(n('app.danger (text)'), app.danger, bg, kText),
      _Pair(n('app.warning (icon)'), app.warning, bg, kGraphic),
      _Pair(n('app.success (icon)'), app.success, bg, kGraphic),
      _Pair(n('app.accentPrimary (icon)'), app.accentPrimary, bg, kGraphic),
      _Pair(n('hud.accent (icon)'), hud.accent, bg, kGraphic),
    ]);
  });
  // hud.success is an icon colour inside cards only.
  out.add(_Pair('$theme hud.success (icon) on card', hud.success,
      app.surfaceElevated, kGraphic));
  // Text on a solid accent fill.
  out.add(_Pair('$theme app.onAccent on accentPrimary', app.onAccent,
      app.accentPrimary, kText));
  out.add(_Pair('$theme hud.onAccent on hud.accent', hud.onAccent, hud.accent,
      kText));
  return out;
}

void main() {
  final pairs = <_Pair>[
    ..._themePairs('dark', AppSemanticColors.dark, HudTokens.dark),
    ..._themePairs('light', AppSemanticColors.light, HudTokens.light),
  ];

  group('semantic token pairs (card and page surfaces)', () {
    for (final p in pairs) {
      test('${p.name} >= ${p.min}', () {
        expect(ratio(p.fg, p.bg), greaterThanOrEqualTo(p.min),
            reason: '${p.name}: ${ratio(p.fg, p.bg).toStringAsFixed(2)}');
      });
    }
  });

  group('HUD glass: text over the dense content panel', () {
    // contentPanel is the only HUD glass recipe used behind body text; it is
    // composited over the worst-case backdrop of each brightness (a white
    // photograph under dark glass, a black photograph under light glass).
    for (final (name, hud, backdrop) in [
      ('dark', HudTokens.dark, const Color(0xFFFFFFFF)),
      ('light', HudTokens.light, const Color(0xFF000000)),
    ]) {
      final panel = over(hud.contentPanel.fill, backdrop);
      for (final (tName, fg) in [
        ('textPrimary', hud.textPrimary),
        ('textSecondary', hud.textSecondary),
      ]) {
        test('$name hud.$tName on contentPanel over worst-case backdrop', () {
          expect(ratio(fg, panel), greaterThanOrEqualTo(kText),
              reason: ratio(fg, panel).toStringAsFixed(2));
        });
      }
    }
  });

  group('camera readiness panel (black at 0.85 over any scene)', () {
    final panelFill = const Color(0xFF000000).withValues(alpha: 0.85);
    // Worst case is the brightest scene; check white, mid grey and black.
    for (final backdrop in const [
      Color(0xFFFFFFFF),
      Color(0xFF808080),
      Color(0xFF000000),
    ]) {
      final panel = over(panelFill, backdrop);
      for (final (name, fg) in [
        ('greenAccent', const Color(0xFF69F0AE)),
        ('orangeAccent', const Color(0xFFFFAB40)),
        ('white', const Color(0xFFFFFFFF)),
        ('redAccent', const Color(0xFFFF5252)),
      ]) {
        test('$name on panel over #${backdrop.toARGB32().toRadixString(16)}',
            () {
          expect(ratio(fg, panel), greaterThanOrEqualTo(kText),
              reason: ratio(fg, panel).toStringAsFixed(2));
        });
      }
    }
  });

  test('ratio() reproduces the documented token ratios', () {
    // app_semantic_colors.dart documents dark textPrimary 17.80:1 and light
    // textSecondary 4.55:1 against the page background.
    expect(
        ratio(AppSemanticColors.dark.textPrimary,
            AppSemanticColors.dark.backgroundPrimary),
        closeTo(17.80, 0.05));
    expect(
        ratio(AppSemanticColors.light.textSecondary,
            AppSemanticColors.light.backgroundPrimary),
        closeTo(4.55, 0.05));
  });
}
