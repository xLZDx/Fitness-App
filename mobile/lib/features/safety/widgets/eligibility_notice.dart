import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/glass.dart';
import '../data/eligibility.dart';
import '../data/health_flags.dart';
import 'safety_refusal_card.dart' show parQQuestionText;

/// Named constructors for the reasons a UI builds directly.
///
/// The eligibility layer produces these itself for every decision it makes;
/// this exists for the one case a screen raises on its own — the onboarding
/// step warning, as the user ticks a chip, that the catalogue carries no tag
/// for what they just told us.
extension EligibilityReasonFor on EligibilityReason {
  static EligibilityReason unscreenable(MovementRestriction r) =>
      EligibilityReason(BlockReason.unscreenableRestriction, restriction: r);
}

/// The reader's wording for a movement restriction.
///
/// Exhaustive switch with no default, so adding a restriction to the enum
/// breaks this at compile time rather than shipping a chip with no label.
String movementRestrictionText(AppLocalizations l10n, MovementRestriction r) =>
    switch (r) {
      MovementRestriction.overhead => l10n.restrictionOverhead,
      MovementRestriction.deepKneeFlexion => l10n.restrictionDeepKneeFlexion,
      MovementRestriction.loadedSpinalFlexion =>
        l10n.restrictionLoadedSpinalFlexion,
      MovementRestriction.spinalExtension => l10n.restrictionSpinalExtension,
      MovementRestriction.wristLoading => l10n.restrictionWristLoading,
      MovementRestriction.impact => l10n.restrictionImpact,
      MovementRestriction.prolongedStanding => l10n.restrictionProlongedStanding,
      MovementRestriction.balance => l10n.restrictionBalance,
      MovementRestriction.other => l10n.restrictionOther,
    };

/// One machine-readable reason, rendered.
///
/// The whole point of [EligibilityReason] being a value rather than a string:
/// the decision is made once, in `eligibility.dart`, and each surface words it
/// for its own context. This function is where the wording happens, and it is
/// the ONLY place — a second copy is how two screens end up giving different
/// reasons for the same refusal.
String eligibilityReasonText(AppLocalizations l10n, EligibilityReason r) =>
    switch (r.reason) {
      // Names the PAR-Q+ question when there is one. A refusal that will not
      // say which answer caused it cannot be corrected by the person it is
      // about, and "your screening did not clear you" is exactly that refusal.
      BlockReason.screening => r.question == null
          ? l10n.eligReasonScreening
          : '${l10n.eligReasonScreening} '
              '${r.unanswered ? l10n.safetyReasonNotAnswered : l10n.safetyReasonYouAnswered} '
              '${parQQuestionText(l10n, r.question!)}',
      BlockReason.injury => l10n.eligReasonInjury,
      BlockReason.movementRestriction => l10n.eligReasonMovement(
          r.restriction == null
              ? l10n.restrictionOther
              : movementRestrictionText(l10n, r.restriction!)),
      BlockReason.postSurgical => l10n.eligReasonPostSurgical,
      BlockReason.clinicianAdvice => l10n.eligReasonClinician,
      BlockReason.equipment => l10n.eligReasonEquipment,
      BlockReason.formCoachUnsupported => l10n.eligReasonFormCoach,
      BlockReason.unscreenableRestriction => l10n.eligAdvisoryUnscreenable(
          r.restriction == null
              ? l10n.restrictionOther
              : movementRestrictionText(l10n, r.restriction!)),
    };

/// What a surface shows where work would have been.
///
/// Used for both halves of the gate — a single withheld exercise and a whole
/// person who may not train — because the user-facing shape is the same: name
/// what happened, name the answer responsible, offer the way to change it.
///
/// It never renders an empty list. A caller with no reasons has nothing to say
/// and should not be drawing this at all; asserting that here would be a crash
/// in production, so it renders the heading alone and the tests pin the
/// reasons instead.
class EligibilityNotice extends StatelessWidget {
  const EligibilityNotice({
    super.key,
    required this.reasons,
    this.title,
    this.onReviewProfile,
  });

  final List<EligibilityReason> reasons;

  /// Overrides the default heading. A withheld exercise and a blocked person
  /// are different sentences.
  final String? title;

  final VoidCallback? onReviewProfile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return GlassCard(
      tint: theme.colorScheme.error,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: theme.colorScheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title ?? l10n.eligBlockedTitle,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(l10n.eligBlockedIntro, style: theme.textTheme.bodyMedium),
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(eligibilityReasonText(l10n, r),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colors.textSecondary)),
                  ),
                ],
              ),
            ),
          if (onReviewProfile != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onReviewProfile,
              child: Text(l10n.eligOpenProfile),
            ),
          ],
        ],
      ),
    );
  }
}
