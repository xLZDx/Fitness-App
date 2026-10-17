/// Scroll and scrollbar helpers of S03-17 (contract 10.9, AC-KB-5).
///
///  * [ShellScrollbar] gives a main scroll view a visible scrollbar on Expanded
///    windows and wherever a mouse is attached; on a touch-only phone it adds
///    nothing, so the Compact look is unchanged.
///  * [scrollToTop] is the "selected destination activated again" action: the
///    page scrolls to its top and the route does not change.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;

import 'window_size.dart';

/// Whether a scrollbar should be drawn: Expanded window or a mouse attached.
bool shouldShowScrollbar(BuildContext context) {
  final bool expanded = WindowSizeInfo.of(context).sizeClass ==
      WindowSizeClass.expanded;
  final bool mouse = RendererBinding.instance.mouseTracker.mouseIsConnected;
  return expanded || mouse;
}

/// Wraps a scroll view with a [Scrollbar] when [shouldShowScrollbar] holds.
///
/// Pass the SAME [controller] the scroll view uses. The scroll view must have
/// `primary: false` or use that controller, as usual for [Scrollbar].
class ShellScrollbar extends StatelessWidget {
  const ShellScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!shouldShowScrollbar(context)) return child;
    return Scrollbar(controller: controller, child: child);
  }
}

/// Scrolls [controller] to its start; a no-op when nothing is attached.
/// Instant when the platform asks for reduced motion.
Future<void> scrollToTop(BuildContext context, ScrollController controller) {
  if (!controller.hasClients) return Future<void>.value();
  if (MediaQuery.disableAnimationsOf(context)) {
    controller.jumpTo(controller.position.minScrollExtent);
    return Future<void>.value();
  }
  return controller.animateTo(
    controller.position.minScrollExtent,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOutCubic,
  );
}

/// Pointer kinds that scroll a page (mouse wheel and trackpad included), for
/// pages that set their own `ScrollBehavior`.
const Set<PointerDeviceKind> kShellScrollDevices = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.mouse,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.stylus,
};
