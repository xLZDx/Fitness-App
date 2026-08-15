import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../ai_planner/data/workout_plan.dart';
import '../../safety/widgets/safety_refusal_card.dart';
import '../state/plan_preview_provider.dart';
import '../widgets/inputs.dart';

/// O10 — the last screen: one real session, built from the answers just given.
///
/// ## What this screen deliberately does NOT do
///
/// No progress bar counting to 100%, and no forecast of results. The spec bans
/// both, and they are banned for the same reason: a bar that is not measuring
/// anything and a curve that predicts a weight loss nobody can predict are
/// theatre that costs the user their trust the first time reality disagrees.
/// What is shown instead is the plan itself — a real one — and the generator's
/// own stated reasons for choosing it.
///
/// ## Why a real plan and not a mock-up
///
/// `buildPlan` exists and is pure, so there was no excuse for a fixture. If the
/// generator cannot produce a session from these answers, this screen says so
/// plainly rather than showing a plausible-looking list of exercises the app
/// would never actually offer.
class StepPreview extends ConsumerWidget {
  const StepPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(onboardingPlanPreviewProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: l10n.onbPreviewTitle,
          subtitle: l10n.onbPreviewSubtitle,
        ),
        const SizedBox(height: 20),
        plan.when(
          // An honest indeterminate spinner: the catalogue read genuinely takes
          // an unknown time, and nothing here knows a percentage.
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => _Message(
            key: const Key('onb.preview.unavailable'),
            text: l10n.onbPreviewUnavailable,
          ),
          data: (outcome) => _outcomeBody(context, l10n, outcome),
        ),
      ],
    );
  }

  /// Gate M. The preview is a plan-producing surface like any other, so it
  /// gets the same floor: if the screening cannot clear the user, the last
  /// screen of onboarding says so instead of showing them a session.
  ///
  /// There is no "answer the screening" button here because this IS the
  /// questionnaire — the user is standing on the form, and a button that
  /// scrolls them back to a step they can already reach is noise.
  Widget _outcomeBody(
      BuildContext context, AppLocalizations l10n, PlanOutcome outcome) {
    if (outcome case PlanRefused(:final reasons)) {
      return SafetyRefusalCard(
        key: const Key('onb.preview.refused'),
        reasons: reasons,
      );
    }
    return _planBody(context, l10n, (outcome as PlanReady).plan);
  }

  Widget _planBody(
      BuildContext context, AppLocalizations l10n, GeneratedPlan plan) {
    // Reached when every candidate conflicts with the limitations just
    // entered. Saying so is the useful answer; inventing a session would be an
    // unsafe one.
    if (plan.exercises.isEmpty) {
      return _Message(
        key: const Key('onb.preview.empty'),
        text: l10n.onbPreviewEmpty,
      );
    }
    final theme = Theme.of(context);
    return Column(
      key: const Key('onb.preview.plan'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onbPreviewLength(plan.estimatedMinutes),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        for (final ex in plan.exercises)
          _PlanRow(name: ex.title, minutes: ex.durationMinutes),
        const SizedBox(height: 14),
        // The generator's own words, not a marketing line written for this
        // screen: it names what it filtered and why, which is the part worth
        // reading.
        Text(
          plan.rationale,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colors.textSecondary),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium
          ?.copyWith(color: theme.colors.textSecondary),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.name, required this.minutes});

  final String name;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 7, color: theme.colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colors.textPrimary),
            ),
          ),
          Text(
            AppLocalizations.of(context).onbPreviewMinutes(minutes),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
