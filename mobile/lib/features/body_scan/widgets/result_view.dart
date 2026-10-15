/// The scan result (design s12, D-73, D-74). Always a "likely range", never a
/// bare number, with the fixed plain-language limit. While the estimator is
/// provisional the screen is weight-first: the weight trend is the headline,
/// the body-fat figure is a secondary "rough estimate" card, and the ring,
/// points to go, fat/lean CHANGE, ETA and the plan decision card are hidden
/// (replaced by "See your plan"). In `measurementOnly` mode no goal figure is
/// shown and the estimate sits behind a neutral ask.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../data/body_fat_estimate.dart';
import '../data/check_items.dart';
import '../data/scan_result_math.dart';
import '../data/scan_trend.dart';
import '../state/scan_result_view_model.dart';
import 'check_items_card.dart';
import 'trend_chart.dart';

String confidenceText(AppLocalizations l10n, EstimateConfidence c) =>
    switch (c) {
      EstimateConfidence.low => l10n.bodyScanConfidenceLow,
      EstimateConfidence.medium => l10n.bodyScanConfidenceMedium,
      EstimateConfidence.high => l10n.bodyScanConfidenceHigh,
    };

class ResultView extends StatefulWidget {
  const ResultView({
    super.key,
    required this.model,
    this.onSeePlan,
    this.onCheckAction,
    this.onHistory,
    this.onEditWeight,
    this.onDeletePhotos,
  });

  final ScanResultViewModel model;

  /// Result actions (C16 follow-up); each button is shown only when wired.
  final VoidCallback? onHistory;
  final VoidCallback? onEditWeight;
  final VoidCallback? onDeletePhotos;
  final VoidCallback? onSeePlan;
  final void Function(CheckAction action)? onCheckAction;

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  bool _askAnswered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final m = widget.model;
    final hidden = m.measurementOnly && !_askAnswered;
    return ListView(
      padding: const EdgeInsets.all(HudTokens.screenGutter),
      children: [
        Semantics(
          header: true,
          child: Text(l10n.bodyScanResultTitle,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(color: hud.textPrimary)),
        ),
        const SizedBox(height: 12),
        if (hidden)
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.bodyScanMeasurementOnlyNote,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: hud.textSecondary)),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('bodyScan.result.ask'),
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => setState(() => _askAnswered = true),
                  child: Text(l10n.bodyScanMeasurementOnlyAsk),
                ),
              ],
            ),
          )
        else ...[
          if (m.provisional) _ProvisionalBanner(),
          if (m.weightFirst) ...[
            _WeightTrendCard(model: m),
            const SizedBox(height: 12),
          ],
          _EstimateCard(model: m),
          if (m.showChange) ...[
            const SizedBox(height: 12),
            _ChangeCard(model: m),
          ],
          if (m.showGoalFigures && m.pointsToGoal != null) ...[
            const SizedBox(height: 12),
            _GoalCard(model: m),
          ],
          if (m.readingSplit != null || m.trendSplit != null) ...[
            const SizedBox(height: 12),
            _MassCard(model: m),
          ],
          if (!m.weightFirst) ...[
            const SizedBox(height: 12),
            _WeightTrendCard(model: m),
          ],
          const SizedBox(height: 12),
          _StrengthCard(sessions: m.data.strengthSessionsLast4Weeks),
          if (m.showPlanDecision) ...[
            const SizedBox(height: 12),
            GlassCard(
              key: const Key('bodyScan.result.planDecision'),
              child: Text(l10n.bodyScanPlanDecisionTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: hud.textPrimary)),
            ),
          ],
          if (m.showSeePlanAction) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('bodyScan.result.seePlan'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: widget.onSeePlan,
              child: Text(l10n.bodyScanSeePlan),
            ),
          ],
          if (m.series != null && m.series!.points.isNotEmpty) ...[
            const SizedBox(height: 12),
            TrendChart(
              series: m.series!,
              trendLabel: m.trendLabel,
              modelChangeAt: m.modelChangeAt,
            ),
          ],
          if (m.checks.isNotEmpty) ...[
            const SizedBox(height: 12),
            CheckItemsCard(items: m.checks, onAction: widget.onCheckAction),
          ],
        ],
        if (widget.onEditWeight != null ||
            widget.onDeletePhotos != null ||
            widget.onHistory != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (widget.onEditWeight != null)
                TextButton(
                  key: const Key('bodyScan.result.editWeight'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: widget.onEditWeight,
                  child: Text(l10n.bodyScanHistoryActionEditWeight),
                ),
              if (widget.onDeletePhotos != null)
                TextButton(
                  key: const Key('bodyScan.result.deletePhotos'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: widget.onDeletePhotos,
                  child: Text(l10n.bodyScanHistoryActionDeletePhotos),
                ),
              if (widget.onHistory != null)
                TextButton(
                  key: const Key('bodyScan.result.history'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: widget.onHistory,
                  child: Text(l10n.bodyScanHistoryTitle),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ProvisionalBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        key: const Key('bodyScan.result.provisionalBanner'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: context.colors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.bodyScanProvisionalBannerTitle,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: hud.textPrimary)),
                  const SizedBox(height: 4),
                  Text(l10n.bodyScanProvisionalBannerBody,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: hud.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.model});
  final ScanResultViewModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final f = NumberFormat('0.0', l10n.localeName);
    final e = model.estimate;
    return GlassCard(
      key: const Key('bodyScan.result.estimate'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (model.provisional)
            Text(l10n.bodyScanRoughLabel,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: hud.textSecondary)),
          Text(l10n.bodyScanThisReading,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: hud.textSecondary)),
          const SizedBox(height: 4),
          Text(l10n.bodyScanLikelyRange(f.format(e.low), f.format(e.high)),
              key: const Key('bodyScan.result.range'),
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: hud.textPrimary)),
          Text(l10n.bodyScanBestGuess(f.format(e.value)),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: hud.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              // Icon + text, not colour only.
              Icon(
                e.confidence == EstimateConfidence.low
                    ? Icons.warning_amber_rounded
                    : Icons.verified_outlined,
                size: 18,
                color: e.confidence == EstimateConfidence.low
                    ? context.colors.warning
                    : hud.success,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                    l10n.bodyScanConfidence(confidenceText(l10n, e.confidence)),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: hud.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l10n.bodyScanLimitNote,
              key: const Key('bodyScan.result.limit'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: hud.textSecondary)),
        ],
      ),
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.model});
  final ScanResultViewModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final f = NumberFormat('0.0', l10n.localeName);
    final series = model.series!;
    final prev = series.points[series.points.length - 2].reading.value;
    final pts = f.format((series.latest.reading.value - prev).abs());
    final text = switch (model.changeLabel!) {
      ChangeLabel.noMeaningfulChange => l10n.bodyScanChangeNone,
      ChangeLabel.down => l10n.bodyScanChangeDown(pts),
      ChangeLabel.up => l10n.bodyScanChangeUp(pts),
    };
    return GlassCard(
      key: const Key('bodyScan.result.change'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: hud.textPrimary)),
          if (model.noisePts != null)
            Text(l10n.bodyScanNoiseNote('±${f.format(model.noisePts)}'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: hud.textSecondary)),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.model});
  final ScanResultViewModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final f = NumberFormat('0.0', l10n.localeName);
    return GlassCard(
      key: const Key('bodyScan.result.goal'),
      child: Text(l10n.bodyScanPointsToGoal(f.format(model.pointsToGoal)),
          style: theme.textTheme.titleMedium?.copyWith(color: hud.textPrimary)),
    );
  }
}

