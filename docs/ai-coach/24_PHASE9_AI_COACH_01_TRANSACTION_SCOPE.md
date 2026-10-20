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

## 3. Selected technical contract (documentary proposal; not implemented or accepted)

The correlated review `3e612e9f-1d41-4e78-8ee8-ff9a3886f431` returned **B — CODE NOT AUTHORIZED**, with 3 BLOCKER and 3 MAJOR findings. A subsequent complete adversarial review, request `d4e49bc9-5e5f-49d9-9ce1-dfa1b4929be3`, returned **MODIFY — 4 BLOCKER, 5 MAJOR, 0 MINOR; CODE NOT AUTHORIZED**. It judged the proposed direction materially improved but did not accept it as closing the earlier design blockers. The nine current findings and required evidence are recorded in `23_PHASE9_ACCEPTANCE_RECONCILIATION_2026-10-20.md` and `25_PHASE9_STATUS_AND_HANDOFF_2026-10-20.md`. The proposal below is not authorization or implementation/runtime evidence.

1. A Firebase-authenticated callable derives the UID from verified auth context, verifies ownership of the existing WorkoutSession, and validates session/exercise identity and eligibility. It never trusts a caller-supplied UID or arbitrary WorkoutSession snapshot.
2. Touch and any later voice adapter use the same typed server action. The callable uses a fresh Firestore transaction over `users/{uid}/workout_sessions/{sessionId}`. It writes the existing authoritative document; it adds no collection, workout lifecycle, or second source of truth.
3. The client creates a UUID `operationId` before first submission and, for `CompleteSet`, a distinct UUID `setId`. IDs are scoped to the authenticated UID and session. A retry reuses the same IDs and typed payload. The server is the sole canonicalizer: v1 validates a fixed versioned field set, normalizes it, hashes the canonical representation, and retains the v1 canonicalizer while v1 receipts exist. **OPEN BLOCKER B-01:** this document does not yet define canonical bytes, per-field normalization (including absent/null, numeric values, timestamps, correction targets and identity fields), complete per-operation schema/result, or worked replay/conflict examples. No client/server implementation may rely on the phrase “canonical representation” until those are frozen and reviewed.
4. The existing WorkoutSession document gains `aiCoachMutationV1: { schemaVersion: 1, epoch: integer, operations: { operationId: receipt } }`. Each receipt has operation ID, kind, canonicalization version, payload hash, state (`RESERVED` or `COMMITTED`), server timestamps, and compact result (session ID, exercise ID, optional set ID, committed revision). A `RESERVED` receipt also contains the validated typed payload needed to recover. After commit, remove that payload but retain the hash and result. A committed CompleteSet also stores its stable set ID in the set row.
5. The callable reserves the operation in the same WorkoutSession document, then applies it in a second transaction. The apply transaction reads current state and atomically applies only the targeted mutation and changes the receipt to `COMMITTED`. A reservation alone is not a completed set, saved result, or permission to start rest. Same ID/hash returns the recorded result; same ID/different hash returns `PAYLOAD_CONFLICT` with no mutation. A new user action, including a correction, gets a new operation ID.
6. Receipt retention is indefinite until the parent WorkoutSession is removed by the existing owner-scoped data-deletion path; there is no receipt TTL or automatic eviction. The ledger is capped at 256 operation IDs and 64 KiB serialized receipt data, whichever is reached first. A new operation at capacity returns `RECEIPT_CAPACITY_REACHED` before mutation, while existing IDs remain reconcilable. If the parent is deleted, every retry returns `SESSION_NOT_FOUND`; it never recreates the session. Capacity refusal is a visible limitation and does not authorize creating a replacement workout lifecycle.
7. Each active writer acquires a monotonically increasing mutation epoch in the existing session document. Every reserve/apply request carries its expected epoch; the server rejects stale epochs. On process restart or same-user return, recovery increments the epoch before reading the ledger. Firestore transaction serialization then yields one of two safe outcomes for a previous in-flight request: it committed before the fence, making its reservation/receipt visible, or it observes the new epoch and cannot commit. Recovery resumes a visible `RESERVED` entry using its stored ID/payload, returns the stored result for `COMMITTED`, and permits a new user-confirmed action only after the fence finds no pending entry. A new epoch invalidates other writer instances for that session; the existing other-device read-only contract remains controlling.
8. `AddEligibleExercise` checks the stable exercise ID against current state. `SetDifficulty` updates only the current exercise, never a stale widget snapshot. An intentional new set uses a new operation ID and set ID and appends; a replay uses the same pair and never appends twice. An explicit correction targets an existing set ID and uses a new operation ID.
9. Deleted-session, changed-eligibility, stale-epoch, account-switch, payload-conflict, capacity and server-denial outcomes are typed no-mutation results. Transaction exhaustion is not success. `SERVER_ACKNOWLEDGED` requires a confirmed committed receipt. `UNKNOWN` requires same-operation server reconciliation. `NOT_SENT_OFFLINE` is valid only before a reservation may have reached the server.
10. Target repetitions remain distinct from performed repetitions. Existing `SetCapture.reps` may originate from a pre-set “Target reps” field; neither legacy nor target values become actual-rep facts. A new `actualReps` value is recorded only when explicitly confirmed as performed; otherwise it remains null/unknown.

