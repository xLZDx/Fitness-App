# Change record: C18 nutrition plan state, repositories and weekly review scheduler

## What changed
New files under `mobile/lib/features/nutrition_plan/`, plus the repository overrides in `mobile/lib/main.dart`.

`data/` (no UI):
- `stored_nutrition_plan.dart`: `StoredNutritionPlan` (design s5.4 shape), `PlanInputsDigest`, `ReviewUndo`. `validated()` recomputes the kcal bounds from the digest and pulls range, macros, steps and rate inside the clamps; it runs on every read and every write. Only an `active` plan is ever written; an unreadable or `needsProfile` document reads as "no plan".
- `plan_review_record.dart`: the immutable review document (s5.5). The classification is stored inside `inputs` (the rules close the top-level key set) and read back as `previousClass`.
- `review_transaction.dart`: the PURE core of the D-57 transaction (`planReviewTransaction`) and of the undo (`planUndoTransaction`). Order: week key exists -> no-op; no plan / `planVersion != basePlanVersion` -> nothing written; cooldown (14 days, `tooFast` exempt), drift cap and bounds re-checked against the stored plan; then review + plan change together (coached: with the 7-day `reviewUndo`; shared/manual: review only).
- `plan_repository.dart` (interface), `firestore_plan_repository.dart` (one `runTransaction`: get review first, then plan, then both writes), `in_memory_nutrition_repositories.dart` (fakes that run the same pure rules, with an `offline` switch and write counters).
- `weight_repository.dart`, `firestore_weight_repository.dart`: day-keyed weigh-ins with ids, 60-day window, `put`, `replace` (edit, one batch if the day moves), `delete`.
- `review_input_builder.dart`: the single `ReviewInput` builder (scheduler, live provider and post-scan decision share it).

`state/`:
- `weight_providers.dart`: `nutritionClockProvider`, `weightRepositoryProvider`, `weightLogItemsProvider`, `weightEntriesProvider`, the ONE `currentWeightProvider` (D-72), `WeightLogActions` (add / scan weight that never silently replaces an equal same-day manual entry / edit / delete, deletion fence).
- `nutrition_providers.dart`: `nutritionPlanRepositoryProvider`, `bodyFatTrendSourceProvider` (port, safe default), `healthMedianStepsProvider` (14-day median through the existing HealthService seam, at least 7 completed days, else null so the manual bucket applies), `nutritionInputsProvider`, device-local `nutritionEligibilityProvider` (null = unknown = no numbers), `storedNutritionPlanProvider`, display-gated `nutritionPlanProvider`, `nutritionReviewsProvider`, read-model `weeklyReviewProvider`.
- `review_scheduler.dart`: `WeeklyReviewScheduler.run(trigger)`; writes nothing when signed out, account being deleted, data notice pending, not eligible, no plan, week already reviewed, or offline. `scanDoneSignalProvider` + `weeklyReviewTriggersProvider` for the scan-done trigger (bridged at the app root; body_scan does not import this feature).
- `nutrition_plan_actions.dart`: ensure plan, set range (coached becomes shared), steps, ownership, auto-adjust, accept a shared proposal, undo; all version-checked and eligibility-gated.
- `nutrition_training_advice_provider.dart`: the C09 function over live plan, weight slope and profile inputs.
- `scan_plan_context_source.dart`: the real `ScanPlanContextSource` (surface mode from the verdict, decision and target only for an eligible user).

`main.dart`: `nutritionPlanRepositoryProvider` and `weightRepositoryProvider` overridden with the Firestore implementations.

## Why
Sprint plan C18; design s5.3-5.5, s14, s15, s21; D-55 (nothing derived from the verdict is persisted), D-57 (atomic review transaction), D-72 (single current weight), D-74/D-71 (ports).

## Deviations
- Repository interface, Firestore implementation and fakes live in `data/` (as `ProfileRepository` does) instead of `state/plan_repository.dart`, per the commit instruction.
- `lastKcalAdjustAt` is set by ANY plan-changing review (kcal or steps), because the design's 14-day cooldown guards both; otherwise a steps change would not start a cooldown.
- Shared and manual reviews write the review document only; a shared proposal is applied by `acceptProposal` (version-checked against the review's `basePlanVersion`).
- A transaction that the in-transaction re-check refuses (`rejected`) or finds stale writes nothing and is retried by the next trigger.
- The app-root override of `scanPlanContextProvider` and the `bodyFatTrendSourceProvider` binding are NOT done here: `scanPlanContextProvider` (C15) and the body_scan trend implementation (C14) do not exist yet. The ready-made `nutritionScanPlanContextSourceProvider` is the value to bind there.
- No UI and no data-notice prompt here: UI callers invoke `ensureDataNoticeAcknowledged` before weight/plan writes (D-79); the scheduler itself refuses to run until the notice is acknowledged.
- Protein adherence, sleep and recovery signals for the training advice are left unset until the diary exists.

## Affected contracts and paths
`firestore.rules` shapes from C01 are matched (Timestamps for `at`, `planVersion == old + 1` on update, closed key sets, no `referProfessional`). No rules or index change.

## Verification state
Not run, per DEVELOPMENT RULES v4. No analyzer or compiler was run: identifiers and imports were checked by reading only.

## Review state
Pending the test phase and specialist reviewers.
