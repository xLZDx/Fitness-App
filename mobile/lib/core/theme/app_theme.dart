import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';
import 'app_semantic_colors.dart';

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? AppSemanticColors.dark : AppSemanticColors.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.auroraViolet,
      brightness: brightness,
      surface: isDark ? AppPalette.darkSurface : AppPalette.lightSurface,
      onSurface: isDark ? AppPalette.darkOnSurface : AppPalette.lightOnSurface,
    );

    final textTheme = GoogleFonts.interTextTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
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
      extensions: <ThemeExtension<dynamic>>[tokens],
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium:
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
          textStyle: GoogleFonts.inter(
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
          textStyle: GoogleFonts.inter(
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
