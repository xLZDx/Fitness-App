/// The HUD's type scale, and the one place the Cyrillic problem is solved.
///
/// ## Archivo cannot set Russian, and this app's default language is Russian
///
/// Measured, twice and independently, on 2026-08-19:
///
/// * `Archivo[wdth,wght].ttf` from `google/fonts@main` has **0 of 256**
///   codepoints in the Cyrillic block, and neither `Ё` (U+0401) nor `ё`
///   (U+0451). Its cmap holds 653 glyphs: Latin, Latin Extended, Vietnamese.
/// * Google's own `ofl/archivo/METADATA.pb` declares
///   `subsets: latin, latin-ext, menu, vietnamese`.
///
/// The handoff names Archivo as the typeface. `pubspec.yaml` names Russian as
/// this app's default language. Both are true, and neither can be satisfied by
/// the other's means, so the resolution is stated here rather than discovered
/// later as a rendering bug:
///
/// **Archivo sets Latin; Inter sets Cyrillic**, through [kHudFontFallback].
/// Flutter's fallback is per-glyph, so a Russian screen renders wholly in Inter,
/// an English screen wholly in Archivo, and a mixed string switches at the
/// glyph. Inter is already bundled at every weight Archivo is, so this costs
/// nothing and — importantly — cannot fail *silently*: the alternative, naming
/// Archivo alone, would have fallen back to the **platform** font for every
/// Russian string, which is a different face on every device and is precisely
/// the failure this project removed when it deleted `google_fonts`.
///
/// Worth stating plainly: the handoff's own screenshots show Russian text in
/// the Form Coach screen. That text was not set in Archivo either — the browser
/// fell back for it, exactly as this does, just without anyone choosing the
/// fallback.
///
/// ## `ui-monospace` is a system font by intent, and here it is a bundled one
///
/// The handoff asks for `ui-monospace` — deliberately "whatever mono the OS
/// has" rather than a brand face. Flutter cannot honour that instruction
/// portably: `fontFamily: 'monospace'` resolves to Roboto Mono on Android and
/// to Courier on iOS, which is not the same design at all, and Courier has no
/// place in this interface. Roboto Mono is bundled instead — it *is* the
/// Android system mono, it carries full Cyrillic (64/64 plus Ё/ё, verified),
/// and bundling it makes the two platforms render the same technical values.
library;

import 'package:flutter/material.dart';

import 'hud_tokens.dart';

/// The display/UI family the handoff names.
const String kHudFont = 'Archivo';

/// Per-glyph fallback for everything Archivo has no glyph for — in practice,
/// all Cyrillic. See the library doc.
const List<String> kHudFontFallback = <String>['Inter'];

/// Technical values, eyebrows and units.
const String kHudMonoFont = 'Roboto Mono';

/// `letter-spacing: <em>` resolved against a size, because tracking is
/// proportional and a single constant that suits 9px is heavy-handed at 22px.
double _tracking(double em, double size) => em * size;

/// The HUD type scale.
///
/// Every method takes the tokens rather than reading a `BuildContext`, so a
/// style can be built inside a `CustomPainter`, a golden fixture or a const-ish
/// helper without a widget tree in scope.
abstract final class HudType {
  // ------------------------------------------------------------- structural

  /// Screen heading — `font:800 24px/1.1 Archivo` (Train / Scan / Progress /
  /// Profile). The handoff's token table says 22px; the prototypes' own screen
  /// titles are 24px and the 22px entry is the Home hero title below. Both are
  /// kept, named for where they are used.
  static TextStyle screenTitle(HudTokens t) => _base(
        size: 24,
        weight: FontWeight.w800,
        height: 1.1,
        letterSpacing: _tracking(-0.02, 24),
        color: t.textPrimary,
      );

  /// Hero title — `font:800 22px/1.12 Archivo; letter-spacing:-.015em`.
  static TextStyle heroTitle(HudTokens t) => _base(
        size: 22,
        weight: FontWeight.w800,
        height: 1.12,
        letterSpacing: _tracking(-0.015, 22),
        color: t.textPrimary,
      );

  /// `font:800 20px/1.1` — a name inside a panel (programme, machine, person).
  static TextStyle panelHeading(HudTokens t) => _base(
        size: 20,
        weight: FontWeight.w800,
        height: 1.1,
        color: t.textPrimary,
      );

  /// Panel title — `font:700 14px`.
  static TextStyle panelTitle(HudTokens t) => _base(
        size: 14,
        weight: FontWeight.w700,
        color: t.textPrimary,
      );

  /// A tappable row's title — `font:700 13.5px` (promo) / `600 13.5px` (list).
  static TextStyle rowTitle(HudTokens t, {bool strong = false}) => _base(
        size: 13.5,
        weight: strong ? FontWeight.w700 : FontWeight.w600,
        color: t.textPrimary,
      );

