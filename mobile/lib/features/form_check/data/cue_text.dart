import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'form_classifier.dart';
import 'pose_gate.dart';
import 'rep_counter.dart';

/// The boundary where the form coach's internal identifiers become words.
///
/// The classifiers and the rep counter are pure Dart with no `BuildContext`,
/// which is why they must not carry sentences — they carry keys, and this file
/// is the single place those keys turn into something a person reads or hears.
///
/// [formCueText] is exhaustive over [FormCueKey] and has no fallback at all —
/// a missing translation is a compile error. [formRuleName] cannot be, because
/// rule ids are Strings that also go into the rep record; its fallback returns
/// the raw id, and `test/l10n/no_untranslated_strings_test.dart` is what stops
/// that fallback ever being reached, by walking the shipped classifier list.

/// Spoken/displayed text for a [FormCueKey].
///
/// No catch-all arm, on purpose: the switch is exhaustive over the enum, so
/// adding a cue without adding its text is a compile error rather than a cue
/// that resolves to nothing and is silently never spoken.
String formCueText(AppLocalizations l10n, FormCueKey cueKey) =>
    switch (cueKey) {
      FormCueKey.squatDepthGood => l10n.formcheckCueSquatDepthGood,
      FormCueKey.squatDepthAlmost => l10n.formcheckCueSquatDepthAlmost,
      FormCueKey.squatDepthHalf => l10n.formcheckCueSquatDepthHalf,
      FormCueKey.deadliftHipHingeShallow =>
        l10n.formcheckCueDeadliftHipHingeShallow,
      FormCueKey.deadliftHipHingeDeep => l10n.formcheckCueDeadliftHipHingeDeep,
      FormCueKey.pushupAlignStraight => l10n.formcheckCuePushupAlignStraight,
      FormCueKey.pushupAlignTuck => l10n.formcheckCuePushupAlignTuck,
      FormCueKey.pushupAlignSagging => l10n.formcheckCuePushupAlignSagging,
      FormCueKey.silhouetteMissed => l10n.formcheckCueSilhouetteMissed,
    };

/// Human name for a rule id, for the post-set tally.
///
/// Without this the summary read "Ошибки: squat.depth, deadlift.back_angle,
/// pushup.alignment" — internal identifiers, in English, on a Russian screen.
String formRuleName(AppLocalizations l10n, String ruleId) => switch (ruleId) {
      'squat.depth' => l10n.formcheckRuleSquatDepth,
      'deadlift.hip_hinge' => l10n.formcheckRuleDeadliftHipHinge,
      'pushup.alignment' => l10n.formcheckRulePushupAlignment,
      // Rule ids are Strings because they are also written into the rep record,
      // so this one arm cannot be made exhaustive. The l10n test walks the
      // shipped classifier list and asserts each id maps, which is what keeps
      // this fallback unreachable in practice.
      _ => ruleId,
    };

/// What to tell the user when a frame cannot be scored.
///
/// Each verdict gets its own sentence on purpose: "step back" and "hold the
/// phone steady" are different problems with different fixes, and collapsing
/// them into one generic hint is how a user ends up repeating the wrong
/// correction.
String poseGateHint(AppLocalizations l10n, PoseGateVerdict verdict) =>
    switch (verdict) {
      PoseGateVerdict.ok => '',
      PoseGateVerdict.missingJoints => l10n.formcheckStandBackSoYourFullBody,
      PoseGateVerdict.lowConfidence => l10n.formcheckGateLowConfidence,
      PoseGateVerdict.outOfFrame => l10n.formcheckGateOutOfFrame,
      PoseGateVerdict.implausibleGeometry =>
        l10n.formcheckStandBackSoYourFullBody,
      // The only verdict whose text asks the user to do nothing, because there
      // is nothing they can do. Every other hint names a correction; this one
      // names a limitation and says what still works, so the screen is not
      // silently degraded into looking broken.
      PoseGateVerdict.unitMismatch => l10n.formcheckGateUnitMismatch,
    };

/// Name of the phase of a repetition.
///
/// Was a bare English `switch` returning 'ready' / 'lowering' / 'bottom' /
/// 'driving up', substituted into the localized template — which is how the
/// Russian screen read "повторения — ready".
String repPhaseText(AppLocalizations l10n, RepPhase phase) => switch (phase) {
      RepPhase.top => l10n.formcheckPhaseReady,
      RepPhase.descending => l10n.formcheckPhaseLowering,
      RepPhase.bottom => l10n.formcheckPhaseBottom,
      RepPhase.ascending => l10n.formcheckPhaseDrivingUp,
    };
