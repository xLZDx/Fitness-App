import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  // Inter is bundled now, so building a theme reaches nothing. This used to
  // need `GoogleFonts.config.allowRuntimeFetching = false`, or a machine with
  // no network failed these for a reason that had nothing to do with colour.

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

      test('onGradient clears AA on every aurora hue too', () {
        // The tile stops are not the whole of the artwork. G1.2b measured the
        // gradients actually painted in feature code and found 79 of 81
        // resolvable stops failing with white — because every aurora hue does,
        // not because the tile list does. A token that only cleared the ten
        // tile stops would have left the other 69 call sites unfixed.
        for (final hue in const {
          'auroraPink': AppPalette.auroraPink,
          'auroraViolet': AppPalette.auroraViolet,
          'auroraBlue': AppPalette.auroraBlue,
          'auroraTeal': AppPalette.auroraTeal,
          'auroraLime': AppPalette.auroraLime,
          'auroraPeach': AppPalette.auroraPeach,
        }.entries) {
          expect(contrast(t.onGradient, hue.value), greaterThanOrEqualTo(4.5),
              reason: 'onGradient on ${hue.key}');
        }
      });

      test('programme-card tags clear AA on every goal wash', () {
        // Bug 6 moved the programme header from a full-strength aurora ramp to
        // a per-goal wash at the prototype's own 0.20 alpha. That changed what
        // the tags sit on, so the pairing had to be re-measured rather than
        // assumed: the old white-pill-plus-`onGradientInk` scored 4.36 and 4.44
        // on two of the five hues. This is the replacement, and it is here so
        // adding a sixth goal cannot quietly reintroduce the problem.
        final card = flatten(t.surfacePrimary, bg);
        for (final hue in const {
          'strength': AppPalette.programmeStrength,
          'muscle': AppPalette.programmeMuscle,
          'form': AppPalette.programmeForm,
          'weightLoss': AppPalette.programmeWeightLoss,
          'comeback': AppPalette.programmeComeback,
        }.entries) {
          final wash =
              Color.alphaBlend(hue.value.withValues(alpha: 0.20), card);
          expect(contrast(t.textPrimary, wash), greaterThanOrEqualTo(4.5),
              reason: 'tag text on the ${hue.key} wash');
        }
      });

      test('the ink cannot be made translucent and stay legible', () {
        // Three call sites carried `Colors.white.withValues(alpha: 0.80..0.85)`
        // for secondary text. Reproducing that hierarchy with a translucent ink
        // does not work: on the violet stop it is already under the bar at 0.90.
        // Those lines went to full opacity and now lean on size and weight.
        Color atAlpha(double a, Color bg) =>
            Color.alphaBlend(t.onGradient.withValues(alpha: a), bg);
        const violet = Color(0xFF8A5BFF);
        expect(contrast(atAlpha(1.0, violet), violet),
            greaterThanOrEqualTo(4.5));
        expect(contrast(atAlpha(0.90, violet), violet), lessThan(4.5));
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
    // Still `testWidgets` rather than `test`: these realise a theme through a
    // pump, which is what the surrounding group asserts against. The
    // `takeException` calls that used to sit here were consuming GoogleFonts'
    // asynchronous download failure and are gone with it — a bare
    // `takeException` left behind would silently swallow a real error.
    testWidgets('both themes carry the extension', (t) async {
      final dark = AppTheme.dark();
      final light = AppTheme.light();
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

    test('both configurations are defined from onGradientInk', () {
      // The const exists so ~50 `const Icon(...)` call sites stay const. That
      // is only safe while it IS the token — if a future edit gives the two
      // themes different inks, this is the assertion that has to be deleted
      // first, and the deleter is the person who will find the const.
      expect(AppSemanticColors.dark.onGradient,
          same(AppSemanticColors.onGradientInk));
      expect(AppSemanticColors.light.onGradient,
          same(AppSemanticColors.onGradientInk));
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
      expect(seen.textPrimary, AppSemanticColors.dark.textPrimary);
    });
  });

  test('textSecondary beats the alphas G1.2c replaced, where it had to', () {
    // The sweep collapsed six alphas of `onSurface` into one token, so the
    // question it has to answer is not "is the token legible" — the group above
    // asserts that — but "did any site get WORSE, and did the failing ones get
    // better".
    //
    // Both answers come from the card surface, not the page background: this
    // text sits on cards, and measuring it against the page was what made an
    // earlier reading of this change look like a regression.
    for (final entry in {
      'dark': AppSemanticColors.dark,
      'light': AppSemanticColors.light,
    }.entries) {
      final t = entry.value;
      final card = flatten(t.surfacePrimary, t.backgroundPrimary);
      final token = contrast(t.textSecondary, card);

      // 0.55 was 19 of the 111 sites, and it failed on BOTH themes once
      // composited onto a card — 4.15 dark, 4.08 light. That is what this gate
      // set out to fix.
      final worst =
          contrast(flatten(t.textPrimary.withValues(alpha: 0.55), card), card);
      expect(worst, lessThan(4.5), reason: '${entry.key}: 0.55 was failing');
      expect(token, greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: and the token is not');

      // The other end: 0.85 was MORE contrasty than the token, so those sites
      // lose some. Passing is the bar, and they still clear it — but if a
      // future token edit drops textSecondary below AA on a card, these are the
      // ninety-odd sites that would go with it.
      final best =
          contrast(flatten(t.textPrimary.withValues(alpha: 0.85), card), card);
      expect(best, greaterThan(token),
          reason: '${entry.key}: 0.85 really was the brighter end');
    }
  });

  test('the hardcoded whites that survived G1.2b stay accounted for', () {
    // A tripwire, not a proof. G1.2b replaced 69 `Colors.white` uses that sat
    // on brand artwork; 43 remain, and each was left deliberately:
    //
    //   * a scrim foreground — white on `Colors.black @0.30..0.65`, which is
    //     correct and is the majority of `form_check_page.dart`'s fifteen;
    //   * a translucent white used as a SURFACE (`color:` / `fillColor:` at
    //     alpha 0.18–0.55), which is a surface-token question, not a
    //     foreground one;
    //   * `exercise_thumb.dart`'s white bed under a poster, which exists so
    //     the letterboxing on a clip rendered on flat white stays invisible.
    //
    // The fourth category is gone: three spinners inside buttons were painted
    // white regardless of the button's own foreground — one of them directly
    // contradicting a `foregroundColor: onError` two lines above it — and now
    // read that foreground instead.
    //
    // If this number moves, one of those categories grew — or a foreground
    // white came back onto a gradient. Read the diff before repinning it.
    //
    // 43 -> 44, 2026-08-08: the first category grew by one. The workout
    // player's failure note gained a second line carrying the platform's own
    // error text, on the same `Colors.black @0.62` scrim as the headline
    // directly above it, because the note used to announce "Нет сети" for
    // every failure including ones on a 1 Gb connection. Diff read: scrim
    // foreground, sanctioned category, not a foreground white on a gradient.
    //
    // 44 -> 45, 2026-08-08 (R8): `_RepCountNotTrackedBadge` in
    // `form_check_page.dart` -- `Colors.white70` on `Colors.black @0.45`,
    // the same corner the rep-count badge occupies and the same scrim
    // pattern as that badge's own phase text. Sanctioned category, same
    // file's count moving 15 -> 16.
    //
    // 45 -> 51, 2026-08-08 (R10): `posture_page.dart` is a new screen that
    // reuses Form Check's own camera-preview scrim wholesale (start/loading
    // spinners, the `_StartFailure` retry text, a dim placeholder icon) plus
    // one new band of its own (`_CaptureBand`'s "hold still" text on
    // `Colors.black @0.55`, the same shape as the capture band it visually
    // extends). All six are the scrim-foreground category, none are a
    // foreground white on a gradient.
    //
    // 51 -> 55, 2026-08-08 (R11d): the two immersive headers. Three in
    // `exercise_reference.dart` -- the white bed under a poster (the SAME
    // third category `exercise_thumb.dart` already occupies, for the same
    // reason: the clips are rendered on flat white) plus the back icon and
    // the muscle chip's text, both on `AppSemanticColors.cameraOverlay`,
    // which is theme-invariant by its own contract, so a theme-reactive
    // foreground would be wrong in one theme. One in
    // `equipment_detail_page.dart` -- the same back icon on the same token.
    // Diff read: one bed, three scrim foregrounds, zero foreground whites on
    // a gradient.
    //
    // 55 -> 57, 2026-08-08 (R11c): `_ScanTopBar`'s title pill and its Live
    // label, both on `cameraOverlay` over a live camera frame -- the same
    // category and the same token as R11d's back buttons. Net zero from the
    // frame itself: `ScanFrame` took the outline's own `Colors.white` with it
    // when it replaced it, which is why `scan_frame.dart: 1` appears while
    // `scanner_page.dart` did not grow by the full amount.
    //
    // 57 -> 59, 2026-08-08 (R11h): `coach_readiness_band.dart`'s icon and its
    // instruction text, on `cameraOverlay` over the Form Coach's camera
    // preview -- the same category, the same token and the same screen family
    // as `form_check_page.dart`'s existing sixteen.
    //
    // 59 -> 62, 2026-08-09 (Gate P + R11e + R11i-Workouts): three new
    // translucent-white SURFACE backgrounds (category 2, alpha 0.28-0.32),
    // none a foreground white on a gradient. `workout_player_page.dart`'s
    // `_AddToProgrammeButton` and `_AddExerciseButton` are the exact same
    // `Colors.white.withValues(alpha: 0.32)` card background
    // `_ScheduleButton` already used on the same screen -- two more buttons
    // in the same family, not a new pattern. `workouts_page.dart`'s
    // `_TemplateChip` is `Colors.white.withValues(alpha: 0.28)` behind
    // `AppSemanticColors.onGradientInk` text on a programme card's gradient
    // header -- the surface the chip sits ON, not the text drawn on it.
    final whites = <String, int>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final n = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .fold<int>(
              0,
              (a, l) =>
                  a + RegExp(r'Colors\.white[0-9]*').allMatches(l).length);
      if (n > 0) whites[f.path.replaceAll(r'\', '/')] = n;
    }
    //
    // 62 -> 61, 2026-08-09 (Ф1c): the first decrease this counter has ever
    // recorded. `glass.dart` lost `final base = tint ?? Colors.white` when the
    // card's default fill stopped being white-at-alpha and became a flat
    // opaque token, so category 2 — "a translucent white used as a SURFACE" —
    // shrank by the one line that was seeding it for all 175 call sites.
    // glass.dart 2 -> 1; the survivor is not a fill.
    //
    // Worth noting for whoever reads this next: a ratchet that only ever goes
    // up is measuring accumulation, not health. This is the direction the
    // token work was for.
    //
    // 61 -> 60, 2026-08-09 (Ф2): the second decrease, same category as the
    // first. `glass_nav_bar.dart` lost `Colors.white.withValues(alpha: 0.10)`
    // — the bar's translucent glass fill — when the bar became the design's
    // flat `backgroundSecondary`. glass_nav_bar.dart 1 -> 0; the two
    // `Colors.black` shadow lines in that file were never counted by this
    // regex and one of them survives on the Scan circle.
    //
    // 60 -> 59, 2026-08-12 (bug 6): the third decrease, and the first that was
    // forced by a contrast measurement rather than chosen. `workouts_page.dart`
    // lost `_TemplateChip`'s `Colors.white.withValues(alpha: 0.28)` pill. Once
    // the programme header stopped being a full-strength aurora ramp and became
    // the design's 0.20 -> 0.08 wash, `onGradientInk` on that pill measured
    // 4.36 (comeback) and 4.44 (strength) — under AA. The chip is outlined now,
    // with `textPrimary` straight on the wash at 7.51-9.28.
    // workouts_page.dart 2 -> 1; the survivor is `_ScheduleButton`'s 0.32 fill,
    // category 2, untouched.
    //
    // 59 -> 58, 2026-08-12 (O1): the fourth decrease. `onboarding_page.dart`
    // lost `_ProgressBar`'s `Colors.white.withValues(alpha: 0.30)` track when
    // the redesign's chrome moved into `ObProgressHeader`, whose track is the
    // `outline` token. onboarding_page.dart 1 -> 0. The header's own fill is
    // `surfaceInteractive`, so replacing the widget did not move the number
    // back up somewhere else — which is the failure this ratchet catches.
    //
    // 58 -> 59, 2026-08-13 (B6): an increase, and the first since 44. Category
    // one, the one this doc calls correct: the playback-rate pips moved off the
    // bottom of the clip, where they covered the movement, to a column down the
    // left edge, and the unselected pip's label is white on `cameraOverlay` —
    // the same token and the same treatment as `_ScrimChip` two hundred lines
    // above it in the same file. exercise_reference.dart +1.
    //
    // Deliberately NOT a new literal: the first draft of that widget carried
    // its own `Colors.black.withValues(alpha: 0.42)` scrim, which would have
    // been a second answer to a question this file had already answered twice.
    final total = whites.values.fold<int>(0, (a, b) => a + b);
    expect(total, 59, reason: 'per file: $whites');
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
