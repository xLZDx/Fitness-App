import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../safety/data/par_q.dart';
import '../../safety/widgets/safety_refusal_card.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

/// Gate M — the PAR-Q+ pre-exercise screen.
///
/// The only screen in this questionnaire whose answers can stop the app
/// producing a workout. Everything else here is a preference.
///
/// ## Why the questions are rendered from the enum
///
/// `for (final q in ParQQuestion.values)` rather than seven hand-written
/// blocks. A hand-written list is a second copy of the instrument, and the
/// failure mode of a second copy is that a question gets added to the model,
/// read by `screen()`, and never shown — at which point every user is blocked
/// by a question they were never asked, with no way to answer it. Rendering
/// from the enum makes that state unreachable.
///
/// ## Why there is no "prefer not to say"
///
/// It would be indistinguishable from unanswered, which already blocks, and
/// offering it as a third chip would suggest it is a way through.
class StepScreening extends ConsumerWidget {
  const StepScreening({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final answers = ref.watch(questionnaireDraftProvider).health.screening;
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final verdict = screen(answers);

    void set(ParQQuestion q, bool value) {
      notifier.updateHealth((h) => h.copyWith(
            screening: {...h.screening, q: value},
          ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnbRefTitle(
          title: l10n.safetyScreeningTitle,
          subtitle: l10n.safetyScreeningIntro,
        ),
        const SizedBox(height: 16),
        for (final q in ParQQuestion.values) ...[
          FieldLabel(parQQuestionText(l10n, q)),
          SingleChoiceChips<bool>(
            key: Key('onb.screening.${q.name}'),
            options: const [false, true],
            labelOf: (v) => v ? l10n.safetyYes : l10n.safetyNo,
            value: answers[q],
            // `SingleChoiceChips` has no deselect — tapping the selected pill
            // re-selects it. So an answer can be CHANGED but not withdrawn,
            // and a user cannot return themselves to the unanswered state from
            // this screen. That is acceptable in this one direction: the state
            // they cannot get back to is the state that blocks, and both
            // answers to every question remain one tap away.
            onChanged: (v) => set(q, v),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Text(
          l10n.safetyScreeningMedicationNote,
          style: HudType.body(t, size: 12.5).overPhoto(t),
        ),
        // The verdict as soon as it exists, on the screen that produced it.
        // Finding out at the preview that an answer three screens back closed
        // the door is worse than being told here, where the answer is still on
        // display and can be corrected if it was a mis-tap.
        if (verdict.decision == SafetyDecision.blocked &&
            verdict.reasons.any((r) => !r.incomplete)) ...[
          const SizedBox(height: 20),
          SafetyRefusalCard(
            key: const Key('onb.screening.blocked'),
            reasons: verdict.reasons.where((r) => !r.incomplete).toList(),
          ),
        ] else if (verdict.decision == SafetyDecision.restricted) ...[
          const SizedBox(height: 20),
          Text(
            l10n.safetyRestrictedNotice,
            key: const Key('onb.screening.restricted'),
            style: HudType.body(t, size: 12.5).overPhoto(t),
          ),
        ],
      ],
    );
  }
}
