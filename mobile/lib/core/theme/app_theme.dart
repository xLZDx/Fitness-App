import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_semantic_colors.dart';
import 'hud_tokens.dart';

/// The two bundled families, declared in `pubspec.yaml` under `fonts:`.
///
/// Named constants rather than string literals at each of the eight use sites:
/// a typo in one of those is not an error, it is a silent fall back to the
/// platform font — the exact failure this gate removed by dropping
/// `google_fonts`' runtime download. `font_bundle_test.dart` pins both names
/// and every weight against what pubspec actually ships.
const String kBodyFont = 'Inter';
const String kDisplayFont = 'Barlow Condensed';

/// What sets a glyph [kDisplayFont] does not have — which, measured, is every
/// Cyrillic one. See the long note beside `display()` below.
const List<String> kDisplayFontFallback = <String>[kBodyFont];

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? AppSemanticColors.dark : AppSemanticColors.light;
    // Surface and onSurface come FROM the tokens rather than from a second set
    // of constants that happened to hold the same four hex values.
    //
    // They did, byte for byte, and nothing linked them: `AppPalette.darkSurface`
    // and `AppSemanticColors.dark.backgroundPrimary` were both `0xFF050214`,
    // both fed the same `ThemeData`, and an edit to either would have left
    // `ColorScheme.surface` and the token disagreeing with nothing to notice.
    // Master prompt §4 rule 2 — do not duplicate a source of truth. Found by
    // the architecture review, 2026-08-06.
    final scheme = ColorScheme.fromSeed(
      // R9 (2026-08-08): the dark theme reseeds to the design's lime accent.
      // Light stays on the pre-R9 violet seed -- Q1/Q41 deferred the light
      // theme ("dark first... light later behind a toggle"), and the design
      // source itself marks its own light palette "открыто" (open,
      // undecided; `App.tsx`'s `LC` block). A single shared seed would have
      // pulled light's Material-derived roles (colorScheme.primary etc.)
      // toward lime while AppSemanticColors.light kept its own violet
      // literals -- the exact two-sources-of-truth failure this token layer
      // exists to prevent, just moved one level down into the seed.
      seedColor: isDark ? AppPalette.auroraLime : AppPalette.auroraViolet,
      brightness: brightness,
      surface: tokens.backgroundPrimary,
      onSurface: tokens.textPrimary,
      // Material's seed-derived error tone is a different red from the one that
      // was measured against these backgrounds (dark 6.77:1, light 4.76:1). A
      // widget reading `colorScheme.error` and one reading `colors.danger`
      // would otherwise paint two different reds for the same meaning.
      error: tokens.danger,
      outline: tokens.outline,
    );

    // Was `GoogleFonts.interTextTheme()`, which returned Material's own
    // typography with Inter's family name attached. `Typography.material2021`
    // is where that geometry came from, so taking it directly and applying the
    // family keeps every size, weight and height identical while removing the
    // download.
    final base = isDark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final textTheme = base
        .apply(fontFamily: kBodyFont)
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    // The prototype runs two families, not one: Inter for reading, Barlow
    // Condensed for anything large — screen titles, stat numbers, the weight
    // and height readouts. `src/index.css` loads exactly these two and gives
    // the second its own class:
    //
    //   @import url('...family=Barlow+Condensed:wght@500..900&family=Inter:...')
    //   .font-display { font-family: 'Barlow Condensed'; letter-spacing: -0.01em; }
    //
    // The app shipped only `GoogleFonts.interTextTheme()`, so every heading
    // that the design draws in a tall condensed face was rendering in the
    // body font. That single omission is most of why the built screens read
    // as a different product from the prototype even after R9 matched the
    // palette.
    //
    // Condensed faces set narrower at the same point size, so the headline
    // sizes go up rather than staying put: matching the design's *presence*
    // means matching how much of the screen the word occupies, not the number
    // in the size field.
    // ## Barlow Condensed cannot set Russian, and Russian is the default
    //
    // Measured 2026-08-19 over every bundled face: `BarlowCondensed-*.ttf`
    // carries 525 glyphs and **none of them are Cyrillic** — 0 of 64 in
    // А–я, no Ё. Archivo, added for the HUD, is the same (653 glyphs,
    // latin/latin-ext/vietnamese per Google's own METADATA.pb). Inter carries
    // 2849 and covers Cyrillic completely.
    //
    // So every `display*`/`headline*` role — which is every large heading in
    // the app — has been rendering Russian in whatever the PLATFORM font
    // happens to be: a different face on every device, and exactly the silent
    // degradation this gate removed `google_fonts` to prevent. It was in the
    // bundle the whole time; nothing failed, because a missing glyph never
    // does.
    //
    // Naming the fallback does not change what a Russian heading looks like
    // today so much as make it the SAME everywhere, and puts the choice in the
    // repository instead of in the OS. Latin headings are unaffected — Barlow
    // Condensed still has those glyphs and still wins.
    TextStyle display(TextStyle? from, double size, FontWeight weight) =>
        (from ?? const TextStyle()).copyWith(
          fontFamily: kDisplayFont,
          fontFamilyFallback: kDisplayFontFallback,
          fontSize: size,
          fontWeight: weight,
          // CSS -0.01em, resolved against each size rather than copied as one
          // constant — tracking is proportional, and a single -0.8 that suits
          // a 32px title is heavy-handed on a 57px number.
          letterSpacing: size * -0.01,
          height: 1.05,
          color: scheme.onSurface,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // The semantic layer. Installed alongside `colorScheme` rather than
      // replacing it: Material's own widgets read the scheme, and taking it
      // away would restyle every stock control in the app in a gate that is
      // supposed to change nothing on screen.
      //
      // Nothing outside `lib/core/theme/` reads this yet — the migration of
      // the 339 hardcoded colour references is its own gate, precisely so the
      // diff that introduces the tokens and the diff that changes what a
      // screen looks like are never the same diff.
      // Two token layers, installed together and doing different jobs.
      //
      // `AppSemanticColors` answers "what colour is this role on the app's own
      // flat background" and serves every screen not yet on the HUD, plus every
      // Material control that reads `ColorScheme`. `HudTokens` answers a
      // question it cannot: what a surface floating over an arbitrary
      // PHOTOGRAPH is made of. Neither is a superset of the other, and merging
      // them would leave every existing token ambiguous about which surface it
      // describes. The HUD migration removes the first one screen at a time.
      extensions: <ThemeExtension<dynamic>>[
        tokens,
        isDark ? HudTokens.dark : HudTokens.light,
      ],
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      textTheme: textTheme.copyWith(
        // display*/headline* -> Barlow Condensed. title*/body*/label* stay
        // Inter: the design switches families by role, not by size, and a
        // condensed face is wrong for anything the user has to actually read
        // a paragraph of.
        displayLarge: display(textTheme.displayLarge, 57, FontWeight.w900),
        displayMedium: display(textTheme.displayMedium, 45, FontWeight.w900),
        displaySmall: display(textTheme.displaySmall, 36, FontWeight.w800),
        headlineLarge: display(textTheme.headlineLarge, 36, FontWeight.w800),
        headlineMedium: display(textTheme.headlineMedium, 30, FontWeight.w800),
        headlineSmall: display(textTheme.headlineSmall, 26, FontWeight.w700),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium:
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      // Bug 4 from the operator's screenshots: an enrolment failure showed a
      // cream snackbar with dark text over the dark theme, because nothing
      // here overrode Material's default. It inherits the app's own elevated
      // surface now, so it belongs to the same screen it appears on.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.surfaceElevated,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: tokens.textPrimary,
        ),
        actionTextColor: tokens.accentPrimary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: null,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontFamily: kBodyFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.18),
            width: 1.2,
          ),
          textStyle: const TextStyle(
            fontFamily: kBodyFont,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.onSurface.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeScalePageTransition(),
          TargetPlatform.iOS: _FadeScalePageTransition(),
        },
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

class _FadeScalePageTransition extends PageTransitionsBuilder {
  const _FadeScalePageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final scale = Tween<double>(begin: 0.985, end: 1.0).animate(fade);
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: scale, child: child),
    );
  }
}
