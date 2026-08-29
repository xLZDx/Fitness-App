/// The one widget that knows how to paint HUD glass, and the three that use it.
///
/// Everything visible in this design is the same surface at four fill levels.
/// Building it once means a panel and a button cannot drift apart, and it means
/// the expensive part — `BackdropFilter` — has exactly one call site to audit
/// when the frame budget is measured.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import '../../../core/background/hud_sky.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';

/// Makes a tap target reachable from an external keyboard or a switch-control
/// device, which `GestureDetector` alone never is.
///
/// `HudButton`, `HudChip` and `HudToggle` are all built on raw
/// `GestureDetector`, not `InkWell`/`ButtonStyleButton` — kept deliberately
/// for their custom press geometry (the 2px lift, the accent wash) rather than
/// Material's ripple. That choice has a real cost: a `GestureDetector` gets no
/// `FocusNode` and no keyboard activation for free, so a person driving the
/// app with a Bluetooth keyboard or "Full Keyboard Access"-style switch input
/// could Tab past every primary control and never be able to press it. This
/// wrapper is the one place that gap is closed, so all three controls fix it
/// the same way rather than three slightly different ways.
class HudKeyboardActivation extends StatelessWidget {
  const HudKeyboardActivation({
    super.key,
    required this.onActivate,
    required this.child,
  });