  /// A row's supporting line — `font:400 10.5px`.
  static TextStyle rowMeta(HudTokens t) => _base(
        size: 10.5,
        weight: FontWeight.w400,
        color: t.textSecondary,
      );

  /// Body copy — `400 11–13px, line-height 1.4–1.6`.
  static TextStyle body(HudTokens t, {double size = 11.5}) => _base(
        size: size,
        weight: FontWeight.w400,
        height: 1.5,
        color: t.textSecondary,
      );

  /// Emphasised body inside a panel — `font:500 12.5px`, primary colour.
  static TextStyle bodyStrong(HudTokens t, {double size = 12.5}) => _base(
        size: size,
        weight: FontWeight.w500,
        color: t.textPrimary,
      );

  // ------------------------------------------------------------------ label

  /// Uppercase tracked label — `600 9–11px, letter-spacing .16–.18em`.
  ///
  /// One method with a size rather than three named constants: the handoff uses
  /// 9.5 / 8.5 / 7.5 in three places for the same role, and naming each would
  /// imply a distinction the design does not make.
  static TextStyle label(
    HudTokens t, {
    double size = 9.5,
    double em = 0.16,
    Color? color,
  }) =>
      _base(
        size: size,
        weight: FontWeight.w600,
        letterSpacing: _tracking(em, size),
        color: color ?? t.textSecondary,
      );

  /// The label inside a circular metric — `600 7.5px, .18em`.
  static TextStyle ringLabel(HudTokens t) =>
      label(t, size: 7.5, em: 0.18, color: t.textSecondary);

  /// Tab bar label — `600 8.5px, .08em, uppercase`.
  static TextStyle navLabel(HudTokens t, {required Color color}) =>
      label(t, size: 8.5, em: 0.08, color: color);

  // ------------------------------------------------------------------- mono

  /// Technical values — `ui-monospace 9–11px, letter-spacing .1em`.
  static TextStyle mono(
    HudTokens t, {
    double size = 10,
    FontWeight weight = FontWeight.w600,
    double em = 0.1,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: kHudMonoFont,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: _tracking(em, size),
        color: color ?? t.textPrimary,
        // Roboto Mono is already fixed-pitch, so this changes nothing for it —
        // it is here so that a fallback face, if one is ever reached for a
        // glyph Roboto Mono lacks, still lines its digits up in a column.
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  // ----------------------------------------------------------- large number

  /// A large metric — **weight 400**, 34–72px, with a soft glow.
  ///
  /// The weight is the whole point and the easiest thing to get wrong: the
  /// handoff states it twice ("Вес крупных чисел — 400, не bold: контраст даёт
  /// размер и свечение"). A bold 54px number is a different design.
  static TextStyle bigNumber(
    HudTokens t, {
    required double size,
    Color? color,
    double em = 0,
  }) =>
      _base(
        size: size,
        weight: FontWeight.w400,
        height: 1.0,
        letterSpacing: em == 0 ? null : _tracking(em, size),
        color: color ?? t.textPrimary,
      ).copyWith(
        shadows: <Shadow>[
          Shadow(
            // `text-shadow: 0 2px 26px rgba(255,255,255,.45)` on dark. On light
            // a white glow behind ink would do nothing, so the glow becomes the
            // theme's own readability shadow instead of being dropped — the
            // number still has to survive a photograph.
            color: t.brightness == Brightness.dark
                ? const Color(0x73FFFFFF)
                : const Color(0xE6FFFFFF),
            blurRadius: 26,
            offset: const Offset(0, 2),
          ),
        ],
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    required Color color,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: kHudFont,
        fontFamilyFallback: kHudFontFallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        // A null field here INHERITS from the ambient `DefaultTextStyle`,
        // which under a Material ancestor is the theme's `bodyMedium` and
        // its 0.3px tracking -- the handoff declares no letter-spacing on
        // these styles, so that is a real leak (measured by SCAN-G1's
        // fidelity diff: the Scan subtitle came out 12 logical px wider than
        // the same string in Chrome). Left as `letterSpacing` unchanged
        // rather than pinned to 0 here: this is every screen's shared base,
        // and R5 (core/SCAN_G1_SCOPE.md) requires existing HUD goldens not
        // to move. Scan pins its own affected styles to 0 explicitly at its
        // own call sites instead (`HudScreenTitle.subtitleLetterSpacing`,
        // `scan_match_card.dart`'s `.copyWith(letterSpacing: 0)`).
        letterSpacing: letterSpacing,
        color: color,
      );
}

/// Adds the readability shadow that lets text sit directly on a photograph.
///
/// Only for text drawn **outside** a panel — a panel already carries its own
/// softer variant, and stacking both produces a smear.
extension HudReadableText on TextStyle {
  TextStyle overPhoto(HudTokens t) => copyWith(shadows: t.readabilityShadow);
  TextStyle inPanel(HudTokens t) =>
      copyWith(shadows: t.panelReadabilityShadow);
}
