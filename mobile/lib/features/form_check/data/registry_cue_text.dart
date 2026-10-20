// Wording for data-driven registry cues (`<exerciseId>.<ruleId>`). The switch
// and [registryCueIds] are asserted equal to the cue ids used by
// `assets/data/coach_exercises.json` by `coach_registry_content_test.dart`.

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Every cue id the registry may reference. Must equal the ids handled by
/// [registryCueText].
const Set<String> registryCueIds = <String>{
  'bentOverRow.hinge',
  'bentOverRow.drift',
  'lateralRaise.too_high',
  'lateralRaise.arms_bent',
  'plank.sag',
  'plank.pike',
  'gluteBridge.lift_hips',
  'gluteBridge.knee_setup',
  'pullUp.partial_rep',
  'stepUp.lean',
  'tricepDip.too_deep',
  'goodMorning.knees',
  'goodMorning.too_deep',
};

/// Localised text for [cueId], or null for an unknown id.
String? registryCueText(AppLocalizations l10n, String cueId) =>
    switch (cueId) {
      'bentOverRow.hinge' => l10n.formcheckRegistryBentOverRowHinge,
      'bentOverRow.drift' => l10n.formcheckRegistryBentOverRowDrift,
      'lateralRaise.too_high' => l10n.formcheckRegistryLateralRaiseTooHigh,
      'lateralRaise.arms_bent' => l10n.formcheckRegistryLateralRaiseArmsBent,
      'plank.sag' => l10n.formcheckRegistryPlankSag,
      'plank.pike' => l10n.formcheckRegistryPlankPike,
      'gluteBridge.lift_hips' => l10n.formcheckRegistryGluteBridgeLiftHips,
      'gluteBridge.knee_setup' => l10n.formcheckRegistryGluteBridgeKneeSetup,
      'pullUp.partial_rep' => l10n.formcheckRegistryPullUpPartialRep,
      'stepUp.lean' => l10n.formcheckRegistryStepUpLean,
      'tricepDip.too_deep' => l10n.formcheckRegistryTricepDipTooDeep,
      'goodMorning.knees' => l10n.formcheckRegistryGoodMorningKnees,
      'goodMorning.too_deep' => l10n.formcheckRegistryGoodMorningTooDeep,
      _ => null,
    };