  /// Null makes the control unfocusable, matching a disabled tap handler.
  final VoidCallback? onActivate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onActivate == null) return child;
    return Focus(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final bool isActivation =
            event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space;
        if (!isActivation) return KeyEventResult.ignored;
        onActivate!();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

/// Whether HUD surfaces actually frost their backdrop.
///
/// `BackdropFilter` is the most expensive thing a Flutter frame can contain: it
/// reads back the composited backdrop, blurs it, and cannot be cached. This
/// design puts one behind every panel, and a Home screen carries six.
///
/// So it is switchable, from one place, for three real reasons:
///
///  * **Golden tests.** `flutter test` rasterizes `BackdropFilter` against an
///    empty backdrop, so a golden of a blurred panel records the blur of
///    nothing — a value that changes if anything is ever painted behind it, and
///    tells you nothing either way.
///  * **Measurement.** A frame-time comparison needs the two states.
///  * **Reduced-motion / low-end devices.** A user who cannot afford the frames
///    should lose the frost, not the interface.
///
/// It is an inherited value rather than a global, so a single screen (a
/// scrolling list, say) can drop the frost without the whole app doing so.
class HudQuality extends InheritedWidget {
  const HudQuality({
    super.key,
    required this.frostedGlass,
    required super.child,
  });

  final bool frostedGlass;

  /// Defaults to **on** when no ancestor supplies one: a component pumped in a
  /// bare test tree should look like the design, not like a degraded variant of
  /// it that nobody chose.
  static bool frostedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HudQuality>()?.frostedGlass ??
      true;

  @override
  bool updateShouldNotify(HudQuality oldWidget) =>
      oldWidget.frostedGlass != frostedGlass;
}

/// A floating glass surface: the fill, the hairline(s), the halo, the frost.
///
/// ## The three shadow kinds are not interchangeable
///
/// CSS gives this design three different things that all arrive as
/// `box-shadow`, and Flutter needs each painted differently:
///
///  * `inset 0 0 0 1px <c>` — an **inner** hairline. That is a `Border`, drawn
///    inside the clip. Painting it as a `BoxShadow` would grow the surface by
///    2px and round its corners on the wrong radius.
///  * `0 0 0 1px <c>` — an **outer** ring (light theme only). A `BoxShadow` with
///    `blurRadius: 0, spreadRadius: 1`, which is exactly a 1px ring.
///  * `0 0 26px -6px <c>` / `0 18px 34px -22px <c>` — an actual shadow.
///  * `inset 0 1px 0 <c>` — a **top-only** highlight, distinct from the
///    all-round inset hairline above. Six elements in the handoff carry this
///    as well as the full ring; it was missing entirely for one gate, caught
///    by a fidelity review that quoted the CSS for the ones that are wired
///    into a screen that exists yet — `HudChip`'s selected wash and (via
///    `HudTokens.navBar`) the floating tab bar. Approximated as a 1px line
///    inset from each top corner by ~30% of the radius, rather than a true
///    path-following stroke: at 1px wide the curve into the corner the real
///    CSS produces is barely perceptible, and a `PathMetric`-based stroke
///    would be materially more code for a difference nobody will see.
///
/// Collapsing them into one list is the mistake this class exists to prevent.
class HudSurface extends StatelessWidget {
  const HudSurface({
    super.key,
    required this.glass,
    required this.borderRadius,
    this.child,
    this.padding,
    this.overlay,
    this.border,
    this.topHighlight,
  });

  final HudGlass glass;
  final BorderRadius borderRadius;
  final Widget? child;
  final EdgeInsetsGeometry? padding;

  /// Painted over the fill and under the child — the accent gradient a selected
  /// chip carries, which replaces the fill rather than tinting it.
  final Gradient? overlay;

  /// Replaces [HudGlass.innerBorder] when a caller needs a different hairline
  /// for one state (a selected chip's accent ring).
  final Color? border;

  /// Replaces [HudGlass.topHighlight] for one state. Explicit `null` here
  /// still falls back to the glass recipe's own value — pass
  /// [Colors.transparent] to suppress it outright.
  final Color? topHighlight;

  @override
  Widget build(BuildContext context) {
    final Color hairline = border ?? glass.innerBorder;
    final Color? highlight = topHighlight ?? glass.topHighlight;
    // `overlay` is a per-instance override (a selected chip's accent wash);
    // `glass.fillGradient` is the recipe's own inherent fill, when the recipe
    // has one (only the dark nav bar does). `overlay` wins when both are
    // somehow present, since it represents a more specific state.
    final Gradient? gradient = overlay ?? glass.fillGradient;

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? glass.fill : null,
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(color: hairline, width: 1),
      ),
      child: padding == null
          ? child
          : Padding(padding: padding!, child: child ?? const SizedBox.shrink()),
    );

    if (highlight != null) {
      final double inset =
          (borderRadius.topLeft.x + borderRadius.topRight.x) / 2 * 0.3;
      surface = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          surface,
          Positioned(
            top: 1,
            left: inset,
            right: inset,
            child: IgnorePointer(
              child: Container(height: 1, color: highlight),
            ),
          ),
        ],
      );
    }

    if (HudQuality.frostedOf(context)) {
      surface = BackdropFilter(filter: glass.backdropFilter, child: surface);
    }

    final List<BoxShadow> shadows = <BoxShadow>[
      if (glass.outerBorder != null)
        BoxShadow(
          color: glass.outerBorder!,
          blurRadius: 0,
          spreadRadius: 1,
        ),
      if (glass.glow != null) glass.glow!,
      ...glass.dropShadows,
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadows,
      ),
      child: ClipRRect(borderRadius: borderRadius, child: surface),
    );
  }
}

