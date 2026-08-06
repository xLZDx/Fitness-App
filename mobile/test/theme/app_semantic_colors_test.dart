import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fitness_app/core/theme/app_palette.dart';
import 'package:fitness_app/core/theme/app_semantic_colors.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

/// Contrast is asserted by computation, not by eye.
///
/// A token file is exactly the kind of thing that looks reviewed and is not:
/// twenty hex values, all plausible, and the only way to know whether any of
/// them is legible is arithmetic. So the arithmetic lives here, and a value
/// edited later has to survive it.
///
/// WCAG 2.1 relative luminance, from the spec's own formula.
double _channel(int v) {
  final c = v / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) as double;
}

double _luminance(Color c) =>
    0.2126 * _channel((c.r * 255).round()) +
    0.7152 * _channel((c.g * 255).round()) +
    0.0722 * _channel((c.b * 255).round());

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [fg] at its own alpha composited onto opaque [bg].
Color flatten(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // `AppTheme` builds its text theme from Inter. Without this the two tests
  // that realise a real theme reach for fonts.gstatic.com, and a machine with
  // no network fails them for a reason that has nothing to do with colour.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Sanity check on the checker itself. A contrast function with a sign error
  // or a missing gamma step would let every assertion below pass.
  group('the measuring stick', () {
    test('black on white is 21:1', () {
      expect(contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21.0, 0.01));
    });

    test('a colour against itself is 1:1', () {
      expect(contrast(const Color(0xFF8A5BFF), const Color(0xFF8A5BFF)),
          closeTo(1.0, 0.001));
    });

    test('it is symmetric', () {
      const a = Color(0xFF2BE5C2), b = Color(0xFF050214);
      expect(contrast(a, b), closeTo(contrast(b, a), 0.0001));
    });
  });

  for (final entry in {
    'dark': AppSemanticColors.dark,
    'light': AppSemanticColors.light,
  }.entries) {
    final name = entry.key;
    final t = entry.value;
    final bg = t.backgroundPrimary;

    group('$name theme', () {
      test('primary and secondary text clear AA on the background', () {
        expect(contrast(t.textPrimary, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(t.textSecondary, bg), greaterThanOrEqualTo(4.5));
      });

      test('disabled text is deliberately below AA but still visible', () {
        // WCAG 1.4.3 exempts inactive components. The lower bound matters as
        // much as the upper one: text nobody can see at all is not a disabled
        // control, it is a missing one.
        final ratio = contrast(t.textDisabled, bg);
        expect(ratio, lessThan(4.5));
        expect(ratio, greaterThan(2.0));
      });

      test('status colours clear AA on the background', () {
        for (final c in {
          'success': t.success,
          'warning': t.warning,
          'danger': t.danger,
        }.entries) {
          expect(contrast(c.value, bg), greaterThanOrEqualTo(4.5),
              reason: '${c.key} on the $name background');
        }
      });

      test('accents clear AA on the background', () {
        expect(contrast(t.accentPrimary, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(t.accentSecondary, bg), greaterThanOrEqualTo(4.5));
      });

      test('onAccent clears AA on both accents', () {
        expect(contrast(t.onAccent, t.accentPrimary),
            greaterThanOrEqualTo(4.5));
        expect(contrast(t.onAccent, t.accentSecondary),
            greaterThanOrEqualTo(4.5));
      });

      test('onGradient clears AA on every tile-gradient stop', () {
        // The defect the token exists for: `Colors.white` scores 1.27–2.56 on
        // these ten stops, and the app has 109 uses of it on exactly this
        // artwork.
        for (final tile in AppPalette.tileGradients) {
          for (final stop in tile) {
            expect(contrast(t.onGradient, stop), greaterThanOrEqualTo(4.5),
                reason: 'onGradient on $stop');
          }
        }
      });

      test('white would NOT clear AA on those stops', () {
        // The negative control. Without it, the assertion above says nothing
        // about whether the token was needed.
        final failures = [
          for (final tile in AppPalette.tileGradients)
            for (final stop in tile)
              if (contrast(const Color(0xFFFFFFFF), stop) < 4.5) stop,
        ];
        expect(failures, hasLength(10),
            reason: 'every stop, which is why the 109 Colors.white are a bug');
      });

      test('translucent surfaces stay readable once composited', () {
        // The fills carry alpha, so their real contrast is only visible after
        // they are flattened onto the background they sit on.
        final card = flatten(t.surfacePrimary, bg);
        expect(contrast(t.textPrimary, card), greaterThanOrEqualTo(4.5),
            reason: 'primary text on a card');
        expect(contrast(t.textSecondary, card), greaterThanOrEqualTo(4.5),
            reason: 'secondary text on a card');
        expect(contrast(t.textPrimary, t.surfaceElevated),
            greaterThanOrEqualTo(4.5),
            reason: 'primary text on a sheet');
      });

      test('an elevated surface is opaque', () {
        // A sheet at card opacity let the page read straight through it once
        // already; the fix must not be undone by a later edit.
        expect(t.surfaceElevated.a, 1.0);
      });
    });
  }

  group('light is authored, not inverted', () {
    test('the accents are different hues, not different lightnesses', () {
      // If the light theme were derived by inversion these would be related.
      // They are not: #8A5BFF scores 3.37 on the light background and had to
      // be replaced outright, not lightened or darkened.
      expect(AppSemanticColors.light.accentPrimary,
          isNot(AppSemanticColors.dark.accentPrimary));
      expect(contrast(AppSemanticColors.dark.accentPrimary,
              AppSemanticColors.light.backgroundPrimary),
          lessThan(4.5),
          reason: 'the dark accent on the light background is why');
    });

    test('onAccent flips and onGradient does not', () {
      // The distinction the two tokens exist for. Accents are theme surfaces
      // and flip; the tile gradients are brand artwork, identical in both
      // themes, so what sits on them cannot.
      expect(AppSemanticColors.light.onAccent,
          isNot(AppSemanticColors.dark.onAccent));
      expect(AppSemanticColors.light.onGradient,
          AppSemanticColors.dark.onGradient);
    });

    test('the camera scrim does not flip either', () {
      expect(AppSemanticColors.light.cameraOverlay,
          AppSemanticColors.dark.cameraOverlay);
    });
  });

  group('the theme installs it', () {
    // `testWidgets`, not `test`: building the theme touches GoogleFonts, which
    // reports its failure asynchronously even with runtime fetching off, and
    // only a tester can consume that. The same reason `app_theme_test.dart`
    // realises every theme through a pump.
    testWidgets('both themes carry the extension', (t) async {
      final dark = AppTheme.dark();
      final light = AppTheme.light();
      t.takeException();
      expect(dark.extension<AppSemanticColors>(), AppSemanticColors.dark);
      expect(light.extension<AppSemanticColors>(), AppSemanticColors.light);
    });

    testWidgets('the ColorScheme agrees with the tokens', (t) async {
      // They used to be two independent sets of the same four hex values —
      // `AppPalette.darkSurface` and `AppSemanticColors.dark.backgroundPrimary`
      // were both 0xFF050214, both fed this same ThemeData, and nothing linked
      // them. Editing one would have left Material's own widgets painting a
      // different background from every widget reading the token, with no
      // failure anywhere. §4 rule 2.
      for (final entry in {
        AppTheme.dark(): AppSemanticColors.dark,
        AppTheme.light(): AppSemanticColors.light,
      }.entries) {
        final scheme = entry.key.colorScheme;
        final tokens = entry.value;
        t.takeException();
        expect(scheme.surface, tokens.backgroundPrimary);
        expect(scheme.onSurface, tokens.textPrimary);
        // `colorScheme.error` is the one a stock Material widget reaches for.
        // Left seed-derived it was a different red from the measured `danger`,
        // so the same meaning painted two colours depending on which widget
        // drew it.
        expect(scheme.error, tokens.danger);
        expect(scheme.outline, tokens.outline);
      }
    });

    test('the palette no longer carries semantic values', () {
      // A guard against re-introducing the duplicate. `AppPalette` is for raw
      // brand values with no semantic role; the moment a "surface" or
      // "onSurface" reappears there, the two sources can drift again.
      final src = File('lib/core/theme/app_palette.dart').readAsStringSync();
      for (final gone in const [
        'lightSurface =',
        'darkSurface =',
        'lightOnSurface =',
        'darkOnSurface =',
      ]) {
        expect(src, isNot(contains(gone)), reason: gone);
      }
    });

    testWidgets('context.colors resolves through the real theme', (t) async {
      late AppSemanticColors seen;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(builder: (c) {
          seen = c.colors;
          return const SizedBox();
        }),
      ));
      // GoogleFonts still reports asynchronously even with fetching off.
      t.takeException();
      expect(seen.textPrimary, AppSemanticColors.dark.textPrimary);
    });
  });

  group('lerp', () {
    test('t=0 and t=1 are the endpoints', () {
      final a = AppSemanticColors.dark;
      final b = AppSemanticColors.light;
      expect(a.lerp(b, 0).textPrimary, a.textPrimary);
      expect(a.lerp(b, 1).textPrimary, b.textPrimary);
    });

    test('a foreign extension leaves it alone rather than throwing', () {
      // `ThemeData.lerp` hands over whatever extension shares the key; being
      // defensive here is cheaper than a crash mid-animation.
      final a = AppSemanticColors.dark;
      expect(a.lerp(null, 0.5), same(a));
    });

    test('copyWith changes one token and keeps nineteen', () {
      const red = Color(0xFFFF0000);
      final c = AppSemanticColors.dark.copyWith(danger: red);
      expect(c.danger, red);
      expect(c.textPrimary, AppSemanticColors.dark.textPrimary);
      expect(c.onGradient, AppSemanticColors.dark.onGradient);
      expect(c.poseError, AppSemanticColors.dark.poseError);
    });
  });
}
