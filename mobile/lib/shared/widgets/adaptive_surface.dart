/// One component that places a transient surface (mode switcher, Record sheet,
/// Coming-later sheet, sign-out sheet) by the window size class (contract
/// 10.6, C-15; design 2.6).
///
/// ## Placement (class only, never the input device)
///
/// | Kind                       | Compact      | Medium             | Expanded                    |
/// |----------------------------|--------------|--------------------|-----------------------------|
/// | [AdaptiveSurfaceKind.anchored] | bottom sheet | bottom sheet 560 | popover 360 under the anchor |
/// | [AdaptiveSurfaceKind.dialog]   | bottom sheet | dialog 480       | dialog 480                  |
///
/// An anchored surface whose anchor is missing, unmounted or has no size
/// becomes a centred dialog of 360 dp instead of an unanchored floating box
/// (contract 10.6).
///
/// ## Every placement is one route (RV-9)
///
/// The surface is a single `PopupRoute`. Its page reads [WindowSizeInfo] live
/// in `build`, so a resize across a boundary re-places the SAME route (sheet,
/// popover or dialog) while it is open. The caller's content sits under one
/// `GlobalKey`, so its `State` (selection, scroll offset, focus) survives the
/// placement change. System Back, a scrim tap and Esc close the route; focus
/// goes to the surface on open and back to the opener on close.
///
/// ## Contract for the content builder
///
///  * It receives bounded constraints (a max width and a max height) and must
///    scroll itself when it can be taller than the surface; it is wrapped in a
///    `HudSheet` with ZERO padding and a transparent `Material`, so it lays out
///    its own padding.
///  * It should give its title `Semantics(header: true)` inside
///    `Focus(autofocus: true)` (the `cloud_consent_sheet.dart` precedent) so
///    first focus lands on the title.
///  * It must not show an indeterminate progress indicator (contract 12).
///
/// ## Open-surface depth
///
/// [openSurfaceDepthProvider] counts open surfaces so the shortcut layer can
/// stay silent beneath a modal. The counter is decremented in
/// `route.completed.whenComplete` inside try/finally, and it is reset when the
/// signed-in account changes (a late decrement from a previous generation is
/// ignored, so the counter can never go negative or leak).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hud_tokens.dart';
import '../../features/auth/state/auth_providers.dart';
import 'hud/hud_surface.dart';
import 'window_size.dart';

/// Which table row of contract 10.6 a surface follows.
enum AdaptiveSurfaceKind {
  /// Mode switcher S-3, Record sheet S-5: popover on Expanded.
  anchored,

  /// Coming-later sheet, sign-out sheet S-10, Day-3: dialog on Medium and up.
  dialog,
}

/// The form a surface currently takes.
enum AdaptiveSurfacePlacement { bottomSheet, popover, dialog }

/// Maximum widths of contract 10.6.
const double kAdaptiveSheetMaxWidth = 560;
const double kAdaptivePopoverWidth = 360;
const double kAdaptiveDialogMaxWidth = 480;

/// Pure placement rule. [hasAnchor] is true when the anchor is mounted, laid
/// out and visible. Exposed so the class table is unit-testable.
({AdaptiveSurfacePlacement placement, double maxWidth}) adaptiveSurfaceLayoutFor(
  WindowSizeClass sizeClass,
  AdaptiveSurfaceKind kind, {
  required bool hasAnchor,
}) {
  switch (sizeClass) {
    case WindowSizeClass.compact:
      return (
        placement: AdaptiveSurfacePlacement.bottomSheet,
        maxWidth: double.infinity,
      );
    case WindowSizeClass.medium:
      return kind == AdaptiveSurfaceKind.anchored
          ? (
              placement: AdaptiveSurfacePlacement.bottomSheet,
              maxWidth: kAdaptiveSheetMaxWidth,
            )
          : (
              placement: AdaptiveSurfacePlacement.dialog,
              maxWidth: kAdaptiveDialogMaxWidth,
            );
    case WindowSizeClass.expanded:
      if (kind == AdaptiveSurfaceKind.anchored) {
        return hasAnchor
            ? (
                placement: AdaptiveSurfacePlacement.popover,
                maxWidth: kAdaptivePopoverWidth,
              )
            : (
                placement: AdaptiveSurfacePlacement.dialog,
                maxWidth: kAdaptivePopoverWidth,
              );
      }
      return (
        placement: AdaptiveSurfacePlacement.dialog,
        maxWidth: kAdaptiveDialogMaxWidth,
      );
  }
}

/// Number of adaptive surfaces currently open. Reset to 0 when the signed-in
/// account changes.
final NotifierProvider<OpenSurfaceDepth, int> openSurfaceDepthProvider =
    NotifierProvider<OpenSurfaceDepth, int>(OpenSurfaceDepth.new);

class OpenSurfaceDepth extends Notifier<int> {
  int _generation = 0;

