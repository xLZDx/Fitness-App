import 'package:flutter/material.dart';

/// A soft, dimensional backdrop in the same palette as the rest of the app.
/// Built from three layers:
///   1. A vertical base gradient (top → bottom flow of the aurora colors).
///   2. A wide radial bloom in the upper-left, in the pink/violet family.
///   3. A wide radial bloom in the lower-right, in the teal/blue family.
/// Every layer is fully static — the background does not animate.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  static const _lightBase = <Color>[
    Color(0xFFFFD8E8), // pink
    Color(0xFFEFD9FF), // lavender
    Color(0xFFFFE6D2), // peach
    Color(0xFFD0EFE8), // mint
    Color(0xFFCEE2F2), // soft blue
  ];

  /// R9 (2026-08-08): this file has its own private palette, independent of
  /// `AppSemanticColors` -- it was not touched by the token-level R9 commit
  /// (`112ee5b`) and kept painting the pre-R9 violet/blue dark scheme behind
  /// EVERY screen (`main.dart:577` wraps the whole app in this widget once).
  /// Retuned to the lime family confirmed for R9 rather than reusing the old
  /// violet/blue hues: the design source (`App.tsx:1234-1236`, Step0) shows a
  /// near-flat `#06060F` background with a single restrained lime glow, not a
  /// colourful multi-hue wash, so the base gradient stays close to the two
  /// confirmed background tones ([AppSemanticColors.dark]'s
  /// backgroundPrimary/backgroundSecondary) and only the two blooms carry
  /// colour -- the primary lime accent and its documented secondary shade.
  static const _darkBase = <Color>[
    Color(0xFF06060F),
    Color(0xFF08080F),
    Color(0xFF0A0A14),
    Color(0xFF08080F),
    Color(0xFF06060F),
  ];

  static const _lightBloomA = Color(0xFFFF6FB5);
  static const _lightBloomB = Color(0xFF2BE5C2);
  static const _darkBloomA = Color(0xFFC9FF47); // accentPrimary
  static const _darkBloomB = Color(0xFFA8D93A); // accentSecondary

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark ? _darkBase : _lightBase,
                stops: const [0.0, 0.30, 0.55, 0.78, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.4, -0.85),
                radius: 1.1,
                colors: [
                  (isDark ? _darkBloomA : _lightBloomA)
                      .withValues(alpha: isDark ? 0.34 : 0.42),
                  (isDark ? _darkBloomA : _lightBloomA)
                      .withValues(alpha: 0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.9, 0.95),
                radius: 1.2,
                colors: [
                  (isDark ? _darkBloomB : _lightBloomB)
                      .withValues(alpha: isDark ? 0.30 : 0.36),
                  (isDark ? _darkBloomB : _lightBloomB)
                      .withValues(alpha: 0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
