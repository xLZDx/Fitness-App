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

  /// Body and heading text. Dark 17.73:1, light 14.98:1.
  final Color textPrimary;

  /// Supporting text. Dark 8.64:1, light 4.55:1 — both clear AA, and they are
  /// **different alphas** (0.70 dark, 0.60 light) because the same alpha does
  /// not produce the same contrast against two different backgrounds.
  final Color textSecondary;

  /// Text of an inactive control. Dark 3.12:1, light 2.38:1.
  ///
  /// Below AA on purpose: WCAG 1.4.3 exempts inactive components, and a
  /// disabled control that reads as strongly as an enabled one is a worse
  /// failure than a low ratio — it invites taps that do nothing.
  final Color textDisabled;

  /// The brand accent, per theme. Dark #8A5BFF at 4.90:1; light #5A25D0 at
  /// 6.49:1 — **not** the same colour, because #8A5BFF on the light background
  /// is 3.37:1 and fails.
  final Color accentPrimary;

  /// The secondary accent. Dark 7.99:1, light 4.57:1.
  final Color accentSecondary;

  /// Content placed on [accentPrimary] or [accentSecondary] as a solid fill.
  ///
  /// Flips between themes for the same reason the accents do: the dark theme's
  /// accents are bright, so content on them must be ink (4.71:1 worst case);
  /// the light theme's accents are deep, so content on them is white (5.67:1
  /// worst case).
  final Color onAccent;

  /// Content placed on an `AppPalette.tileGradients` tile.
  ///
  /// Separate from [onAccent] because the gradients are the **same in both
  /// themes** — they are brand artwork, not a theme surface — so what sits on
  /// them cannot flip. Ink scores 4.44–11.57 across the ten stops and white
  /// scores 1.27–2.56, i.e. white fails on every one of them. The 109
  /// `Colors.white` uses in feature code are that failure.
  final Color onGradient;

  /// Dark 12.77:1, light 5.20:1.
  final Color success;

  /// Dark 11.70:1, light 5.05:1.
  final Color warning;

  /// Dark 6.77:1, light 4.76:1.
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
  static const dark = AppSemanticColors(
    backgroundPrimary: Color(0xFF050214),
    backgroundSecondary: Color(0xFF0C0725),
    surfacePrimary: Color(0x38FFFFFF), // white @ 0.22
    surfaceElevated: Color(0xFF1E1B2C), // white @ 0.10 flattened onto the bg
    surfaceInteractive: Color(0x1FFFFFFF), // white @ 0.12
    textPrimary: Color(0xFFF1ECFF),
    textSecondary: Color(0xFFAAA6B8),
    textDisabled: Color(0xFF5F5B6D),
    accentPrimary: Color(0xFF8A5BFF),
    accentSecondary: Color(0xFFFF6FB5),
    onAccent: Color(0xFF0B0918),
    onGradient: Color(0xFF0B0918),
    success: Color(0xFF2BE5C2),
    warning: Color(0xFFFFB37C),
    danger: Color(0xFFFF5A6E),
    outline: Color(0x2EFFFFFF), // white @ 0.18
    cameraOverlay: Color(0x73000000), // black @ 0.45
    poseCorrect: Color(0xFF2BE5C2),
    poseWarning: Color(0xFFFFB37C),
    poseError: Color(0xFFFF5A6E),
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
    onGradient: Color(0xFF0B0918),
    success: Color(0xFF0B6B58),
    warning: Color(0xFF9A4A05),
    danger: Color(0xFFC0243C),
    outline: Color(0x24131027), // ink @ 0.14
    cameraOverlay: Color(0x73000000),
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
