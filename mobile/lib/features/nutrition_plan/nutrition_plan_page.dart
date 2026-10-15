/// The plan screen `/nutrition` (design s13, s15, s18, s24).
///
/// Everything numeric is gated on the device-local verdict: `referProfessional`
/// sees one calm notice and no numbers, `needsAnswer` / `needsProfile` are sent
/// to the profile flow, and only `eligible` sees the plan. Every write first
/// passes `ensureDataNoticeAcknowledged` and goes through
/// `NutritionPlanActions` (bounds, version check, deletion fence).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/privacy/data_notice.dart';
import '../../core/theme/hud_tokens.dart';
import '../../shared/widgets/glass.dart';
import '../body_scan/state/body_scan_providers.dart';
import '../profile/data/profile_models.dart';
import 'data/nutrition_eligibility.dart';
import 'data/plan_calculator.dart';
import 'data/stored_nutrition_plan.dart';
import 'data/weekly_review.dart';
import 'state/nutrition_plan_actions.dart';
import 'state/nutrition_providers.dart';
import 'state/review_scheduler.dart';
import 'state/weight_providers.dart';
import 'widgets/auto_adjust_toggles.dart';
import 'widgets/kcal_range_slider.dart';
import 'widgets/macro_ranges_card.dart';
import 'widgets/ownership_selector.dart';
import 'widgets/professional_notice.dart';
import 'widgets/review_card.dart';

class NutritionPlanPage extends ConsumerStatefulWidget {
  const NutritionPlanPage({super.key});

  @override
  ConsumerState<NutritionPlanPage> createState() => _NutritionPlanPageState();
}

