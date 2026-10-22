# Offline command protocol for CompleteSet, AddEligibleExercise and SetDifficulty

Version 1.0, 2026-10-22. Status: PROPOSED DESIGN, NOT IMPLEMENTED, no test has been run.

Purpose: close review findings B-01 and B-02 (`package-amendments/PACKAGE_RECONCILIATION_2026-10-22.md`) at the design level, so that the durable local queue decided in `docs/v1/LOCAL_QUEUE_DECISION.md` can be implemented without further decisions. Where this document and the rebaseline package (`04_CORE_TDD.md` sections 3 to 7, `05_DATA_MODEL.md`, ADR-CMD-02/03, `API_CONTRACTS.json`, `COMMAND_GOLDEN_VECTORS.json`) disagree, this document wins for the three queued commands, as the reconciliation folder already states for the amendments.

Claim labels used throughout:
- FACT: read from a cited file in this session.
- DECISION: a design choice made by this document (an engineer implements it as written).
- UNKNOWN: not verified; the text says what must be checked and by whom.

Package paths are relative to `D:\Temp\claude\d--Repo\c10b37ff-3506-44a4-9cd1-d2e82bb71961\scratchpad\fup_pkg\FitnessUp_v1_Rebaseline_2026-10-20\` (an external deliverable, not in this repository). Code paths are relative to `D:\Repo\Fitness_App\` (master as read on 2026-10-22).

---

## 1. Scope and non-goals

### 1.1 In scope
- DECISION: exactly three commands use this protocol: CompleteSet (modes APPEND and CORRECT), AddEligibleExercise, SetDifficulty. Touch and voice produce the same command through one local entry point (LOCAL_QUEUE_DECISION criterion 10).
- DECISION: the protocol covers the client queue, the server apply transaction, receipt and fence storage, ordering, conflicts, writer epoch and the legacy-writer migration states.

### 1.2 Non-goals
- FACT: StartSet is not queued and creates no queue entry, no receipt and no completed-set fact (`docs/v1/VOICE_READY_PROMPT_DECISION.md`, section "StartSet is not CompleteSet"; acceptance FU-AC-101 in `package-amendments/ACCEPTANCE_AMENDMENTS.csv`). This document never mentions StartSet as a command.
- DECISION: not covered here, each needs its own contract: sign-out sheet, account deletion, export and backup UI (criteria 11 to 14; only the protocol hooks they need are named in 3.6), multi-writer collaboration (ADR-CMD-04 stays one writer), set deletion, ScheduledSession and programme writers, AI intent parsing.
- DECISION: no new online admission step. The package `prepareWorkoutCommand`, `applyWorkoutCommand`, `resolveAndCloseCommand` endpoints, the admission token, the 2-minute `admissibleUntil`, and "birth epoch" closure are withdrawn for these three commands (see 2.4 and 5.1).

### 1.3 Code facts that shape the design
- FACT: today a whole `WorkoutSession` document is written with `doc(id).set(session.toJson())` and a 4 second timeout whose `onTimeout` handler returns normally, so a missing server acknowledgement is hidden (`mobile/lib/features/workouts/data/firestore_workout_session_repository.dart`, lines 61 to 71).
- FACT: a session stores `sets` as a list of `{weightKg, reps}` with no set id, no revision and no writer field (`mobile/lib/features/workouts/data/workout_session.dart`, lines 52 and 70 to 81).
- FACT: the player writes at most one set per exercise per session and a repeat tap overwrites it (`mobile/lib/features/equipment/workout_player_page.dart`, lines 632 to 636). A day session id is deterministic, `day_{dayId}` (same file, lines 81 and 664 to 666); a free session id is `{microsecondsSinceEpoch}_{sessionKey}` and is created on the client (same file, line 666).
- FACT: rest starts only after the save future completes and the error check passes (`workout_player_page.dart`, lines 730 to 736 and 973 to 977). Under this protocol "persist" means the local durable commit of 3.3.
- FACT: `firestore.rules` lines 61 to 83 give the owner read and write on every `users/{uid}/{coll}/...` collection except a named carve-out list; `workout_sessions` is not in the list, so the owner can write it directly today.
- FACT: a search of `functions/src` (excluding test folders) for "workout" found only `abuse_guard.ts`, `account_export.ts`, `scaling.ts`, `video_urls.ts`; no workout command callable was found. Their content was not inspected beyond that. UNKNOWN: whether any of them writes `workout_sessions`.
- UNKNOWN: the local storage engine available in the Flutter app (needs a transactional store with unique indexes); the deployed Cloud Functions runtime; whether Firestore TTL policies are enabled in the project.

---

## 2. Identity model

### 2.1 Identifiers
| Name | Definition | Created by | Mutable |
|---|---|---|---|
| `operationId` | 22 characters, base64url of 16 CSPRNG bytes (128 bit). Matches the package id pattern `^[A-Za-z0-9_-]{1,128}$` | client, inside the atomic acceptance commit (3.3), before any network call | never |
| `uid` | Firebase Auth UID active at acceptance | client reads the signed-in UID; the server trusts only the authenticated UID | never |
| `sessionId` | existing scheme: `day_{dayId}` or the client-generated free id | client (FACT, 1.3) | never |
| `sessionGeneration` | integer, 1 for a new session; after an observed server deletion, tombstone generation plus 1 | client, copied from its last synced view | never (part of the hash) |
| `logicalSetId` (CompleteSet only) | `{sessionId}:{exerciseId}:{setIndex}`, `setIndex` integer 1..1000, allocated by the client as the next free index for that exercise in its merged view (synced state plus queue) | client | never |
| `seq` | integer, strictly increasing per (uid, sessionId) in acceptance order, starting at 1 | client, in the acceptance commit | never |
| `dependsOn` | sorted list of at most 2 `operationId`: the session-creating operation and the AddEligibleExercise operation for this exercise, only while those are not yet `synced` | client | never |
| `setId` in the body | derived: `set_` plus `setIndex` zero-padded to 4 digits (keeps the shape of `COMMAND_GOLDEN_VECTORS.json` `set_0001`) | client | never |

- DECISION: the package `clientIntentId` and the server-minted `commandId` collapse into the single client-generated `operationId`. A retry, a restart and a reconnect reuse the same bytes (LOCAL_QUEUE_DECISION criterion 4).
- DECISION: a user-initiated re-submission after a terminal conflict (7.3) is a new intent with a new `operationId` and a `supersedes` link kept locally. This does not violate criterion 4: criterion 4 forbids changing the id on transport retry, not creating a new intent after the user explicitly resubmits.

### 2.2 Canonical payload and hash (hashVersion 2)
- FACT: version 1 hashes `expectedRevision`, `writerEpoch` and `sessionGeneration` inside the payload (`registers/COMMAND_GOLDEN_VECTORS.json`, payload objects; `registers/API_CONTRACTS.json` schemas `CompleteSet`, `SetDifficulty` require them).
- DECISION: an offline command cannot know the server revision at execution time and must not change its bytes when the writer epoch is renewed, so version 2 removes `expectedRevision` and `writerEpoch` from the hashed payload. `writerEpoch` moves to the unhashed envelope (2.3). Version 1 vectors stay valid for the withdrawn online endpoints only; new version 2 golden vectors must be generated and checked in Dart and on the server before implementation (NOT_RUN).
- DECISION: hashed canonical object (keys in recursive lexicographic order, UTF-8, no whitespace, integers only, explicit `null` for nullable fixed fields, unknown keys rejected, same rules as `API_CONTRACTS.json` `x-canonicalization`):

```
{ protocolVersion: 2, hashVersion: 2,
  operationId, uid, sessionId, sessionGeneration, seq,
  dependsOn: [operationId...],
  exerciseId, operation,
  logicalSetId: string | null,
  sessionInit: { title, dayId | null, startedAtClientMs } | null,
  body: <operation body of API_CONTRACTS.json, see below> }
