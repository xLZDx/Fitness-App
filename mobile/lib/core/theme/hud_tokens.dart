/// The HUD design system's tokens: the numbers the handoff actually states.
///
/// ## Why this is a second token layer beside `AppSemanticColors`
///
/// [AppSemanticColors] answers "what colour is this role on a flat app
/// background". The HUD handoff answers a different question: the interface no
/// longer sits on a background the app controls, it floats over a **photograph**
/// the app does not control. Nothing in the old layer can express that — there
/// is no token for "the alpha of a fill that is 1.4% white", none for the
/// hairline that actually draws the shape, and none for the veil that makes text
/// survive an arbitrary image.
///
/// So the two coexist rather than one replacing the other: `AppSemanticColors`
/// keeps serving every screen not yet migrated and every Material control that
/// reads `ColorScheme`, and this extension carries the HUD. The alternative —
/// widening `AppSemanticColors` with twenty glass fields — would have made every
/// existing screen's tokens ambiguous about which surface they describe.
///
/// ## Every value here is transcribed, not chosen
///
/// Source of record, in precedence order:
///  1. `design_handoff_fitness_hud/CLAUDE.md` — "утверждённая формула дизайна —
///     читать первым" (the approved formula, read first).
///  2. `design_handoff_fitness_hud/README.md` — the token tables.
///  3. The `.dc.html` prototypes' inline CSS, for anything the two above do not
///     state.
///
/// Where (3) contradicts (1) the approved formula wins and the divergence is
/// recorded at the field. There is exactly one such case, [success].
///
/// ## CSS blur IS the Flutter sigma — corrected 2026-08-19
///
/// This file shipped one gate carrying `blurSigma(css) => css / 2`, on the
/// belief that CSS `blur(R)` halves into a Gaussian sigma the way a
/// `box-shadow` blur radius does. It does not, and a D1 review round caught
/// it by quoting the spec rather than trusting the comment that was here.
/// CSSWG filter-effects-1 on `blur()`, verbatim: *"The passed parameter
/// defines the value of the standard deviation to the Gaussian function."*
/// The length IS the sigma. Every frosted surface in the app was rendering at
/// **half** its designed strength — `blur(7px)` at σ 3.5 instead of 7,
/// `blur(30px)` at σ 15 instead of 30 — for the whole of D1.
///
/// `box-shadow`'s blur radius is the thing that halves (its radius is
/// conventionally ~2× the equivalent sigma, which is why Flutter's own
/// `BoxShadow.blurRadius` needs no correction here — Skia already applies
/// that conversion internally, so a literal CSS `box-shadow` radius passed
/// straight into `BoxShadow(blurRadius: …)` is correct as-is). `blur()` and
/// `drop-shadow()` do NOT share that halving: the spec draws the distinction
/// explicitly — *"Values are interpreted as for box-shadow but with the
/// optional 3rd `<length>` value being the standard deviation instead of
/// blur radius… Standard deviation is different to box-shadow's blur
/// radius."* `hud_metric.dart`'s ring glow, painted as a simulated
/// `drop-shadow()`, carried the identical bug for the identical reason and is
/// fixed alongside this.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// CSS `blur(<radius>)` -> the Gaussian sigma Flutter's `ImageFilter.blur`
/// wants. Identity, not a halving — see the library doc for why a halving
/// was here for one gate and was wrong.
double blurSigma(double cssRadius) => cssRadius;

