import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_metric.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import 'scan_glyph.dart';

/// The reference's match card: ring, eyebrow, name, category line, and the
/// "Open exercises" call to action. Ends at the CTA (SCAN-G1, R4).
///
/// `Sunset.dc.html:199-217` / `Light.dc.html:199-217`, top to bottom:
///
///  * the panel: `margin:14px 16px 0; padding:16px 18px; border-radius:30px`
///    on the `t.panel` recipe (line 199);
///  * a row, `gap:16px` (200): a `78px` ring, `r=34`, track `1.5px` at
///    `rgba(_,.22)` (`t.ringTrack`), arc `2.5px` with a `0 0 6px` glow (202-204),
///    the value centred in `400 20px Archivo` (206); then a column: eyebrow
///    `600 9px .16em uppercase` at `.72`/`.78` (209), name `800 19px/1.15`
///    `margin-top:3px` (210), category `400 11.5px` at `.8`/`.86`,
///    `margin-top:3px` (211);
///  * the CTA, `margin-top:14px; padding:14px 16px; border-radius:22px;
///    justify-content:space-between` on [HudTokens.scanCta], label
///    `700 13.5px`, a `19px` `arrow_forward` glyph (214-216).
///
/// Every text in the card carries the card's `text-shadow:0 1px 14px
/// rgba(6,8,18,.85)` (dark) / `0 1px 12px rgba(255,255,255,.9)` (light) --
/// `HudTokens.readabilityShadow`, applied with `overPhoto`. Not `inPanel`:
/// that is the softer `12px/.7` variant other panels declare, and the Scan
/// panels do not.
///
/// The number in the ring is [confidence] exactly as the classifier reported
/// it, `toStringAsFixed(0)` -- `rankTopK` deliberately does not renormalise
/// (`visual_equipment_match.dart`) after a past bug inflated a lone weak
/// survivor to "100%", so this widget must never re-derive or invent one.
class ScanMatchCard extends StatelessWidget {
  const ScanMatchCard({
    super.key,
    required this.confidence,
    required this.name,
    required this.subtitle,
    required this.onOpen,
  });

  /// 0..1.
  final double confidence;
  final String name;

  /// "Strength · Lats, Biceps" -- category, then the muscles the machine's
  /// exercises are for. Assembled by the caller from the catalogue.
  final String subtitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool dark = t.brightness == Brightness.dark;
    final Color eyebrowInk =
        dark ? const Color(0xB8FFFFFF) : const Color(0xC71B2030);
    final Color categoryInk =
        dark ? const Color(0xCCFFFFFF) : const Color(0xDB1B2030);
    final String value = (confidence * 100).toStringAsFixed(0);

    return HudSurface(
      key: const Key('scan-match-card'),
      glass: t.panel,
      // See `HudSurface.shadowOutsideOnly`'s doc -- Scan opts in, the
      // panel-family default (every other panel) does not.
      shadowOutsideOnly: true,
      borderRadius: BorderRadius.circular(HudTokens.radiusPanel),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              HudRing(
                key: const Key('scan-match-ring'),
                size: 78,
                radius: 34,
                strokeWidth: 2.5,
                trackWidth: 1.5,
                glowBlur: 6,
                progress: confidence,
                semanticsLabel: '${l10n.scannerMatchLabel} $value%',
                child: Center(
                  child: Text(
                    value,
                    key: const Key('scan-match-value'),
                    // `font:400 20px Archivo` -- not `HudType.bigNumber`,
                    // whose glow the reference's value does not carry.
                    style: TextStyle(
                      fontFamily: kHudFont,
                      fontFamilyFallback: kHudFontFallback,
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      height: 22 / 20,
                      letterSpacing: 0,
                      color: t.textPrimary,
                    ).overPhoto(t),
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Excluded from semantics: the ring right beside it
                    // already carries `semanticsLabel: "$scannerMatchLabel
                    // $value%"`, so an unguarded second node here duplicated
                    // the announcement ("Match, 20 percent" then, as its own
                    // stop, "MATCH" again) instead of reading as one card
                    // (SCAN-G1 review).
                    ExcludeSemantics(
                      child: Text(
                        l10n.scannerMatchLabel.toUpperCase(),
                        key: const Key('scan-match-eyebrow'),
                        // Line heights are the reference's rendered line
                        // boxes (`scan_anchors.json`: eyebrow 10, name 21.84
                        // = 19*1.15, category 12), set explicitly so the
                        // Material ancestor's body line-height cannot leak in
                        // and move the column.
                        style:
                            HudType.label(t, size: 9, em: 0.16, color: eyebrowInk)
                                .copyWith(height: 10 / 9)
                                .overPhoto(t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name,
                      key: const Key('scan-match-name'),
                      // `letterSpacing: 0` -- the handoff declares none here;
                      // `HudType.panelHeading`'s shared default is left alone
                      // for every other screen (R5).
                      style: HudType.panelHeading(t)
                          .copyWith(fontSize: 19, height: 1.15, letterSpacing: 0)
                          .overPhoto(t),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      key: const Key('scan-match-category'),
                      // `font:400 11.5px` at line-height normal; `HudType.body`
                      // would add the 1.5 line-height body copy carries.
                      style: TextStyle(
                        fontFamily: kHudFont,
                        fontFamilyFallback: kHudFontFallback,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                        height: 12 / 11.5,
                        letterSpacing: 0,
                        color: categoryInk,
                      ).overPhoto(t),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HudButton(
            key: const Key('scan-open-exercises'),
            label: l10n.scannerOpenExercises,
            onPressed: onOpen,
            glass: t.scanCta,
            // See `HudSurface.shadowOutsideOnly`'s doc -- Scan opts in, the
            // panel-family default (every other button) does not.
            shadowOutsideOnly: true,
            radius: HudTokens.radiusButton,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            // `700 13.5px` at line-height normal: a 15px line box
            // (`cta_label`), set explicitly for the same reason as above.
            // Letter-spacing pinned to 0 the same way `scan-match-name` is --
            // the handoff declares none, `HudType.rowTitle`'s shared default
            // is left alone for every other button (R5). ... and it inherits
            // the card's text-shadow (line 199), so `overPhoto` here too.
            labelStyle: HudType.rowTitle(t, strong: true)
                .copyWith(height: 15 / 13.5, letterSpacing: 0)
                .overPhoto(t),
            trailing: ScanGlyph(
              codePoint: ScanGlyph.arrowForward,
              size: 19,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
