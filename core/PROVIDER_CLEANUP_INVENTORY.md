# Provider cleanup inventory (F010)

**Status: INVENTORY ONLY. Nothing is deleted by this document.**
Measured 2026-08-17 against branch `formcoach/gates-a-c`.

**Disposition:** `F010 = DEFERRED_TO_DEDICATED_CLEANUP_GATE`. Not release-blocking.

---

## Why this is not being fixed now

The audit's own `minimal_fix` said *"decide per feature: wire it up or delete it. **Do not delete
during an audit.**"* That is right, and worth stating rather than assuming: a deletion pass in the
middle of a remediation programme makes every subsequent diff harder to read, and the whole value of
the remaining work is that its diffs are reviewable.

There is also a distinction this document exists to keep:

```text
AUDIT FINDING RESOLVED AS PRODUCT/MAINTENANCE DEBT
!=
CODE DELETED
```

F010 is resolved in the first sense. Nothing is deleted.

---

## The measurement, and a correction

The audit recorded **7 of 196** providers with no reference. Re-measured at this HEAD:

| | Audit | Now |
|---|---|---|
| Providers declared | 196 | **193** |
| No reader outside their own file | 7 | **14** |

The gap **widened**. Quoting the audit's figure would have understated it, which is why the number
is re-derived here rather than copied.

What moved in the other direction: `momentRepositoryProvider` and `wearSyncServiceProvider` — the
two the audit named — **are now wired**, in `lib/main.dart`. So the specific claim "the whole moments
provider set and both Wear OS providers are unreferenced" is no longer true as written, while the
general condition is more widespread than recorded.

Method: a provider is counted unread when no file in `lib/` or `test/` other than its own declaring
file mentions it by name. That is deliberately generous — it counts a mention in a test as a reader —
so the list below is a lower bound.

---

## Classification

| Provider | Location | Class | Reasoning |
|---|---|---|---|
| `_filteredExercisesProvider` | `lib/features/workouts/workouts_page.dart` | **VALID_BY_CONSTRUCTION** | Private (`_`). "No reader outside its own file" is what private means. Not debt; it is the only one of the fourteen that is a measurement artefact rather than a finding. |
| `aiCoachServiceProvider` | `lib/features/ai_coach/ai_coach_service.dart` | **PRODUCT_DECISION** | The AI coach is a live feature reached from three surfaces. A service provider with no reader means the sheet constructs its service another way — worth understanding before touching, because the answer may be a wiring defect rather than dead code. |
| `celebrityPlanRepositoryProvider` | `lib/features/celebrity_plans/state/celebrity_plan_providers.dart` | **DORMANT** | Same feature as F025's dangling ids. The repository is finished and nothing reads it. Coupled to the F025 tripwire: if a reader appears, both this and the nine ids need attention together. |
| `hasShownProvider` | `lib/features/moments/state/moment_providers.dart` | **DORMANT** | Nurture-moments set. `momentRepositoryProvider` beside it IS now wired, so the feature is half-live. |
| `injuryFilterUsesProvider` | `lib/features/moments/state/moment_providers.dart` | **DORMANT** | As above. |
| `launchCountProvider` | `lib/features/moments/state/moment_providers.dart` | **DORMANT** | As above. |
| `momentControllerProvider` | `lib/features/moments/state/moment_providers.dart` | **DORMANT** | As above. The controller is the piece a reader would need first. |
| `last7DaysHealthProvider` | `lib/core/health/state/health_providers.dart` | **INTENDED** | Health-sync surfaces exist (`health_sync_card.dart`). A seven-day window with no consumer is a feature that was built to the edge of its UI. |
| `photoMonthsProvider` | `lib/features/progress_photos/state/progress_photos_providers.dart` | **INTENDED** | Progress photos ship. A month-grouping provider is a view that was not finished. |
| `progressPhotosStoreProvider` | `lib/features/progress_photos/state/progress_photos_providers.dart` | **PRODUCT_DECISION** | A *store* with no reader in a feature that does ship is the same shape as `aiCoachServiceProvider` — possibly a superseded wiring path rather than dead code. Check before deleting. |
| `poseGateConfigProvider` | `lib/features/form_check/state/form_check_providers.dart` | **INTENDED** | Form Coach ships and the pose gate is live; a config provider with no reader means the gate is configured by constant instead. |
| `summaryDayProvider` | `lib/features/workouts/state/day_result_providers.dart` | **INTENDED** | Day-result surfaces exist. |
| `watchPairedProvider` | `lib/core/wear/state/wear_providers.dart` | **DORMANT** | Wear OS. `wearSyncServiceProvider` beside it is now wired; these two are not. |
| `wearIncomingProvider` | `lib/core/wear/state/wear_providers.dart` | **DORMANT** | As above. |

Counts: **VALID_BY_CONSTRUCTION 1 · INTENDED 4 · DORMANT 7 · PRODUCT_DECISION 2 · SUPERSEDED 0 ·
SAFE_TO_DELETE 0.**

**`SAFE_TO_DELETE` is deliberately empty.** Not one of the thirteen public providers can be called
safe to delete on the evidence in this document alone: every one is either part of a feature that
ships, or part of a feature somebody deliberately built. Deciding otherwise is what the dedicated
gate is for, and populating this column from a name and a reference count would be exactly the
closure-count work this programme has refused elsewhere.

---

## Safety

None of the fourteen can influence a prescription. Nothing unread reaches the eligibility layer, the
programme builder or the planner — verified by the fact that they have no readers at all.

**Release impact: none.**

---

## What the dedicated gate should do

1. Re-measure. This list is a snapshot and the count has already moved once.
2. For each `PRODUCT_DECISION` row, establish whether it is dead code or a **wiring defect**. Those
   look identical to a reference count and are opposite problems.
3. For `DORMANT` rows, take the roadmap decision (moments, Wear OS, celebrity plans) before touching
   code. `N07` sets the precedent: a finished feature is not deleted merely for lacking a route.
4. Delete only what survives 2 and 3, in one commit per feature, on a green tree.
5. Do not run it during active feature work or immediately before a release.
