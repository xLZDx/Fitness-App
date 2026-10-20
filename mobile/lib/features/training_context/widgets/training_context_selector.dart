import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/hud/hud_surface.dart';
import '../data/training_context.dart';
import '../state/training_context_providers.dart';

String trainingContextLabel(AppLocalizations l10n, TrainingContext c) =>
    switch (c) {
      TrainingContext.gymMachines => l10n.trainingContextGym,
      TrainingContext.outdoorMinimal => l10n.trainingContextOutdoor,
      TrainingContext.home => l10n.trainingContextHome,
      TrainingContext.yoga => l10n.trainingContextYoga,
    };

/// A tap must never surface a storage failure as an unhandled async error.
Future<void> _guarded(Future<void> write) async {
  try {
    await write;
  } catch (e) {
    debugPrint('training context choice not stored: $e');
  }
}

/// The "what is this training for" chooser used by every recommendation
/// surface.
///
/// Unanswered: the prompt, the four choices and a Skip action. Answered or
/// skipped: the same choices as a compact row, so the context can be changed
/// per request (a tap stores it and regenerates what watches it).
class TrainingContextSelector extends ConsumerWidget {
  const TrainingContextSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final answer = ref.watch(trainingContextProvider).valueOrNull;
    if (answer == null) return const SizedBox.shrink();
    final notifier = ref.read(trainingContextProvider.notifier);
    return HudPanel(
      key: const Key('training-context.selector'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!answer.answered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l10n.trainingContextPrompt,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in TrainingContext.values)
                ChoiceChip(
                  key: Key('training-context.${c.name}'),
                  label: Text(trainingContextLabel(l10n, c)),
                  selected: answer.context == c,
                  onSelected: (_) => _guarded(notifier.choose(c)),
                ),
            ],
          ),
          if (!answer.answered)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('training-context.skip'),
                onPressed: () => _guarded(notifier.skip()),
                child: Text(l10n.trainingContextSkip),
              ),
            )
          else if (answer.context == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.trainingContextUsingProfile,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
