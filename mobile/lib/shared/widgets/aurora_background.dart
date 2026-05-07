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

  static const _darkBase = <Color>[
    Color(0xFF1A0830),
    Color(0xFF12103A),
    Color(0xFF1B0826),
    Color(0xFF0A1F30),
    Color(0xFF071626),
  ];

  static const _lightBloomA = Color(0xFFFF6FB5);
  static const _lightBloomB = Color(0xFF2BE5C2);
  static const _darkBloomA = Color(0xFF8A5BFF);
  static const _darkBloomB = Color(0xFF3DC8FF);

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
