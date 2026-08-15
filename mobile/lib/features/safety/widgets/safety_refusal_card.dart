import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/glass.dart';
import '../data/par_q.dart';

/// The wording for one PAR-Q+ question, in the reader's locale.
///
/// Lives here rather than on [ParQQuestion] because the enum is in `data/`
/// and a pure model must not reach for a `BuildContext`. The `switch` is
/// exhaustive with no default, so adding a question to the enum breaks this
/// function at compile time — which is the only reliable way to stop a
/// question shipping with no text.
String parQQuestionText(AppLocalizations l10n, ParQQuestion q) => switch (q) {
      ParQQuestion.heartConditionOrHighBloodPressure =>
        l10n.safetyQHeartConditionOrHighBloodPressure,
      ParQQuestion.chestPain => l10n.safetyQChestPain,
      ParQQuestion.dizzinessOrLossOfConsciousness =>
        l10n.safetyQDizzinessOrLossOfConsciousness,
      ParQQuestion.otherChronicCondition => l10n.safetyQOtherChronicCondition,
      ParQQuestion.prescribedMedication => l10n.safetyQPrescribedMedication,
      ParQQuestion.musculoskeletalProblem => l10n.safetyQMusculoskeletalProblem,
      ParQQuestion.medicallySupervisedOnly =>
        l10n.safetyQMedicallySupervisedOnly,
    };

/// What the user sees where a workout would have been.
///
/// The state this app did not have. It is a card and not a dialog on purpose:
/// a dialog is something you dismiss to get to the thing behind it, and there
/// is nothing behind this one.
///
/// The two headings are not interchangeable. "You told us X" and "you have not
/// told us whether X" call for different words and a different next step — one
/// is a referral, the other is a form to finish — and collapsing them into a
/// single "not eligible" message is how a screen that merely needs completing
/// reads as a rejection.
class SafetyRefusalCard extends StatelessWidget {
  const SafetyRefusalCard({
    super.key,
    required this.reasons,
    this.onOpenScreening,
  });

  final List<SafetyReason> reasons;

  /// Route to the screening form. Null hides the button — a caller that IS the
  /// screening form has nowhere to send anyone.
  final VoidCallback? onOpenScreening;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final answered = reasons.where((r) => !r.incomplete).toList();
    final unanswered = reasons.where((r) => r.incomplete).toList();

    // An answered blocking reason outranks an unfinished form: someone who has
    // told us about chest pain is not asked to go and tick more boxes.
    final referral = answered.isNotEmpty;

    return GlassCard(
      tint: theme.colorScheme.error,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(referral ? Icons.medical_services_outlined : Icons.pending_actions,
                  color: theme.colorScheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  referral ? l10n.safetyBlockedTitle : l10n.safetyIncompleteTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(referral ? l10n.safetyBlockedBody : l10n.safetyIncompleteBody,
              style: theme.textTheme.bodyMedium),
          if (answered.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(l10n.safetyReasonYouAnswered,
                style: theme.textTheme.labelLarge),
            for (final r in answered)
              _Bullet(text: parQQuestionText(l10n, r.question)),
          ],
          if (unanswered.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(l10n.safetyReasonNotAnswered,
                style: theme.textTheme.labelLarge),
            for (final r in unanswered)
              _Bullet(text: parQQuestionText(l10n, r.question)),
          ],
          if (onOpenScreening != null && !referral) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenScreening,
              child: Text(l10n.safetyOpenScreening),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
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
            child: Text(text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
