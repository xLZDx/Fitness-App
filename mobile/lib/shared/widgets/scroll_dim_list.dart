import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A vertical list where, while the user is actively scrolling, every card
/// except the one closest to the viewport center is blurred and dimmed.
/// As soon as the user releases (scroll settles) every card animates back
/// to full clarity. Cards keep their natural heights — no fixed itemExtent.
class ScrollDimList extends StatefulWidget {
  const ScrollDimList({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.physics,
    this.dimOpacity = 0.40,
    this.dimScale = 0.96,
    this.dimBlur = 7,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;

  /// Opacity applied to non-focused cards while scrolling (1.0 = unchanged).
  final double dimOpacity;

  /// Scale applied to non-focused cards while scrolling (1.0 = unchanged).
  final double dimScale;

  /// Blur sigma applied to non-focused cards while scrolling (0 = unchanged).
  final double dimBlur;

  @override
  State<ScrollDimList> createState() => _ScrollDimListState();
}

class _ScrollDimListState extends State<ScrollDimList> {
  late final ScrollController _ctrl;
  late List<GlobalKey> _keys;
  int? _focused;
  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    _ctrl = ScrollController()..addListener(_recomputeFocus);
    _keys = List.generate(widget.children.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(covariant ScrollDimList old) {
    super.didUpdateWidget(old);
    if (widget.children.length != old.children.length) {
      _keys = List.generate(widget.children.length, (_) => GlobalKey());
      _focused = null;
    }
  }

  @override
  void dispose() {
    _ctrl
      ..removeListener(_recomputeFocus)
      ..dispose();
    super.dispose();
  }

  void _recomputeFocus() {
    if (!_ctrl.hasClients) return;
    final selfBox = context.findRenderObject() as RenderBox?;
    if (selfBox == null || !selfBox.hasSize) return;
    final viewportTop = selfBox.localToGlobal(Offset.zero).dy;
    final viewportCenter =
        viewportTop + _ctrl.position.viewportDimension / 2;

    int? best;
    double bestDistance = double.infinity;
    for (var i = 0; i < _keys.length; i++) {
      final ctx = _keys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final cardCenter =
          box.localToGlobal(Offset.zero).dy + box.size.height / 2;
      final dist = (cardCenter - viewportCenter).abs();
      if (dist < bestDistance) {
        bestDistance = dist;
        best = i;
      }
    }
    if (best != _focused) setState(() => _focused = best);
  }

  bool _onNotification(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _recomputeFocus();
      if (!_scrolling) setState(() => _scrolling = true);
    } else if (n is ScrollEndNotification) {
      if (_scrolling) setState(() => _scrolling = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: ListView.builder(
        controller: _ctrl,
        padding: widget.padding,
        physics: widget.physics ??
            const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
        itemCount: widget.children.length,
        itemBuilder: (context, i) {
          final dim = _scrolling && _focused != null && _focused != i;
          return KeyedSubtree(
            key: _keys[i],
            child: _DimWrap(
              dim: dim,
              dimOpacity: widget.dimOpacity,
              dimScale: widget.dimScale,
              dimBlur: widget.dimBlur,
              child: widget.children[i],
            ),
          );
        },
      ),
    );
  }
}

class _DimWrap extends StatelessWidget {
  const _DimWrap({
    required this.dim,
    required this.dimOpacity,
    required this.dimScale,
    required this.dimBlur,
    required this.child,
  });

  final bool dim;
  final double dimOpacity;
  final double dimScale;
  final double dimBlur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: dim ? 1.0 : 0.0),
      child: child,
      builder: (context, t, child) {
        if (t == 0) return child!;
        return Opacity(
          opacity: 1.0 - t * (1.0 - dimOpacity),
          child: Transform.translate(
            offset: Offset(0, -t * 4),
            child: Transform.scale(
              scale: 1.0 - t * (1.0 - dimScale),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: t * dimBlur,
                  sigmaY: t * dimBlur,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