```
- DECISION: `body` for CompleteSet is the package body (`mode`, `setId`, `performedConfirmed`, `actualReps`, `actualRepsConfirmed`, `targetReps`, `loadGrams`, `source`) plus `performedAtClientMs` (integer, ms since epoch, informational, see 9). AddEligibleExercise and SetDifficulty bodies are unchanged from the package.
- DECISION: `sessionInit` is non-null only on the operation that is first accepted for a session the client has not seen on the server; it carries what `WorkoutSession` requires on creation (FACT: `title` and `startedAt` are required, `workout_session.dart` lines 193 to 202).
- DECISION: `payloadHash` = lowercase hex SHA-256 of the canonical bytes. The client stores the canonical bytes verbatim in the queue record and always sends those bytes; it never re-serializes.
- DECISION: binding to identity: the hash covers `operationId`, `uid` and `sessionId`, so a payload cannot be re-labelled to another id, account or session without changing the hash.

### 2.3 Envelope (sent with the payload, not hashed)
`{ payloadBytes, payloadHash, writerEpochClaim, deviceInstallId, clientBuild }` - DECISION. `writerEpochClaim` may change between retries (after an explicit takeover, 8.5) without changing identity. The server recomputes the hash from `payloadBytes`; it never trusts a client-supplied hash, role, UID or time.

### 2.4 What the server mints (answer to B-01)
- DECISION: the server mints no identity before the effect. It mints only: `serverTime`, `revisionBefore`/`revisionAfter`, and the receipt, whose id equals `operationId`. Nothing in this list gates local acceptance, so the package conflict (an online `prepare` that mints id, token and 2-minute expiry before the effect) no longer exists for these commands.
- DECISION: what the package token bound (UID, device session, account epoch, session writer epoch, session generation, payload digest) is instead checked inside the apply transaction at apply time (4.2 steps 2 to 6). The authority is the authenticated caller plus current server state, not a pre-issued token. This is not weaker than today: FACT, the owner can already write `workout_sessions` directly (`firestore.rules` lines 61 to 83); the new path adds validation.
- DECISION: there is no server-side maximum command age. A command accepted 30 days ago (LOCAL_QUEUE_DECISION criterion 3) is applied if the session state allows it. Age never makes a command inadmissible; only a fence hit (5.2) or a session rule (7) can refuse it.

---

## 3. Local queue

### 3.1 Record
One record per command, keyed by `(uid, operationId)`. DECISION fields:

| Field | Meaning |
|---|---|
| `uid`, `operationId`, `sessionId`, `exerciseId`, `operation` | identity, immutable |
| `canonicalBytes`, `payloadHash`, `hashVersion` | immutable |
| `seq`, `dependsOn`, `logicalSetId` | immutable |
| `state` | one of the five states in 3.2 |
| `maybeSent` | boolean; set to true in the same commit that moves the record to `sending`, never reset |
| `attempts`, `lastAttemptLocalMs`, `lastResultCode` | diagnostics |
| `writerEpochClaim`, `deviceInstallId` | envelope, `writerEpochClaim` mutable |
| `conflictKind`, `conflictTerminal` | set when `state = conflicted` (section 7) |
| `ackSummary` | revisionAfter, serverTime, detailExpired flag; set when `synced` |
| `supersedes` | operationId of a terminal-conflicted record this one replaces, or null |
| `acceptedAtLocalWallMs`, `acceptedAtMonotonic` | informational only |

Local unique indexes (DECISION), enforced by the store, not by UI code: `(uid, operationId)`; `(uid, sessionId, seq)`; `(uid, logicalSetId)` for `operation = CompleteSet` and `mode = APPEND` and `state` not in (`discarded`). The third index makes a double tap on the same logical set a no-op or a CORRECT, never a second APPEND (FU-AC-096 duplicate tap).

### 3.2 States
| State | Meaning | Counts toward the 500 cap |
|---|---|---|
| `accepted` | committed locally, not yet in flight | yes |
| `sending` | a send attempt is in flight or may have been in flight at process death | yes |
| `synced` | server answered COMMITTED or ALREADY_COMMITTED (also detail-expired) | no |
| `conflicted` | server refused it (terminal) or a non-terminal hold needs user action (section 7) | yes |
| `discarded` | user explicitly discarded after export, or confirmed discard naming the count | no |

Transitions (DECISION; any other transition is a bug):
- (none) -> `accepted`: only by the acceptance commit (3.3).
- `accepted` -> `sending`: one local commit that sets `maybeSent = true` and increments `attempts`, then the network call.
- `sending` -> `synced` | `conflicted` (terminal or hold) | `accepted` (retryable network or server error, same bytes).
- on process start, every `sending` record is treated as `accepted` with `maybeSent = true` and is re-sent with the same bytes (never a new id).
- `conflicted` (non-terminal hold) -> `accepted` after the user action named in 7.2 (same `operationId`).
- `conflicted` (terminal) -> `discarded` only by the export-then-discard or confirmed-discard flow; a "retry" creates a new record (2.1).
- `synced` records are kept for 7 days after the acknowledgement (DECISION, display and support only) and then pruned. This is not eviction of an unacknowledged command, so criterion 3 is not touched.
- `accepted`, `sending` and `conflicted` are never removed by age or size (criterion 3).

### 3.3 Atomic durable acceptance (criterion 2)
DECISION: acceptance is one transaction of the local store that does all of the following or nothing:
1. read the count of records in `accepted`, `sending`, `conflicted` for the UID; refuse with a visible message if it is 500 (criterion 3), show the warning at 400, and show the age warning when the oldest such record is 25 days old;
2. allocate `seq` for (uid, sessionId) and, for CompleteSet, check the `logicalSetId` index;
3. generate `operationId`, build and store the canonical bytes and the hash;
4. insert the record in state `accepted`.
Only after the transaction reports commit may the UI show "pending sync" or start the rest timer. A failed or interrupted transaction leaves nothing and the UI reports "not saved". No network call happens before the commit. UNKNOWN: the storage engine and its durability setting (fsync on commit) must be chosen and shown by the fault-injection test of FU-AC-093; "kill the process" is the test, not an assumption.

### 3.4 Sender
- DECISION: one sender per UID. Per session, strictly one operation in flight, in `seq` order (head-of-line). Different sessions may run in parallel. A batch call carries up to 25 consecutive operations of one session in order (4.5).
- DECISION: an operation whose `dependsOn` contains a record that is `conflicted` or not yet `synced` is not sent; if the dependency is terminal-conflicted the dependent is set to `conflicted` (kind `DEPENDENCY_REJECTED`, terminal, locally decided and re-confirmed by the server on send only if the user forces a send).
- DECISION: backoff on retryable errors is exponential from 2 seconds to 5 minutes, with jitter, reset on connectivity change; it never changes the bytes.

### 3.5 Honest status (criterion 8)
DECISION: UI states map as: `accepted`/`sending` = "saved on this device, waiting to sync"; `synced` = "synced"; `conflicted` = "could not sync". "Synced" is shown only from a server answer of 4.4 classes C1 to C3. Local pending data is excluded from history, progress, coach replies and exports as canonical fact until `synced` (FU-AC-099), but is included in the device-only part of the export snapshot (criterion 14).

### 3.6 Hooks for lifecycle criteria (11 to 14), protocol part only
- DECISION: the queue store is keyed by UID; the sender takes a per-UID send lease before each attempt and releases it after the answer or cancellation. Sign-out and account deletion must acquire the lease exclusively (waiting for or cancelling the in-flight call) before releasing the UID binding or deleting data. A send never starts without the lease.
- DECISION: the queue file is excluded from OS backup and device-to-device restore (see 9, device restore).
- DECISION: on the server, an apply for a UID in deletion is refused (8.6), so a send racing with deletion cannot recreate data.

---

## 4. Server apply

### 4.1 Interface
DECISION (names are proposals): callable `submitWorkoutCommands({ sessionId, items: Envelope[<=25] })` returning one result per item in order; read-only callable `getWorkoutCommandOutcomes({ operationIds[<=50] })` for status after restart (reads the fence and receipts of the caller, applies nothing). Authentication is required on both; the UID is the authenticated UID only.

### 4.2 One Firestore transaction per item
All reads first, then all writes, in one `runTransaction` (the package already requires one atomic effect, `04_CORE_TDD.md` section 4). Steps:

1. Parse and validate: schema for hashVersion 2, ASCII ids, integer ranges (reuse the package proposal limits 1000 reps and 1000000 grams, FACT in `API_CONTRACTS.json` `x-boundaries.existing_domain`, labelled there as new schema limits needing domain review). Recompute `payloadHash`. Reject `payload.uid != auth.uid` with `UID_MISMATCH` before reading any receipt or fence (nothing is exposed). Invalid shape -> non-terminal `INVALID_PAYLOAD` (nothing recorded).
2. Read `AccountCommandPolicy` (`users/{uid}/workout_command_policy/current`, package name, FACT in `05_DATA_MODEL.md` section 2). Absent, or account deleting, or sending paused, or the device not drain-acknowledged in state `DRAIN`: non-terminal `MIGRATION_HOLD` / `ACCOUNT_DELETING` (nothing recorded).
3. Read the fence shard for the item (5.2). If an entry exists for the operation digest, go to the idempotency table 4.3 and return; no effect.
4. Read device/account revocation state (UNKNOWN: the existing server representation of device sessions; the package assumes one, `04_CORE_TDD.md` section 6). Revoked: non-terminal `AUTH_REVOKED`.
5. Read `workout_mutation_controls/{sessionId}` (writerEpoch, sessionGeneration), the session tombstone `workout_session_tombstones/{sessionId}` (8.4 and 7), the session document, and the fence shards of each `dependsOn` id.
6. Decide, in this order: tombstone with `deletedGeneration >= payload.sessionGeneration` -> terminal `SESSION_DELETED`; `writerEpochClaim != controls.writerEpoch` -> non-terminal `NOT_WRITER`; a `dependsOn` entry absent from the fence -> non-terminal `DEPENDENCY_PENDING`; a `dependsOn` entry with code `R` -> terminal `DEPENDENCY_REJECTED`; operation-specific preconditions (7.1) -> terminal reasons.
7. Apply the one targeted mutation to the session document (create it if `sessionInit` is present and the document is absent and no blocking tombstone; convert a legacy-shaped document first, 8.3), increment `revision`, set `protocolVersion = 2`.
8. Write the fence entry (code `C` or, for terminal refusals, `R`), the detail receipt, and the outbox record if the package requires one for this operation (`04_CORE_TDD.md` section 4). Steps 7 and 8 commit together or not at all.

DECISION: non-terminal results write nothing (no receipt, no fence entry). Terminal refusals write a fence entry with code `R` and a detail receipt with the reason, so a replay returns the same refusal even if preconditions later change (this keeps FU-AC-059 semantics).

### 4.3 Idempotency table
Key: the operation digest (5.2) within the caller's UID scope.

| # | Situation | Result | Effect | Recorded |
|---|---|---|---|---|
| I1 | no fence entry, valid, all rules pass | `COMMITTED` with receipt | one set / exercise / difficulty change | fence `C` + receipt |
| I2 | fence `C`, hash matches, receipt detail present | `ALREADY_COMMITTED` with the original receipt | none | none |
| I3 | fence `C`, hash prefix matches, detail expired | `ALREADY_COMMITTED_DETAIL_EXPIRED` (revision, time, reason unavailable) | none | none |
| I4 | fence `R`, hash matches | `ALREADY_REJECTED` (reason code if detail present, else `reason: UNAVAILABLE`) | none | none |
| I5 | same `operationId`, different payload (hash differs from receipt, or prefix differs from fence) | `ID_PAYLOAD_MISMATCH`, no receipt contents exposed | none | none |
| I6 | same `operationId` presented by another authenticated UID with its original payload (`payload.uid` differs from `auth.uid`) | `UID_MISMATCH`, nothing read, nothing exposed | none | none |
| I7 | same `operationId`, session digest in the fence differs from `payload.sessionId` | `ID_SESSION_MISMATCH`, no receipt contents exposed | none | none |
| I8 | different `operationId`, same `logicalSetId`, mode APPEND, slot already holds a set (any origin) | terminal `DUPLICATE_LOGICAL_SET`; the existing set is untouched | none | fence `R` + receipt |
| I9 | different `operationId`, CORRECT of an existing `setId` | applies as its own operation (a correction is not a second completion) | replaces values of that one set | fence `C` + receipt |
| I10 | different `operationId`, same payload otherwise (two devices, same logical set) | same as I8 | none | fence `R` |

I6 note (DECISION, interpretation of FU-AC-095): ids are unique inside one UID scope. Presenting A's envelope under B's authentication fails on `payload.uid` (I6). If a client rewrites the payload to B's UID, that is a command of B for B's own data and is judged only by B's state; it cannot reach A's data. If FU-AC-095 intends a stronger global rule, a global id registry is needed; this document does not add one (see 11).

### 4.4 Result classes returned to the client
| Class | Codes | Client state |
|---|---|---|
| C1 applied | `COMMITTED` | `synced` |
| C2 already applied | `ALREADY_COMMITTED`, `ALREADY_COMMITTED_DETAIL_EXPIRED` | `synced` (ack summary notes detail expired) |
| C3 already refused | `ALREADY_REJECTED`, terminal codes of 4.2 step 6 | `conflicted`, terminal |
| C4 identity violation | `ID_PAYLOAD_MISMATCH`, `UID_MISMATCH`, `ID_SESSION_MISMATCH` | `conflicted`, terminal-local (nothing recorded server-side; kept for export; indicates a client bug or tampering) |
| C5 hold | `NOT_WRITER`, `DEPENDENCY_PENDING`, `MIGRATION_HOLD`, `AUTH_REVOKED`, `ACCOUNT_DELETING` | `conflicted` non-terminal or back to `accepted` per 7.2 |
| C6 retryable | transport error, `UNAVAILABLE`, `INVALID_PAYLOAD` is not retryable | `accepted` with backoff (or `conflicted` for INVALID_PAYLOAD) |

### 4.5 Batch semantics
DECISION: items of one call are processed in order, each in its own transaction. Processing continues after a terminal result (C1 to C4) and stops at the first C5 or C6 result; the remaining items are returned as `NOT_ATTEMPTED`.

---

## 5. Receipt retention and the replay fence

### 5.1 Why the package model cannot hold with a queue (B-02)
- FACT: the package makes admission last 2 minutes and requires, before the 90-day detail TTL, that every birth epoch is durably closed and replay "permanently inadmissible" (`04_CORE_TDD.md` sections 3 and 4; `05_DATA_MODEL.md` retention row). A command first sent after more than 2 minutes, or after the epoch close, is inadmissible there.
- FACT: the queue forbids eviction by age (LOCAL_QUEUE_DECISION criterion 3: the 30-day mark is a warning, not a deadline). A command accepted offline and unsent for 100 days must still be applied once.
- DECISION: so the fence must distinguish "never seen by the server" (apply) from "seen, applied or refused" (never apply again). A time-based or epoch-based inadmissibility cannot make this distinction and is dropped. Instead the fence records every operation the server has ever resolved, permanently, written in the same transaction as the effect.
- DECISION (invariant F1): a fence entry exists for an `operationId` if and only if the apply transaction for it committed (as `C` or `R`). Because the entry and the effect are one transaction, a fence miss proves "this operation was never applied", for any command age.

### 5.2 The compact fence (kept for the life of the account)
- DECISION: `users/{uid}/workout_command_fence/{shard}` with 256 documents at most, `shard` = two lowercase hex characters = first byte of `D = SHA-256("op1|" + operationId)`. Each document has one map field `e`: key = base64url of the first 16 bytes of `D` (22 characters), value = one string of 23 characters: 1 code character (`C` or `R`), 11 characters base64url of the first 8 bytes of `SHA-256("s1|" + sessionId)`, 11 characters base64url of the first 8 bytes of the payload hash.
- DECISION: size bound. One entry is about 45 bytes of payload (about 55 with field overhead). A user who logs 15 sets a day for 10 years makes about 55,000 entries, about 3 MB over 256 documents (about 12 KB each). The hard guard is 12,000 entries per shard document (about 700 KB, below the 1 MiB document limit): at the limit the server refuses new operations in that shard with non-terminal `FENCE_SHARD_FULL` (fails closed, never evicts). 256 shards times 12,000 is about 3.07 million operations per user, far above any realistic life.
- DECISION: relation to the queue cap. The queue holds at most 500 unacknowledged commands (criterion 3); the fence has no count-based eviction at all, so it holds at least the 500 plus every earlier operation. This satisfies criterion 7 ("at least as many receipts per user as the queue can hold plus the retention window"). The 256-receipt proposal of the AI-Coach design is not adopted anywhere in this protocol.
- DECISION: the map field `e` must be exempt from Firestore indexing (single-field index exemption); otherwise the per-document index entry limit would cap a shard long before 1 MiB. UNKNOWN: confirm in the emulator and in a staging project that the exemption works and that a write to the map key is atomic with the session write in one transaction.
- DECISION: the fence is deleted only with the account (the deletion framework, 8.6). It has no TTL.
- DECISION (collision safety): a 128-bit key and 64-bit hash prefix make an accidental collision negligible. The failure direction is safe: a false fence hit returns "already applied", which never applies an effect.

### 5.3 Detail receipt (cleanup only, not the correctness boundary)
- DECISION: `users/{uid}/workout_command_receipts/{operationId}` holds: `payloadHash` (full), `status` (`COMMITTED` or `REJECTED`), `reasonCode`, `sessionId`, `exerciseId`, `operation`, `logicalSetId`, `seq`, `revisionBefore`, `revisionAfter`, `serverTime`, `performedAtClientMs`, `clockSuspect`, and `expireAt = serverTime + 90 days`. It is deleted by a Firestore TTL policy (UNKNOWN: TTL policy availability; a scheduled sweep is the fallback). Package retention of 90 days is kept as the proposal (FACT: `05_DATA_MODEL.md` retention row); the closure precondition for deleting it is replaced by invariant F1, because the fence already outlives it.
- DECISION: the receipt is owner-readable only through the callable; collections `workout_command_fence`, `workout_command_receipts`, `workout_mutation_controls`, `workout_session_tombstones`, `workout_command_policy` are carved out of the wildcard rule (FACT that carve-outs are by name in `firestore.rules` lines 61 to 83) with `allow read, write: if false` for clients.

### 5.4 What is answered for an expired detail
- DECISION: with the fence the historical outcome is known in coarse form. Fence `C` with no receipt -> `ALREADY_COMMITTED_DETAIL_EXPIRED` (I3). Fence `R` with no receipt -> `ALREADY_REJECTED` with `reason: UNAVAILABLE` (I4). Neither re-applies. The client treats I3 as `synced`.
- DECISION: the package status `OUTCOME_EXPIRED` (FACT: `04_CORE_TDD.md` section 10 FC-01 and `API_CONTRACTS.json` `ExpiredHistoricalOutcome`) is kept only for the case where the server has no fence entry and cannot prove a miss means "never applied": operations accepted before this protocol existed, or after a restore of fence data that is older than the session data (not expected inside one Firestore database, since both are in the same database). In that case the server returns `OUTCOME_UNKNOWN_REPLAY_CLOSED`, never applies, and the client shows current canonical history and keeps the record `conflicted` terminal for export. UNKNOWN: whether a point-in-time restore of only some collections is ever performed; the runbook must forbid partial restores of these collections.
- This closes B-02 for the stated case: an acked-but-lost command replayed after 90 days hits the fence (I3), so no set is duplicated; a command unsent for 100 days misses the fence and is applied exactly once; a replay fence never claims an outcome it does not hold.

### 5.5 Session tombstones (same retention class)
DECISION: `users/{uid}/workout_session_tombstones/{sessionId}` = `{deletedGeneration, deletedAtServer}`, written by the session deletion operation (8.4), kept for the life of the account, no workout payload. Size: one tiny document per deleted session. It is what prevents a late command from recreating a deleted session (criterion 9).

---

## 6. Ordering and dependencies per session

- DECISION: `seq` is the delivery and display order inside a session. The server does not require `seq` to be contiguous (a locally discarded record leaves a gap and must not stall the session) and does not require `seq` order across independent commands; it records `seq` in the receipt and stores `maxSeqSeen` in `workout_mutation_controls/{sessionId}` for diagnostics.
- DECISION: correctness comes from explicit `dependsOn` plus identity rules, not from contiguity:
  - the first operation for a session carries `sessionInit`; every later operation of that session carries it in `dependsOn` until the creating operation is `synced`;
  - CompleteSet or SetDifficulty on an exercise added by a not-yet-synced AddEligibleExercise carries that operation in `dependsOn`;
  - a CORRECT carries the APPEND of the same `logicalSetId` in `dependsOn` while that APPEND is not `synced`.
- DECISION: canonical order of sets inside an exercise is by `setIndex`, never by arrival order, so reordered delivery of independent CompleteSet commands yields the same document (FU-AC-097).
- DECISION: server behaviour: a missing dependency fence entry gives non-terminal `DEPENDENCY_PENDING` (the client holds and retries in order); a dependency with fence `R` gives terminal `DEPENDENCY_REJECTED` (criterion 6: held as "could not sync", not applied).
- DECISION: SetDifficulty has no logical-slot uniqueness; the last applied command wins, and head-of-line delivery per session makes apply order equal acceptance order for one device.
- DECISION: to recover a chain after a terminal predecessor conflict the user resubmits the predecessor and its held dependents as new operations in one action; the client creates new ids, new `seq` and new `dependsOn` links and keeps `supersedes` links to the old records.

---

## 7. Conflict taxonomy and client behaviour

### 7.1 Server conditions
| Code | Condition | Terminal on server | Applies when |
|---|---|---|---|
| `SESSION_DELETED` | tombstone generation >= claimed generation (or session absent, init op is `C` in the fence, no `sessionInit`) | yes (fence `R`) | any operation |
| `SESSION_CLOSED` | session `status = abandoned` | yes | any operation. FACT: statuses are `pending`, `completed`, `abandoned` (`workout_session.dart` line 11). DECISION: `completed` is not terminal because the player keeps appending to a completed session (`workout_player_page.dart` lines 664 to 686 and 948 to 959) |
| `EXERCISE_NOT_IN_SESSION` | CompleteSet/SetDifficulty on an exercise not in the document and no satisfied `dependsOn` add | yes | CompleteSet, SetDifficulty |
| `EXERCISE_ALREADY_IN_SESSION` | AddEligibleExercise for an exercise already present, with different content | yes | AddEligibleExercise. DECISION: identical re-add is I2-like only through the same `operationId`; a different id for an existing exercise is refused |
| `DUPLICATE_LOGICAL_SET` | I8 / I10 | yes | CompleteSet APPEND |
| `SET_NOT_FOUND` | CORRECT of a `setId` not present | yes | CompleteSet CORRECT |
| `DEPENDENCY_REJECTED` | a dependency has fence `R` | yes | any |
| `NOT_WRITER` | `writerEpochClaim` differs from current | no | any |
| `DEPENDENCY_PENDING` | a dependency not yet in the fence | no | any |
| `MIGRATION_HOLD` | policy absent, paused, device not drained | no | any |
| `AUTH_REVOKED`, `ACCOUNT_DELETING` | revocation / deletion in progress | no | any |
| `FENCE_SHARD_FULL`, `SESSION_COMMAND_LIMIT` | capacity guards (session limit 2,000 resolved operations, DECISION) | no | any |
| C4 codes of 4.4 | identity violations | no (nothing recorded) | any |

### 7.2 Client behaviour
| Condition | Client state and message | User actions |
|---|---|---|
| any terminal code | `conflicted`, terminal, "could not sync", data kept visible | export, discard (confirmation), resubmit as a new operation (2.1) where the cause can change; never auto-retry |
| `SESSION_DELETED` | same; the client must never recreate the session. A new session needs the next generation, which the client learns only from a synced view | export or discard only (resubmit is not offered) |
| `NOT_WRITER` | `conflicted`, non-terminal, "another device is the writer" | "take over and sync" (calls `takeOverWorkoutWriter`, updates `writerEpochClaim`, state back to `accepted`, same id), or export or discard |
| `DEPENDENCY_PENDING` | stays `accepted`, not shown as an error until it persists for 10 minutes while the dependency is `synced` locally | none |
| `MIGRATION_HOLD`, `AUTH_REVOKED` | stays `accepted` or `conflicted` non-terminal with an explanation | wait, sign in again, export |
| C4 identity violation | `conflicted`, "internal error, data kept" | export; report |
| `ALREADY_COMMITTED_DETAIL_EXPIRED` | `synced` | none |
| `OUTCOME_UNKNOWN_REPLAY_CLOSED` | `conflicted` terminal with a notice that the old confirmation is no longer available and current history is shown separately | export, discard |

### 7.3 Terminal rule
DECISION: every refusal caused by data state is terminal and recorded (fence `R`), and a replay returns the same refusal even if the state later changes. Refusals caused by who is asking or when (writer, migration, auth, dependency pending) are non-terminal and record nothing. This keeps every outcome of a given `operationId` unique over time.

---

## 8. Writer epoch and legacy-writer migration

### 8.1 Writer epoch with a queue
- FACT: ADR-CMD-04 keeps one active writer per workout; an explicit takeover increments a session writer epoch that the commit transaction reads (`04_CORE_TDD.md` section 5; `15_DECISIONS_AND_RISKS.md` ADR-CMD-04).
- DECISION: the epoch lives in `workout_mutation_controls/{sessionId}` (package name). It is checked at apply time against `writerEpochClaim` (4.2 step 6). A device that was writer at acceptance and lost the role while offline gets `NOT_WRITER`; its queued commands are not lost and not applied; the user chooses takeover (then the same ids are sent with the new claim) or export (FU-AC-102/103 interplay: UID binding is separate from writer role).
- DECISION: creating a session through `sessionInit` creates its controls document with `writerEpoch = 1` and the creating device as writer. A command for an existing legacy session (8.3) gets `writerEpoch = 1` on conversion and the first claimant wins.

### 8.2 Migration states
AccountCommandPolicy (`users/{uid}/workout_command_policy/current`, server-only) holds `migrationState`, `migrationEpoch`, `drainedDevices` (set of `deviceInstallId`, at most 20), `sendingPaused` (boolean). DECISION: exact states:

| State | Who may write `workout_sessions` | Typed commands | Entered by |
|---|---|---|---|
| `LEGACY_OPEN` (also: policy document absent) | client whole-document `.set` as today | refused `MIGRATION_HOLD`; the app queue feature flag is off for the account, so the old code path runs | default |
| `DRAIN` | client `.set` only on documents with no `protocolVersion` (or lower than 2) and only for ids not in tombstones; never on a document that has `protocolVersion >= 2` | accepted only from a device present in `drainedDevices` | server cohort enrollment (operator action) |
| `SERVER_ONLY` | nobody from the client (create, update and delete denied for every `workout_sessions` id, including absent and newly invented ids) | accepted from drained devices; after the cutover also from any new-protocol device | server, when the rule in 8.5 is met |

- DECISION: transitions are forward-only: `LEGACY_OPEN` -> `DRAIN` -> `SERVER_ONLY`. `sendingPaused` is the rollback lever: it makes the server return `MIGRATION_HOLD`, queues keep accumulating on devices (nothing lost, bounded by the 500 cap), and voice and touch keep working locally. Reopening whole-document writers after any typed command has committed is forbidden (package rule, `04_CORE_TDD.md` section 7 and `14_INTEGRATION_MIGRATION_RUNBOOK.md` section 5).
- FACT: the package FC-02 puts the policy at the same path and requires rules to read trusted policy, not client protocol fields (`04_CORE_TDD.md` section 10). Rules cost: the DRAIN and SERVER_ONLY checks need `get()` of the policy document and of the session document inside rules. UNKNOWN: rule evaluation cost and the 10-`get()` limit must be checked in the emulator (FU-AC-063 wildcard OR bypass test applies).

### 8.3 Coexistence without overwrite or duplication
Risks and the DECISIONs that remove them:
1. Overwrite: a pending legacy whole-document `.set` flushes after a typed command was applied and erases the typed sets. Fix: in `DRAIN` and `SERVER_ONLY` the rule denies any client write to a document whose `protocolVersion >= 2`. The first typed apply sets `protocolVersion = 2` in the same transaction that applies the command. A late legacy write is therefore denied, never merged.
2. Lost legacy work: that denial discards the legacy write on the old device. Mitigation: the new client runs the drain barrier first (8.4); the remaining exposure is old-client devices that never ran it. This is the residual risk in 11 (decision O-1).
3. Conversion: when a typed command meets a legacy-shaped document (no `protocolVersion`), the apply transaction converts it first: assign set ids `legacy_{exerciseIndex}_{n}`, mark each existing set `source = LEGACY_UNVERIFIED` (package label, `05_DATA_MODEL.md` section 8), set `revision = 1`, `protocolVersion = 2`, create controls with `writerEpoch = 1` and `sessionGeneration = 1`.
4. Duplication: a typed CompleteSet APPEND whose `logicalSetId` slot is already occupied by a `LEGACY_UNVERIFIED` set (FACT: the legacy player holds one set per exercise, so index 1 is the same physical set) is refused as `DUPLICATE_LOGICAL_SET` (I8); the user may fix it with a CORRECT command (new id). No value is guessed and no set is added twice.
5. New session ids: a legacy write for an id that the typed path created is denied by the same `protocolVersion` rule. A typed `sessionInit` for an id that already exists as a legacy document is treated as the conversion case (3), not as a create.

### 8.4 Drain barrier on the device and ack
- DECISION: a new-protocol client in a `DRAIN` account (a) stops issuing `.set` for the three operations (no direct fallback), (b) waits until all previously issued Firestore writes are acknowledged by the server (candidate mechanism: the SDK `waitForPendingWrites`; UNKNOWN: its availability in the pinned `cloud_firestore` version and its behaviour offline have not been verified; the package also warns that the SDK queue cannot be enumerated without a verified mechanism, `04_CORE_TDD.md` section 7), (c) then calls `ackLegacyDrain({deviceInstallId, migrationEpoch})`, which adds the device to `drainedDevices`. Until the ack, typed sends return `MIGRATION_HOLD`; local acceptance continues unaffected.
- DECISION: session deletion becomes a server operation `deleteWorkoutSession(sessionId)` in `SERVER_ONLY`: in one transaction it deletes the document, bumps `sessionGeneration` in the tombstone (`deletedGeneration = generation`), and deletes the controls. FACT: today delete is a plain client delete (`firestore_workout_session_repository.dart` lines 73 to 76).

### 8.5 Cutover rule `DRAIN` -> `SERVER_ONLY`
DECISION: the server moves the account when every device that was seen on the account within the last 90 days is in `drainedDevices` (UNKNOWN: the source of "devices seen" is the device-session registry the package assumes; if it does not exist, use the deadline alone), or when a per-cohort deadline passes (30 days after entering `DRAIN`; operator decision O-1 of 2026-10-22: 30 days). Before the move, reconcile: no automated data rewrite beyond the lazy conversion of 8.3.

### 8.6 Account deletion and fence
DECISION: account deletion sets `migrationState = DELETING` first (all applies return `ACCOUNT_DELETING`, 4.2 step 2), then the client sends are cancelled and the queue cleared, then server data including fence, receipts, controls, tombstones and sessions is deleted, the policy document last. An apply for a missing policy document is refused (`MIGRATION_HOLD`), so nothing is recreated after deletion completes (criterion 13). UNKNOWN: how the existing deletion framework (referenced as an extension point in `05_DATA_MODEL.md` section 2, row DeletionTombstone) would host this state; its code was not read.

### 8.7 New acceptance id
DECISION: the proof that legacy pending set writes and typed local commands cannot overwrite or duplicate each other's accepted effects is owed (`package-amendments/SUPERSESSION.csv`, row for FU-RQ-014: "OWED: not covered by FU-AC-095"). Propose FU-AC-119; scenario in section 10.

---

## 9. Failure-mode table

| Event | Required behaviour | Mechanism |
|---|---|---|
| Lost ack (server applied, client never heard) | Retry with the same id and bytes; the server answers `ALREADY_COMMITTED` (or the detail-expired form after 90 days); exactly one set exists; local state ends `synced` | F1, I2/I3, 5 |
| App kill mid-send | On restart `sending` records become `accepted` with `maybeSent = true` and resend with the same bytes; the outcome is the same as lost ack or never-arrived | 3.2 |
| App kill during acceptance | Either the whole record exists (shown pending) or nothing (reported "not saved"); no seq or logical set index is consumed without a record | 3.3 |
| Network drop inside a batch | Items already answered keep their state; the rest stay `accepted` | 4.5 |
| Clock skew on the device | No server decision uses client time. Order uses `seq` and `setIndex`. `performedAtClientMs` is stored as informational; if it is more than 5 minutes after `serverTime` or more than 400 days before it, `clockSuspect = true` is stored and the value is still kept (DECISION); history readers sort a session by `seq` and show device time with the flag. A 30-day or 25-day warning on the device uses the monotonic clock plus wall clock difference; a clock set backwards must not hide a warning (DECISION: take the larger of the two ages) | 2.4, 6 |
| Server clock | Receipt `expireAt` uses server time only | 5.3 |
| Device restore or new phone | The queue is excluded from OS backup. If a restored copy appears anyway (UNKNOWN platform guarantee), replays are harmless because of the fence; the risk is that commands the user had discarded come back. The client binds the queue to `deviceInstallId` stored outside backup; on a mismatch it marks every record `conflicted` non-terminal "restored from backup, review before sending" and sends nothing automatically (DECISION) | 3.6, 5 |
| Second device, same account | Second device is read-only unless takeover; offline it may still accept, then gets `NOT_WRITER`. Both devices logging the same set give `DUPLICATE_LOGICAL_SET` on the later one | 7, 8.1 |
| Long offline (over 90 days) | Command never seen: fence miss, applied once. Seen and acked-but-lost: fence hit, no duplicate | 5.1 to 5.4 |
| Session deleted elsewhere meanwhile | `SESSION_DELETED`, kept, never recreated | 5.5, 7 |
| Sign-out or deletion during a send | Lease is held exclusively before releasing the UID; the in-flight call finishes or is cancelled; a call that was already on the wire is resolved by the fence on next sign-in | 3.6, 8.6 |
| Fence shard full | Non-terminal hold, visible message, nothing evicted, escalation to engineering | 5.2 |
| Legacy write races a typed command | Legacy write denied by rule, typed effect intact | 8.3 |
| Server rejects as `INVALID_PAYLOAD` | Treated as a client defect; record kept `conflicted`; release blocked in test (FU-AC-095 vectors) | 4.2 |

---

## 10. Test obligations

All cases are NOT_RUN. Each case must name the exact implementation SHA, as every row of `ACCEPTANCE_AMENDMENTS.csv` requires. For each row the scenario below must FAIL on a build that breaks the stated guard.

| ID | Concrete failing scenario (what must fail if the design is broken) |
|---|---|
| FU-AC-092 | Airplane mode 20 minutes, 15 CompleteSet taps (touch and voice mixed). Each tap shows "pending sync" and the rest timer starts with zero network calls recorded. Reconnect: server holds exactly 15 sets, queue has 0 non-synced records. Fails if any set is missing, doubled, or if a tap waited on the network. |
| FU-AC-093 | Kill the process (a) between the store transaction start and commit, (b) right after commit, (c) with a power-loss simulation if the platform allows. After restart every set shown "pending" before the kill is present with identical bytes and hash; a command killed in (a) is absent and the user was told "not saved". Fails if a half record exists, a seq or `setIndex` is consumed without a record, or "pending" was shown before the commit returned. |
| FU-AC-094 | Fill 500 records, try the 501st: refused with a message before any record is created, all 500 intact. Warnings at 400 and when the oldest is 25 days old (clock moved forward 31 days, then clock moved backward: the warning must remain). Fails if any record disappears or the 501st is accepted. |
| FU-AC-095 | (a) Send the same record 3 times with the same bytes: one effect, identical receipt. (b) Same `operationId` with `loadGrams` changed: `ID_PAYLOAD_MISMATCH`, no receipt contents in the answer, the stored set unchanged. (c) A's envelope under B's authentication: `UID_MISMATCH`, B's data unchanged, no A receipt exposed. (d) Same `operationId` with another `sessionId`: `ID_SESSION_MISMATCH`. (e) Hash version 2 golden vectors agree between Dart and the server byte for byte; `expectedRevision` and `writerEpoch` are absent from the hash input. Fails if any of (a) to (e) differs. |
| FU-AC-096 | (a) Server applies, ack dropped, client retries: one set. (b) Two taps on one set: the local unique index yields one record. (c) Two devices, two different `operationId`, same `logicalSetId`: the second ends `conflicted` `DUPLICATE_LOGICAL_SET`, the first set value unchanged. (d) Process killed between `sending` and the answer, then restart: one set. Fails if the session has two sets at the slot in any case. |
| FU-AC-097 | Queue: init+AddEligibleExercise(op1), CompleteSet(op2, dependsOn op1), SetDifficulty(op3, dependsOn op1). Deliver 2 before 1: `DEPENDENCY_PENDING`, nothing applied. Make op1 terminal-fail: op2 and op3 end `conflicted` `DEPENDENCY_REJECTED`, not applied. Deliver two independent CompleteSet commands (setIndex 1 and 2) in reverse order: document has sets in setIndex order. Fails if a dependent applies first or order follows arrival. |
| FU-AC-098 | Accept 500 commands; resolve 300 successfully, then apply 300 more (more than 256 newer); then replay the original 500 in random order: every replay returns an already-applied class, zero new sets. Then (clock/data fixture): delete every detail receipt older than 90 days (simulated TTL), replay the 500 again: `ALREADY_COMMITTED_DETAIL_EXPIRED`, zero new sets. Then a command held 100 days that the server never saw: applied exactly once. Also: fence entry written in the same transaction as the effect (fault injection: abort after the effect write; both or neither). Fails if any replay applies, if a never-seen old command is rejected for age, or if any entry is evicted. |
| FU-AC-099 | While pending, history, progress, coach context and server-side exports contain no pending set; the device-side export snapshot lists it as pending. "Synced" appears only after a C1/C2 answer; with the server answering `MIGRATION_HOLD` the UI never says synced. Fails otherwise. |
| FU-AC-100 | Offline log a set and start rest; delete the session from another device; reconnect: `SESSION_DELETED`, the set remains visible and exportable, server history and volume metrics unchanged, no document `workout_sessions/{id}` exists. Also: session `abandoned` elsewhere: `SESSION_CLOSED`. Also: a deleted day session id re-used by an old queue never recreates it. Fails if any document is created. |
| FU-AC-101 | One shared entry point: a voice-originated CompleteSet and a touch-originated one produce records differing only in `body.source`, written by the same code path (coverage assertion on the accept function). StartSet by voice or touch: queue size unchanged, no receipt, no completed set. Fails if a voice path writes without the queue or a StartSet creates a record. |
| FU-AC-119 (NEW, proposed) | Migration proof for legacy writers and typed commands, under `DRAIN` and `SERVER_ONLY`. Scenarios: (1) a legacy device holds a pending whole-document `.set` for session S while a typed command for S is applied and converts S; the legacy write then flushes: it is denied by rules, S keeps the typed sets (no overwrite), and the device reports unsynced work. (2) Reverse order: legacy write lands first, typed command converts it: legacy sets are `LEGACY_UNVERIFIED`, a typed APPEND at the same slot returns `DUPLICATE_LOGICAL_SET`, no set doubled. (3) In `SERVER_ONLY` a client create/update/delete of any `workout_sessions` id, including a never-seen id, is denied under every matching rule (wildcard OR bypass). (4) A typed command from a device not in `drainedDevices` returns `MIGRATION_HOLD`, stays queued, applies after the ack. (5) `sendingPaused = true`: 15 commands accepted and kept, none applied; after unpausing 15 sets exist once each. (6) Attempted state regression `SERVER_ONLY` -> `DRAIN` is refused. Fails if any set is lost, doubled, or a legacy write is accepted after typed data exists. Requires `package-amendments/ACCEPTANCE_AMENDMENTS.csv` row FU-AC-119 and a `SUPERSESSION.csv` update, at priority P0, parent FU-RQ-014 / FU-014. |

Cross-reference with existing package rows (FACT, `registers/ACCEPTANCE.csv`): FU-AC-012 (terminal close vs late commit), 058 (closed epoch after TTL), 060 (closure races effect), 057 (lost prepare response) are about the withdrawn admission model and need rewriting for this protocol (FU-AC-058 -> "fence after detail TTL", FU-AC-057 -> "lost ack with same operationId"); FU-AC-014, 063, 081 to 083 stay and are extended by FU-AC-119.

---

## 11. Open questions and unknowns

### 11.1 Questions that need an operator decision
- O-1 (DECIDED by the operator on 2026-10-22): the `DRAIN` period is 30 days; after it the account moves to `SERVER_ONLY` and unsynced legacy whole-document writes on never-updated devices are denied and lost on that device, with an error shown there. A force-update gate before `DRAIN` is recommended if a version-gate mechanism exists (UNKNOWN, see 11.2); it is not required by this decision.

No other operator decision is needed to implement this design; everything else above is a DECISION of this document and can be changed only by editing it.

### 11.2 Explicit unknowns (engineering must verify, none blocks writing the code)
1. Local store engine and its durability guarantee (3.3).
2. Firestore index exemption for the fence map and the 1 MiB / entry-count behaviour (5.2); TTL policy availability (5.3).
3. `waitForPendingWrites` availability and offline behaviour in the pinned SDK; no verified way to enumerate the SDK write queue (8.4).
4. Existence of a device-session registry, a force-update gate, and the shape of the existing deletion framework (8.5, 8.6, 4.2 step 4).
5. Rule evaluation cost of `get()` calls for the DRAIN/SERVER_ONLY checks (8.2).
6. Whether any existing function in `functions/src` writes `workout_sessions` (1.3).
7. Deployed Cloud Functions runtime and billing for the extra writes per command (fence, receipt, session, controls: four document writes per command); no measurement exists.
8. Whether a global operationId registry is wanted for FU-AC-095 (4.3 note); not added here.
9. Whether v1 introduces an explicit "workout finished" terminal state; today `completed` is appendable (7.1). If it does, `SESSION_CLOSED` extends to it and the player flow changes.
10. Any future set-deletion feature must write a set tombstone in the same transaction, otherwise I8 can re-apply a deleted slot.

### 11.3 Contradictions found in the inputs
1. Package v1 canonical payload includes `expectedRevision` and `writerEpoch` (`COMMAND_GOLDEN_VECTORS.json`, `API_CONTRACTS.json`), which an offline-accepted command cannot know or keep stable across retries. Resolved by hashVersion 2 (2.2).
2. The package 2-minute admission plus closed birth epoch before the 90-day TTL (`04_CORE_TDD.md` sections 3, 4; `05_DATA_MODEL.md` retention row) makes any command unsent past the window permanently inadmissible, which contradicts "no silent eviction" and the 30-day warning (LOCAL_QUEUE_DECISION criterion 3). Resolved by the fence invariant F1 (5.1).
3. `04_CORE_TDD.md` FC-01 says the epoch fence alone gives `OUTCOME_EXPIRED` without historical outcome. This design stores a coarse outcome in the fence and so can answer more precisely; `OUTCOME_EXPIRED` survives only for the no-entry-but-unprovable case (5.4). Needs the package author to update FC-01 and `API_CONTRACTS.json` `ExpiredHistoricalOutcome`.
4. LOCAL_QUEUE_DECISION criterion 4 (id never changes across retries) versus criterion 9 ("kept in the queue for retry"): reconciled by separating transport retry (same id) from user resubmission after a terminal conflict (new id, `supersedes` link) (2.1).
5. The package data model assumes stable set ids and an increasing revision (`05_DATA_MODEL.md` section 8); FACT: the current document has neither (1.3). The design therefore adds a lazy conversion with `LEGACY_UNVERIFIED` sets (8.3), and requires the readers listed in the package migration contract to ship before the flag is on.
6. Current player behaviour (one set per exercise, re-tap overwrites, FACT 1.3) conflicts with "one logical set, one completion, tap twice = one set" only if the second tap carries different values; the design turns that case into CORRECT (3.1), which the UI must expose. UNKNOWN: the exact UI for this.
7. `SUPERSESSION.csv` marks the migration proof as owed without an id; this document proposes FU-AC-119 (section 10).
