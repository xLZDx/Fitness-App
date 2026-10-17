/// The two mode widgets of Home (S03-12; contract S-6 and C-2): the mode chip
/// in the greeting row and the one-time upgrader intro card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/app_shortcuts.dart'
    show modeSwitcherOpenerProvider;
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../modes/data/mode_models.dart' show AppMode;
import '../../modes/widgets/mode_switcher_sheet.dart' show kHomeModeChipKey;
import '../../modes/widgets/mode_text.dart';

/// C-2: the mode chip (`home.modeChip`). Opens the mode switcher through
/// [modeSwitcherOpenerProvider] (lane L6 sets it; null does nothing). Hugs its
/// text, never below 48 dp high, wraps to two lines instead of truncating.
class HomeModeChip extends ConsumerWidget {
  const HomeModeChip({super.key, required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // `Key('home.modeChip')` is the test locator; the global key is the anchor
    // the switcher popover measures (lane L6).
    return KeyedSubtree(
      key: const Key('home.modeChip'),
      // HudChip takes a text label only, so the leading mode icon sits beside
      // it (decorative; the chip keeps its key and accessible name).
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(modeIconOf(mode), size: 20, color: context.hud.accent),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: HudChip(
              key: kHomeModeChipKey,
              label: modeNameOf(l10n, mode),
              selected: true,
              minHeight: 48,
              maxLines: 2,
              semanticLabel: l10n.homeModeChipLabel(mode.name),
              showFocusRing: true,
              hoverStyle: true,
              cursor: true,
              onTap: () => ref.read(modeSwitcherOpenerProvider)?.call(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// The upgrader intro card (`home.modeIntro`, contract S-6 item 4). Shown by
/// `HomePage` only for `chooserStatus == migrated` and never beside the Day-3
/// modal. Both actions are supplied by the page.
class HomeModeIntroCard extends StatelessWidget {
  const HomeModeIntroCard({
    super.key,
    required this.onChoose,
    required this.onDismiss,
  });

  final VoidCallback onChoose;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HudTokens.screenGutter, 0, HudTokens.screenGutter, 14),
      child: HudPanel(
        key: const Key('home.modeIntro'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.modeIntroTitle, style: HudType.panelTitle(t).inPanel(t)),
            const SizedBox(height: 6),
            Text(l10n.modeIntroBody,
                style: HudType.body(t, size: 12.5).inPanel(t)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                HudButton(
                  key: const Key('home.modeIntro.choose'),
                  label: l10n.modeIntroChoose,
                  tone: HudButtonTone.accent,
                  minHeight: 48,
                  onPressed: onChoose,
                ),
                HudButton(
                  key: const Key('home.modeIntro.dismiss'),
                  label: l10n.modeIntroDismiss,
                  minHeight: 48,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
