import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../data/eligibility.dart';
import '../data/health_flags.dart';
import '../data/par_q.dart' show ParQQuestion;
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
      // F014. The wording is load-bearing and is tested for what it must NOT
      // say: it states what this app will not do, never that the user is
      // medically unsafe and never that exercise is prohibited. Both of those
      // would be medical advice, which is exactly what the absence of a
      // validated policy means we may not give.
      BlockReason.professionalGuidance => l10n.eligReasonProfessionalGuidance,
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
    final t = context.hud;

    // F017: this card is the one every whole-person block renders through
    // (Train tab, programme-enrolment refusal, deep links) — not only the
    // onboarding screen SafetyRefusalCard covers. A chest-pain reason must
    // read as urgent here too, or the routine "no sessions right now" wording
    // survives on every surface except the one it was first noticed on.
    //
    // Matches SafetyRefusalCard's `answered.any(...)`: urgency requires the
    // person to have actually answered "yes". An unanswered chest-pain
    // question must not collapse into "you indicated you have chest pain" —
    // that is a false claim about what the person said, not a safety margin.
    final urgent = reasons.any((r) =>
        r.reason == BlockReason.screening &&
        r.question == ParQQuestion.chestPain &&
        !r.unanswered);

    // `wholePersonBlocks` can carry several `BlockReason.screening` entries at
    // once — one per PAR-Q+ question — and `eligibilityReasonText` prefixes
    // EACH with the same "screening did not clear you" sentence, because that
    // function also has to word single-reason cases (a withheld exercise) on
    // its own. Rendered one bullet per reason, a six-question refusal repeats
    // that sentence six times. Grouping them here, the way
    // `SafetyRefusalCard` already groups PAR-Q+ answers, states the shared
    // sentence once and lists only the specific questions — no wording
    // changes, the same localised strings composed differently.
    final screened = reasons
        .where((r) => r.reason == BlockReason.screening && r.question != null)
        .toList();
    final other = reasons.where((r) => !screened.contains(r)).toList();
    final answered = screened.where((r) => !r.unanswered).toList();
    final unanswered = screened.where((r) => r.unanswered).toList();

    // `dense: true` reuses the adaptive-alpha surface already solved for
    // Workouts' cards over a photograph background — the refusal sits on the
    // same sky as the rest of the screen. Danger is carried by the icon and
    // heading colour, matching the handoff's semantic-state language, not a
    // full tinted fill.
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
                      : Icons.shield_outlined,
                  color: t.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    urgent
                        ? l10n.eligTrainingBlockedUrgentTitle
                        : title ?? l10n.eligBlockedTitle,
                    style: HudType.panelTitle(t).copyWith(fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(urgent ? l10n.eligBlockedUrgentIntro : l10n.eligBlockedIntro,
              style: HudType.body(t, size: 12.5)),
          if (screened.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l10n.eligReasonScreening,
                style: HudType.bodyStrong(t, size: 12.5)),
            if (answered.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.safetyReasonYouAnswered, style: HudType.label(t)),
              for (final r in answered)
                _ReasonBullet(text: parQQuestionText(l10n, r.question!)),
            ],
            if (unanswered.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.safetyReasonNotAnswered, style: HudType.label(t)),
              for (final r in unanswered)
                _ReasonBullet(text: parQQuestionText(l10n, r.question!)),
            ],
          ],
          for (final r in other)
            _ReasonBullet(text: eligibilityReasonText(l10n, r)),
          if (onReviewProfile != null) ...[
            const SizedBox(height: 16),
            HudButton(
              label: l10n.eligOpenProfile,
              tone: HudButtonTone.accent,
              onPressed: onReviewProfile,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReasonBullet extends StatelessWidget {
  const _ReasonBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.hud;
    return Padding(
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