### Frozen UI outcome and disposal policy (design; not runtime-proven)

- Before reservation, `NOT_SENT_OFFLINE` keeps the unsaved capture and original operation ID only in the active UI. The user may retry that same ID when online or explicitly leave and discard it. No mutation, rest start, or saved claim occurs.
- Once reservation might have reached the server, the operation is submitted: show pending/unknown, do not start rest, and do not discard or replace it with a fresh ID. Navigation may continue after an explicit warning; the session ledger must be reconciled.
- After route disposal, no stale widget callback may report success. A response may update session state only when UID, session ID, operation ID, and epoch still match.
- Sign-out/account switch clears the previous account's in-memory capture and blocks access under the new UID. Never retry the prior account's ID under another UID. Same-user return first acquires an epoch and reconciles.
- After process death, the UI may be gone. Same-user recovery fences prior requests, then reads the ledger: committed returns the stored result; reserved resumes the same ID/payload; no entry after the fence permits a new user-confirmed action. A stale request cannot commit past the fence. No local offline operation queue or second collection is introduced.
- If recovery itself is unavailable, remain visibly blocked/unknown and retry recovery only; do not issue a new mutation ID.

### Old/new-client protection and rollout contract (design only)

The current `firestore.rules` owner wildcard at lines 84–126 does not exclude `workout_sessions` from its read/write predicates. Firestore evaluates matching grants permissively, so a nested deny alone would not override the wildcard. The selected enforceable strategy is:

1. Move both existing WorkoutSession touch writers to the authenticated server callable described above; keep owner-scoped reads.
2. Exclude `workout_sessions` from both broad wildcard predicates, add an explicit owner-scoped read rule, and deny client create/update/delete for that collection. The Admin SDK callable remains the only client-requested write path. `ScheduledSession` and `WorkoutLogEntry` remain outside this carve-out.
3. Previously installed full-document writers and queued offline `.set` writes are denied when they reach the server; the UI must show rejected/unsaved, never saved. The new client has no fallback to client `.set`. Rollback retains server-only writes; restoring wildcard access while receipts exist is prohibited.
4. Re-enable any legacy direct writer only after its exact write path is proven not to erase receipts or acknowledged sets and receives a separate review. No old-client version range is assumed.

This selects a design but does not prove a callable or rule change. GPT-PM explicitly marked Firestore rules/schema changes **NOT AUTHORIZED** in request `3e612e9f-1d41-4e78-8ee8-ff9a3886f431`; those changes need explicit authorization for the exact scope.

## 4. Source compatibility matrix

The paths below were inspected read-only in this checkout. Source evidence establishes current code shape, not runtime behavior or client-version coverage.

