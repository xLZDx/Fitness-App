# AI-COACH-01 existing-workout transaction scope

Status: **PREPARATION ONLY — CODE GO NOT AUTHORIZED.** This document records a bounded implementation candidate and the evidence still required for a later authorization decision. It does not authorize implementation, tests, rules/schema changes, migration, release, production use, or alert changes.

Decision source: GPT-PM request `4b6238a0-1c80-4d69-87ba-45a214fc7e31`, correlated job `4176bb29-d3f1-42a8-920c-e7f562f42ee0`, user turn `313be192-99de-436e-bc12-0ddd545f0a16`, reply `5e446c22-bca5-464f-9fac-c167648855d4`. GPT-PM returned **PARTIAL ACCEPT — OPTION A APPROVED, IMPLEMENTATION NOT AUTHORIZED**. See the [decision and transport record](../../core/changes/2026-10-20-ai-coach-offline-tradeoff-decision.md).

## 1. Bounded purpose

Prepare one shared action/persistence boundary over the existing `WorkoutSession` record so existing touch operations and a later authorized voice adapter can request the same typed mutations. Preserve the current workout identity and existing readers. Do not create a second workout tracker, session lifecycle, collection, or offline operation journal.

Candidate typed operations:

- `CompleteSet`: record one performed-set fact for an existing eligible exercise.
- `AddEligibleExercise`: add an eligible exercise to the current authoritative session.
- `SetDifficulty`: update the selected exercise's difficulty against current session state.

This is an operation boundary proposal, not a statement that voice recognition exists or that any command is currently executable.

## 2. Product behavior already decided

GPT-PM accepted Option A for these mutations in the new shared transactional contract:

- Read the latest authoritative session document and apply only the targeted mutation in a Firestore transaction.
- Do not durably queue these mutations while offline. Show an unsaved capture in the current UI only; leaving or losing that UI may discard it. Do not start rest or say the action was saved.
- Return `NOT_SENT_OFFLINE` only when evidence establishes the operation did not cross the submission boundary. If submission or commit may have occurred, return `UNKNOWN` and reconcile the same operation identity against the server before reporting success or creating a new identity.
- Return `SERVER_ACKNOWLEDGED` only after confirmed transaction success.
- Option B (a separate keyed offline-operation representation) is rejected for this scope. The current whole-document offline queue is not an equivalent implementation.
- OQ-07 remains fail-closed: this decision supplies no clinical values, symptom thresholds, qualified signer, or clinical authorization. OQ-14/OQ-18 retain their accepted bounded directions; deferred source, locale, recovery, calendar and persistence values stay open.

This is a bounded exception to the broad AICR-074 offline manual-result requirement for set/add/difficulty operations only after they are migrated into this new shared action. Existing offline timer, exercise display, cached-plan access and unrelated offline/manual operations remain requirements. The current touch writer has not changed and this source statement is not runtime evidence.

## 3. Candidate technical contract

These rules make the product choice implementable in principle; they do not close the physical storage or mixed-version design gates.

1. Resolve authenticated user, session identity, route context, exercise eligibility and current policy at the shared action boundary. Voice must not submit an arbitrary `WorkoutSession` snapshot.
2. Allocate a stable `operationId` before first submission. `CompleteSet` also carries a stable `setId`. A retry after timeout or `UNKNOWN` reuses the same IDs and normalized typed payload.
3. In the transaction, read the current session and apply a targeted mutation. Preserve unrelated exercises, sets, session metadata and concurrent accepted changes.
4. Same operation ID plus same canonical typed payload is an idempotent no-op with the prior outcome. Same ID plus a different payload is a visible conflict with no mutation. A new/corrected user action gets a new operation ID.
5. `AddEligibleExercise` checks the stable exercise ID against the transaction's current document. `SetDifficulty` updates only the current selected exercise, never resubmits an earlier widget snapshot.
6. `UNKNOWN` recovery performs a server-backed lookup of the same operation identity. A cache-only read is not acknowledgement. Do not silently queue a whole-document write after an ambiguous result.
7. Invalid, unsupported, terminal/deleted-session, changed-eligibility, account-switch, payload-conflict and server-denial outcomes are typed no-mutation results. Transaction retry exhaustion is not reported as success.
8. Keep target repetitions separate from performed repetitions. The current `SetCapture.reps` value may originate from a pre-set field labelled “Target reps”; do not relabel historical or target values as performed facts. Actual repetitions are unknown unless captured as such by an authorized interaction.

### UI outcome and disposal policy candidate

