import 'package:flutter/material.dart';

import '../../core/theme/app_semantic_colors.dart';

/// The app's bottom tab bar: flat, full width, pinned to the screen edge, with
/// the Scan tab lifted out of it as a circle.
///
/// That is the prototype's own `BottomNav` — an 80px bar filled with `C.s1`, a
/// `rgba(255,255,255,0.07)` top hairline, 20px monoline icons and 10px labels.
/// No floating pill, no backdrop blur, no gradient behind the selected tab; the
/// selected tab is the accent colour and nothing else changes.
///
/// ## The name is now wrong, deliberately
///
/// Nothing here is glass any more. Renaming this one widget would leave
/// `GlassCard` (175 call sites) and `GlassAppBar` carrying the same dead
/// metaphor, and one accurate name beside four stale ones is harder to read
/// than five consistently stale ones. The family gets renamed in a single
/// mechanical pass once Ф3 has settled what the design system actually is.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<GlassNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// The prototype's numbers. Named rather than inlined because the raised
  /// circle's geometry is derived from them and the derivation only makes sense
  /// if the inputs are visible.
  static const double barHeight = 80;
  static const double _bottomInset = 4;
  static const double itemPadding = 8;
  static const double iconSize = 20;
  static const double _gap = 3;
  static const double circleSize = 46;

  /// How far the Scan circle is pulled up out of the bar — the prototype's
  /// `marginTop: -18` on that one element.
  static const double circleLift = 18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Read nullably, not through `context.colors`. That getter ends in `!`, and
    // this widget is shared chrome whose tests pump it under a bare
    // `MaterialApp` with no app theme installed — the bang would throw before a
    // single pixel was laid out. Ф1b shipped exactly that bug.
    final tokens = theme.extension<AppSemanticColors>();

    final background = tokens?.backgroundSecondary ?? scheme.surface;
    final outline = tokens?.outline ?? scheme.outline;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        // The source's weaker border tier (`bd`, white @ 0.07). The `outline`
        // token carries the stronger one (`bd2`, 0.13), which is right for a
        // card edge and too loud for a full-width hairline.
        border: Border(top: BorderSide(color: outline.withValues(alpha: 0.07))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: _bottomInset),
            child: Row(
              // Each tab fills the bar's full height rather than shrinking to
              // its own content. Without this the ink region ends where the
              // column ends, and the top of the Scan circle — the part that
              // sticks out and draws the eye — sits outside its own tab's
              // hit box.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _Tab(
                      item: items[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelect(i),
                      active: tokens?.accentPrimary ?? scheme.primary,
                      inactive: tokens?.textSecondary ?? scheme.onSurfaceVariant,
                      onActive: tokens?.onAccent ?? scheme.onPrimary,
                      circleFill: tokens?.surfaceElevated ??
                          scheme.surfaceContainerHighest,
                      circleBorder: outline,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.active,
    required this.inactive,
    required this.onActive,
    required this.circleFill,
    required this.circleBorder,
  });

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color active;
  final Color inactive;
  final Color onActive;
  final Color circleFill;
  final Color circleBorder;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? active : inactive;

    return Semantics(
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(vertical: GlassNavBar.itemPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.raised)
                _circle()
              else
                Icon(item.icon, size: GlassNavBar.iconSize, color: foreground),
              const SizedBox(height: GlassNavBar._gap),
              Text(
                item.label,
                // A nav label that wraps pushes its tab out of line with the
                // other four; one that is merely clipped does not.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Scan tab's circle, drawn 46px tall but occupying only 28px of layout.
  ///
  /// That difference is the whole effect: the column is measured and centred as
  /// if the circle were 28px, then the circle paints downward from its own
  /// bottom edge, so its top lands 18px higher than the flow position. It is
  /// the same arithmetic CSS performs for `marginTop: -18`, and it lands the
  /// circle's cap ~2px above the bar's hairline rather than floating it free —
  /// which is what the prototype actually looks like.
  ///
  /// Keeping the lift in LAYOUT rather than in a `Transform` matters for taps:
  /// a transformed circle would paint 18px above a hit region that never moved.
  Widget _circle() {
    return SizedBox(
      width: GlassNavBar.circleSize,
      height: GlassNavBar.circleSize - GlassNavBar.circleLift,
      child: OverflowBox(
        minWidth: GlassNavBar.circleSize,
        maxWidth: GlassNavBar.circleSize,
        minHeight: GlassNavBar.circleSize,
        maxHeight: GlassNavBar.circleSize,
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? active : circleFill,
            border: Border.all(
              color: selected ? active : circleBorder,
              width: 2,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: active.withValues(alpha: 0.40),
                  blurRadius: 20,
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Center(
            child: Icon(
              item.icon,
              size: GlassNavBar.iconSize,
              color: selected ? onActive : inactive,
            ),
          ),
        ),
      ),
    );
  }
}

class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.label,
    this.raised = false,
  });

  /// One glyph per tab, selected or not. The prototype does not swap to a
  /// filled variant on selection — only the colour moves — so there is no
  /// second icon to hold.
  final IconData icon;

  final String label;

  /// Drawn as a circle lifted out of the bar. True for Scan and nothing else.
  final bool raised;
}
