/// What the shell publishes to its tab pages (contract 10.4, design 2.6;
/// S03-05): the window class, the navigation presentation, the rail width and
/// the clearances, in one inherited object so no page computes them.
///
/// [ShellLayout.maybeOf] is null on pushed routes (they are outside the shell),
/// and `HudScreenBody` then behaves exactly as before S03.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'window_size.dart';

/// Compact rail form width (dp).
const double kRailCompactWidth = 96;

/// Extended rail form width (dp).
const double kRailExtendedWidth = 240;

/// Window width from which the extended rail form is always used (dp).
const double kRailExtendedMinWindowWidth = 1200;

/// Padding added to the widest measured label before comparing with the
/// compact width (dp).
const double kRailLabelPadding = 16;

/// Height reserved for the dock (pill or strip) in the bar presentation (dp).
const double kShellDockHeight = 56;

/// Gap between the dock and the content/bar (dp).
const double kShellDockGap = 12;

/// Bar (and dock) width cap on the Medium class (dp).
const double kShellBarMaxWidth = 560;

/// Bar or rail.
enum ShellNavigation { bar, rail }

/// Measures one rail label. The ONLY way the rail form rule reads label widths
/// (tests override [railLabelMeasurerProvider] with a fixed-width stub).
typedef RailLabelMeasurer = double Function(
    String label, TextStyle style, TextScaler scaler);

/// The default measurer: a one-line `TextPainter` width.
double measureRailLabel(String label, TextStyle style, TextScaler scaler) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final double width = painter.width;
  painter.dispose();
  return width;
}

final Provider<RailLabelMeasurer> railLabelMeasurerProvider =
    Provider<RailLabelMeasurer>((Ref ref) => measureRailLabel);

/// The rail form rule: 240 dp when the window is 1200 dp or wider, or when the
/// widest measured label plus 16 dp is more than 96 dp; else 96 dp.
double resolveRailWidth({
  required double windowWidth,
  required double widestLabel,
}) {
  if (windowWidth >= kRailExtendedMinWindowWidth) return kRailExtendedWidth;
  if (widestLabel + kRailLabelPadding > kRailCompactWidth) {
    return kRailExtendedWidth;
  }
  return kRailCompactWidth;
}

/// Memoises the widest-label measurement by locale, text scale, font family,
/// label set and measurer, so a window resize never re-runs `TextPainter`
/// (RV-18c).
class RailWidthMemo {
  final Map<String, double> _cache = <String, double>{};

  double widest({
    required String localeTag,
    required double textScaleKey,
    required String? fontFamily,
    required List<String> labels,
    required Object measurerKey,
    required double Function(String label) measure,
  }) {
    final String key = '$localeTag|$textScaleKey|${fontFamily ?? ''}|'
        '${identityHashCode(measurerKey)}|${labels.join('\u0001')}';
    final double? hit = _cache[key];
    if (hit != null) return hit;
    double widest = 0;
    for (final String label in labels) {
      final double w = measure(label);
      if (w > widest) widest = w;
    }
    if (_cache.length >= 16) _cache.clear();
    _cache[key] = widest;
    return widest;
  }
}

/// The shell's published layout.
class ShellLayout extends InheritedWidget {
  const ShellLayout({
    super.key,
    required this.info,
    required this.navigation,
    required this.railWidth,
    required this.railFootprint,
    required this.contentStartInset,
    required this.bottomClearance,
    required this.dockHeight,
    required super.child,
  });

  final WindowSizeInfo info;
  final ShellNavigation navigation;

  /// 96 or 240 for the rail, 0 for the bar.
  final double railWidth;

  /// Space the rail takes at the start edge (safe area + 12 + rail + 12); the
  /// content pane is already placed after it, so pages add nothing for it.
  final double railFootprint;

  /// Rail footprint + 16 (contract 10.4): where the first child of a page
  /// starts, counting the page's own 16 dp gutter. 0 for the bar.
  final double contentStartInset;

  /// What a scroll view must clear at its foot (dock included while shown).
  final double bottomClearance;

  /// Height of the dock while it shows (56), else 0.
  final double dockHeight;

  /// Null outside the shell (pushed routes).
  static ShellLayout? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellLayout>();

  @override
  bool updateShouldNotify(ShellLayout old) =>
      info != old.info ||
      navigation != old.navigation ||
      railWidth != old.railWidth ||
      railFootprint != old.railFootprint ||
      contentStartInset != old.contentStartInset ||
      bottomClearance != old.bottomClearance ||
      dockHeight != old.dockHeight;
}