- `REJECTED`: show a no-mutation reason; do not start rest or clear a different active capture.
- `NOT_SENT_OFFLINE`: keep the capture and original operation ID only in the active workout UI; show it as unsaved; offer retry with the same identity after connectivity returns. Do not start rest. A requested route change offers “stay and retry” or “leave and discard”; confirmed discard cancels this unsubmitted action, and a later user action is a new operation.
- `UNKNOWN`: keep the same operation identity and payload context in unresolved application state; show “result unknown,” do not start rest, and disable replacement/retry with a new ID until the same ID is reconciled. Navigation may proceed only after an explicit warning; it must not convert UNKNOWN to success or silently create another operation.
- Account switch: bind unresolved state to the submitting UID/session and never retry it under another UID. Clear UI capture from a different account's view. A same-user return may resume same-ID reconciliation.
- Process death: no durable offline payload or second operation journal is approved. If the operation receipt is present in the authoritative session, a later server read may reconcile it. If neither a recoverable operation ID nor a receipt is available, the result remains UNKNOWN; the client must not invent success or issue a replacement ID.

The last case exposes an unresolved acceptance question: the UI can preserve a safe in-process outcome, but durable recovery of an ambiguous operation across process death depends on the still-open physical identity/receipt and retention design. Do not claim this lifecycle gate is closed until that design is approved and proven.

### Unresolved identity-storage gate

`operationId`, `setId`, canonical payload and receipt lifetime must be durable enough to survive acknowledgement ambiguity and support same-operation reconciliation. Their exact encoding within the existing authoritative workout record remains OPEN. No sidecar journal or second source of truth is approved. Before code GO, decide and evidence how receipt retention/capacity, old-client reads and writes, and rollback behave. An older full-document writer may omit fields it does not model; this risk is not solved by merely writing an additive field.

## 4. Source compatibility matrix

The paths below were inspected read-only in this checkout. Source evidence establishes current code shape, not runtime behavior or client-version coverage.

| Surface | Current source evidence | Candidate requirement | State before code GO |
|---|---|---|---|
| Repository write and acknowledgement | `mobile/lib/features/workouts/data/firestore_workout_session_repository.dart:61-70` uses `doc(session.id).set(session.toJson())` and a 4-second timeout whose handler returns normally. | Replace snapshot replacement for the three typed operations with transaction outcomes; do not interpret timeout return as server acknowledgement. | Contract described; code NOT AUTHORIZED. |
| Shared action | `mobile/lib/features/workouts/state/workout_session_providers.dart:89-110` accepts a whole `WorkoutSession`, suppresses only concurrent loading, then publishes data after `save`. | Both input modes call the same typed action and receive honest typed outcomes. `isLoading` is not replay protection. | Contract described; code NOT AUTHORIZED. |
| Touch writer: complete/log set | `mobile/lib/features/equipment/workout_player_page.dart:572-780` (`_MarkCompleteButton`) constructs a session from an earlier UI snapshot, replaces an exercise's set list with zero/one capture, then starts rest after provider success. | Preserve touch validation, session/day identity and ordering; append/correct against fresh transaction state. Do not claim rest starts after server persistence unless acknowledged. | Exact behavior mapped; migration and UI outcome changes NOT IMPLEMENTED. |
| Touch writer: add exercise | `mobile/lib/features/equipment/workout_player_page.dart:900-1023` (`_AddExerciseButton`) checks eligibility, collects capture/rating, appends to its snapshot, writes, then starts rest. | Preserve eligibility and rating semantics; merge against fresh state and preserve concurrent work. | Exact behavior mapped; migration NOT IMPLEMENTED. |
| Delayed difficulty | The rating path in `workout_player_page.dart:786-818` can submit a value based on an earlier entry snapshot. | Update only the current exercise in the transaction, not the whole stale snapshot. | Risk mapped; transaction NOT IMPLEMENTED. |
| Stored set model and provenance | `mobile/lib/features/workouts/data/set_capture.dart:8` has only nullable `weightKg` and `reps`; `workout_session.dart:29-105` serializes the set list. The normal sheet labels pre-set reps “Target reps” (`set_capture_sheet.dart:154-185`). | Define compatible set identity without inventing performed-rep provenance. | Physical encoding and actual-reps capture remain OPEN. |
| Legacy/full-document writers | Current repository uses a full document `set`; no reviewed code evidence proves that older installed clients preserve new metadata. | Establish a client/version/rules/write gate or another proven compatibility mechanism before persisting identity fields. | BLOCKING OPEN QUESTION; no version range or protection evidence supplied. |
| History projection | `mobile/lib/features/workouts/data/workout_session.dart:354-408` uses `_workingSet` and `asLogEntries()` to project one best set per exercise. | Preserve the existing projected history contract unless separately approved. | Reader mapped; behavior NOT_RUNTIME_VERIFIED. |
| Direct metrics | `mobile/lib/features/personalisation/data/volume_ledger.dart:96-133`, `mobile/lib/features/progress/data/progress_charts.dart:65-76,151-166`, and `mobile/lib/features/workouts/data/day_result.dart:86-129` consume stored sets directly. | Define treatment of only valid performed sets and avoid treating targets as completed reps. | Compatibility requirements mapped; code/tests NOT RUN. |
| Exports | `mobile/lib/features/data_export/data_export_providers.dart:80-96,121-124` supplies projected mobile `workoutLogs` and attaches server export; `functions/src/account_export.ts:514-520,560-568,593-646` includes raw `workout_sessions` subject to caps and `truncated` markers. | Preserve both existing representations; do not create duplicate export plumbing or call a truncated result complete. | Export paths mapped; code/tests NOT RUN. |
| Scheduled session writers | `workouts/state/scheduled_session_providers.dart:84-100` and `programmes/state/programme_providers.dart:389-403` write the separate `ScheduledSession` model. | Keep this transaction scope limited to `WorkoutSession`; do not imply programme/schedule persistence is included. | Explicitly OUT OF SCOPE. |
| UI lifecycle and account context | Current completion and add-exercise callbacks check `context.mounted` around asynchronous prompts, but no durable offline queue or cross-route capture guarantee is established by the reviewed paths. | Define navigation/disposal, account switch, retained unsaved capture, retry, and late reconciliation behavior before claiming honest status. | Prerequisite; exact product/UI contract and runtime proof OPEN. |

