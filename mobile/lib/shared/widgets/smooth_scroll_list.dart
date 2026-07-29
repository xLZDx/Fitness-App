import 'package:flutter/material.dart';

/// A padded, bouncing vertical list used for the app's main scrolling pages.
///
/// This replaces `ScrollDimList`, which blurred and dimmed every card except
/// the one nearest the viewport centre while the user was scrolling. That
/// effect cost, per frame of every scroll:
///
///   * an `ImageFiltered` gaussian blur per off-centre card,
///   * an `Opacity` layer per off-centre card,
///   * two `Transform`s per off-centre card, and
///   * a `localToGlobal` sweep over every card on every scroll tick, each
///     focus change calling `setState` on the whole list.
///
/// On top of the per-card `BackdropFilter` that `GlassCard` used to apply, a
/// scroll on the workout page was compositing roughly thirty blur/layer passes
/// a frame. The effect was decoration; the cost was the whole frame budget, so
/// the effect is gone.
///
/// Kept as a named widget rather than raw `ListView` so the padding and physics
/// stay consistent across pages and there is one place to change them.
class SmoothScrollList extends StatelessWidget {
  const SmoothScrollList({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.physics,
    this.controller,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding,
      physics: physics ??
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      itemCount: children.length,
      // Builder rather than a plain ListView so off-screen rows are not built
      // or laid out — the pages that use this are long.
      itemBuilder: (context, i) => children[i],
    );
  }
}
