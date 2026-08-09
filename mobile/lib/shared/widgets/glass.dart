import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/theme/app_semantic_colors.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 26,
    this.blurSigma = 28,
    this.blur = false,
    this.floating = false,
    this.tint,
    this.gradient,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blurSigma;

  /// Whether to actually frost the backdrop.
  ///
  /// **Off by default, deliberately.** `BackdropFilter` is one of the most
  /// expensive things a Flutter frame can contain: it reads back the composited
  /// backdrop, blurs it, and cannot be cached. Cards used to switch it on
  /// unconditionally, so the workout page carried 11 of them and the home page
  /// 7 — measured, not guessed — on top of the app bar's and nav bar's. That is
  /// what made scrolling crawl.
  ///
  /// The fill is opaque enough to read as a surface without it. Reserve `true`
  /// for chrome that sits over moving content and does not repeat, i.e. the
  /// app bar and nav bar.
  final bool blur;

  /// Whether this card floats over content it does not control.
  ///
  /// A card inside a page sits on the app's own background, so a fill of white
  /// at 0.22 reads as a surface. A bottom sheet sits on WHATEVER was on screen
  /// when it opened, and at that opacity the page shows straight through it:
  /// the operator's day-3 donation sheet rendered its heading directly on top
  /// of "Восстановление за сегодня", "Шаги 834" and a stats row, and none of
  /// the three was readable. *"поздравление с 3 днем просто наезжает и не
  /// читается"*.
  ///
  /// The barrier behind the sheet was not the problem and darkening it further
  /// would not have fixed it — text over dimmed text is still text over text.
  /// A sheet needs to be a surface, not a tint.
  final bool floating;

  final Color? tint;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Ф1c: flat opaque surface, not translucent white.
    //
    // The prototype's own design-system page is explicit about where glass is
    // allowed — camera overlays, floating controls, modal sheets, temporary
    // status overlays — and lists three things it must NOT be used on:
    // "Scrolling cards", "Exercise list items", "Regular surfaces". This
    // widget is all three, on 175 call sites across 43 files, and it was
    // painting white at 0.22 over the background on every one of them.
    //
    // Translucency is also what made the surface colour unstable: white over
    // an olive-tinted backdrop is a different colour than white over black,
    // so the "same" card read differently on every screen. An opaque token
    // is the same card everywhere.
    //
    // `tint` and `gradient` are still honoured — a caller that asks for a
    // specific fill (the programme cards' coloured headers) gets it. What
    // changed is the default.
    // Read the extension without the `!` that `theme.colors` uses.
    //
    // `GlassCard` is a shared presentational widget: it is pumped inside a
    // stock `MaterialApp` by six of its own tests, by widget previews, and by
    // anything else that does not install the app's theme. The first version
    // of this change used `theme.colors`, whose getter ends in
    // `extension<AppSemanticColors>()!` — so under a bare MaterialApp the
    // widget threw before it built anything, and the tests that failed were
    // not the colour assertions but "renders its child" and "invokes onTap".
    // A card that cannot render outside one specific ThemeData is a worse
    // card, regardless of how it is coloured.
    final tokens = theme.extension<AppSemanticColors>();
    final surfaceColor = tint ??
        tokens?.surfaceElevated ??
        theme.colorScheme.surfaceContainerHighest;
    final borderColor = (tokens?.outline ?? theme.colorScheme.outline)
        .withValues(alpha: isDark ? 0.10 : 0.14);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? surfaceColor : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        // The design separates a card from the page with a hairline, not with
        // a brightness step — at #06060F there is very little room below the
        // surface colour to step down into.
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        // `InkWell` gives a ripple and no semantics, so every tappable card in
        // the app announced itself to a screen reader as plain content. One
        // shared widget, so one flag fixes all of them; and `button` is
        // conditional because a GlassCard without `onTap` is genuinely not a
        // button and claiming otherwise is the opposite error.
        child: Semantics(
          button: onTap != null,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(borderRadius),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );

    if (blur) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.07),
            blurRadius: 36,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: surface,
      ),
    );
  }
}

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: AppBar(
          backgroundColor: Colors.white.withValues(alpha: isDark ? 0.04 : 0.16),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          title: Text(title),
          actions: actions,
        ),
      ),
    );
  }
}

class FrostedScaffold extends StatelessWidget {
  const FrostedScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.extendBody = true,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final bool extendBody;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: extendBody,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: body,
    );
  }
}
