/// The weekly review card (design s15, s18): what was decided, always WHY
/// (closed reason codes), a 7-day undo for an automatically applied (coached)
/// change and an accept button for a shared proposal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../../profile/data/profile_models.dart';
import '../data/plan_review_record.dart';
import '../data/stored_nutrition_plan.dart';
import '../data/weekly_review.dart';

String reviewReasonText(AppLocalizations l10n, ReviewReason r) => switch (r) {
      ReviewReason.onTrack => l10n.reviewReasonOnTrack,
      ReviewReason.aheadOfPlan => l10n.reviewReasonAheadOfPlan,
      ReviewReason.behindWaiting => l10n.reviewReasonBehindWaiting,
      ReviewReason.cooldownActive => l10n.reviewReasonCooldownActive,
      ReviewReason.tooFast => l10n.reviewReasonTooFast,
      ReviewReason.stepsRaised => l10n.reviewReasonStepsRaised,
      ReviewReason.kcalLowered => l10n.reviewReasonKcalLowered,
      ReviewReason.kcalRaised => l10n.reviewReasonKcalRaised,
      ReviewReason.atSafetyLimit => l10n.reviewReasonAtSafetyLimit,
      ReviewReason.recomposition => l10n.reviewReasonRecomposition,
      ReviewReason.driftTooLarge => l10n.reviewReasonDriftTooLarge,
      ReviewReason.needMoreDataPoints => l10n.reviewReasonNeedMoreDataPoints,
      ReviewReason.needMoreDataSpan => l10n.reviewReasonNeedMoreDataSpan,
      ReviewReason.autoAdjustOff => l10n.reviewReasonAutoAdjustOff,
    };

/// The one-line decision for [review] under [ownership].
String reviewDecisionText(
  AppLocalizations l10n,
  PlanReviewRecord review,
  PlanOwnership ownership,
  NumberFormat nf,
) {
  final dir = review.deltaKcal < 0 ? 'down' : 'up';
  switch (review.decision) {
    case ReviewDecisionKind.keep:
      return l10n.nutritionReviewKeep;
    case ReviewDecisionKind.needMoreData:
      return l10n.nutritionReviewNeedMoreData;
    case ReviewDecisionKind.needRecalculation:
      return l10n.nutritionReviewNeedRecalculation;
    case ReviewDecisionKind.adjustKcal:
      final amount = nf.format(review.deltaKcal.abs());
      return switch (ownership) {
        PlanOwnership.coached => l10n.nutritionReviewKcalApplied(dir, amount),
        PlanOwnership.shared => l10n.nutritionReviewKcalProposed(dir, amount),
        PlanOwnership.manual => l10n.nutritionReviewKcalInsight(dir, amount),
      };
    case ReviewDecisionKind.adjustSteps:
      final amount = nf.format(review.deltaSteps.abs());
      return switch (ownership) {
        PlanOwnership.coached => l10n.nutritionReviewStepsApplied(amount),
        PlanOwnership.shared => l10n.nutritionReviewStepsProposed(amount),
        PlanOwnership.manual => l10n.nutritionReviewStepsInsight(amount),
      };
  }
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.review,
    required this.plan,
    required this.now,
    this.onUndo,
    this.onAccept,
  });

  /// The newest review, or null when none exists yet.
  final PlanReviewRecord? review;
  final StoredNutritionPlan plan;
  final DateTime now;
  final VoidCallback? onUndo;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final locale = Localizations.localeOf(context).toString();
    final nf = NumberFormat.decimalPattern(locale);
    final r = review;
    final children = <Widget>[
      Semantics(
        header: true,
        child:
            Text(l10n.nutritionReviewTitle, style: theme.textTheme.titleMedium),
      ),
      const SizedBox(height: 8),
    ];
    if (r == null) {
      children.add(Text(l10n.nutritionReviewNone,
          style: theme.textTheme.bodyMedium));
    } else {
      final changes = r.decision == ReviewDecisionKind.adjustKcal ||
          r.decision == ReviewDecisionKind.adjustSteps;
      children.addAll([
        Text(l10n.nutritionReviewDecidedOn(DateFormat.yMMMd(locale)
            .format(r.decidedAt.toLocal())),
            style:
                theme.textTheme.bodySmall?.copyWith(color: hud.textSecondary)),
        const SizedBox(height: 4),
        Text(reviewDecisionText(l10n, r, plan.ownership, nf),
            style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text(l10n.nutritionReviewWhyTitle,
              style: theme.textTheme.titleSmall),
        ),
        for (final reason in r.reasonCodes)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(reviewReasonText(l10n, reason),
                style: theme.textTheme.bodyMedium),
          ),
        const SizedBox(height: 8),
        Text(l10n.nutritionReviewBasis(r.inputs.dataPoints),
            style:
                theme.textTheme.bodySmall?.copyWith(color: hud.textSecondary)),
        if (r.inputs.weightSlopeKgPerWeek != null)
          Text(
              l10n.nutritionReviewTrend(
                  NumberFormat('0.0#', locale)
                      .format(r.inputs.weightSlopeKgPerWeek)),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: hud.textSecondary)),
      ]);
      final undo = plan.reviewUndo;
      final canUndo = plan.ownership == PlanOwnership.coached &&
          changes &&
          undo != null &&
          undo.week == r.week &&
          undo.isAvailableAt(now) &&
          onUndo != null;
      if (canUndo) {
        children.addAll([
          const SizedBox(height: 8),
          Text(
              l10n.nutritionReviewUndoUntil(
                  DateFormat.yMMMd(locale).format(undo.expiresAt.toLocal())),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: hud.textSecondary)),
          const SizedBox(height: 4),
          OutlinedButton(
            key: const Key('nutrition.review.undo'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: onUndo,
            child: Text(l10n.nutritionReviewUndo),
          ),
        ]);
      }
      final canAccept = plan.ownership == PlanOwnership.shared &&
          changes &&
          plan.planVersion == r.basePlanVersion &&
          onAccept != null;
      if (canAccept) {
        children.addAll([
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('nutrition.review.accept'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: onAccept,
            child: Text(l10n.nutritionReviewAccept),
          ),
        ]);
      }
    }
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
