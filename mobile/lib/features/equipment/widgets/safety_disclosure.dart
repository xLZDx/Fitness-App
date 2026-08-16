import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../state/safety_coverage_providers.dart';
import '../../../core/theme/app_semantic_colors.dart';

/// Says plainly that the exercise list has not been screened against the
/// user's injuries.
///
/// ## Why a banner and not something else
///
/// A dialog was the first idea and is wrong twice over: it interrupts on
/// every surface that would show it, and once dismissed it is invisible
/// precisely when it matters. A per-item badge is worse — badging the
/// exercises that conflict implies the un-badged ones were checked and
/// cleared, which is the exact false claim being removed. An acknowledgement
/// buried in Settings reads as shifting liability onto the user rather than
/// informing them.
///
/// So: persistent, in place, not dismissible by tapping past it, and a
/// `liveRegion` so a screen reader announces it when it appears rather than
/// only when the user happens to reach it.
///
/// ## Why it renders nothing once the catalog is tagged
///
/// It is not a permanent disclaimer. `injuryFilteringIsRealProvider` reads the
/// catalog's actual tag coverage, so the moment tagging lands this disappears
/// on its own and the surfaces underneath go back to saying what they always
/// meant to say. Nobody has to remember to delete it.
class SafetyDisclosure extends ConsumerWidget {
  const SafetyDisclosure({super.key, this.compact = false});

  /// Drops the second line, for places that already carry a lot of text.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(safetyScreeningLevelProvider);
    if (level == SafetyScreeningLevel.clinical) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colour = theme.colorScheme.tertiary;

    // F019: safetyFilterCoverage was authored, translated and computed by
    // catalogSafetyCoverageProvider, and rendered nowhere — the one figure
    // that would show a user how much of the catalog "screened by rules" (or
    // "not screened yet") actually covers. Coverage is null only for one
    // frame while the provider's first read is in flight; nothing is shown
    // rather than a stale or invented number.
    final coverage = ref.watch(catalogSafetyCoverageProvider).valueOrNull;

    // Two different truths, and the weaker one is not a softened version of
    // the stronger. "Nothing was screened" and "screened by rules, not by a
    // clinician" describe different products, and collapsing the second into
    // silence is how the first claim came back last time.
    final headline = level == SafetyScreeningLevel.none
        ? l10n.safetyFilterNotYetScreened
        : l10n.safetyFilterRulesOnly;
    final detail = level == SafetyScreeningLevel.none
        ? l10n.safetyFilterNotYetScreenedDetail
        : l10n.safetyFilterRulesOnlyDetail;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colour.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: colour),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                    if (coverage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.safetyFilterCoverage(
                            coverage.tagged, coverage.total),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
