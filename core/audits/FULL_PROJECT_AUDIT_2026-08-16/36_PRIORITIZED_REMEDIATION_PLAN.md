# 36 - Remediation plan

Not started. Awaiting `REMEDIATION-GO`.

## P0 - safety, privacy, security

| Task | Findings | Files | Acceptance |
|---|---|---|---|
| P0.1 Close the fail-open exercise filter | F013 | `equipment/data/exercise_filter.dart:38`, `safety/data/eligibility.dart:282` | An untagged row yields `Degraded`/withheld for an injured user, not `Allowed`. Mutation: restore the early `return false`, test goes red |
| P0.2 Add a pregnancy question | F014 | `safety/data/par_q.dart`, `onboarding/steps/step_screening.dart` | Persist a boolean only, per the recorded decision at `cycle_phase.dart:56-64`. `SafetyContext(pregnancy: yes).allowsAnyTraining == false`; `buildPlan` returns `PlanRefused` |
| P0.3 Pass the safety context into the spec-less programme path | F015 | `programmes/state/programme_providers.dart:199-206` | Enrol `from_answers` with a blocked profile: zero `ScheduledSession` rows written, refusal stated |
| P0.4 Validate AI `uses` against the catalogue | F016 | `visual_equipment/data/machine_describer.dart:165-177` | A stub returning an invented movement renders no `uses`, or renders them explicitly flagged as not from the library |
| P0.5 Give the chest-pain refusal urgency | F017 | `safety/data/par_q.dart:123`, `app_*.arb` | Copy branches on `kBlockingQuestions`; chest pain gets urgent-evaluation wording |
| P0.6 Remove the false claim at the point of collection | F018 | `app_en.arb:212`, `onboarding/steps/step_health.dart:97` | "We use this to keep your plan safe" no longer sits above fields that reach no filter. It contradicts `healthStepIntro` two steps later |
| P0.7 Render `safetyFilterCoverage` | F019 | `equipment/widgets/safety_disclosure.dart` | The tagged/total figure is shown; the provider already computes it |
| P0.8 Show `SafetyDisclosure` on every exercise-serving surface | F020 | 6 screens listed in `22_HEALTH_SAFETY_AUDIT.md` | Currently rendered on one page only, while the per-item caution badge ships on two others |
| P0.9 Exclude `usage` and `receipts` from client writes | F005, F006 | `firestore.rules:16` | Rules-emulator tests assert both denied |

## P1 - incorrect logic

P1.1 replace the alphabetical `_fillDay` default (F021) · P1.2 fix the day-to-day repetition stride
(F022) · P1.3 either enforce `difficulty` or stop presenting level as personalisation (F001) ·
P1.4 widen the `ai::` exclusion to restriction-only profiles (F023) · P1.5 add the index tie-break to
`sortByTierFit` (F024) · P1.6 delete or repair the nine dangling celebrity-plan ids (F025) ·
P1.7 set explicit `SafetySetting`s on all three Gemini calls (F026)

## P2 - reliability

P2.1 localise the seven hardcoded English safety strings (F027) · P2.2 make the analyzer count
non-regressing in CI (F007) · P2.3 add the working branch to the push trigger (F008) · P2.4 add a
timeout to the AI coach call · P2.5 consume or drop the 14 unused questionnaire fields (F003, F004)

## P3 - cleanup

P3.1 the 7 unreferenced providers and two reader-less features (F010) · P3.2 correct the model row in
`FINAL_SCOPE` (F012) · P3.3 fix the left/right copy bug in `ea_diagonal_chop_*` · P3.4 remove the
duplicate blood-pressure question · P3.5 the dead l10n keys, including
`momentsYouJustDodgedAFlareUp`, which must not be wired up as written