  @override
  int build() {
    // A new account (or sign-out) starts a new generation at depth 0.
    ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid));
    _generation++;
    return 0;
  }

  /// Registers an opened surface; returns the generation token for [closed].
  int opened() {
    state = state + 1;
    return _generation;
  }

  /// Registers a closed surface. A token from an earlier generation is
  /// ignored (the counter was already reset).
  void closed(int generation) {
    if (generation != _generation) return;
    state = state > 0 ? state - 1 : 0;
  }
}

class AdaptiveSurface {
  const AdaptiveSurface._();

  /// Opens [builder] as an adaptive surface and completes when it closes.
  ///
  /// [anchorKey] is the control the popover hangs under (for example
  /// `home.modeChip`); it is only read for [AdaptiveSurfaceKind.anchored].
  /// [semanticLabel] names the route for screen readers.
  static Future<T?> show<T>(
    BuildContext context,
    WidgetBuilder builder, {
    GlobalKey? anchorKey,
    AdaptiveSurfaceKind kind = AdaptiveSurfaceKind.anchored,
    String? semanticLabel,
  }) {
    final NavigatorState navigator =
        Navigator.of(context, rootNavigator: true);
    final FocusNode? opener = FocusManager.instance.primaryFocus;

    // Depth tracking needs a ProviderScope; without one the surface still
    // opens and simply is not counted.
    OpenSurfaceDepth? depth;
    int generation = 0;
    try {
      final ProviderContainer container =
          ProviderScope.containerOf(context, listen: false);
      depth = container.read(openSurfaceDepthProvider.notifier);
      generation = depth?.opened() ?? 0;
    } on StateError {
      depth = null;
    }

    final _AdaptiveSurfaceRoute<T> route = _AdaptiveSurfaceRoute<T>(
      builder: builder,
      anchorKey: anchorKey,
      kind: kind,
      semanticLabel: semanticLabel,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      capturedThemes:
          InheritedTheme.capture(from: context, to: navigator.context),
      reduceMotion: context.reduceMotion,
    );

    route.completed.whenComplete(() {
      try {
        // A disposed container (app teardown) is not an error worth surfacing.
        try {
          depth?.closed(generation);
        } on StateError {
          // Container already disposed: nothing left to count.
        }
      } finally {
        if (opener != null && opener.context != null && opener.canRequestFocus) {
          opener.requestFocus();
        }
      }
    });

    return navigator.push<T>(route);
  }
}

class _AdaptiveSurfaceRoute<T> extends PopupRoute<T> {
  _AdaptiveSurfaceRoute({
    required this.builder,
    required this.anchorKey,
    required this.kind,
    required this.semanticLabel,
    required this.barrierLabel,
    required this.capturedThemes,
    required this.reduceMotion,
  });

  final WidgetBuilder builder;
  final GlobalKey? anchorKey;
  final AdaptiveSurfaceKind kind;
  final String? semanticLabel;
  final CapturedThemes capturedThemes;
  final bool reduceMotion;

  /// Keeps the caller's content (and its State) alive across placements.
  final GlobalKey contentKey = GlobalKey();

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return capturedThemes.wrap(
      Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: semanticLabel != null,
        label: semanticLabel,
        child: _SurfaceHost(route: this, animation: animation),
      ),
    );
  }
}

class _SurfaceHost extends StatefulWidget {
  const _SurfaceHost({required this.route, required this.animation});

  final _AdaptiveSurfaceRoute<dynamic> route;
  final Animation<double> animation;

  @override
  State<_SurfaceHost> createState() => _SurfaceHostState();
}

class _SurfaceHostState extends State<_SurfaceHost> {
  Rect? _anchorUsed;

  /// The anchor rectangle in the coordinates of the route's navigator, or null
  /// when there is no usable anchor.
  Rect? _readAnchor() {
    final GlobalKey? key = widget.route.anchorKey;
    final BuildContext? anchorContext = key?.currentContext;
    final BuildContext? navigatorContext = widget.route.navigator?.context;
    if (anchorContext == null || navigatorContext == null) return null;
    final RenderObject? anchor = anchorContext.findRenderObject();
    final RenderObject? nav = navigatorContext.findRenderObject();
    if (anchor is! RenderBox || nav is! RenderBox) return null;
    if (!anchor.attached || !anchor.hasSize || !nav.attached || !nav.hasSize) {
      return null;
    }
    if (anchor.size.isEmpty) return null;
    final Offset topLeft = anchor.localToGlobal(Offset.zero, ancestor: nav);
    return topLeft & anchor.size;
  }

  void _syncAnchor() {
    if (!mounted) return;
    if (_readAnchor() != _anchorUsed) setState(() {});
  }

