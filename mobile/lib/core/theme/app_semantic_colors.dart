/// The colours features are allowed to name, and what they mean.
///
/// ## Why a token layer at all
///
/// Measured 2026-08-06 across `lib/`: 197 direct `AppPalette.*` references,
/// 128 `Colors.white` / `Colors.black` references and 14 raw `Color(0x...)`
/// literals outside this directory. Every one of them is a decision made in a
/// feature widget about a value that belongs to the theme, and none of them can
/// react to brightness.
///
/// That is not only untidy. It is measurably wrong today:
///
/// * `Colors.white` on the aurora tile gradients scores between **1.27:1** and
///   **2.56:1** — the whole range fails WCAG AA (4.5:1) for text, and most of
///   it fails the 3:1 floor for icons. Dark ink on the same tiles scores
///   4.44–11.57. The app has 109 of these.
/// * `AppPalette.auroraViolet` on the light background is **3.37:1**. It is the
///   accent colour, it is used for text and icons, and on the light theme it
///   does not pass. The same colour on the dark background is 4.90:1, which is
///   why nobody noticed.
///
/// So the light theme cannot be reached by inverting anything: on the dark
/// background the palette's own bright accents already pass, and on the light
/// background they cannot. Master prompt §5 says this in one line — "Light and
/// dark modes must be separate semantic configurations rather than mechanical
/// colour inversion" — and the numbers above are why.
///
/// ## Every value here is measured, not chosen by eye
///
/// The ratio beside each token is WCAG 2.1 relative luminance against the
/// background of its own theme, computed rather than estimated. Two deliberate
/// exceptions, both stated where they occur: [textDisabled] (WCAG 1.4.3 exempts
/// inactive components) and the three pose colours (they sit on a live camera
/// frame whose colour nothing controls — see [poseCorrect]).
///
/// ## What this file does NOT do
///
/// It does not migrate anything. The 339 hardcoded references are still
/// hardcoded; this is the surface they move onto, and the move is its own gate
/// so that the diff which introduces the tokens and the diff which changes what
/// a screen looks like are never the same diff.
library;

import 'package:flutter/material.dart';