| Surface | Current source evidence | Candidate requirement | State before code GO |
|---|---|---|---|
| Repository write and acknowledgement | `mobile/lib/features/workouts/data/firestore_workout_session_repository.dart:61-70` uses `doc(session.id).set(session.toJson())` and a 4-second timeout whose handler returns normally. | Replace snapshot replacement for the three typed operations with transaction outcomes; do not interpret timeout return as server acknowledgement. | Contract described; code NOT AUTHORIZED. |
| Shared action | `mobile/lib/features/workouts/state/workout_session_providers.dart:89-110` accepts a whole `WorkoutSession`, suppresses only concurrent loading, then publishes data after `save`. | Both input modes call the same typed action and receive honest typed outcomes. `isLoading` is not replay protection. | Contract described; code NOT AUTHORIZED. |
| Touch writer: complete/log set | `mobile/lib/features/equipment/workout_player_page.dart:572-780` (`_MarkCompleteButton`) constructs a session from an earlier UI snapshot, replaces an exercise's set list with zero/one capture, then starts rest after provider success. | Preserve touch validation, session/day identity and ordering; append/correct against fresh transaction state. Do not claim rest starts after server persistence unless acknowledged. | Exact behavior mapped; migration and UI outcome changes NOT IMPLEMENTED. |
| Touch writer: add exercise | `mobile/lib/features/equipment/workout_player_page.dart:900-1023` (`_AddExerciseButton`) checks eligibility, collects capture/rating, appends to its snapshot, writes, then starts rest. | Preserve eligibility and rating semantics; merge against fresh state and preserve concurrent work. | Exact behavior mapped; migration NOT IMPLEMENTED. |
| Delayed difficulty | The rating path in `workout_player_page.dart:786-818` can submit a value based on an earlier entry snapshot. | Update only the current exercise in the transaction, not the whole stale snapshot. | Risk mapped; transaction NOT IMPLEMENTED. |
| Stored set model and provenance | `mobile/lib/features/workouts/data/set_capture.dart:8` has nullable `weightKg` and `reps`; the normal sheet labels pre-set reps “Target reps” (`set_capture_sheet.dart:154-185`). | Store stable `setId`; preserve legacy `reps` as unverified; new nullable `actualReps` is populated only by explicit confirmation. | Schema selected for review; code NOT AUTHORIZED. |
| Legacy/full-document writers | Current `firestore.rules` owner wildcard grants user collection writes and does not exclude `workout_sessions`; current repository uses full-document `.set`. | Server callable becomes the only client mutation path; wildcard carve-out denies legacy `.set`, while explicit owner reads remain. | Strategy selected; rule/callable implementation NOT AUTHORIZED or runtime-proven. |
| History projection | `mobile/lib/features/workouts/data/workout_session.dart:354-408` uses `_workingSet` and `asLogEntries()` to project one best set per exercise. | Preserve best-set selection and one-entry-per-exercise projection. Mark legacy reps unverified; actual-rep consumers use confirmed `actualReps` only. | Acceptance frozen; code NOT AUTHORIZED or runtime-proven. |
| Direct metrics | `mobile/lib/features/personalisation/data/volume_ledger.dart:96-133`, `mobile/lib/features/progress/data/progress_charts.dart:65-76,151-166`, and `mobile/lib/features/workouts/data/day_result.dart:86-129` consume stored sets directly. | Preserve historical set-entry counts; count each committed new set once. Rep-based metrics exclude null/legacy-unknown actual reps; corrections count one current row. | Acceptance frozen; code NOT AUTHORIZED; tests NOT RUN. |
| Exports | `mobile/lib/features/data_export/data_export_providers.dart:80-96,121-124` supplies projected mobile `workoutLogs`; `functions/src/account_export.ts:514-520,560-568,593-646` includes raw `workout_sessions` subject to caps and `truncated` markers. | Preserve projected mobile and raw server views, provenance, receipts, and explicit truncation. | Acceptance frozen; code NOT AUTHORIZED or runtime-proven. |
| Scheduled session writers | `workouts/state/scheduled_session_providers.dart:84-100` and `programmes/state/programme_providers.dart:389-403` write the separate `ScheduledSession` model. | Keep this transaction scope limited to `WorkoutSession`; do not imply programme/schedule persistence is included. | Explicitly OUT OF SCOPE. |
| UI lifecycle and account context | Current completion and add-exercise callbacks check `context.mounted` around asynchronous prompts; no approved durable offline queue exists. | Apply the frozen outcome/lifecycle rules above; session recovery is epoch-fenced and uses the existing server ledger. | Acceptance frozen; code NOT IMPLEMENTED or runtime-proven. |

