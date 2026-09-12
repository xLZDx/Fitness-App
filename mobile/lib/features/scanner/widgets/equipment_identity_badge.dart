import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../visual_equipment/data/equipment_identity.dart';

/// P2.G4's scan-result surface for the server's identity verdict.
///
/// ## What this is, and what it deliberately is not
///
/// This gate ("Additive mobile identity contract & progressive UX plumbing")
/// builds the plumbing, not a finished catalog display: no canonical brand/
/// product-line/model/setup-spec display data exists on the client yet (see
/// the Rosetta plan's own NOT-IN-SCOPE list), so this widget never invents
/// one. Every value it shows is the server's own opaque identifier
/// (`modelId`/`catalogVersion`) or a raw contract enum value -- honest about
/// being a technical detail, never dressed up as a friendly catalog entry.
///
/// ## OP-01: silence is the default
///
/// Renders `SizedBox.shrink()` for every [EquipmentIdentity] that is `null`
/// (enrichment off, no result yet, or any upstream failure --
/// `equipmentIdentityProvider` already fails open to `null`), and for
/// `ABSTAIN`/every `UNAVAILABLE_*` decision -- none of those give the user
/// anything actionable to see, and a badge that renders for "the server
/// could not tell" would read as a claim it never made. `CANCELLED_STALE`
/// and `UNSUPPORTED_CLIENT_CONTRACT` render nothing for the same reason:
/// both are protocol-level states about the REQUEST, not a finding about
/// the machine. `NEED_MORE_VIEW` is handled by the caller, not this widget
/// -- see [EquipmentIdentityNeedMoreViewPrompt] below.
///
/// ## OP-02: collapsed by default
///
/// Only `MATCH` and `NOT_SUPPORTED` (the only decisions that can carry a
/// [EquipmentIdentity.model] or [EquipmentIdentity.shadowCandidate]) render
/// anything -- a single-line, tap-to-expand pill. Expanding shows the
/// decision's identity level and the opaque model/shadow-candidate fields;
/// a [EquipmentIdentityShadowCandidate] is always captioned as an internal,
/// non-authoritative experimental candidate, never as a confirmed match --
/// mirroring the server's own `ShadowCandidateSchema` doc comment.
class EquipmentIdentityBadge extends StatefulWidget {
  const EquipmentIdentityBadge({super.key, required this.identity});

  final EquipmentIdentity? identity;

  /// Whether [identity] is one this widget renders anything for at all --
  /// exposed so callers (the scan-level identity slot in `scanner_page.dart`)
  /// can decide layout (e.g. spacing) without duplicating this decision.
  ///
  /// GPT-PM pre-commit review, this gate: an ordinary `NOT_SUPPORTED` with no
  /// `shadowCandidate` is the server's own genuine zero-evidence/no-candidate
  /// answer (`exact_resolution_policy.ts`'s `NOT_ELIGIBLE` -> orchestrator's
  /// `NOT_SUPPORTED`, no shadow) -- OP-01 requires that to render nothing,
  /// same as any other empty/ABSTAIN/error state, because a plain "Server
  /// check" pill on an ordinary no-placard scan would make enrichment-on and
  /// enrichment-off visibly different for the exact case OP-01 exists to
  /// keep invisible. `NOT_SUPPORTED` is only ever visible here when it
  /// carries a `shadowCandidate` -- a real (if non-authoritative) finding,
  /// not silence.
  static bool isVisible(EquipmentIdentity? identity) {
    if (identity == null) return false;
    return identity.decision == EquipmentIdentityDecision.match ||
        (identity.decision == EquipmentIdentityDecision.notSupported &&
            identity.shadowCandidate != null);
  }

  @override
  State<EquipmentIdentityBadge> createState() => _EquipmentIdentityBadgeState();
}