/// The primary floating panel — radius 30, `margin:0 16px` at the call site.
class HudPanel extends StatelessWidget {
  const HudPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = HudTokens.radiusPanel,
    this.secondary = false,
    this.dense = false,
    this.onTap,
    this.semanticLabel,
  }) : assert(!(secondary && dense),
            'A panel is one tier: subPanel is the lightest, contentPanel the '
            'most protective. Asking for both describes no surface.');

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Draws the lighter `subPanel` tier — list wrappers and promo rows.
  final bool secondary;

  /// Draws the `contentPanel` tier, for a card carrying a title, metadata,
  /// body copy and an action together.
  ///
  /// Its fill alpha is taken from `HudSkyScope` — the measured
  /// [HudBackgroundProfile.denseSurfaceAlpha] for the picture actually on
  /// screen — rather than from the recipe, so a dark scene keeps more of its
  /// photograph than a bright one. With no scope above, the protective
  /// default applies; see [HudSkyScope.of].
  final bool dense;

  final VoidCallback? onTap;
  final String? semanticLabel;

  /// The `contentPanel` recipe with its placeholder alpha replaced by the one
  /// measured for the picture on screen.
  ///
  /// Only the alpha moves. Colour, blur, saturation, hairline and glow stay
  /// exactly as the tier defines them, so this cannot drift into being a
  /// second, differently-shaped surface.
  HudGlass _denseGlass(BuildContext context, HudTokens t) {
    final HudGlass base = t.contentPanel;
    final double alpha = HudSkyScope.of(context).denseSurfaceAlpha;
    return HudGlass(
      fill: base.fill.withValues(alpha: alpha),
      cssBlur: base.cssBlur,
      innerBorder: base.innerBorder,
      outerBorder: base.outerBorder,
      glow: base.glow,
      dropShadows: base.dropShadows,
      saturate: base.saturate,
      topHighlight: base.topHighlight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final BorderRadius br = BorderRadius.circular(radius);

    // The text inside a panel takes the panel's softer readability shadow, not
    // the harder one used over bare photograph. Applied here, once, rather than
    // at every Text — the handoff sets it on the panel and lets it inherit.
    final Widget body = DefaultTextStyle.merge(
      style: TextStyle(shadows: t.panelReadabilityShadow),
      child: child,
    );

    final Widget surface = HudSurface(
      glass: dense ? _denseGlass(context, t) : (secondary ? t.subPanel : t.panel),
      borderRadius: br,
      padding: onTap == null ? padding : null,
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: br,
                child: Padding(padding: padding, child: body),
              ),
            ),
    );

    if (semanticLabel == null && onTap == null) return surface;
    // Without `ExcludeSemantics`, the panel's own Text children merge into
    // this node and a screen reader announces the label and then the visible
    // copy again — `HudButton`'s doc comment names this exact bug for the
    // same reason. Excluded only when a label is actually supplied: a bare
    // `onTap` with no override should still let the real content through.
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: semanticLabel != null ? ExcludeSemantics(child: surface) : surface,
    );
  }
}

