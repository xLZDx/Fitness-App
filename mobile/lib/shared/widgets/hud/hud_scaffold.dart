/// The shell every HUD screen is built inside: the scroll region, the fade at
/// its foot, the section headers, and the floating tab bar.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import 'hud_surface.dart';

/// A screen's scrollable body, inset and masked the way the handoff draws it.
///
/// ## The reference insets are 390×844; a phone is not
///
/// The prototype pins content to `inset:46px 0 158px` — 46 for a drawn status
/// bar, 158 for a tab bar that is only 86 of it. Neither number can be copied:
/// 46px is a simulated iOS notch and the real one is whatever
/// `MediaQuery.padding.top` says, and 158px of dead space at the foot of a
/// 640pt phone is a fifth of the screen.
///
/// So the top comes from the real inset and the bottom is **derived** from the
/// bar's own geometry — `bottom (14) + height (72) + safe area + 24` — which
/// lands within a few points of 158 on a 844pt device and shrinks correctly on
/// a smaller one. The 34px fade the handoff masks every scroll view with is
/// kept exactly.
class HudScreenBody extends StatelessWidget {
  const HudScreenBody({
    super.key,
    required this.children,
    this.controller,
    this.reserveNavBar = true,
    this.topPadding = 6,
  });

  final List<Widget> children;
  final ScrollController? controller;

  /// False for a full-screen view with no tab bar under it (Session, the form
  /// coach), which would otherwise reserve space for a bar that is not there.
  final bool reserveNavBar;

  final double topPadding;

  /// What a scroll view must clear so its last row is not under the tab bar.
  static double bottomClearance(BuildContext context) =>
      HudTokens.navBarBottom +
      HudTokens.navBarHeight +
      MediaQuery.paddingOf(context).bottom +
      24;

  @override
  Widget build(BuildContext context) {
    final double bottom = reserveNavBar
        ? bottomClearance(context)
        : MediaQuery.paddingOf(context).bottom + 18;

    return HudScrollFade(
      child: ListView(
        controller: controller,
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + topPadding,
          bottom: bottom,
        ),
        children: children,
      ),
    );
  }
}

/// `mask-image: linear-gradient(180deg, #000 calc(100% - 34px), transparent)`.
///
/// A real mask rather than a fake one painted in the background colour: there is
/// no background colour here — the thing behind is a photograph — so a gradient
/// overlay would be a visible dark band instead of a dissolve.
class HudScrollFade extends StatelessWidget {
  const HudScrollFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        final double h = bounds.height;
        // Guard the degenerate case: a zero-height or very short box would give
        // a stop above 1.0 and throw inside the shader.
        final double start =
            h <= HudTokens.scrollFade ? 0.0 : (h - HudTokens.scrollFade) / h;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: <double>[start, 1.0],
          colors: const <Color>[Color(0xFF000000), Color(0x00000000)],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

/// `font:800 24px/1.1` at `padding:6px 20px 12px`, drawn on the photograph.
class HudScreenTitle extends StatelessWidget {
  const HudScreenTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HudTokens.headerGutter, 6, HudTokens.headerGutter, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: HudType.screenTitle(t).overPhoto(t)),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              subtitle!,
              style: HudType.body(t, size: 12.5).overPhoto(t),
            ),
          ],
        ],
      ),
    );
  }
}

/// `padding:16px 20px 8px; font:600 9.5px; letter-spacing:.16em; uppercase`.
class HudSectionHeader extends StatelessWidget {
  const HudSectionHeader(this.label, {super.key, this.strong = false});

  final String label;

  /// Profile's section headers are weight 700 where Train's are 600. The
  /// difference is in the handoff; it is surfaced rather than averaged away.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          HudTokens.headerGutter, strong ? 18 : 16, HudTokens.headerGutter, 8),
      child: Text(
        label.toUpperCase(),
        style: HudType.label(t)
            .copyWith(fontWeight: strong ? FontWeight.w700 : FontWeight.w600)
            .overPhoto(t),
      ),
    );
  }
}

/// One tab of [HudNavBar].
@immutable
class HudNavItem {
  const HudNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The floating tab bar: `left:12 right:12 bottom:14`, 72 tall, radius 26.
///
/// ## Differences from what the app shipped, and why each one
///
/// * **It floats.** The old bar was a full-width flat strip pinned to the
///   screen edge. The handoff's is an inset glass pill; over a photograph a
///   flat strip reads as a different app.
/// * **Scan is no longer raised.** The old bar lifted Scan out as a circle. The
///   handoff has no raised tab and no centre affordance at all — selection is
///   ink plus a 4px accent dot, and nothing else moves.
/// * **Scan moves from second to centre.** The handoff's order is Home ·
///   Workouts · Scan · Progress · Profile. This is an information-architecture
///   choice in the design, not a routing one: the five routes and what each
///   does are untouched.
class HudNavBar extends StatelessWidget {
  const HudNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<HudNavItem> items;

  /// −1 while a full-screen view is open. The handoff lights no tab during a
  /// session, and that is deliberate: the session is not one of the five
  /// sections, and pretending otherwise tells the user they are somewhere they
  /// are not.
  final int selectedIndex;

  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final bool isDark = t.brightness == Brightness.dark;

    // The bar's own unselected ink is neither of the two named text tiers —
    // `rgba(255,255,255,.74)` dark, `rgba(27,32,48,.62)` light. Kept literal
    // rather than rounded to a tier, because the bar is the one element the eye
    // compares against itself five times at once.
    final Color inactive =
        isDark ? const Color(0xBDFFFFFF) : const Color(0x9E1B2030);

    return Padding(
      padding: EdgeInsets.only(
        left: HudTokens.navBarInset,
        right: HudTokens.navBarInset,
        bottom: HudTokens.navBarBottom + MediaQuery.paddingOf(context).bottom,
      ),
      child: SizedBox(
        height: HudTokens.navBarHeight,
        child: HudSurface(
          glass: t.navBar,
          borderRadius: BorderRadius.circular(HudTokens.radiusDevice),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTab(
                    item: items[i],
                    selected: i == selectedIndex,
                    active: t.textPrimary,
                    inactive: inactive,
                    dot: t.accent,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.active,
    required this.inactive,
    required this.dot,
    required this.onTap,
  });

  final HudNavItem item;
  final bool selected;
  final Color active;
  final Color inactive;
  final Color dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final Color ink = selected ? active : inactive;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        containedInkWell: true,
        borderRadius: BorderRadius.circular(28),
        // Excluded from semantics because the wrapper above already carries
        // the label in its proper case. Without this a screen reader announces
        // "Scan" and then "SCAN" -- the uppercasing is a display transform and
        // must not reach the accessibility tree.
        child: ExcludeSemantics(
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(item.icon, size: 20, color: ink),
                  const SizedBox(height: 6),
                  // A label that wraps pushes its tab out of line with the other
                  // four; one that is merely clipped does not. Russian labels are
                  // materially longer than English ones, so this is load-bearing.
                  Text(
                    item.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: HudType.navLabel(t, color: ink),
                  ),
                ],
              ),
              Positioned(
                bottom: 7,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Selection is carried by ink AND the dot, never by colour
                    // alone — the dot is a second, non-chromatic channel for the
                    // same fact.
                    color: selected ? dot : Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