class _NutritionPlanPageState extends ConsumerState<NutritionPlanPage> {
  /// The range being dragged; null when the stored one is shown.
  KcalRange? _draft;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // First display of the plan surface: run this week's review once (the
    // scheduler is idempotent per ISO week and writes nothing when ineligible).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(weeklyReviewSchedulerProvider)
            .run(ReviewTrigger.planSurfaceShown);
      }
    });
  }

  String _statusText(AppLocalizations l10n, PlanActionStatus s) => switch (s) {
        PlanActionStatus.saved => l10n.nutritionSaved,
        PlanActionStatus.conflict => l10n.nutritionActionConflict,
        PlanActionStatus.offline => l10n.nutritionActionOffline,
        PlanActionStatus.refused => l10n.nutritionActionRefused,
        _ => l10n.nutritionActionFailed,
      };

  /// Notice first, then the write; shows the outcome. A declined notice defers
  /// the write (nothing is sent).
  Future<PlanActionResult?> _write(
      Future<PlanActionResult> Function(NutritionPlanActions a) f,
      {bool quietSuccess = false}) async {
    if (_busy) return null;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await ensureDataNoticeAcknowledged(context, ref)) {
      if (mounted) setState(() => _draft = null);
      return null;
    }
    setState(() => _busy = true);
    PlanActionResult result;
    try {
      result = await f(ref.read(nutritionPlanActionsProvider));
    } catch (e) {
      // An unreadable stored plan (or a failed read) is a visible failure, not
      // an unhandled error from a button handler.
      debugPrint('nutrition plan: write failed (${e.runtimeType})');
      result = const PlanActionResult(PlanActionStatus.unreadable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return result;
    setState(() => _draft = null);
    if (!(result.saved && quietSuccess)) {
      messenger.showSnackBar(
          SnackBar(content: Text(_statusText(l10n, result.status))));
    }
    return result;
  }

  Future<void> _setPaused(bool paused) async {
    if (!await ensureDataNoticeAcknowledged(context, ref)) return;
    try {
      await ref.read(bodyScanSettingsStoreProvider).setPaused(paused);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).nutritionActionFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final verdict = ref.watch(nutritionEligibilityProvider);
    final Widget body;
    if (verdict == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (verdict is ReferProfessional) {
      body = _scroll([const ProfessionalNotice(), ..._links(l10n, false)]);
    } else if (verdict is! Eligible) {
      body = _scroll([_needsProfile(l10n), ..._links(l10n, false)]);
    } else {
      body = _eligible(l10n);
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.nutritionPlanTitle)),
      body: SafeArea(child: body),
    );
  }

  Widget _scroll(List<Widget> children) => ListView.separated(
        padding: const EdgeInsets.all(HudTokens.screenGutter),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => children[i],
      );

  Widget _needsProfile(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.nutritionNeedsProfileTitle,
                style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Text(l10n.nutritionNeedsProfileBody,
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => GoRouter.of(context).push('/nutrition/profile'),
            child: Text(l10n.nutritionNeedsProfileAction),
          ),
        ],
      ),
    );
  }

  List<Widget> _links(AppLocalizations l10n, bool withWeight) => [
        if (withWeight) _linkTile(l10n.nutritionLinkWeightLog, '/nutrition/weight'),
        _linkTile(l10n.nutritionLinkHowItAdapts, '/nutrition/how-it-adapts'),
        _linkTile(l10n.nutritionLinkSources, '/nutrition/sources'),
      ];

  Widget _linkTile(String label, String path) => ListTile(
        minVerticalPadding: 12,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => GoRouter.of(context).push(path),
      );

  Widget _eligible(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final hud = context.hud;
    final planAsync = ref.watch(nutritionPlanProvider);
    if (planAsync.isLoading && !planAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (planAsync.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.nutritionPlanLoadError),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('nutrition.loadRetry'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => ref.invalidate(storedNutritionPlanProvider),
                child: Text(l10n.commonRetry),
              ),
            ],
          ),
        ),
      );
    }
    final plan = planAsync.valueOrNull;
    if (plan == null) {
      return _scroll([
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(l10n.nutritionCreateTitle,
                    style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              Text(l10n.nutritionCreateBody, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('nutrition.create'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed:
                    _busy ? null : () => _write((a) => a.ensurePlan()),
                child: Text(l10n.nutritionCreateAction),
              ),
            ],
          ),
        ),
        ..._links(l10n, true),
      ]);
    }

    final reviews = ref.watch(nutritionReviewsProvider).valueOrNull ?? const [];
    final latest = reviews.isEmpty ? null : reviews.first;
    final now = ref.watch(nutritionClockProvider)();
    final bounds = plan.recomputeBounds();
    final shown = _draft ?? plan.kcalRange;
    final nf = NumberFormat.decimalPattern(
        Localizations.localeOf(context).toString());
    final flags = ref.watch(nutritionInputsProvider)?.inputs == null
        ? const <PlanFlag>{}
        : computePlan(ref.watch(nutritionInputsProvider)!.inputs!).flags;
    final weight = ref.watch(currentWeightProvider);
    final paused =
        ref.watch(bodyScanSettingsProvider).valueOrNull?.paused ?? false;

    return _scroll([
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(l10n.nutritionKcalTitle,
                  style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 4),
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.nutritionKcalRangeValue(
                    nf.format(shown.low), nf.format(shown.high)),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: hud.textPrimary),
              ),
            ),
            Text(
              l10n.nutritionKcalBoundsHint(
                  nf.format(bounds.minKcal), nf.format(bounds.maxKcal)),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: hud.textSecondary),
            ),
            const SizedBox(height: 8),
            KcalRangeSlider(
              bounds: bounds,
              range: shown,
              enabled: !_busy,
              onChanged: (r) => setState(() => _draft = r),
              onChangeEnd: (r) => _write((a) => a.setKcalRange(r)),
            ),
            if (plan.ownership == PlanOwnership.coached) ...[
              const SizedBox(height: 8),
              Text(l10n.nutritionEditSharedNote,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: hud.textSecondary)),
            ],
          ],
        ),
      ),
      MacroRangesCard(
        plan: plan,
        onStepsChanged: (s) => _write((a) => a.setStepsGoal(s)),
      ),
      OwnershipSelector(
        value: plan.ownership,
        enabled: !_busy,
        onChanged: (o) => _write((a) => a.setOwnership(o)),
      ),
      AutoAdjustToggles(
        value: plan.autoAdjust,
        ownership: plan.ownership,
        onChanged: (v) => _write((a) => a.setAutoAdjust(v)),
      ),
      ReviewCard(
        review: latest,
        plan: plan,
        now: now,
        onUndo: () => _write((a) => a.undoLastReview()),
        onAccept: latest == null
            ? null
            : () => _write((a) => a.acceptProposal(latest)),
      ),
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.nutritionWeightHint, style: theme.textTheme.bodyMedium),
            if (weight != null) ...[
              const SizedBox(height: 4),
              Text(
                weight.stale
                    ? l10n.weightLogCurrentStale(
                        NumberFormat('0.0#', Localizations.localeOf(context).toString())
                            .format(weight.kg))
                    : l10n.weightLogCurrent(
                        NumberFormat('0.0#', Localizations.localeOf(context).toString())
                            .format(weight.kg)),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: hud.textSecondary),
              ),
            ],
          ],
        ),
      ),
      GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (flags.contains(PlanFlag.underweightNoDeficit))
              Text(l10n.planToneNoDeficit, style: theme.textTheme.bodyMedium),
            if (flags.contains(PlanFlag.targetBelowHealthyRange))
              Text(l10n.planToneTargetRange, style: theme.textTheme.bodyMedium),
            if (flags.contains(PlanFlag.floorBinding))
              Text(l10n.planToneFloorBinding, style: theme.textTheme.bodyMedium),
            Text(l10n.planToneNoEta, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(l10n.planToneScansMonthly,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: hud.textSecondary)),
          ],
        ),
      ),
      GlassCard(
        child: SwitchListTile(
          key: const Key('nutrition.pause'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.nutritionPauseTitle),
          subtitle: Text(l10n.nutritionPauseBody),
          value: paused,
          onChanged: _setPaused,
        ),
      ),
      ..._links(l10n, true),
    ]);
  }
}
