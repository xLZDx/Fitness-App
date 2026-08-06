import 'package:flutter/material.dart';

class AppPalette {
  static const auroraPink = Color(0xFFFF6FB5);
  static const auroraViolet = Color(0xFF8A5BFF);
  static const auroraBlue = Color(0xFF3DC8FF);
  static const auroraTeal = Color(0xFF2BE5C2);
  static const auroraLime = Color(0xFFC2F562);
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