/// A `saturate(<amount>)` colour matrix, as `filter: saturate()` defines it.
///
/// The luminance coefficients are the ones the filter-effects spec names
/// (0.213 / 0.715 / 0.072 — Rec. 709), not the older Rec. 601 set, because that
/// is what a browser applied when the handoff's screenshots were taken.
ColorFilter saturationFilter(double amount) {
  const lr = 0.213, lg = 0.715, lb = 0.072;
  final s = amount;
  return ColorFilter.matrix(<double>[
    lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}

/// One glass recipe: everything needed to paint a single floating surface.
///
/// A record rather than four loose fields on [HudTokens] because the handoff
/// defines glass as a *set* — fill, blur, hairline, glow move together, and a
/// panel that took its fill from one tier and its hairline from another is not
/// a tier the design has. Grouping them makes that mistake impossible to express.
@immutable
class HudGlass {
  // Not `const`: `backdropFilter` below is a `late final` field that caches
  // an `ui.ImageFilter` on first read, and Dart forbids that combination on a
  // const-constructible class. No call site actually built one as a const
  // literal -- every recipe is assembled at `HudTokens.dark`/`.light`'s
  // static-init time, in a `static final`, not a `static const`.
  HudGlass({
    required this.fill,
    required this.cssBlur,
    required this.innerBorder,
    this.outerBorder,
    this.glow,
    this.dropShadows = const <BoxShadow>[],
    this.saturate,
    this.topHighlight,
    this.fillGradient,
  });

  /// The surface fill. On dark this is `rgba(255,255,255,.014)` — so nearly
  /// nothing that the shape is carried entirely by [innerBorder] and [glow].
  ///
  /// Ignored when [fillGradient] is set; kept as the single-colour value
  /// closest to it (this recipe's top stop) so a consumer that only reads
  /// [fill] — there is none today, but the field stays meaningful on its own.
  final Color fill;

  /// The CSS blur radius. Pass through [blurSigma] before handing it to
  /// `ImageFilter.blur`.
  final double cssBlur;

  /// `box-shadow: inset 0 0 0 1px <colour>` — an inner hairline, which in
  /// Flutter is a `Border`, not a `BoxShadow`. Getting that wrong grows the
  /// element by 2px and rounds its corners differently.
  final Color innerBorder;

  /// The light theme's second ring, `0 0 0 1px rgba(27,32,48,.16)` — an
  /// **outer** ink line that keeps a white-on-white panel from dissolving into
  /// a pale photograph. Dark has no equivalent.
  final Color? outerBorder;

  /// `0 0 26px -6px rgba(255,255,255,.26)` — the halo that makes the panel read
  /// as lit rather than cut out. Dark only.
  final BoxShadow? glow;

  /// Ordinary drop shadows. Light theme uses one; dark uses none on panels.
  final List<BoxShadow> dropShadows;

  /// `saturate(<amount>)` applied with the backdrop blur, as a multiplier
  /// (1.5 for `saturate(150%)`). Null means no colour filter at all — which is
  /// cheaper, and is why dark does not carry one it does not need.
  final double? saturate;

  /// `box-shadow: inset 0 1px 0 <colour>` — a top-only bevel highlight,
  /// distinct from [innerBorder]'s all-round ring. Missing entirely until a
  /// D1 review round quoted the CSS; wired only where it is currently
  /// reachable from a built screen (see `HudSurface`'s doc). Null where the
  /// handoff genuinely draws no such highlight, or where a value has not yet
  /// been read off a screen this repository does not build yet.
  final Color? topHighlight;

  /// `background:linear-gradient(180deg, <top>, <bottom>)` — the floating tab
  /// bar's own fill, not the flat [fill] every other surface uses. Null for
  /// every other recipe: the handoff draws exactly one gradient-filled glass
  /// surface (`Sunset.dc.html:449`, the dark nav bar's `.40` top to `.24`
  /// bottom), and painting it as [fill]'s flat `.40` for one D1 review round
  /// was a confirmed fidelity gap. Reinstated once measured: a
  /// `BoxDecoration.gradient` and a `BoxDecoration.color` are the same GPU
  /// primitive -- a single cached `Shader` fill of one rounded rect -- so a
  /// two-stop linear gradient costs nothing meaningful next to the
  /// `BackdropFilter`/drop-shadow work already on the same surface. Takes
  /// priority over [fill] in `HudSurface` when set.
  final Gradient? fillGradient;

  /// The composed backdrop filter, or a plain blur when there is no saturation.
  ///
  /// `HudSurface` reads this on every frame the one `BackdropFilter` call site
  /// rebuilds, and a Home screen carries six. Computed once and cached per
  /// [HudGlass] instance -- safe because the class is immutable, so the value
  /// can only ever come out identical for a given instance.
  ///
  /// That guarantee is scoped to one instance, not to a theme. The two
  /// static [HudTokens.dark]/[HudTokens.light] singletons each build their
  /// [HudGlass] recipes exactly once, so this genuinely caches across the
  /// app's whole lifetime for ordinary (non-transitioning) frames. `lerp`
  /// below constructs a fresh [HudGlass] on every animated frame of a theme
  /// transition, so during the ~200ms toggle this filter is recomputed each
  /// frame rather than reused -- unmeasured, but worth knowing if that
  /// transition is ever profiled as janky.
  late final ui.ImageFilter backdropFilter = _computeBackdropFilter();

  ui.ImageFilter _computeBackdropFilter() {
    final blur = ui.ImageFilter.blur(
      sigmaX: blurSigma(cssBlur),
      sigmaY: blurSigma(cssBlur),
    );
    final s = saturate;
    if (s == null) return blur;
    return ui.ImageFilter.compose(
      outer: saturationFilter(s),
      inner: blur,
    );
  }

  static HudGlass lerp(HudGlass a, HudGlass b, double t) {
    // `fillGradient` has no meaningful "in between" the way a flat colour
    // does: `Gradient.lerp` treats one side being null as "fade this
    // gradient down to transparent", not "cross-fade into the other side's
    // opaque flat fill". For the one recipe this is reachable on today (the
    // dark nav bar, whose light counterpart carries no gradient), that made
    // the settled end of a dark->light theme transition paint the bar fully
    // transparent instead of light's own opaque fill -- confirmed against
    // `LinearGradient.lerp`'s source, which returns `otherSide.scale(...)`
    // rather than `null` on a one-sided-null lerp. Snapped at the midpoint
    // instead, the same way `brightness` a few lines below already snaps
    // rather than interpolates for the identical kind of property. `fill` is
    // snapped in lockstep, but only while a gradient is actually involved,
    // so this changes nothing for every gradient-less recipe (panel,
    // subPanel, button, chip in both themes), which keep the smooth
    // `Color.lerp` they already had.
    final bool hasGradient = a.fillGradient != null || b.fillGradient != null;
    return HudGlass(
      fill: hasGradient
          ? (t < 0.5 ? a.fill : b.fill)
          : Color.lerp(a.fill, b.fill, t)!,
      cssBlur: ui.lerpDouble(a.cssBlur, b.cssBlur, t)!,
      innerBorder: Color.lerp(a.innerBorder, b.innerBorder, t)!,
      outerBorder: Color.lerp(a.outerBorder, b.outerBorder, t),
      glow: BoxShadow.lerp(a.glow, b.glow, t),
      dropShadows: BoxShadow.lerpList(a.dropShadows, b.dropShadows, t) ??
          const <BoxShadow>[],
      saturate: ui.lerpDouble(a.saturate ?? 1.0, b.saturate ?? 1.0, t),
      topHighlight: Color.lerp(a.topHighlight, b.topHighlight, t),
      fillGradient: hasGradient ? (t < 0.5 ? a.fillGradient : b.fillGradient) : null,
    );
  }
}

/// The HUD's colours, glass recipes, geometry and typography scale.
@immutable
class HudTokens extends ThemeExtension<HudTokens> {
  const HudTokens({
    required this.brightness,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.onAccent,
    required this.base,
    required this.success,
    required this.warning,
    required this.danger,
    required this.zonePoor,
    required this.zoneMid,
    required this.zoneGood,
    required this.panel,
    required this.subPanel,
    required this.contentPanel,
    required this.button,
    required this.chip,
    required this.navBar,
    required this.scanPrimaryButton,
    required this.scanCta,
    required this.trackFill,
    required this.trackBorder,
    required this.progressFill,
    required this.divider,
    required this.tileFill,
    required this.tileBorder,
    required this.readabilityShadow,
    required this.panelReadabilityShadow,
    required this.veilStops,
    required this.ringTrack,
    required this.ringStroke,
    required this.ringGuide,
    required this.ringGlow,
  });

  final Brightness brightness;

  /// `#C9FF47` dark / `#4B7A00` light. Two hues, not one lightened: the light
  /// theme's glass is 30% white over a photograph, and lime on that is
  /// unreadable at any size.
  final Color accent;

  /// Content sitting on a solid [accent] fill — `#14182c` dark, white light.
  final Color onAccent;

  final Color textPrimary;

  /// `rgba(255,255,255,.80)` dark / `rgba(27,32,48,.80)` light. The handoff
  /// gives secondary text as a **range** (.62–.80); this is its top and
  /// [textTertiary] its bottom, so a call site picks a named tier instead of
  /// inventing an alpha.
  final Color textSecondary;

  final Color textTertiary;

  /// The device body colour — what shows before a photograph loads, and what a
  /// solid-accent chip's text sits on.
  final Color base;

  /// `#7BF08A` dark / `#2F7A3A` light.
  ///
  /// The prototypes' inline CSS uses `#96F0A0` for a logged set and a recovered
  /// muscle. `CLAUDE.md` — which names itself the approved formula and says to
  /// read it first — states `#7BF08A`, and the token wins over a literal typed
  /// into one element. The two differ by about 4% lightness; recorded rather
  /// than silently reconciled.
  final Color success;

  final Color warning;
  final Color danger;

  /// The three-zone readiness/recovery ramp, which is **not** success/warning/
  /// danger: it grades a continuous quantity rather than reporting an outcome,
  /// and the handoff gives it its own literals (`#FF6E8C` / `#FFBA5A` /
  /// `#96F0A0`). Sharing the semantic colours here would have made a 32%
  /// recovered chest look like an error, which it is not.
  final Color zonePoor;
  final Color zoneMid;
  final Color zoneGood;

  /// The primary floating surface. Radius 30 on screens, 26 on sheets.
  final HudGlass panel;

  /// The lighter secondary surface — list wrappers, promo rows, week chips.
  final HudGlass subPanel;

  /// The surface for a card that carries a title, metadata, body copy AND an
  /// action together — where [panel]'s 1.4% white fill leaves body text
  /// sitting on whatever pixel the photograph happens to put behind it.
  ///
  /// Its fill alpha is not fixed: `HudPanel(dense: true)` substitutes
  /// `HudBackgroundProfile.denseSurfaceAlpha` for the picture on screen, so a
  /// dark scene keeps more of its photograph than a bright one does.
  final HudGlass contentPanel;

  /// The brightest element on the screen. Never more than one per view.
  final HudGlass button;

  /// Small filter/segment chips in their *unselected* state.
  final HudGlass chip;

  /// The floating tab bar.
  final HudGlass navBar;

  /// The Scan screen's one glass button ("Recognise" / "Scan again").
  ///
  /// SCAN-G1 (core/SCAN_G1_SCOPE.md, R5). Not [button]: the reference's Scan
  /// button is a *different* recipe from the panel-family button every other
  /// screen uses -- on dark it is the nav bar's ink wash, not white glass:
  /// `Sunset.dc.html:221` = `linear-gradient(180deg, rgba(26,15,34,.5),
  /// rgba(26,15,34,.3)); blur(22px); inset 0 1px 0 rgba(255,255,255,.4);
  /// inset 0 0 0 1px rgba(255,255,255,.2); 0 20px 36px -16px rgba(12,7,24,.85);
  /// 0 6px 14px -8px rgba(12,7,24,.5)`. On light (`Light.dc.html:221`) it is
  /// exactly the light panel recipe. Held as its own token, verified by
  /// `scan_glass_recipes_test.dart` against those lines, rather than
  /// approximated with [button] -- a "close enough" recipe is exactly the
  /// class of drift that gate exists to stop.
  final HudGlass scanPrimaryButton;

  /// The Scan match card's "Open exercises" call to action.
  ///
  /// `Sunset.dc.html:214` / `Light.dc.html:214`: `linear-gradient(180deg,
  /// accentSoft, accentFaint)` (accent @ .35 -> .12, the same arithmetic as
  /// [accentChipGradient]) over `blur(18px) saturate(160%)`, `inset 0 1px 0
  /// rgba(255,255,255,.55)`, an `accentLine` (accent @ .40) inner ring, and
  /// two drop shadows (`0 20px 34px -16px` + `0 6px 14px -8px`, ink
  /// `rgba(12,7,24,.85/.5)` on dark, `rgba(42,52,74,.18)` twice on light).
  /// Derived from [accent] in [_withAccent] so an accent preset carries it.
  final HudGlass scanCta;

  /// Indicator tracks: `rgba(255,255,255,.16)` dark, `rgba(27,32,48,.10)` light.
  final Color trackFill;

  /// Light theme only draws a hairline inside its tracks; dark leaves it null-
  /// equivalent (fully transparent) rather than making the field nullable, so
  /// call sites never branch on theme.
  final Color trackBorder;

  /// What fills a track. White on dark (the handoff's own progress rings are
  /// white, not accent); accent on light.
  final Color progressFill;

  final Color divider;

  /// `text-shadow: 0 1px 14px rgba(6,8,18,.85)` — the reason text survives an
  /// arbitrary photograph. Applied to anything drawn outside a panel.
  final List<Shadow> readabilityShadow;

  /// The softer variant panels override to, `0 1px 12px rgba(6,8,18,.7)`.
  final List<Shadow> panelReadabilityShadow;

  /// The veil between photograph and interface, per phase. Keyed by the phase
  /// name so the background engine can look one up without a switch.
  final Map<String, List<Color>> veilStops;

  /// The small inset square behind an icon, and the same treatment on a photo
  /// tile and a volume-chart column: `rgba(255,255,255,.03)` + a `.18` hairline
  /// on dark, `rgba(255,255,255,.28)` + an ink `.16` hairline on light.
  ///
  /// A token rather than two literals at each of the four call sites, because
  /// the two themes do not merely restate it at a different alpha — the
  /// hairline changes from white to ink, which no single expression covers.
  final Color tileFill;
  final Color tileBorder;

  /// Circular-metric ring parts.
  final Color ringTrack;
  final Color ringStroke;
  final Color ringGuide;
  final Color ringGlow;

  // ---------------------------------------------------------------- geometry

  /// Radii, from `CLAUDE.md`: "корпус 26, панели 30, вторичные панели 24–28,
  /// кнопки и чипы 20–22, плитки кадров 16–22".
  static const double radiusDevice = 26;
  static const double radiusPanel = 30;
  static const double radiusSubPanel = 28;
  static const double radiusSheet = 26;
  static const double radiusButton = 22;
  static const double radiusChip = 20;
  static const double radiusTile = 16;

  /// The switch handle, and the ring around it when lit.
  ///
  /// **Theme-invariant on purpose**, and the handoff says why in one line:
  /// "ручка белая с тенью, видна на любом кадре" — white with a shadow, so it
  /// reads on any frame. A handle that flipped to ink on the light theme would
  /// vanish against the white glass it sits on. Same class as
  /// `AppSemanticColors.onGradientInk`: content on something that is not a
  /// theme surface.
  static const Color switchHandleOn = Color(0xFFFFFFFF);
  static const Color switchHandleOff = Color(0xD1FFFFFF); // white @ .82
  static const Color switchRingOn = Color(0x66FFFFFF); // white @ .40

  /// The two rotated gradients at the top of the device.
  ///
  /// Also theme-invariant, and this one is measured rather than argued: a
  /// line-for-line diff of the Light and Sunset prototypes shows both streaks
  /// byte-identical, `rgba(255,255,255,.10)` and `.07` in each. They are a lit
  /// surface, not a surface colour.
  static const Color decorativeHighlight = Color(0xFFFFFFFF);

  /// The reference viewport the handoff is drawn at.
  static const Size referenceViewport = Size(390, 844);

  /// `padding:0 22px` on the status row, `0 20px` on screen headers,
  /// `margin:0 16px` on panels.
  static const double screenGutter = 16;
  static const double headerGutter = 20;

  /// The floating tab bar: `left:12px;right:12px;bottom:14px;height:72px`.
  static const double navBarHeight = 72;
  static const double navBarInset = 12;
  static const double navBarBottom = 14;

  /// What a screen's scroll view must clear at the bottom. The prototype's
  /// `inset:46px 0 158px` — the bar occupies 86 of it and the remaining 72 is
  /// deliberate breathing room.
  static const double navBarClearance = 158;

  /// The fade the handoff masks every scroll view with, so content dissolves
  /// into the photograph instead of being cut by an invisible edge.
  static const double scrollFade = 34;

  /// WCAG 2.5.5 / the handoff's own "хит-таргеты не меньше 44 px".
  static const double minTapTarget = 44;

  // ------------------------------------------------------------ dark tokens

  static final HudTokens dark = HudTokens(
    brightness: Brightness.dark,
    accent: const Color(0xFFC9FF47),
    onAccent: const Color(0xFF14182C),
    textPrimary: const Color(0xFFFFFFFF),
    textSecondary: const Color(0xCCFFFFFF), // white @ .80
    textTertiary: const Color(0xB8FFFFFF), // white @ .72
    base: const Color(0xFF14182C),
    success: const Color(0xFF7BF08A),
    warning: const Color(0xFFFFB86B),
    danger: const Color(0xFFFF5A5A),
    zonePoor: const Color(0xFFFF6E8C),
    zoneMid: const Color(0xFFFFBA5A),
    zoneGood: const Color(0xFF96F0A0),
    panel: HudGlass(
      fill: const Color(0x04FFFFFF), // white @ .014 -> 0x04 (3.57 -> 4)
      cssBlur: 7,
      innerBorder: const Color(0x57FFFFFF), // white @ .34
      glow: BoxShadow(
        color: const Color(0x42FFFFFF), // white @ .26
        blurRadius: 26,
        spreadRadius: -6,
      ),
    ),
    subPanel: HudGlass(
      fill: const Color(0x05FFFFFF), // white @ .02
      cssBlur: 6,
      innerBorder: const Color(0x47FFFFFF), // white @ .28
    ),
    // The fill alpha here is a PLACEHOLDER that `HudPanel(dense: true)`
    // replaces with `HudBackgroundProfile.denseSurfaceAlpha` for the picture
    // actually on screen; only the colour, blur, saturation and hairline come
    // from this recipe. It is written at the protective end so that a surface
    // drawn with no `HudSkyScope` above it still separates.
    //
    // The ink is `#0A0C16` -- the veil's own colour, not a new one -- so a
    // dense card reads as more veil in that spot rather than as a foreign
    // panel. `panel` fills with WHITE at 1.4%, which is why it adds no
    // separation at all over a bright photograph and why this tier had to
    // exist: on a dark interface, more white is the wrong direction. `navBar`
    // already proved the right one (`rgba(26,15,34,.40)`), and is the only
    // surface in the app whose body copy measured above 4.5:1 before this.
    //
    // Blur 20 and saturate 1.5 are not decoration either: the review's
    // complaint was "visual noise from the photograph remains active through
    // content-heavy cards", and luminance alone does not fix competing detail.
    contentPanel: HudGlass(
      fill: const Color(0xAD0A0C16), // #0A0C16 @ .68 -- see maxDenseAlpha
      cssBlur: 20,
      saturate: 1.5,
      innerBorder: const Color(0x3DFFFFFF), // white @ .24
      glow: BoxShadow(
        color: const Color(0x2EFFFFFF), // white @ .18
        blurRadius: 22,
        spreadRadius: -8,
      ),
    ),
    button: HudGlass(
      fill: const Color(0x0DFFFFFF), // white @ .05
      cssBlur: 7,
      innerBorder: const Color(0x75FFFFFF), // white @ .46
      glow: BoxShadow(
        color: const Color(0x59FFFFFF), // white @ .35
        blurRadius: 28,
        spreadRadius: -8,
      ),
    ),
    chip: HudGlass(
      fill: const Color(0x05FFFFFF), // white @ .02
      cssBlur: 6,
      innerBorder: const Color(0x47FFFFFF), // white @ .28
      topHighlight: const Color(0x4DFFFFFF), // white @ .30
    ),
    navBar: HudGlass(
      fill: const Color(
          0x661A0F22), // rgba(26,15,34,.40) -- fillGradient's top stop
      fillGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0x661A0F22), // rgba(26,15,34,.40)
          Color(0x3D1A0F22), // rgba(26,15,34,.24)
        ],
      ),
      cssBlur: 30,
      saturate: 1.8,
      innerBorder: const Color(0x2EFFFFFF), // white @ .18
      topHighlight: const Color(0x6BFFFFFF), // white @ .42
      dropShadows: <BoxShadow>[
        BoxShadow(
          color: const Color(0xE614081E), // rgba(20,10,30,.9)
          blurRadius: 36,
          spreadRadius: -18,
          offset: const Offset(0, 18),
        ),
      ],
    ),
    // `Sunset.dc.html:221` -- see the field's doc comment.
    scanPrimaryButton: HudGlass(
      fill: const Color(0x801A0F22), // rgba(26,15,34,.5) -- the top stop
      fillGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0x801A0F22), // rgba(26,15,34,.5)
          Color(0x4D1A0F22), // rgba(26,15,34,.3)
        ],
      ),
      cssBlur: 22,
      innerBorder: const Color(0x33FFFFFF), // white @ .20
      topHighlight: const Color(0x66FFFFFF), // white @ .40
      dropShadows: <BoxShadow>[
        BoxShadow(
          color: const Color(0xD90C0718), // rgba(12,7,24,.85)
          blurRadius: 36,
          spreadRadius: -16,
          offset: const Offset(0, 20),
        ),
        BoxShadow(
          color: const Color(0x800C0718), // rgba(12,7,24,.5)
          blurRadius: 14,
          spreadRadius: -8,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    scanCta: scanCtaFor(const Color(0xFFC9FF47), Brightness.dark),
    trackFill: const Color(0x29FFFFFF), // white @ .16
    trackBorder: const Color(0x00000000),
    progressFill: const Color(0xFFFFFFFF),
    divider: const Color(0x21FFFFFF), // white @ .13
    tileFill: const Color(0x08FFFFFF), // white @ .03
    tileBorder: const Color(0x2EFFFFFF), // white @ .18
    readabilityShadow: const <Shadow>[
      Shadow(color: Color(0xD9060812), blurRadius: 14, offset: Offset(0, 1)),
    ],
    panelReadabilityShadow: const <Shadow>[
      Shadow(color: Color(0xB3060812), blurRadius: 12, offset: Offset(0, 1)),
    ],
    veilStops: _darkVeil,
    ringTrack: const Color(0x38FFFFFF), // white @ .22
    ringStroke: const Color(0xFFFFFFFF),
    ringGuide: const Color(0x24FFFFFF), // white @ .14
    ringGlow: const Color(0xE6FFFFFF), // white @ .90
  );

  // ----------------------------------------------------------- light tokens

  static final HudTokens light = HudTokens(
    brightness: Brightness.light,
    accent: const Color(0xFF4B7A00),
    onAccent: const Color(0xFFFFFFFF),
    textPrimary: const Color(0xFF1B2030),
    // Light does not mirror dark's alphas: every secondary tier is ~.06
    // HIGHER (dark .80 -> light .86, dark .72 -> light .78). Ink on a 30%
    // white wash over a photograph needs the extra weight that white on a
    // dark wash does not.
    textSecondary: const Color(0xDB1B2030), // ink @ .86
    textTertiary: const Color(0xC71B2030), // ink @ .78
    base: const Color(0xFFEEF0F6),
    success: const Color(0xFF2F7A3A),
    warning: const Color(0xFFFFB86B),
    danger: const Color(0xFFFF5A5A),
    zonePoor: const Color(0xFFFF6E8C),
    zoneMid: const Color(0xFFFFBA5A),
    zoneGood: const Color(0xFF96F0A0),
    panel: HudGlass(
      fill: const Color(0x4DFFFFFF), // white @ .30
      cssBlur: 14,
      saturate: 1.5,
      innerBorder: const Color(0xD9FFFFFF), // white @ .85
      outerBorder: const Color(0x291B2030), // ink @ .16
      dropShadows: <BoxShadow>[
        BoxShadow(
          color: const Color(0x592A344A), // rgba(42,52,74,.35)
          blurRadius: 34,
          spreadRadius: -22,
          offset: const Offset(0, 18),
        ),
      ],
    ),
    subPanel: HudGlass(
      fill: const Color(0x3DFFFFFF), // white @ .24
      cssBlur: 12, // NOT the panel's 14 -- the light prototype drops it here
      innerBorder: const Color(0xCCFFFFFF), // white @ .80
      outerBorder: const Color(0x291B2030), // ink @ .16
    ),
    // Light inverts the direction: its text is ink `#1B2030`, so a dense
    // surface has to push the photograph UP toward white, not down toward
    // black. Same job, opposite end of the scale -- which is exactly why the
    // fill lives in the recipe and the alpha is substituted per picture.
    contentPanel: HudGlass(
      fill: const Color(0xADF6F7FC), // #F6F7FC @ .68 -- light's own veil ink
      cssBlur: 20,
      saturate: 1.5,
      innerBorder: const Color(0xF2FFFFFF), // white @ .95
      outerBorder: const Color(0x3D1B2030), // ink @ .24
    ),
    button: HudGlass(
      fill: const Color(0x75FFFFFF), // white @ .46
      cssBlur: 16,
      saturate: 1.6,
      innerBorder: const Color(0xF2FFFFFF), // white @ .95
      outerBorder: const Color(0x4D1B2030), // ink @ .30
      dropShadows: <BoxShadow>[
        BoxShadow(
          color: const Color(0x662A344A), // rgba(42,52,74,.40)
          blurRadius: 30,
          spreadRadius: -18,
          offset: const Offset(0, 18),
        ),
      ],
    ),
    chip: HudGlass(
      fill: const Color(0x47FFFFFF), // white @ .28
      cssBlur: 12,
      // A single ink ring, not the double white-then-ink ring this recipe
      // carried until a review round checked it against the source: the
      // prototype's chipOff draws exactly one `inset 0 0 0 1px` line.
      innerBorder: const Color(0x3D1B2030), // ink @ .24
      topHighlight: const Color(0x66FFFFFF), // white @ .40
    ),
    // Light does NOT give the bar its own recipe: it reuses panel glass
    // verbatim, dropping dark's tinted gradient and 30px blur entirely.
    navBar: HudGlass(
      fill: const Color(0x4DFFFFFF), // white @ .30
      cssBlur: 14,
      saturate: 1.5,
      innerBorder: const Color(0xD9FFFFFF), // white @ .85
      outerBorder: const Color(0x291B2030), // ink @ .16
      dropShadows: <BoxShadow>[
        BoxShadow(
          color: const Color(0x592A344A),
          blurRadius: 34,
          spreadRadius: -22,
          offset: const Offset(0, 18),
        ),
      ],
    ),
    // `Light.dc.html:221` -- the light Scan button is the light panel recipe
    // verbatim (`rgba(255,255,255,.3); blur(14px) saturate(150%); inset ring
    // .85; ink ring .16; 0 18px 34px -22px rgba(42,52,74,.35)`), restated
    // here rather than aliased so the two cannot drift apart silently.
    scanPrimaryButton: HudGlass(
      fill: const Color(0x4DFFFFFF), // white @ .30
      cssBlur: 14,
      saturate: 1.5,
      innerBorder: const Color(0xD9FFFFFF), // white @ .85
      outerBorder: const Color(0x291B2030), // ink @ .16
      dropShadows: <BoxShadow>[
        BoxShadow(
          color: const Color(0x592A344A), // rgba(42,52,74,.35)
          blurRadius: 34,
          spreadRadius: -22,
          offset: const Offset(0, 18),
        ),
      ],
    ),
    scanCta: scanCtaFor(const Color(0xFF4B7A00), Brightness.light),
    trackFill: const Color(0x1A1B2030), // ink @ .10
    trackBorder: const Color(0x291B2030), // ink @ .16
    progressFill: const Color(0xFF4B7A00),
    divider: const Color(
        0x1F1B2030), // ink @ .12 -- light unifies dark's .12/.13/.14
    tileFill: const Color(0x47FFFFFF), // white @ .28
    tileBorder:
        const Color(0x291B2030), // ink @ .16 -- an ink hairline, not white
    readabilityShadow: const <Shadow>[
      Shadow(color: Color(0xE6FFFFFF), blurRadius: 12, offset: Offset(0, 1)),
    ],
    panelReadabilityShadow: const <Shadow>[
      Shadow(color: Color(0xE6FFFFFF), blurRadius: 12, offset: Offset(0, 1)),
    ],
    veilStops: _lightVeil,
    ringTrack: const Color(0x381B2030),
    ringStroke: const Color(0xFF1B2030),
    ringGuide: const Color(0x241B2030),
    ringGlow: const Color(0x661B2030),
  );

  /// `linear-gradient(180deg, rgba(10,12,22,a+.1) 0%, a 58%, a*.74 82%, a*.9 100%)`
  ///
  /// The alpha per phase is **not** monotonic in daylight — dawn and dusk share
  /// .44 and night and morning share .5 — so this is a table, not a formula
  /// over the phase index.
  static const Map<String, double> darkVeilAlpha = <String, double>{
    'night': 0.50,
    'dawn': 0.44,
    'morning': 0.50,
    'day': 0.56,
    'golden': 0.46,
    'dusk': 0.44,
  };

  /// The stops the veil gradient is sampled at, shared by both themes.
  static const List<double> veilPositions = <double>[0.0, 0.58, 0.82, 1.0];

  static Map<String, List<Color>> get _darkVeil => darkVeilAlpha.map(
        (String phase, double a) => MapEntry<String, List<Color>>(
          phase,
          <Color>[
            const Color(0xFF0A0C16).withValues(alpha: a + 0.1),
            const Color(0xFF0A0C16).withValues(alpha: a),
            const Color(0xFF0A0C16).withValues(alpha: a * 0.74),
            const Color(0xFF0A0C16).withValues(alpha: a * 0.9),
          ],
        ),
      );

  /// Light's veil is phase-independent in the handoff — one gradient,
  /// `rgba(246,247,252,.66/.6/.7)` — because a white glass interface needs the
  /// photograph held down evenly whatever the hour. The 82% stop is
  /// interpolated so both themes carry four stops and the crossfade between
  /// them can lerp position for position.
  static Map<String, List<Color>> get _lightVeil => <String, List<Color>>{
        for (final String phase in darkVeilAlpha.keys)
          phase: <Color>[
            const Color(0xFFF6F7FC).withValues(alpha: 0.66),
            const Color(0xFFF6F7FC).withValues(alpha: 0.60),
            const Color(0xFFF6F7FC).withValues(alpha: 0.64),
            const Color(0xFFF6F7FC).withValues(alpha: 0.70),
          ],
      };

  /// The selected-chip fill: `linear-gradient(180deg, accent@35%, accent@12%)`
  /// with a `accent@50%` hairline. Derived rather than stored because it is
  /// defined in the handoff as arithmetic on the accent
  /// (`accentSoft = accent+'59'`, `accentFaint = accent+'1f'`,
  /// `accentLine = accent+'80'`), and an accent preset must carry it along.
  /// The Scan CTA recipe for an accent -- `Sunset.dc.html:214` /
  /// `Light.dc.html:214`; see [scanCta]. A static so the two static token
  /// sets and [_withAccent] all build it the same way.
  static HudGlass scanCtaFor(Color accent, Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    return HudGlass(
      fill: accent.withValues(alpha: 0.35), // accentSoft = accent + '59'
      fillGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          accent.withValues(alpha: 0.35), // accentSoft = accent + '59'
          accent.withValues(alpha: 0.12), // accentFaint = accent + '1f'
        ],
      ),
      cssBlur: 18,
      saturate: 1.6,
      innerBorder: accent.withValues(alpha: 0.40), // accentLine = accent + '66'
      topHighlight: const Color(0x8CFFFFFF), // white @ .55
      dropShadows: <BoxShadow>[
        BoxShadow(
          color: dark
              ? const Color(0xD90C0718) // rgba(12,7,24,.85)
              : const Color(0x2E2A344A), // rgba(42,52,74,.18)
          blurRadius: 34,
          spreadRadius: -16,
          offset: const Offset(0, 20),
        ),
        BoxShadow(
          color: dark
              ? const Color(0x800C0718) // rgba(12,7,24,.5)
              : const Color(0x2E2A344A), // rgba(42,52,74,.18)
          blurRadius: 14,
          spreadRadius: -8,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  LinearGradient get accentChipGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          accent.withValues(alpha: 0.35),
          accent.withValues(alpha: 0.12),
        ],
      );

  Color get accentChipBorder => accent.withValues(alpha: 0.50);

  /// `inset 0 1px 0 rgba(255,255,255,.5)` on the selected accent chip
  /// (`chipOn`, `Fitness Glass Phone v1 - Sunset.dc.html:686`). The light
  /// prototype's equivalent block was never independently confirmed, so this
  /// stays null there rather than guessing a value.
  Color? get accentChipTopHighlight =>
      brightness == Brightness.dark ? const Color(0x80FFFFFF) : null;

  @override
  HudTokens copyWith({Color? accent}) =>
      accent == null ? this : _withAccent(accent);

  /// The alternate accent presets the prototype offers (`#7CE0FF`, `#FFB86B`,
  /// `#FF7A9C`) work by substitution: every accent-derived value above is
  /// arithmetic on this one colour. Exposed as a method rather than a setting —
  /// per the redesign brief, a preset the prototype could express is not by
  /// itself a reason to ship a user-facing option.
  HudTokens _withAccent(Color next) => HudTokens(
        brightness: brightness,
        accent: next,
        onAccent: onAccent,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textTertiary: textTertiary,
        base: base,
        success: success,
        warning: warning,
        danger: danger,
        zonePoor: zonePoor,
        zoneMid: zoneMid,
        zoneGood: zoneGood,
        panel: panel,
        subPanel: subPanel,
        contentPanel: contentPanel,
        button: button,
        chip: chip,
        navBar: navBar,
        scanPrimaryButton: scanPrimaryButton,
        scanCta: scanCtaFor(next, brightness),
        trackFill: trackFill,
        trackBorder: trackBorder,
        progressFill: progressFill,
        divider: divider,
        tileFill: tileFill,
        tileBorder: tileBorder,
        readabilityShadow: readabilityShadow,
        panelReadabilityShadow: panelReadabilityShadow,
        veilStops: veilStops,
        ringTrack: ringTrack,
        ringStroke: ringStroke,
        ringGuide: ringGuide,
        ringGlow: ringGlow,
      );

  @override
  HudTokens lerp(ThemeExtension<HudTokens>? other, double t) {
    if (other is! HudTokens) return this;
    return HudTokens(
      // Brightness is a discrete fact, not a quantity: half-way between light
      // and dark is not a theme. Snapping at the midpoint keeps anything that
      // branches on it (icon brightness, status-bar style) from reading a value
      // that never existed.
      brightness: t < 0.5 ? brightness : other.brightness,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      base: Color.lerp(base, other.base, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      zonePoor: Color.lerp(zonePoor, other.zonePoor, t)!,
      zoneMid: Color.lerp(zoneMid, other.zoneMid, t)!,
      zoneGood: Color.lerp(zoneGood, other.zoneGood, t)!,
      panel: HudGlass.lerp(panel, other.panel, t),
      subPanel: HudGlass.lerp(subPanel, other.subPanel, t),
      contentPanel: HudGlass.lerp(contentPanel, other.contentPanel, t),
      button: HudGlass.lerp(button, other.button, t),
      chip: HudGlass.lerp(chip, other.chip, t),
      navBar: HudGlass.lerp(navBar, other.navBar, t),
      scanPrimaryButton:
          HudGlass.lerp(scanPrimaryButton, other.scanPrimaryButton, t),
      scanCta: HudGlass.lerp(scanCta, other.scanCta, t),
      trackFill: Color.lerp(trackFill, other.trackFill, t)!,
      trackBorder: Color.lerp(trackBorder, other.trackBorder, t)!,
      progressFill: Color.lerp(progressFill, other.progressFill, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      tileFill: Color.lerp(tileFill, other.tileFill, t)!,
      tileBorder: Color.lerp(tileBorder, other.tileBorder, t)!,
      readabilityShadow:
          Shadow.lerpList(readabilityShadow, other.readabilityShadow, t)!,
      panelReadabilityShadow: Shadow.lerpList(
          panelReadabilityShadow, other.panelReadabilityShadow, t)!,
      veilStops: t < 0.5 ? veilStops : other.veilStops,
      ringTrack: Color.lerp(ringTrack, other.ringTrack, t)!,
      ringStroke: Color.lerp(ringStroke, other.ringStroke, t)!,
      ringGuide: Color.lerp(ringGuide, other.ringGuide, t)!,
      ringGlow: Color.lerp(ringGlow, other.ringGlow, t)!,
    );
  }
}

/// `context.hud.accent` instead of the full extension lookup.
///
/// Falls back to [HudTokens.dark]/[HudTokens.light] by the ambient brightness
/// rather than throwing. `GlassCard` shipped the throwing version of this exact
/// getter once and took down every widget test that pumped a bare `MaterialApp`;
/// a design token that cannot be read outside one specific `ThemeData` makes the
/// component untestable, which is the opposite of what a design system is for.
extension HudTokensX on BuildContext {
  HudTokens get hud {
    final ThemeData theme = Theme.of(this);
    return theme.extension<HudTokens>() ??
        (theme.brightness == Brightness.dark
            ? HudTokens.dark
            : HudTokens.light);
  }
}

extension HudTokensThemeX on ThemeData {
  HudTokens get hud =>
      extension<HudTokens>() ??
      (brightness == Brightness.dark ? HudTokens.dark : HudTokens.light);
}

/// The one place every HUD surface asks "should this actually animate".
///
/// `MediaQuery.of(context).disableAnimations` is the real, standard Flutter
/// API for the OS-level "reduce motion" accessibility signal -- it mirrors
/// `Settings > Accessibility > Reduce Motion` on iOS and
/// `Settings > Accessibility > Remove animations` on Android, and Flutter
/// keeps it live if the user flips it while the app is running. There is
/// deliberately no app-level settings toggle for this: it is the same class
/// of concern as locale or platform brightness -- an OS signal the app must
/// respect, not a preference the app invents its own copy of.
///
/// A HUD surface reads [reduceMotion] directly when it only needs the yes/no
/// (a repeating `AnimationController` deciding whether to `repeat()` at all,
/// for instance) and [hudMotionDuration] when it owns a plain `Duration` --
/// most `Animated*` widgets and `TweenAnimationBuilder` calls -- so the
/// `disableAnimations ? ... : ...` conditional is written once rather than at
/// every call site.
extension HudMotionX on BuildContext {
  /// The platform's "reduce motion" signal, read live off [MediaQuery].
  bool get reduceMotion => MediaQuery.of(this).disableAnimations;

  /// The duration a HUD animation should actually run for.
  ///
  /// Ambient/decorative motion -- a background crossfade, a bar chart
  /// growing in, a value ring sweeping to a number that is also shown as
  /// text -- should call this with the default [reduced] (`Duration.zero`):
  /// reduce motion means that motion is skipped outright and the surface
  /// jumps straight to its end state.
  ///
  /// An animation that IS the state change the user needs to perceive (a
  /// switch flipping, a selected tab's fill changing) should pass a short
  /// but nonzero [reduced] instead, so the change still visibly registers --
  /// just without the animated motion getting there.
  Duration hudMotionDuration(
    Duration normal, {
    Duration reduced = Duration.zero,
  }) =>
      reduceMotion ? reduced : normal;
}
