import 'package:flutter/material.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import 'scan_frame.dart';
import 'scan_glyph.dart';

/// The reference's viewfinder card, with the live camera inside it.
///
/// SCAN-G1 (core/SCAN_G1_SCOPE.md). `Sunset.dc.html:186-196` /
/// `Light.dc.html:186-196`: a `230px` panel (`border-radius:30px`, the
/// `t.panel` glass recipe -- verified field by field against line 186 in
/// the scope note) holding four corner brackets and a sweep line
/// ([ScanFrame]), and, centred, a 36px `center_focus_weak` glyph over a
/// `600 10px` monospace hint tracked `.14em`, 9px apart. The reference draws
/// no photo in the card; here the camera preview fills it, under the frame,
/// which is the one production capability the reference does not model and
/// the scope note keeps.
///
/// Colours, per theme, from the same lines:
///
/// | | dark (`Sunset`) | light (`Light`) |
/// |---|---|---|
/// | brackets | `rgba(255,255,255,.9)` | `rgba(27,32,48,.42)` |
/// | glyph | `rgba(255,255,255,.9)` | `rgba(27,32,48,.92)` |
/// | hint | `rgba(255,255,255,.8)` | `rgba(27,32,48,.86)` |
///
/// The card's rendered size is what the capture path maps the bracket
/// window through ([windowNormalized], `cropToViewfinder`), so the caller
/// gives it a key and reads its `RenderBox` at capture time -- the crop IS
/// the window the user saw, not a guess about it (R7).
class ScanViewfinder extends StatelessWidget {
  const ScanViewfinder({
    super.key,
    required this.preview,
    required this.phase,
    required this.hint,
    this.guides = true,
    this.banner,
    this.corner,
  });

  /// The camera (or whatever stands in for it). Fills the card.
  final Widget preview;

  final ScanFramePhase phase;

  /// Already uppercase, already localised.
  final String hint;

  /// False draws the camera alone: no brackets, no glyph, no hint, no sweep.
  /// The camera-unavailable state (an aiming frame over "camera access is
  /// blocked" tells the user to aim at nothing) and the evidence mode (R1,
  /// which needs the raw preview to prove liveness) both use it.
  final bool guides;

  /// Drawn along the top edge, over the preview -- the low-light banner.
  final Widget? banner;

  /// Drawn in the top-left corner, over everything -- the evidence-mode
  /// frame counter.
  final Widget? corner;

  /// `height:230px`.
  static const double height = 230;

  /// `border-radius:30px`.
  static const double radius = HudTokens.radiusPanel;

  /// `gap:9px` between the glyph and the hint.
  static const double glyphHintGap = 9;

  /// The bracket window as fractions of the card, for [viewfinderSourceRect]:
  /// `ScanFrame.inset` in from every edge.
  static Rect windowNormalized(Size card) => Rect.fromLTRB(
        ScanFrame.inset / card.width,
        ScanFrame.inset / card.height,
        1 - ScanFrame.inset / card.width,
        1 - ScanFrame.inset / card.height,
      );

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final bool dark = t.brightness == Brightness.dark;
    final Color bracket =
        dark ? const Color(0xE6FFFFFF) : const Color(0x6B1B2030);
    final Color glyph = dark ? const Color(0xE6FFFFFF) : const Color(0xEB1B2030);
    final Color hintInk =
        dark ? const Color(0xCCFFFFFF) : const Color(0xDB1B2030);

    return HudSurface(
      glass: t.panel,
      // See `HudSurface.shadowOutsideOnly`'s doc -- Scan opts in, the
      // panel-family default (every other panel) does not.
      shadowOutsideOnly: true,
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            preview,
            if (guides) ...<Widget>[
              IgnorePointer(
                child: ScanFrame(
                  key: const Key('scan-frame'),
                  phase: phase,
                  bracket: bracket,
                  accent: t.accent,
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ScanGlyph(
                        key: const Key('scan-centre-glyph'),
                        codePoint: ScanGlyph.centerFocusWeak,
                        size: 36,
                        color: glyph,
                      ),
                      const SizedBox(height: glyphHintGap),
                      // `liveRegion`: this one node's VALUE is what carries
                      // the scan's whole progress (align -> recognising ->
                      // locked), not a new node appearing -- without it a
                      // screen-reader user has no way to learn a scan
                      // finished short of re-swiping the screen after every
                      // tap (SCAN-G1 review).
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          hint,
                          key: const Key('scan-hint'),
                          // Line-height normal for Roboto Mono at 10px is a
                          // 13px line box (`scan_anchors.json` `hint`); set
                          // explicitly so no ancestor `DefaultTextStyle`
                          // (Material's 1.43) can change where the hint
                          // sits under the glyph.
                          // The card's own `text-shadow:0 1px 14px
                          // rgba(6,8,18,.85)` (line 186) is `readabilityShadow`
                          // (`overPhoto`), not the softer 12px/.7 panel variant.
                          style:
                              HudType.mono(t, size: 10, em: 0.14, color: hintInk)
                                  .copyWith(height: 1.3)
                                  .overPhoto(t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // The hint is a fixed piece of the design, not
                          // running text; scaled up it would collide with
                          // the brackets. Its meaning is repeated by the
                          // screen's subtitle at the user's size.
                          textScaler: TextScaler.noScaling,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (banner != null)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Center(child: banner),
              ),
            if (corner != null)
              Positioned(top: 6, left: 6, child: corner!),
          ],
        ),
      ),
    );
  }
}