### Frozen writer/reader/export outcome matrix (design; not runtime-proven)

| Record/action | Write rule | Raw WorkoutSession | History projection | Direct analytics | Export |
|---|---|---|---|---|---|
| Legacy set without identity/provenance | Preserve as-is; no backfill or invented actual value in this scope. | Existing `reps` remains unchanged and is interpreted as legacy/unknown. | Keep current best-set selection; tag projected reps as legacy/unverified and do not expose them as `actualReps`. | Preserve historical set-entry counts; exclude legacy `reps` from actual-rep calculations. | Raw server view retains original fields; projected mobile view keeps best-set shape and unknown provenance. |
| New completed set | Append a unique `setId`; only committed `CompleteSet` is a stored performed-set entry. New intentional set = new operation/set IDs. | Persist input load, nullable `actualReps`, separate optional target reps, set ID and receipt. | Continue one best-set row per exercise with existing selection semantics; expose only confirmed reps as actual. | Count each committed set once. Rep metrics use confirmed `actualReps`; null remains unknown. | Raw server view retains all sets/receipts; mobile view remains best-set only. |
| Repeated request | Same ID/hash is a no-op with the stored result; different hash conflicts. An explicitly confirmed new set uses new IDs and appends. | Replay adds no row. | No duplicate projection effect. | No duplicate set count. | Same raw/projected outcome after replay. |
| Corrected set | Target existing `setId` with a new operation ID; replace that row's current values and retain operation receipts. | One current row; old and correction receipts remain until parent deletion. | Recompute best-set projection from current rows; do not emit both values as sets. | Count once and use the corrected confirmed values. | Raw view shows corrected row plus receipts; projected view shows the recomputed best set. |
| Add exercise / difficulty | Apply against current transaction state; stable exercise ID prevents duplicate exercises; difficulty targets the current exercise. | One exercise identity and current difficulty; keep receipt per operation. | Preserve current per-exercise projection. | Existing consumers see one current exercise state. | Continue existing raw/projected paths; add no export path. |
| Truncated server export | No write effect. | N/A | N/A | N/A | Keep the explicit `truncated` marker; never claim a capped raw section is complete. |

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

GPT-PM's correlated response specifically withheld code GO pending the following. The first documentary proposals are now present in §§2–5, but none is accepted by GPT-PM or implementation/runtime evidence:

1. AICR-074 and legacy touch impact: operation mapping is documented in §2 and AICR-074/AC-8–AC-11; code review must prove unaffected offline paths remain.
2. Transaction/replay: schema, canonical payload hash, conflict behavior, retention/capacity and same-ID reconciliation are specified in §3; focused review and later implementation evidence remain required.
3. Mixed clients: an enforceable server-callable plus rules carve-out and rollback strategy is selected in §3; actual rules/callable changes are separately gated and must be reviewed/exercised.
4. Writer/reader/export: both touch writers, delayed difficulty, repeated/corrected sets, best-set projection, direct metrics and two export views are covered in §§4–5; runtime conformance remains unverified.
5. UI lifecycle: unsent, reserved, UNKNOWN, late result, navigation, process death and account switch are specified in §3; code/test evidence remains outstanding.
6. Scope isolation: voice recognition, clinical policy, OQ-14 activation, OQ-18 generation, alert configuration and deployment stay excluded.
7. A new explicit authorization response is still required for the exact code scope, and a separate authorization must cover the callable/rules changes. This document and either earlier PM decision are not those authorizations.

After authorization, map each focused functional/E2E scenario to the relevant acceptance criterion and have only the designated functional-test/e2e agents author and execute tests. No tests, checks, builds, CI, migrations, rules changes or runtime actions were performed to prepare this document.
