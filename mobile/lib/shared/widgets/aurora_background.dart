import 'package:flutter/material.dart';

import '../../core/theme/app_semantic_colors.dart';

/// The app's page background: one flat fill, nothing else.
///
/// ## Why this is flat, and why the name did not change
///
/// The design's background is a single colour — `#06060F` — with no gradient
/// and no glow. `src/index.css` in the prototype export is one line about it:
///
///   html, body, #root { ... background: #06060F; }
///
/// This widget used to paint three layers over that: a five-stop vertical
/// gradient plus two wide radial blooms in the lime accent at 34% and 30%
/// alpha. On a phone the two blooms overlap across most of the screen, and
/// lime at a third opacity over near-black reads as olive — which is the
/// green haze the operator saw on every screen and the single largest reason
/// the built app did not look like the prototype.
///
/// R9 had already identified the target ("a near-flat #06060F background with
/// a single restrained lime glow" — its own comment, since removed with the
/// code it justified) and then kept the blooms anyway. Restraint at 34% alpha
/// across a whole screen is not restraint.
///
/// The class keeps its name. `AuroraBackground` is referenced from `main.dart`
/// and eight test files, and renaming it would put a ten-file sweep in the
/// same diff as a visual change — the exact coupling the design-token gate
/// was structured to avoid. The name is now inaccurate and that is a cleanup,
/// not a bug.
///
/// It stays a widget rather than becoming `scaffoldBackgroundColor` because
/// the app sets that to transparent on purpose: one wrapper is the single
/// place a future full-screen treatment (camera, onboarding hero) can be
/// introduced without editing every route.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Without the `!` in `theme.colors` — this widget is pumped under a stock
    // `MaterialApp` by its own tests and by every page test's harness, and a
    // background that throws when the app theme is absent takes the whole
    // page down with it. Same reason as `GlassCard`.
    final tokens = theme.extension<AppSemanticColors>();
    return ColoredBox(
      color: tokens?.backgroundPrimary ?? theme.colorScheme.surface,
      child: child,
    );
  }
}