  void _close() {
    final _AdaptiveSurfaceRoute<dynamic> route = widget.route;
    if (route.isCurrent && route.navigator != null) {
      route.navigator!.maybePop();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final _AdaptiveSurfaceRoute<dynamic> route = widget.route;
    // Live read: a resize or a test override re-places the open surface.
    final WindowSizeClass sizeClass =
        WindowSizeInfo.of(context, aspect: WindowSizeAspect.sizeClass).sizeClass;
    final MediaQueryData mq = MediaQuery.of(context);
    final bool reduce = mq.disableAnimations;

    final Rect? anchor = route.kind == AdaptiveSurfaceKind.anchored
        ? _readAnchor()
        : null;
    _anchorUsed = anchor;
    if (route.kind == AdaptiveSurfaceKind.anchored) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncAnchor());
    }

    final ({AdaptiveSurfacePlacement placement, double maxWidth}) layout =
        adaptiveSurfaceLayoutFor(sizeClass, route.kind,
            hasAnchor: anchor != null);

    final Widget content = HudSheet(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: KeyedSubtree(
          key: route.contentKey,
          child: Builder(builder: route.builder),
        ),
      ),
    );

    final Widget placed;
    switch (layout.placement) {
      case AdaptiveSurfacePlacement.bottomSheet:
        final double bottom =
            math.max(mq.padding.bottom, mq.viewInsets.bottom) + 8;
        final double maxHeight =
            math.max(0.0, mq.size.height * 0.9 - mq.viewInsets.bottom);
        final Widget sheet = Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: layout.maxWidth,
                maxHeight: maxHeight,
              ),
              child: content,
            ),
          ),
        );
        placed = reduce
            ? sheet
            : SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: widget.animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                )),
                child: sheet,
              );
      case AdaptiveSurfacePlacement.dialog:
        final double maxHeight = math.max(
          0.0,
          mq.size.height * 0.9 - mq.viewInsets.bottom,
        );
        final Widget dialog = Padding(
          padding: EdgeInsets.fromLTRB(
            24 + mq.padding.left,
            24 + mq.padding.top,
            24 + mq.padding.right,
            24 + math.max(mq.padding.bottom, mq.viewInsets.bottom),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: layout.maxWidth,
                maxHeight: maxHeight,
              ),
              child: content,
            ),
          ),
        );
        placed = reduce
            ? dialog
            : FadeTransition(opacity: widget.animation, child: dialog);
      case AdaptiveSurfacePlacement.popover:
        final Widget popover = CustomSingleChildLayout(
          delegate: _PopoverLayout(
            anchor: anchor!,
            safe: mq.padding,
            width: layout.maxWidth,
            textDirection: Directionality.of(context),
          ),
          child: content,
        );
        placed = reduce
            ? popover
            : FadeTransition(opacity: widget.animation, child: popover);
    }

    // A nested scope (not a plain Focus): the content's own autofocus title
    // still wins inside this scope, and Esc bubbles up to it from any child.
    return FocusScope(
      autofocus: true,
      onKeyEvent: _onKey,
      child: FocusTraversalGroup(child: placed),
    );
  }
}

/// Places a popover under (or, when there is no room, above) its anchor and
/// keeps it inside the window and the safe area.
class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout({
    required this.anchor,
    required this.safe,
    required this.width,
    required this.textDirection,
  });

  final Rect anchor;
  final EdgeInsets safe;
  final double width;
  final TextDirection textDirection;

  static const double _margin = 8;
  static const double _gap = 8;

  /// Room below and above the anchor inside the safe area.
  ({double below, double above}) _room(Size size) => (
        below: size.height - safe.bottom - _margin - (anchor.bottom + _gap),
        above: anchor.top - _gap - (safe.top + _margin),
      );

  bool _placeBelow(Size size) {
    final r = _room(size);
    return r.below >= r.above;
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final Size size = constraints.biggest;
    final r = _room(size);
    final double room = _placeBelow(size) ? r.below : r.above;
    final double w = math.max(
      0.0,
      math.min(width, size.width - safe.horizontal - 2 * _margin),
    );
    return BoxConstraints(
      minWidth: w,
      maxWidth: w,
      maxHeight: math.max(0.0, room),
    );
  }

  static double _clamp(double v, double lo, double hi) =>
      hi < lo ? lo : v.clamp(lo, hi);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double y = _placeBelow(size)
        ? anchor.bottom + _gap
        : anchor.top - _gap - childSize.height;
    final double x = textDirection == TextDirection.rtl
        ? anchor.right - childSize.width
        : anchor.left;
    return Offset(
      _clamp(
        x,
        safe.left + _margin,
        size.width - safe.right - _margin - childSize.width,
      ),
      _clamp(
        y,
        safe.top + _margin,
        size.height - safe.bottom - _margin - childSize.height,
      ),
    );
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.anchor != anchor ||
      old.safe != safe ||
      old.width != width ||
      old.textDirection != textDirection;
}
