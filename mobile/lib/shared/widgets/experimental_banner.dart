import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Says, on the feature's own screen, that what it reports is not validated.
///
/// ## Why this exists
///
/// A1. `ML_STRATEGY_2026-08-11.md:223-227` names exactly one item in the whole
/// document as something that "should become a gate before release": the
/// scanner, Form Coach and Posture carrying an explicit experimental label.
/// It restates audit recommendation 7 (`AUDIT_REPORT_2026-08-11.md:360`,
/// listed under "до любого публичного релиза").
///
/// The reason is narrow and worth keeping in front of whoever edits this: none
/// of the three is broken, and none is being hidden. What is missing is the
/// disclosure. Live recognition can name the wrong machine, the rep counter is
/// a display rather than a measurement, and posture cannot produce a defensible
/// number from a single frame (`ML_STRATEGY_2026-08-11.md:201-212`) — and until
/// this banner, every one of those numbers was presented in the same visual
/// register as a fact the app stands behind.
///
/// ## Why the label word lives here and the sentence does not
///
/// [AppLocalizations.experimentalLabel] is rendered by this widget, so all
/// three surfaces say the same word and cannot drift into "beta" on one screen
/// and "experimental" on another. The [message] is per-surface, because the
/// useful part of the disclosure is not the word — it is what specifically is
/// unreliable and what the user should do instead, and that differs: check the
/// machine by hand, do not treat cues as coaching, do not read posture as a
/// medical assessment.
///
/// ## Why this is not `DemoDataBanner`
///
/// `demo_data_banner.dart` looks nearly identical and answers a different
/// question. It says the DATA is fake and removes itself automatically when a
/// real repository is bound — it is gated on `repo is MockXxxRepository`.
/// These three features are real, wired to real models, and running on the
/// user's own frames; nothing about them will flip a runtime type when they
/// become validated. Sharing one widget would tie a self-removing banner to a
/// deliberately permanent one, so that a restyle of either silently restyles
/// the other. The ~20 duplicated lines of decoration are the cost of keeping
/// those two claims independent, and that is the cheaper mistake.
class ExperimentalBanner extends StatelessWidget {
  const ExperimentalBanner({super.key, required this.message});

  /// What is specifically unreliable here, and what to do instead.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final colour = theme.colorScheme.tertiary;
    // `MergeSemantics`, not `Semantics(container: true)` — which is what this
    // had first, and a test caught it. A container makes a node; it does not
    // merge the two Texts inside it, so a screen reader announced
    // "Experimental" and the sentence it qualifies as two separate stops and a
    // user could swipe past the warning having heard only the word. Merged,
    // the disclosure and what it applies to cannot be separated.
    //
    // `DemoDataBanner` gets away with a plain container because it has exactly
    // one Text child; this one does not.
    return MergeSemantics(
      child: Container(
        key: const Key('experimental.banner'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colour.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, size: 20, color: colour),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.experimentalLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colour,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(message, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