/// An opaque HUD surface for content presented over a screen it does not
/// control -- a confirm/rate bottom sheet, a modal card -- where [HudPanel]'s
/// deliberately near-transparent fill (`HudGlass.fill` is ~1.4% alpha on
/// dark, by design: the panel's shape is carried by its border and glow, not
/// its fill) would let whatever is behind it show through.
///
/// ## Why this exists, and why it is not a sixth glass style
///
/// The HUD migration gate's own census (`core/plans/
/// HUD_MIGRATION_CENSUS_2026-08-29.md`) found the legacy `GlassCard`'s
/// history already proves the failure mode this widget exists to prevent: a
/// translucent card behind a bottom sheet became unreadable in production
/// (the day-3 donation sheet bug, see `GlassCard.floating`'s own doc
/// comment) until a later fix made `GlassCard`'s default fill opaque. GPT-PM's
/// explicit ruling on the migration of that fix onto HUD (round review,
/// 2026-08-29): derive the existing, spec-derived `panel` recipe rather than
/// inventing a new one -- `sheet = panel` with only its `fill` replaced by
/// the same already-shipped opaque semantic surface `GlassCard`'s own fix
/// uses (`AppSemanticColors.surfaceElevated`, falling back to
/// `ColorScheme.surfaceContainerHighest`). Every other value -- border,
/// glow, top highlight, drop shadows -- stays byte-identical to `panel`, so
/// this can never drift into an undocumented second surface language.
///
/// `HudGlass` has no `copyWith`; this follows the same field-by-field
/// reconstruction [HudPanel._denseGlass] already establishes for exactly
/// this "same recipe, one field overridden" shape, rather than adding a
/// method only this one call site would use.
///
/// `cssBlur`/`saturate` are zeroed rather than inherited from `panel`: an
/// opaque fill has nothing to gain from `BackdropFilter`ing the content it
/// is about to fully cover, and skipping it avoids a wasted composited
/// readback -- the same reasoning `GlassCard`'s own `blur` flag documents
/// ("one of the most expensive things a Flutter frame can contain").
class HudSheet extends StatelessWidget {
  const HudSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = HudTokens.radiusSheet,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  HudGlass _opaqueGlass(BuildContext context, HudTokens t) {
    final HudGlass base = t.panel;
    // Read the extension directly, not via the `theme.colors` getter that
    // ends in `extension<AppSemanticColors>()!` -- HudSheet is a shared
    // presentational widget, reachable from a bare MaterialApp in tests and
    // widget previews that do not install the app's own ThemeData, exactly
    // the reason GlassCard's own fill resolution avoids that getter too.
    final AppSemanticColors? tokens =
        Theme.of(context).extension<AppSemanticColors>();
    final Color opaqueFill =
        tokens?.surfaceElevated ?? Theme.of(context).colorScheme.surfaceContainerHighest;
    return HudGlass(
      fill: opaqueFill,
      cssBlur: 0,
      innerBorder: base.innerBorder,
      outerBorder: base.outerBorder,
      glow: base.glow,
      dropShadows: base.dropShadows,
      saturate: null,
      topHighlight: base.topHighlight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return HudSurface(
      glass: _opaqueGlass(context, t),
      borderRadius: BorderRadius.circular(radius),
      padding: padding,
      child: child,
    );
  }
}

/// What a HUD button is made of.
enum HudButtonTone {
  /// The plain glass button — `fill .05`, hairline `.46`, halo `28px -8px`.
  /// The brightest element on the screen, and there is at most one per view.
  glass,

  /// `linear-gradient(180deg, accent@35%, accent@12%)` with an `accent@40%`
  /// hairline. Used where an action commits something: log a set, open the
  /// exercises a scan found, continue a programme.
  accent,

  /// The dark wash the Scan screen's Recognise control uses so it does not
  /// compete with the viewfinder it sits under.
  ink,
}

/// The handoff's button: label left, icon right, lifts 2px while pressed.
///
/// ## Why the lift is on *press* and not on hover
///
/// The prototype animates `translateY(-2px)` on `:hover` and returns to 0 on
/// `:active`. A phone has no hover. Dropping the motion entirely would lose the
/// only feedback the design gives a tap, so it is moved to the press: down 2px
/// is the gesture the design already draws, just bound to the input this
/// platform actually has.
class HudButton extends StatefulWidget {
  const HudButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = HudButtonTone.glass,
    this.radius = HudTokens.radiusButton,
    this.padding = const EdgeInsets.fromLTRB(16, 15, 16, 15),
    this.centered = false,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final HudButtonTone tone;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Scan's Recognise control centres its icon and label instead of pushing
  /// them to the two ends.
  final bool centered;

  final bool enabled;

  @override
  State<HudButton> createState() => _HudButtonState();
}

class _HudButtonState extends State<HudButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final bool live = widget.enabled && widget.onPressed != null;

