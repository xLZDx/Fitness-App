/// One mode card of the chooser (contract C-1, S-1; AC-CH-1 to AC-CH-3, DT-08-5).
///
/// Built on [HudPanel] with the S03-03 extensions (selected flag, hint, enabled,
/// focus ring, hover wash, cursor). A coming-later card stays ENABLED so it can
/// be focused and tapped (the sheet opens), but its label and hint say "Coming
/// later" and it can never be selected.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../data/mode_models.dart';
import 'mode_text.dart';

class ModeCard extends StatefulWidget {
  const ModeCard({
    super.key,
    required this.mode,
    required this.name,
    required this.blurb,
    required this.description,
    required this.comingLaterWord,
    required this.selectedWord,
    required this.selected,
    required this.comingLater,
    required this.showBlurb,
    required this.onTap,
    this.onHighlight,
    this.minHeight = 120,
    this.loadingOutline = false,
  });

  final AppMode mode;
  final String name;
  final String blurb;

  /// The card's description, spoken as its hint.
  final String description;
  final String comingLaterWord;
  final String selectedWord;
  final bool selected;
  final bool comingLater;
  final bool showBlurb;

  /// Null in the loading outline.
  final VoidCallback? onTap;

  /// Called with true while the pointer hovers or keyboard focus is on the card,
  /// false when both are gone. Never changes the selection.
  final ValueChanged<bool>? onHighlight;

  final double minHeight;

  /// Four empty outlines with no button behaviour while the saved mode loads.
  final bool loadingOutline;

  @override
  State<ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<ModeCard> {
  bool _hover = false;
  bool _focus = false;
  bool _reported = false;

  void _report() {
    final bool now = _hover || _focus;
    if (now == _reported) return;
    _reported = now;
    widget.onHighlight?.call(now);
  }

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    const double radius = 22;

    if (widget.loadingOutline) {
      return HudPanel(
        radius: radius,
        secondary: true,
        padding: EdgeInsets.zero,
        enabled: false,
        // An invisible loaded card keeps the outline exactly as tall as the
        // loaded card (no row shift when the saved mode arrives, P-7).
        child: Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: ModeCard(
            mode: widget.mode,
            name: widget.name,
            blurb: widget.blurb,
            description: widget.description,
            comingLaterWord: widget.comingLaterWord,
            selectedWord: widget.selectedWord,
            selected: false,
            comingLater: widget.comingLater,
            showBlurb: widget.showBlurb,
            onTap: null,
            minHeight: widget.minHeight,
          ),
        ),
      );
    }

    final String? chipWord = widget.comingLater
        ? widget.comingLaterWord
        : (widget.selected ? widget.selectedWord : null);
    final String label = widget.comingLater
        ? '${widget.name}. ${widget.comingLaterWord}'
        : (widget.showBlurb ? '${widget.name}. ${widget.blurb}' : widget.name);
    final String hint = widget.comingLater
        ? '${widget.description} ${widget.comingLaterWord}'
        : widget.description;

    final Widget panel = HudPanel(
      radius: radius,
      padding: const EdgeInsets.all(14),
      onTap: widget.onTap,
      semanticLabel: label,
      semanticHint: hint,
      selected: widget.selected,
      enabled: true,
      inMutuallyExclusiveGroup: true,
      showFocusRing: true,
      hoverStyle: true,
      cursor: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: double.infinity,
          minHeight: widget.minHeight - 28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  modeIconOf(widget.mode),
                  size: 26,
                  color: widget.selected ? t.accent : t.textPrimary,
                ),
                const SizedBox(width: 8),
                // The chip takes all the room left of the icon and wraps
                // instead of being cut (a Spacer would halve its width).
                Expanded(
                  child: chipWord == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: HudChip(
                            label: chipWord,
                            selected: widget.selected,
                            minHeight: 24,
                            maxLines: 2,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // No maxLines: Russian names must wrap, never be cut (AC-CH-13).
            Text(
              widget.name,
              style: HudType.rowTitle(t, strong: true).copyWith(fontSize: 16),
            ),
            if (widget.showBlurb) ...<Widget>[
              const SizedBox(height: 4),
              Text(widget.blurb, style: HudType.body(t, size: 12)),
            ],
          ],
        ),
      ),
    );

    // The selection border is always present (transparent when not selected) so
    // the element tree does not change shape when the selection moves.
    return MouseRegion(
      onEnter: (_) {
        _hover = true;
        _report();
      },
      onExit: (_) {
        _hover = false;
        _report();
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (bool focused) {
          _focus = focused;
          _report();
        },
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: widget.selected ? t.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: panel,
        ),
      ),
    );
  }
}
