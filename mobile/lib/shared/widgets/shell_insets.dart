/// Layout arithmetic for content that lives inside `MainShell`'s tabs.
///
/// `MainShell` sets `extendBody: true`, so a tab's body is laid out against the
/// FULL screen height and the nav bar is then painted over its bottom edge.
/// Nothing in the app compensated for that — grepped across `lib/` before this
/// file existed, `viewPadding.bottom` and `GlassNavBar.barHeight` had exactly
/// zero readers outside the bar itself — which is why anything anchored to the
/// bottom of a tab ended up underneath the bar.
///
/// The functions here are deliberately pure and take their inputs explicitly:
/// the geometry is the part worth testing, and a widget that reads MediaQuery
/// internally can only be tested by pumping it.
library;

import 'package:flutter/widgets.dart';

/// How many logical pixels at the bottom of a shell tab's body are covered by
/// the nav bar.
///
/// This is the framework's own number, not a reconstruction. When
/// `extendBody: true`, `Scaffold` hands its body a MediaQuery whose
/// `padding.bottom` is `max(systemInset, bottomWidgetsHeight)` —
/// `scaffold.dart:976-978`, `_BodyBuilder` — which is precisely "how much of
/// the body the bottom widgets sit over", already including the bar's own
/// `SafeArea` consumption of the gesture inset.
///
/// The first version of this function added `GlassNavBar.barHeight` to
/// `viewPadding.bottom` by hand. `shell_insets_test.dart` failed it at every
/// non-zero inset: `viewPadding` is not what `Scaffold` rewrites, so the
/// hand-rolled sum silently dropped the gesture bar — 24 to 48px, exactly the
/// band a Samsung home indicator occupies. Reading `padding.bottom` instead
/// also means this stays correct if the bar's height changes, if a page has no
/// bar at all, or if persistent footer buttons appear.
double shellBottomObstruction(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// Bottom padding for the content of a modal bottom sheet, so its last row of
/// controls clears whatever the system is drawing at the bottom of the screen.
///
/// A modal sheet is pushed on the ROOT navigator, so the app's own nav bar is
/// not the problem — the system's is. On a gesture-navigation phone the bottom
/// 24-48px carry the home indicator and the system's own swipe region, and a
/// sheet that pads its buttons by a flat `24` puts them there. That is the
/// second, separate cause behind "нельзя нормально выйти" on Workouts and
/// Programmes: those sheets' Cancel/Confirm row sat under the indicator.
///
/// [MediaQueryData.viewInsets] is the keyboard and [MediaQueryData.padding] is
/// the system furniture; the larger of the two wins rather than their sum,
/// because a raised keyboard already covers the indicator and adding both
/// leaves a visible dead band above the keyboard.
double sheetBottomInset(BuildContext context, {double base = 0}) {
  final mq = MediaQuery.of(context);
  final keyboard = mq.viewInsets.bottom;
  final system = mq.padding.bottom;
  return (keyboard > system ? keyboard : system) + base;
}

/// A sheet size expressed as a fraction of [viewportHeight], raised if needed
/// so that [visibleContentNeeded] logical pixels stay clear of [obstruction].
///
/// **A floor under a fraction, not a replacement for it.** Both halves are
/// load-bearing and each was wrong alone:
///
///  * A bare fraction ignores the bar, and the error grows as the screen
///    shrinks. At `minChildSize: 0.24` the scan sheet kept 0.24 × height, of
///    which the bottom ~110-130px sat behind the bar, so a 780px phone had
///    ~50px left for a 68px shutter AND its scrollable strip — and that strip
///    is the only surface a drag can reach, so the sheet became unreachable
///    rather than merely cramped.
///  * A bare pixel budget does not scale UP. Replacing the fraction outright
///    pinned the sheet near ~280px on every screen; on a 2,200px-tall surface
///    that is 12% instead of 34%, and `scanner_page_test.dart` caught it
///    immediately — a list row landed at y=2281 on a 2200px screen, the tap
///    missed, and the page sat spinning.
///
/// So: keep the design's proportion, and refuse to go below what the controls
/// physically need. [floor] is the designed fraction; the pixel budget wins
/// only where the screen is too short for it.
///
/// [ceiling] must be the sheet's own `maxChildSize`. `DraggableScrollableSheet`
/// asserts `minChildSize <= maxChildSize`, so an unclamped result would turn a
/// tall nav bar on a short screen into a crash rather than a tight layout — and
/// [floor] is clamped to it first, because `clamp` itself asserts when handed a
/// lower bound above its upper one.
double sheetMinChildSize({
  required double viewportHeight,
  required double obstruction,
  required double visibleContentNeeded,
  double floor = 0.0,
  double ceiling = 1.0,
}) {
  if (viewportHeight <= 0) return 0;
  final needed = (obstruction + visibleContentNeeded) / viewportHeight;
  final low = floor.clamp(0.0, ceiling);
  return needed.clamp(low, ceiling);
}
