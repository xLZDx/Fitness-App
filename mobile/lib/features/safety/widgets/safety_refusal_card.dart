import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
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
    final t = context.hud;
    final answered = reasons.where((r) => !r.incomplete).toList();
    final unanswered = reasons.where((r) => r.incomplete).toList();

    // An answered blocking reason outranks an unfinished form: someone who has
    // told us about chest pain is not asked to go and tick more boxes.
    final referral = answered.isNotEmpty;

    // F017: chest pain is the one PAR-Q+ answer this app treats as urgent
    // rather than routine (see kBlockingQuestions' doc comment). The generic
    // "talk to a doctor first" referral used for every other blocking answer
    // reads as routine, which is the wrong message for this one — it must not
    // collapse into the same wording as, say, an unanswered question about
    // prescribed medication.
    final urgent =
        answered.any((r) => r.question == ParQQuestion.chestPain);

    // `dense: true` reuses the same adaptive-alpha surface Workouts' cards
    // use over a photograph background (`HudSkyScope.denseSurfaceAlpha`) —
    // the refusal is drawn on the same sky as everything else on the screen,
    // so it needs the same readability fix, not a second one. Danger is
    // carried by the icon and heading colour, not a full tinted fill: the
    // handoff's semantic states colour an accent, not the glass itself.
    return HudPanel(
      dense: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  urgent
                      ? Icons.local_hospital_outlined
                      : referral
                          ? Icons.medical_services_outlined
                          : Icons.pending_actions,
                  color: t.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  urgent
                      ? l10n.safetyBlockedUrgentTitle
                      : referral
                          ? l10n.safetyBlockedTitle
                          : l10n.safetyIncompleteTitle,
                  style: HudType.panelTitle(t).copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
              urgent
                  ? l10n.safetyBlockedUrgentBody
                  : referral
                      ? l10n.safetyBlockedBody
                      : l10n.safetyIncompleteBody,
              style: HudType.body(t, size: 12.5)),
          if (answered.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(l10n.safetyReasonYouAnswered, style: HudType.label(t)),
            for (final r in answered)
              _SafetyBullet(text: parQQuestionText(l10n, r.question)),
          ],
          if (unanswered.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(l10n.safetyReasonNotAnswered, style: HudType.label(t)),
            for (final r in unanswered)
              _SafetyBullet(text: parQQuestionText(l10n, r.question)),
          ],
          if (onOpenScreening != null && !referral) ...[
            const SizedBox(height: 16),
            HudButton(
              label: l10n.safetyOpenScreening,
              tone: HudButtonTone.accent,
              onPressed: onOpenScreening,
            ),
          ],
        ],
      ),
    );
  }
}

class _SafetyBullet extends StatelessWidget {
  const _SafetyBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.hud;
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
                color: t.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(text, style: HudType.body(t, size: 12)),
          ),
        ],
      ),
    );
  }
}
