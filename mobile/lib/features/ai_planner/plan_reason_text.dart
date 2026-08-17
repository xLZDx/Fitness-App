import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../cycle_aware/data/cycle_phase.dart';
import '../safety/widgets/eligibility_notice.dart';
import 'data/workout_plan.dart';

/// Where a plan's reason codes become sentences.
///
/// F027. This is the boundary the builder does not cross. `plan_builder.dart`
/// is a pure function with no `BuildContext`, so every sentence it composed
/// itself was English by construction — including the screening ceiling, the
/// one line whose whole job is to tell a user the app has NOT cleared them.
/// That line reached Russian users in English.
///
/// The same shape as `_reasonText` in `home_page.dart`, and deliberately so:
/// a `switch` over a sealed type, in the layer that has the locale. The
/// compiler's exhaustiveness check is the point — a new [PlanReason] cannot be
/// added without this file failing to compile, which is the opposite of the
/// old arrangement, where a new reason was one more string literal in a data
/// file and nothing anywhere noticed.
String planReasonText(AppLocalizations l10n, PlanReason reason) =>
    switch (reason) {
      ScreeningCeilingReason(:final percent) =>
        l10n.planReasonScreeningCeiling(percent),
      DeloadReason(:final percent) => l10n.planReasonDeload(percent),
      CycleSelfReportReason(:final report) => switch (report) {
          CycleSelfReport.lowEnergy => l10n.planReasonCycleLowEnergy,
          CycleSelfReport.significantSymptoms =>
            l10n.planReasonCycleSignificantSymptoms,
          // The builder does not emit this case — `asUsual` yields no
          // adjustment at all, which is the whole of Gate O's reform. Rendered
          // as the neutral fallback rather than thrown on: a reason that
          // reached the screen should never be able to crash it.
          CycleSelfReport.asUsual => l10n.planReasonDeficitOrder,
        },
      CyclePhaseReason(:final phase) => switch (phase) {
          CyclePhase.menstrual => l10n.planReasonPhaseMenstrual,
          CyclePhase.follicular => l10n.planReasonPhaseFollicular,
          CyclePhase.ovulatory => l10n.planReasonPhaseOvulatory,
          CyclePhase.luteal => l10n.planReasonPhaseLuteal,
        },
      // Through the same table every other safety surface uses. The old
      // builder interpolated `restriction.name` — the raw Dart identifier —
      // so a user was shown "deepKneeFlexion" in both languages.
      UntaggedRestrictionReason(:final restriction) =>
        l10n.planReasonUntaggedRestriction(
          restriction == null
              ? l10n.restrictionOther
              : movementRestrictionText(l10n, restriction),
        ),
      InjuryFilterReason(:final count) => l10n.planReasonInjuryFiltered(count),
      NoHistoryReason() => l10n.planReasonNoHistory,
      DeficitOrderReason() => l10n.planReasonDeficitOrder,
    };

/// The plan's heading.
String planTitleText(AppLocalizations l10n, PlanTitle title) => switch (title) {
      PlanTitle.reduced => l10n.planTitleReduced,
      PlanTitle.deload => l10n.planTitleDeload,
      PlanTitle.easy => l10n.planTitleEasy,
      PlanTitle.adaptive => l10n.planTitleAdaptive,
    };

/// The rationale as one paragraph, in the order the builder emitted it.
///
/// Joining here rather than in the builder keeps the ordering decision (which
/// is a product decision — the ceiling comes first) with the data, and the
/// punctuation (which is a language decision) with the locale.
String planRationaleText(AppLocalizations l10n, Iterable<PlanReason> reasons) =>
    reasons.map((r) => planReasonText(l10n, r)).join(' ');
