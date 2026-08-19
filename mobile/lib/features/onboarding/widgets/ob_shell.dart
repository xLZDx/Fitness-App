import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';

/// The onboarding chrome: back chevron, progress bar, step counter.
///
/// Traced from the design's own `OBHeader` (`App.tsx:1205-1217`): a 36pt round
/// back button, a 3pt track filled to `step / total` in the accent, and the
/// counter as `N/M` at the right, 12pt semibold in the secondary text colour.
///
/// ## Why the counter says 7 and not 9
///
/// The design's header hard-codes `TOTAL_OB_STEPS = 9` (`App.tsx:1202`). This
/// app renders seven steps today; O2 is the gate that renumbers them. Printing
/// "1/9" over a flow that ends at seven would be a progress bar that lies about
/// how much is left, which is the one thing a progress bar exists not to do.
/// [total] is therefore passed in from whatever the page actually renders.
class ObProgressHeader extends StatelessWidget {
  const ObProgressHeader({
    super.key,
    required this.step,
    required this.total,
    this.onBack,
  });

  /// 1-based, so the first screen reads "1/7" rather than "0/7".
  final int step;
  final int total;

  /// Null on the first step: there is nowhere to go back to, and a chevron
  /// that does nothing is worse than no chevron.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final l10n = AppLocalizations.of(context);
    final fraction = total <= 0 ? 0.0 : (step / total).clamp(0.0, 1.0);

    return Row(
      children: [
        // Kept in the layout when disabled rather than removed, so the bar and
        // the counter do not jump sideways between step 1 and step 2.
        SizedBox(
          width: 36,
          height: 36,
          child: onBack == null
              ? null
              : Semantics(
                  button: true,
                  label: l10n.onboardingBack,
                  child: Material(
                    color: t.button.fill,
                    shape: CircleBorder(
                        side: BorderSide(color: t.button.innerBorder)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('onboarding.back'),
                      onTap: onBack,
                      child: Icon(
                        Icons.chevron_left,
                        size: 22,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 3,
              child: Stack(
                children: [
                  Container(color: t.textPrimary.withValues(alpha: 0.14)),
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    widthFactor: fraction,
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: t.accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Read by a screen reader as "step 3 of 7" rather than as the glyph
        // salad "3 slash 7".
        Semantics(
          label: l10n.onboardingStepCounterA11y(step, total),
          excludeSemantics: true,
          child: SizedBox(
            width: 36,
            child: Text(
              '$step/$total',
              textAlign: TextAlign.right,
              softWrap: false,
              // No letter-spacing: HudType.label's default tracking is wide
              // enough that "10/10" wraps inside this box's fixed 36px width,
              // matched to the back button on the other side for symmetry.
              style: HudType.label(t, size: 12, em: 0).overPhoto(t),
            ),
          ),
        ),
      ],
    );
  }
}