class _EquipmentIdentityBadgeState extends State<EquipmentIdentityBadge> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final identity = widget.identity;
    if (!EquipmentIdentityBadge.isVisible(identity)) return const SizedBox.shrink();
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final bool dark = t.brightness == Brightness.dark;
    final Color ink = dark ? const Color(0xB8FFFFFF) : const Color(0xC71B2030);
    final BorderRadius radius = BorderRadius.circular(14);

    // Accessibility review (this gate): the header row's own icon/label/
    // chevron text is excluded here (`excludeSemantics`) so it is not
    // announced a second time under the explicit `label:` below -- same
    // reason `HudButton`/`HudPanel` exclude their own labelled content.
    // Verified (widget test, `matchesSemantics`): because this is the only
    // semantics boundary anywhere in the pill, the expanded detail lines
    // below -- siblings of this node, not descendants of it -- merge INTO
    // this same node rather than being dropped: a screen reader gets one
    // focus stop per state that reads label + role + expanded state, and
    // (once expanded) the detail content too, all together.
    final Widget header = Semantics(
      key: const Key('equipment-identity-badge-header-semantics'),
      button: true,
      expanded: _expanded,
      label: l10n.equipmentIdentityBadgeLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.verified_outlined, size: 14, color: ink),
          const SizedBox(width: 6),
          Text(
            l10n.equipmentIdentityBadgeLabel,
            style: TextStyle(fontSize: 11, color: ink),
          ),
          const SizedBox(width: 4),
          Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 16,
            color: ink,
          ),
        ],
      ),
    );

    // Accessibility review (this gate): a bare Container/BoxDecoration
    // is a flat, unblurred, low-alpha fill that the app's own HUD
    // design tokens document as insufficient over the photograph this
    // screen shows (`hud_tokens.dart`'s own doc comment on `panel`'s
    // 1.4% fill). Routed through `HudSurface`/`t.chip` instead -- the
    // same contrast-engineered recipe every other tappable chip-style
    // surface in this app already uses -- and given a 44px minimum
    // tap target (WCAG 2.5.5 / `HudTokens.minTapTarget`), which the
    // original 12/8-padded ~32px pill fell well under.
    final Widget pill = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: HudTokens.minTapTarget),
      child: HudSurface(
        glass: t.chip,
        borderRadius: radius,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              header,
              if (_expanded) ...<Widget>[
                const SizedBox(height: 6),
                ..._expandedLines(identity!, l10n, ink),
              ],
            ],
          ),
        ),
      ),
    );

    // GPT-PM round-2 review (this gate): OP-02/T6's "small fixed badge size"
    // is a footprint requirement, width included, for the COLLAPSED state
    // specifically ("the collapsed indicator's footprint" -- T6's own DoD
    // wording; the expanded panel is explicitly allowed to grow). Verified
    // empirically (not by reasoning about the widget tree, which was wrong
    // twice before this): `HudSurface`'s `topHighlight` branch always wraps
    // its content in `Stack(fit: StackFit.passthrough)` -- every `HudGlass`
    // recipe with a `topHighlight` (including `t.chip`, used here) hits
    // this -- and that Stack reports its OWN size as the biggest its
    // incoming constraints allow, regardless of its children's actual size.
    // No shrink-wrap technique (`Align`+`widthFactor`, `IntrinsicWidth`)
    // changes that; it is `HudSurface`'s own behavior, shared by every
    // caller, not specific to this widget. So a stretch `Column` (this
    // widget's ScannerPage placement) or a `ListView` item (its
    // WorkoutPlayerPage placement) makes the pill fill that width exactly
    // -- fixed here with an explicit `maxWidth`, which the same Stack
    // quirk then honours literally, giving a genuinely small, FIXED
    // footprint rather than an organic content-hugging one. Bounding
    // `maxHeight` alongside it is required too: an unbounded height next to
    // a newly-bounded width made the same Stack fall back to some large,
    // unrelated value (measured 208px for one short line) rather than its
    // small natural height -- bounding both together avoids that. Only
    // applied while collapsed: constraining the EXPANDED state the same way
    // risks silently clipping a longer detail line (`HudSurface` clips via
    // its own `ClipRRect`), which T6 never asks for.
    final Widget bounded = _expanded
        ? pill
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220, maxHeight: 60),
            child: pill,
          );

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        key: const Key('equipment-identity-badge'),
        padding: const EdgeInsets.only(top: 10),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: () => setState(() => _expanded = !_expanded),
            child: bounded,
          ),
        ),
      ),
    );
  }

  List<Widget> _expandedLines(
    EquipmentIdentity identity,
    AppLocalizations l10n,
    Color ink,
  ) {
    final lines = <String>[];
    final model = identity.model;
    final shadow = identity.shadowCandidate;
    if (model != null) {
      lines.add(l10n.equipmentIdentityBadgeMatchLine(model.modelId, model.catalogVersion));
    }
    if (shadow != null) {
      lines.add(
        l10n.equipmentIdentityBadgeShadowLine(shadow.modelId, shadow.catalogVersion),
      );
    }
    final level = identity.identityLevel;
    if (level != null) {
      lines.add(l10n.equipmentIdentityBadgeLevelLine(_levelWireName(level)));
    }
    return [
      for (final line in lines)
        Text(line, style: TextStyle(fontSize: 10.5, color: ink)),
    ];
  }

  static String _levelWireName(EquipmentIdentityLevel level) => switch (level) {
        EquipmentIdentityLevel.typeOnly => 'TYPE_ONLY',
        EquipmentIdentityLevel.brandAndType => 'BRAND_AND_TYPE',
        EquipmentIdentityLevel.productLine => 'PRODUCT_LINE',
        EquipmentIdentityLevel.exactModel => 'EXACT_MODEL',
      };
}

/// The separate, plain re-scan prompt for `NEED_MORE_VIEW` -- deliberately
/// not part of [EquipmentIdentityBadge] (which never renders for this
/// decision): this is actionable guidance, not a verdict to disclose.
class EquipmentIdentityNeedMoreViewPrompt extends StatelessWidget {
  const EquipmentIdentityNeedMoreViewPrompt({super.key, required this.identity});

  final EquipmentIdentity? identity;

  static bool isVisible(EquipmentIdentity? identity) =>
      identity?.decision == EquipmentIdentityDecision.needMoreView;

  @override
  Widget build(BuildContext context) {
    if (!isVisible(identity)) return const SizedBox.shrink();
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final bool dark = t.brightness == Brightness.dark;
    final Color ink = dark ? const Color(0xB8FFFFFF) : const Color(0xC71B2030);

    // GPT-PM round-2 review (this gate): the width-footprint finding was
    // about the COLLAPSED identity BADGE specifically (T6's own DoD text:
    // "the collapsed indicator's footprint") -- this widget is a full
    // instructional sentence meant to wrap across a few lines, not a
    // collapsed one-line pill, so it is deliberately left filling its
    // normal width rather than force-narrowed to match.
    return Padding(
      key: const Key('equipment-identity-need-more-view'),
      padding: const EdgeInsets.only(top: 10),
      // Accessibility review (this gate): same fix as `EquipmentIdentityBadge`
      // -- this had no background at all, an even milder case of the same
      // "flat/no fill over an uncontrolled photograph" gap -- routed through
      // the same `HudSurface`/`t.chip` recipe for consistency.
      child: HudSurface(
        glass: t.chip,
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          l10n.equipmentIdentityNeedMoreViewPrompt,
          style: TextStyle(fontSize: 11.5, color: ink),
        ),
      ),
    );
  }
}