/// Semantic colour roles, resolved per brightness.
///
/// Read it as `Theme.of(context).extension<AppSemanticColors>()!` or, shorter,
/// `context.colors`.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surfacePrimary,
    required this.surfaceElevated,
    required this.surfaceInteractive,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.onAccent,
    required this.onGradient,
    required this.success,
    required this.warning,
    required this.danger,
    required this.outline,
    required this.cameraOverlay,
    required this.poseCorrect,
    required this.poseWarning,
    required this.poseError,
  });

  /// The page itself. `AuroraBackground` paints over it and the scaffold is
  /// transparent, so this is what shows where nothing else does.
  final Color backgroundPrimary;

  /// A second background plane — inset regions, sheet barriers, group headers.
  final Color backgroundSecondary;

  /// The translucent fill of a card sitting on the app's own background.
  ///
  /// Deliberately semi-transparent: the design is glass, and `GlassCard`
  /// composites this over whatever is behind it.
  final Color surfacePrimary;

  /// The **opaque** fill of something that floats over content it does not
  /// control — a bottom sheet, a dialog.
  ///
  /// Opaque on purpose, and this is a bug that already shipped: at card opacity
  /// a sheet let the page read straight through it, and the operator's day-3
  /// congratulation rendered on top of "Восстановление за сегодня" with neither
  /// legible. A sheet has to be a surface, not a tint.
  final Color surfaceElevated;

  /// Pressed / hovered / selected fill on top of a surface.
  final Color surfaceInteractive;

  /// Body and heading text. Dark 17.80:1 (R9, `#F0F0F8` on `#06060F`), light
  /// 14.98:1.
  final Color textPrimary;

  /// Supporting text. Dark 9.58:1 (R9, `#B1B1C6` on `#06060F` — 5.12:1 on the
  /// translucent card, which is the binding constraint; see the R9 class doc),
  /// light 4.55:1 — both clear AA. The dark and light values are no longer
  /// drawn from a shared alpha rule; each theme's hex is picked for its own
  /// background and surfaces.
  final Color textSecondary;

  /// Text of an inactive control. Dark 2.23:1 (R9, `#47475B` on `#06060F`),
  /// light 2.38:1.
  ///
  /// Below AA on purpose: WCAG 1.4.3 exempts inactive components, and a
  /// disabled control that reads as strongly as an enabled one is a worse
  /// failure than a low ratio — it invites taps that do nothing.
  final Color textDisabled;

  /// The brand accent, per theme. Dark `#C9FF47` at 17.18:1 (R9, lime on
  /// `#06060F`); light `#5A25D0` at 6.49:1 — **not** the same colour: the two
  /// themes were never going to share one hue (`#8A5BFF`, the pre-R9 dark
  /// accent, was already 3.37:1 on the light background and failed), and R9
  /// widens the gap further by design, not by accident.
  final Color accentPrimary;

  /// The secondary accent. Dark 12.16:1 (R9, `#A8D93A` on `#06060F` — the
  /// design's own documented-but-unused `accentSecondary` token; see the R9
  /// class doc), light 4.57:1.
  final Color accentSecondary;

  /// Content placed on [accentPrimary] or [accentSecondary] as a solid fill.
  ///
  /// Flips between themes for the same reason the accents do: the dark
  /// theme's accents are bright, so content on them must be ink (R9: 11.76:1
  /// worst case, `#060F00` on `#A8D93A`); the light theme's accents are deep,
  /// so content on them is white (5.67:1 worst case).
  final Color onAccent;

  /// Content placed on brand artwork — an `AppPalette.tileGradients` tile, an
  /// aurora gradient, or a solid aurora hue.
  ///
  /// Separate from [onAccent] because the artwork is the **same in both
  /// themes** — it is not a theme surface — so what sits on it cannot flip.
  ///
  /// Measured against all six aurora hues and all ten tile stops: ink scores
  /// 4.71 at worst, white scores 1.27–4.18 and so fails the 4.5:1 text bar on
  /// every single one, and the 3:1 non-text bar on thirteen of the sixteen.
  /// The `Colors.white` uses sitting on that artwork in feature code are that
  /// failure.
  final Color onGradient;

  /// The value of [onGradient], as a compile-time constant.
  ///
  /// Call sites want `const Icon(..., color: ...)`. Reading the token through
  /// `context.colors` would de-const roughly fifty widgets to express a value
  /// that, by the paragraph above, is the same in every theme — paying a
  /// rebuild cost for a choice that cannot vary.
  ///
  /// This is not a second source of truth: both configurations below are
  /// defined FROM it, and a test asserts they still are. The day the artwork
  /// stops being theme-invariant, that test is what has to be deleted first,
  /// and this constant is what the deleter will find.
  static const onGradientInk = Color(0xFF0B0918);

  /// Dark 12.39:1 (R9, `#22E87A` on `#06060F`), light 5.20:1.
  final Color success;

  /// Dark 10.62:1 (R9, `#FFAA33` on `#06060F`), light 5.05:1.
  final Color warning;

  /// Dark 6.29:1 (R9, `#FF4D70` on `#06060F`), light 4.76:1.
  final Color danger;

  /// Hairlines, card borders, dividers.
  final Color outline;

  /// The scrim between a camera preview and the controls drawn on it.
  ///
  /// Identical in both themes: a camera frame is not a theme surface, and
  /// lightening the scrim on the light theme would only make the controls
  /// harder to read against whatever the user happens to be pointing at.
  final Color cameraOverlay;

  /// Form-check skeleton segment: within tolerance.
  ///
  /// The three pose colours carry **no contrast guarantee**, and cannot: they
  /// are drawn over a live camera frame, whose colour is whatever the room is.
  /// Against mid-grey they score 2.46, 2.26 and 1.31. That is exactly why
  /// master prompt §18.10 requires "Do not rely on colour alone. Pair colour
  /// with icon and/or text semantics" — the shape and the cue text carry the
  /// meaning, and the colour only reinforces it.
  final Color poseCorrect;

  /// Form-check skeleton segment: borderline.
  final Color poseWarning;

  /// Form-check skeleton segment: out of tolerance.
  final Color poseError;

  /// The dark configuration — the app's shipping default.
  ///
  /// R9 (2026-08-08): recoloured from the violet palette to the design's
  /// lime-on-near-black scheme. Every value below traces to the Figma Make
  /// export (`xLZDx/ReviewExistingExamples`, commit `8209787`, `src/App.tsx`
  /// + `src/index.css`) — the app's own `C.*` constants and its
  /// `TOKEN_COLORS` documentation table — not chosen by eye, per this file's
  /// own header rule. Two categories of exception, both computed rather than
  /// copied, because the prototype's opaque `#141422` card does not match
  /// this app's translucent glass card: [surfaceElevated] is the prototype's
  /// `white @ 10%` flattened onto the NEW background (`Color.alphaBlend`,
  /// verified by `app_semantic_colors_test.dart`'s own contrast function),
  /// and [textSecondary]/[textDisabled] keep the prototype's hue but are
  /// lightened until they clear this app's actual contrast bars — the
  /// prototype's own `#888898` passes against its opaque card (`#141422`)
  /// but not against this app's lighter translucent one (`3.09:1` measured).
  /// `accentSecondary` has no single documented value in the source: the
  /// design's own `TOKEN_COLORS.accentSecondary` (`#A8D93A`) is declared but
  /// never actually used anywhere in the 5471-line prototype, and the
  /// recurring violets (`#7C3AED`/`#7C6AFF`) are muscle-group category tags,
  /// not a brand secondary — `#A8D93A` is used anyway, as the only value the
  /// design source states for this role, and flagged here rather than
  /// silently presented as equally solid evidence to the rest of the table.
  static const dark = AppSemanticColors(
    backgroundPrimary: Color(0xFF06060F),
    backgroundSecondary: Color(0xFF0D0D1A),
    surfacePrimary: Color(0x38FFFFFF), // white @ 0.22, unchanged mechanism
    surfaceElevated: Color(0xFF1F1F27), // white @ 0.10 flattened onto the new bg
    surfaceInteractive: Color(0x1FFFFFFF), // white @ 0.12, unchanged mechanism
    textPrimary: Color(0xFFF0F0F8),
    textSecondary: Color(0xFFB1B1C6), // hue of measured #888898, lightened for this app's card
    textDisabled: Color(0xFF47475B), // hue of measured #3E3E50, lightened into the (2.0,4.5) band
    accentPrimary: Color(0xFFC9FF47),
    accentSecondary: Color(0xFFA8D93A), // documented but unused in the source; see class doc
    onAccent: Color(0xFF060F00),
    onGradient: onGradientInk,
    success: Color(0xFF22E87A),
    warning: Color(0xFFFFAA33),
    danger: Color(0xFFFF4D70),
    outline: Color(0x21FFFFFF), // white @ 0.13, the source's stronger/interactive border tier
    cameraOverlay: Color(0x8C000000), // black @ 0.55, the source's documented cameraOverlay token
    poseCorrect: Color(0xFF22E87A),
    poseWarning: Color(0xFFFFAA33),
    poseError: Color(0xFFFF4D70),
  );

  /// The light configuration.
  ///
  /// Authored against the light background, not derived from [dark]. Six of the
  /// twenty tokens hold a different hue rather than a different lightness, and
  /// an inversion would have produced none of them.
  static const light = AppSemanticColors(
    backgroundPrimary: Color(0xFFEDE3F8),
    backgroundSecondary: Color(0xFFE3D7F2),
    surfacePrimary: Color(0xADFFFFFF), // white @ 0.68
    surfaceElevated: Color(0xFFF7F2FC), // white @ 0.55 flattened onto the bg
    surfaceInteractive: Color(0x14131027), // ink @ 0.08
    textPrimary: Color(0xFF131027),
    textSecondary: Color(0xFF6A647B),
    textDisabled: Color(0xFF9A93A9),
    accentPrimary: Color(0xFF5A25D0),
    accentSecondary: Color(0xFFC21E6E),
    onAccent: Color(0xFFFFFFFF),
    onGradient: onGradientInk,
    success: Color(0xFF0B6B58),
    warning: Color(0xFF9A4A05),
    danger: Color(0xFFC0243C),
    outline: Color(0x24131027), // ink @ 0.14
    // R9: kept in sync with dark's cameraOverlay -- theme-invariant by this
    // class's own contract (see the field doc + the "does not flip either"
    // test), so it moved to the design's documented 0.55 alongside dark's,
    // even though the rest of the light configuration is untouched (Q1/Q41
    // deferred).
    cameraOverlay: Color(0x8C000000),
    poseCorrect: Color(0xFF2BE5C2),
    poseWarning: Color(0xFFFFB37C),
    poseError: Color(0xFFFF5A6E),
  );

  @override
  AppSemanticColors copyWith({
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? surfacePrimary,
    Color? surfaceElevated,
    Color? surfaceInteractive,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? accentPrimary,
    Color? accentSecondary,
    Color? onAccent,
    Color? onGradient,
    Color? success,
    Color? warning,
    Color? danger,
    Color? outline,
    Color? cameraOverlay,
    Color? poseCorrect,
    Color? poseWarning,
    Color? poseError,
  }) =>
      AppSemanticColors(
        backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
        backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
        surfacePrimary: surfacePrimary ?? this.surfacePrimary,
        surfaceElevated: surfaceElevated ?? this.surfaceElevated,
        surfaceInteractive: surfaceInteractive ?? this.surfaceInteractive,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textDisabled: textDisabled ?? this.textDisabled,
        accentPrimary: accentPrimary ?? this.accentPrimary,
        accentSecondary: accentSecondary ?? this.accentSecondary,
        onAccent: onAccent ?? this.onAccent,
        onGradient: onGradient ?? this.onGradient,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        outline: outline ?? this.outline,
        cameraOverlay: cameraOverlay ?? this.cameraOverlay,
        poseCorrect: poseCorrect ?? this.poseCorrect,
        poseWarning: poseWarning ?? this.poseWarning,
        poseError: poseError ?? this.poseError,
      );

  /// Interpolates every token, so a light/dark switch animates rather than
  /// snapping. `Color.lerp` returns null only when both inputs are null, which
  /// cannot happen here — every field is non-nullable.
  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      backgroundPrimary:
          Color.lerp(backgroundPrimary, other.backgroundPrimary, t)!,
      backgroundSecondary:
          Color.lerp(backgroundSecondary, other.backgroundSecondary, t)!,
      surfacePrimary: Color.lerp(surfacePrimary, other.surfacePrimary, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceInteractive:
          Color.lerp(surfaceInteractive, other.surfaceInteractive, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      onGradient: Color.lerp(onGradient, other.onGradient, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      cameraOverlay: Color.lerp(cameraOverlay, other.cameraOverlay, t)!,
      poseCorrect: Color.lerp(poseCorrect, other.poseCorrect, t)!,
      poseWarning: Color.lerp(poseWarning, other.poseWarning, t)!,
      poseError: Color.lerp(poseError, other.poseError, t)!,
    );
  }
}

/// `context.colors.textSecondary` instead of
/// `Theme.of(context).extension<AppSemanticColors>()!.textSecondary`.
///
/// The `!` is safe because `AppTheme.light()` and `AppTheme.dark()` both
/// install the extension, and a widget tree without one of those is not this
/// app. A test that builds a bare `MaterialApp` will throw here — loudly, at
/// the first token read, rather than by silently painting a default.
extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get colors =>
      Theme.of(this).extension<AppSemanticColors>()!;
}

/// The same tokens, reached from a `ThemeData` that is already in hand.
///
/// Feature code overwhelmingly opens with `final theme = Theme.of(context)`
/// and then reads `theme.colorScheme.…`; 124 of the 128 `onSurface` uses did.
/// Without this those call sites would have to reach back through `context`
/// for a second `Theme.of` lookup they already performed — or be rewritten to
/// carry a `BuildContext` into helper methods that currently take a
/// `ThemeData` and have no need of one.
extension AppSemanticColorsThemeX on ThemeData {
  AppSemanticColors get colors => extension<AppSemanticColors>()!;
}