class _MassCard extends StatelessWidget {
  const _MassCard({required this.model});
  final ScanResultViewModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final f = NumberFormat('0.0', l10n.localeName);
    // Never mix the two in one tile: the trend split (non-provisional) or the
    // single reading, each with its own label.
    final MassSplit s = model.trendSplit ?? model.readingSplit!;
    final label =
        model.trendSplit != null ? l10n.bodyScanFromTrend : l10n.bodyScanThisReading;
    String v(double a, double lo, double hi) =>
        l10n.bodyScanMassValue(f.format(a), f.format(lo), f.format(hi));
    return GlassCard(
      key: const Key('bodyScan.result.mass'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: hud.textSecondary)),
          const SizedBox(height: 6),
          Text('${l10n.bodyScanFatMass}: ${v(s.fatKg, s.fatLowKg, s.fatHighKg)}',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: hud.textPrimary)),
          Text(
              '${l10n.bodyScanLeanMass}: ${v(s.leanKg, s.leanLowKg, s.leanHighKg)}',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: hud.textPrimary)),
        ],
      ),
    );
  }
}

class _WeightTrendCard extends StatelessWidget {
  const _WeightTrendCard({required this.model});
  final ScanResultViewModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final f = NumberFormat('0.0#', l10n.localeName);
    final slope = model.data.weightSlopeKgPerWeek;
    final text = switch (model.weightTrend) {
      WeightTrendDirection.down => l10n.bodyScanWeightTrendDown(f.format(slope!.abs())),
      WeightTrendDirection.up => l10n.bodyScanWeightTrendUp(f.format(slope!.abs())),
      WeightTrendDirection.flat => l10n.bodyScanWeightTrendFlat,
      WeightTrendDirection.unknown => l10n.bodyScanWeightTrendNone,
    };
    return GlassCard(
      key: const Key('bodyScan.result.weightTrend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.bodyScanWeightTrendTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: hud.textPrimary)),
          ),
          const SizedBox(height: 4),
          Text(text,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: hud.textPrimary)),
        ],
      ),
    );
  }
}

class _StrengthCard extends StatelessWidget {
  const _StrengthCard({required this.sessions});
  final int? sessions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final n = sessions;
    return GlassCard(
      key: const Key('bodyScan.result.strength'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.bodyScanStrengthTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: hud.textPrimary)),
          ),
          const SizedBox(height: 4),
          Text(
              n == null || n == 0
                  ? l10n.bodyScanStrengthNone
                  : l10n.bodyScanStrengthCount(n),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: hud.textSecondary)),
        ],
      ),
    );
  }
}
