# 23 - Female health and cycle logic

**Status: the feature is dead code, and what it was warned about has already been removed.**

`estimatePhase` (`cycle_phase.dart:138-161`) validates its inputs properly - cycle length 21..35,
day 1..cycleLength - and has **no production caller**. Both `buildPlan` call sites omit `cycle:` and
`cycleSelfReport:` (`ai_planner_providers.dart:42-47`, `plan_preview_provider.dart:48-54`), so the
phase is permanently `CycleUnknown(notTracked)`.

No date arithmetic exists anywhere in the feature, which means the documented guard against a
last-period date in the future (`cycle_phase.dart:66-72`) cannot fire - there is no date input to
guard.

**The dangerous version was already deleted.** Deterministic performance claims - an
`intensityFactor: 1.10` and copy reading "Peak performance day. PR attempts welcome" - were removed,
recorded at `DECISION_LOG.md:10376-10379`. The audit mandate's central concern for this section,
"cycle phase must not claim deterministic performance capability", has already been acted on by this
project of its own accord.

**Two residual issues:**

1. Remaining cycle copy is hardcoded English and absent from both `.arb` files - it would render
   untranslated if the feature were ever wired up.
2. `CycleUnavailable.notApplicable` is one value deliberately covering pregnancy, postpartum and any
   other reason (`cycle_phase.dart:56-64`). The reasoning is sound and recorded. It is also the
   nearest thing the app has to a pregnancy signal, and it feeds nothing - see BLOCKER 2 in
   `22_HEALTH_SAFETY_AUDIT.md`.
