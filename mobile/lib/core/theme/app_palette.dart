import 'package:flutter/material.dart';

class AppPalette {
  static const auroraPink = Color(0xFFFF6FB5);
  static const auroraViolet = Color(0xFF8A5BFF);
  static const auroraBlue = Color(0xFF3DC8FF);
  static const auroraTeal = Color(0xFF2BE5C2);
  /// R9: corrected 2026-08-08 from `0xFFC2F562`. The audit's first pass
  /// (`FIGMA_MAKE_REFACTOR_AUDIT_2026-08-05.md` §11.2) measured that value
  /// from a compressed 800x675 thumbnail, which is not evidence; the real
  /// design token, confirmed against `index.css` and the prototype's own
  /// `TOKEN_COLORS` table, is `0xFFC9FF47`. This is also the R9 seed --
  /// `app_theme.dart` reads it for the dark theme's `ColorScheme.fromSeed`.
  static const auroraLime = Color(0xFFC9FF47);

  /// R9: second stop for the brand gradient (login/splash/onboarding CTAs),
  /// paired with [auroraLime]. The design's own `TOKEN_COLORS.accentSecondary`
  /// -- declared but never actually used anywhere in the 5471-line prototype
  /// (`App.tsx`), so this is the best-evidenced value for a second lime tone,
  /// not an invented one. Same value as `AppSemanticColors.dark.accentSecondary`;
  /// duplicated here rather than referenced because this file holds
  /// theme-independent literals and that token is theme-scoped.
  static const auroraLimeDeep = Color(0xFFA8D93A);

  static const auroraPeach = Color(0xFFFFB37C);

  static const tileGradients = <List<Color>>[
    [Color(0xFFFF7AC6), Color(0xFFFFB37C)],
    [Color(0xFF7B6CFF), Color(0xFF3DC8FF)],
    [Color(0xFF2BE5C2), Color(0xFFC2F562)],
    [Color(0xFFFF9F6B), Color(0xFFFFD93D)],
    [Color(0xFF8A5BFF), Color(0xFFFF6FB5)],
  ];

  // `lightSurface` / `darkSurface` / `lightOnSurface` / `darkOnSurface` used to
  // live here. They were byte-identical duplicates of
  // `AppSemanticColors.{light,dark}.backgroundPrimary` and `.textPrimary`, with
  // no link between the two — and both fed the same `ThemeData`, so editing one
  // would have left them silently disagreeing. Deleted rather than made to
  // reference the tokens, because a constant whose only job is to forward
  // another constant is one more place to look.
  //
  // What belongs in THIS file: raw brand values with no semantic role — the
  // aurora hues and the tile gradients above. What a colour MEANS lives in
  // `app_semantic_colors.dart`.
}