    final HudGlass glass;
    Gradient? overlay;
    Color? hairline;
    switch (widget.tone) {
      case HudButtonTone.glass:
        glass = t.button;
      case HudButtonTone.accent:
        glass = t.button;
        overlay = t.accentChipGradient;
        hairline = t.accent.withValues(alpha: 0.40);
      case HudButtonTone.ink:
        glass = t.button;
        overlay = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: t.brightness == Brightness.dark
              ? const <Color>[Color(0x801A0F22), Color(0x4D1A0F22)]
              : const <Color>[Color(0xB3FFFFFF), Color(0x80FFFFFF)],
        );
        hairline = t.textPrimary.withValues(alpha: 0.20);
    }

    // `accent` paints a bright lime (dark theme) / saturated green (light
    // theme) fill; `textPrimary` (white on dark) is the wrong ink for either
    // -- measured on the shipped Workouts CTA at 4.17:1, under AA, because
    // white text loses contrast against a fill that is itself light. `onAccent`
    // exists in this exact token set for this exact case and was defined but
    // never wired to a button; every other tone keeps `textPrimary`, since
    // `glass`/`ink` fill dark regardless of theme.
    final Color base =
        widget.tone == HudButtonTone.accent ? t.onAccent : t.textPrimary;
    final Color foreground = live ? base : base.withValues(alpha: 0.38);

    final List<Widget> content = <Widget>[
      Flexible(
        child: Text(
          widget.label,
          style: HudType.panelTitle(t).copyWith(color: foreground),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (widget.icon != null) ...<Widget>[
        if (widget.centered)
          const SizedBox(width: 9)
        else
          const SizedBox(width: 12),
        Icon(widget.icon, size: 20, color: foreground),
      ],
    ];

    return Semantics(
      button: true,
      enabled: live,
      label: widget.label,
      // The visible label is excluded below, not left to merge: the outer
      // `Semantics` already carries it, and a merged pair makes a screen
      // reader announce the same words twice. Measured: the node's label came
      // back with the child's own appended after a separator until this was
      // added.
      child: HudKeyboardActivation(
        onActivate: live ? widget.onPressed : null,
        child: GestureDetector(
          onTapDown: live ? (_) => setState(() => _pressed = true) : null,
          onTapUp: live ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: live ? () => setState(() => _pressed = false) : null,
          onTap: live ? widget.onPressed : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedSlide(
            offset: _pressed ? const Offset(0, -0.035) : Offset.zero,
            // Decorative press feedback only -- the tap itself already fires
            // through `onTap` regardless of this settling instantly.
            duration: context.hudMotionDuration(
              const Duration(milliseconds: 180),
            ),
            curve: Curves.ease,
            child: ConstrainedBox(
              // The handoff's own floor, and WCAG 2.5.5's.
              constraints:
                  const BoxConstraints(minHeight: HudTokens.minTapTarget),
              child: HudSurface(
                glass: glass,
                overlay: overlay,
                border: hairline,
                borderRadius: BorderRadius.circular(widget.radius),
                padding: widget.padding,
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: widget.centered
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.spaceBetween,
                    mainAxisSize:
                        widget.centered ? MainAxisSize.min : MainAxisSize.max,
                    children: widget.centered
                        ? <Widget>[
                            if (widget.icon != null) ...<Widget>[
                              Icon(widget.icon, size: 20, color: foreground),
                              const SizedBox(width: 9),
                            ],
                            Flexible(
                              child: Text(
                                widget.label,
                                style: HudType.panelTitle(t)
                                    .copyWith(color: foreground),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]
                        : content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A filter or segment chip. Selected is a solid accent wash, not a fill swap.
class HudChip extends StatelessWidget {
  const HudChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.radius = HudTokens.radiusChip,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    this.expand = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// A segmented control's halves fill their cell; a filter chip hugs its text.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final BorderRadius br = BorderRadius.circular(radius);

    final Widget text = Text(
      label,
      textAlign: expand ? TextAlign.center : TextAlign.start,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: HudType.body(t, size: expand ? 12.5 : 11.5).copyWith(
        fontWeight: FontWeight.w600,
        height: 1.0,
        color: selected ? t.textPrimary : t.textTertiary,
      ),
    );

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      child: HudKeyboardActivation(
        onActivate: onTap,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: HudTokens.minTapTarget),
            child: HudSurface(
              glass: t.chip,
              overlay: selected ? t.accentChipGradient : null,
              border: selected ? t.accentChipBorder : null,
              topHighlight: selected ? t.accentChipTopHighlight : null,
              borderRadius: br,
              padding: padding,
              child: ExcludeSemantics(
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: expand ? null : 1.0,
                  heightFactor: 1.0,
                  child: text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