## 5. Proposed implementation boundary for a later authorization

### Included only if separately authorized

- Extract/introduce the shared typed action and transaction repository method over the existing `WorkoutSession` document.
- Migrate the two existing touch writers to that action while preserving authentication, safety/eligibility, exercise resolution, day/session identity, delayed rating intent and current reader/export contracts.
- Keep the user-visible Option A offline behavior: unsaved-only in-memory capture, no success/rest on unsent or unknown result, and same-ID server reconciliation for `UNKNOWN`.
- Preserve existing workout representation and avoid any independent workout collection, journal, or workout-wide lifecycle.

### Explicitly excluded

- Speech recognition, microphone permissions, voice dispatch/confirmation, and AI-COACH-02.
- Clinical policy, prescription values, symptom limits, clinical signer or activation of OQ-07-dependent behavior.
- OQ-14 factual-source activation, populated source allowlists/locales/freshness values, or free-form factual advice.
- OQ-18 programme generation, recovery/calendar values, or schedule persistence.
- ACS-100 production alert binding, paging/on-call configuration, monitoring mutation or delivery claim.
- Database migration, Firestore rules change, production mutation, deployment, push, merge, or tests/checks in this preparation pass.

## 6. Code-GO prerequisites and later acceptance evidence

GPT-PM's correlated response specifically withheld code GO pending:

1. AICR-074 and legacy touch impact frozen to the operation-level exception above; demonstrate that unrelated offline behaviors remain outside the changed contract.
2. A complete transaction/replay contract, including persisted identity encoding, canonical payload equality, changed-payload conflict, receipt lifetime/capacity, transaction exhaustion and `UNKNOWN` retry/reconciliation.
3. A proven old/new-client compatibility strategy showing an older full-document writer cannot silently strip identity or operation metadata during the rollout/rollback window.
4. A writer/reader/export impact review for both touch writers, repeated sets, delayed rating, existing session identity, best-set projection, direct per-set readers and both export views.
5. A UI lifecycle contract for retained-unsaved, `NOT_SENT_OFFLINE`, `UNKNOWN`, late resolution, account switch and navigation/disposal.
6. A minimal AI-COACH-01 scope that keeps voice recognition, clinical policy, OQ-14 activation, OQ-18 generation, alert configuration and deployment separate.
7. A new explicit authorization response for the exact frozen scope. This document and the product decision are not that response.

After authorization, map each focused functional/E2E scenario to the relevant acceptance criterion and have only the designated functional-test/e2e agents author and execute tests. No tests, checks, builds, CI, migrations, rules changes or runtime actions were performed to prepare this document.
