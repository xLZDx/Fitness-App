import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 26,
    this.blurSigma = 28,
    this.blur = false,
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

  final Color? tint;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = tint ?? Colors.white;

    // Without the frost the fill carries the whole separation from the
    // background, so it runs more opaque than the blurred variant.
    final fill = gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: blur
              ? [
                  base.withValues(alpha: isDark ? 0.16 : 0.50),
                  base.withValues(alpha: isDark ? 0.06 : 0.28),
                ]
              : [
                  base.withValues(alpha: isDark ? 0.22 : 0.68),
                  base.withValues(alpha: isDark ? 0.12 : 0.46),
                ],
        );

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        gradient: fill,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(padding: padding, child: child),
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
