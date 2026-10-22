# Offline command protocol for CompleteSet, AddEligibleExercise and SetDifficulty

Version 1.2, 2026-10-22. Status: PROPOSED DESIGN, NOT IMPLEMENTED, no test has been run. Version 1.1 incorporated the independent reliability review (1 BLOCKER, 8 MAJOR, 4 MINOR) of version 1.0; version 1.2 closes the 5 MAJOR holes (R1 to R5) and 3 minor points found when verifying 1.1.

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
- DECISION: the protocol covers the client queue, the server apply transaction, receipt and fence storage, ordering, conflicts, writer epoch, version compatibility and the legacy-writer migration states.

### 1.2 Non-goals
- FACT: StartSet is not queued and creates no queue entry, no receipt and no completed-set fact (`docs/v1/VOICE_READY_PROMPT_DECISION.md`, section "StartSet is not CompleteSet"; acceptance FU-AC-101 in `package-amendments/ACCEPTANCE_AMENDMENTS.csv`). This document never treats StartSet as a command.
- DECISION: not covered here, each needs its own contract: sign-out sheet, account deletion, export and backup UI (criteria 11 to 14; only the protocol hooks they need are named in 3.6), multi-writer collaboration (ADR-CMD-04 stays one writer), set deletion, ScheduledSession and programme writers, AI intent parsing.
- DECISION: no new online admission step. The package `prepareWorkoutCommand`, `applyWorkoutCommand`, `resolveAndCloseCommand` endpoints, the admission token, the 2-minute `admissibleUntil`, and "birth epoch" closure are withdrawn for these three commands (see 2.4 and 5.1).

### 1.3 Code facts that shape the design
- FACT: today a whole `WorkoutSession` document is written with `doc(id).set(session.toJson())` and a 4 second timeout whose `onTimeout` handler returns normally, so a missing server acknowledgement is hidden; the code comment states that "a genuine server rejection after the timeout is not reported to this caller" (`mobile/lib/features/workouts/data/firestore_workout_session_repository.dart`, lines 61 to 71). Delete is a plain `await ...delete()` with no timeout (same file, lines 73 to 76).
- FACT: a session stores `sets` as a list of `{weightKg, reps}` with no set id, no revision and no writer field (`mobile/lib/features/workouts/data/workout_session.dart`, lines 52 and 70 to 81).
- FACT: the player writes at most one set per exercise per session and a repeat tap overwrites it (`mobile/lib/features/equipment/workout_player_page.dart`, lines 632 to 636). A day session id is deterministic, `day_{dayId}` (same file, lines 81 and 664 to 666); a free session id is `{microsecondsSinceEpoch}_{sessionKey}` and is created on the client (same file, line 666).
- FACT: rest starts only after the save future completes and the error check passes (`workout_player_page.dart`, lines 730 to 736 and 973 to 977). Under this protocol "persist" means the local durable commit of 3.3.
- FACT: `firestore.rules` lines 61 to 83 give the owner read and write on every `users/{uid}/{coll}/...` collection except a named carve-out list; `workout_sessions` is not in the list, so the owner can write it directly today.
- FACT: a search of `functions/src` (excluding test folders) for "workout" found only `abuse_guard.ts`, `account_export.ts`, `scaling.ts`, `video_urls.ts`; no workout command callable was found. Their content was not inspected beyond that. UNKNOWN: whether any of them writes `workout_sessions`.
- UNKNOWN: the local storage engine available in the Flutter app (needs a transactional store with unique indexes); the deployed Cloud Functions runtime; whether Firestore TTL policies are enabled in the project; whether the app has a minimum-version gate.

---

## 2. Identity model

### 2.1 Identifiers
| Name | Definition | Created by | Mutable |
|---|---|---|---|
| `operationId` | 30 characters: `uidTag` (8 characters, base64url of the first 6 bytes of `SHA-256("u1|" + uid)`) followed by 22 characters, base64url of 16 CSPRNG bytes (128 bit random part). Matches the package id pattern `^[A-Za-z0-9_-]{1,128}$` | client, inside the atomic acceptance commit (3.3), before any network call | never |
| `uid` | Firebase Auth UID active at acceptance | client reads the signed-in UID; the server trusts only the authenticated UID | never |
| `sessionId` | existing scheme: `day_{dayId}` or the client-generated free id | client (FACT, 1.3) | never |
| `sessionGenerationClaim` (envelope, not hashed) | 0 = the client has never observed this session on the server; otherwise the generation it last saw. A new session is generation 1; after a deletion the next session on the same id is `deletedGeneration + 1` | client, from its last synced view or from a server answer | yes, restamped only by the rules in 4.2 and 7.2 |
| `logicalSetId` (CompleteSet only) | `{sessionId}:{exerciseId}:{setIndex}`, `setIndex` integer 1..1000. `setIndex` is the index of the player's CURRENT set context for that (session, exercise) (3.3), not "the next free index". The context starts at 1 and advances only by an explicit user "next set" action | client | never |
| `seq` | integer, strictly increasing per (uid, sessionId, originDeviceInstallId), from a persistent counter row that is never derived from remaining records and never pruned with them (F12). Used for delivery order from one device and for the server guard of 4.2 step 6g; NOT for display order | client, in the acceptance commit | never |
| `dependsOn` | sorted list of at most 3 `operationId`: the session-creating operation, the AddEligibleExercise operation for this exercise, and (for a CORRECT) the APPEND of the same set, each only while it is not yet `synced` | client | never |
| `setId` in the body | derived: `set_` plus `setIndex` zero-padded to 4 digits (keeps the shape of `COMMAND_GOLDEN_VECTORS.json` `set_0001`) | client | never |

- DECISION: the package `clientIntentId` and the server-minted `commandId` collapse into the single client-generated `operationId`. A retry, a restart and a reconnect reuse the same bytes (LOCAL_QUEUE_DECISION criterion 4).
- DECISION: the `uidTag` makes an `operationId` valid only under the UID it was minted for, statelessly. The server rejects an id whose tag differs from the tag of the authenticated UID (`ID_UID_MISMATCH`, 4.3 I6). This implements the strong reading of FU-AC-095 (an identity presented under another UID is rejected) without a global id registry.
- DECISION: a user-initiated re-submission after a terminal conflict (7.3) is a new intent with a new `operationId` and a `supersedes` link kept locally. This does not violate criterion 4: criterion 4 forbids changing the id on transport retry, not creating a new intent after the user explicitly resubmits.

### 2.2 Canonical payload and hash (hashVersion 2)
- FACT: version 1 hashes `expectedRevision`, `writerEpoch` and `sessionGeneration` inside the payload (`registers/COMMAND_GOLDEN_VECTORS.json`, payload objects; `registers/API_CONTRACTS.json` schemas `CompleteSet`, `SetDifficulty` require them).
- DECISION: an offline command cannot know the server revision, writer epoch or generation at execution time, and these values must be restampable without changing the command's identity. Version 2 therefore removes `expectedRevision`, `writerEpoch` and `sessionGeneration` from the hashed payload. The last two move to the unhashed envelope (2.3). Version 1 vectors stay valid for the withdrawn online endpoints only; new version 2 golden vectors must be generated and checked in Dart and on the server before implementation (NOT_RUN).
- DECISION: hashed canonical object (keys in recursive lexicographic order, UTF-8, no whitespace, integers only, explicit `null` for nullable fixed fields, unknown keys rejected, same rules as `API_CONTRACTS.json` `x-canonicalization`):

```
{ protocolVersion: 2, hashVersion: 2, limitsVersion: 1,
  operationId, uid, sessionId, seq,
  dependsOn: [operationId...],
  exerciseId, operation,
  logicalSetId: string | null,
  sessionInit: { title, dayId | null, startedAtClientMs } | null,
  body: <operation body of API_CONTRACTS.json, see below> }
```
- DECISION: `body` for CompleteSet is the package body (`mode`, `setId`, `performedConfirmed`, `actualReps`, `actualRepsConfirmed`, `targetReps`, `loadGrams`, `source`) plus `performedAtClientMs` (integer, ms since epoch, informational, see 9). AddEligibleExercise and SetDifficulty bodies are unchanged from the package.
- DECISION: `sessionInit` is non-null only on the operation that is first accepted for a session the client has not seen on the server; it carries what `WorkoutSession` requires on creation (FACT: `title` and `startedAt` are required, `workout_session.dart` lines 193 to 202).
- DECISION: `payloadHash` = lowercase hex SHA-256 of the canonical bytes. The client stores the canonical bytes verbatim in the queue record and always sends those bytes; it never re-serializes (except the rebuild path of 2.5).
- DECISION: binding to identity: the hash covers `operationId`, `uid` and `sessionId`, so a payload cannot be re-labelled to another id, account or session without changing the hash.

### 2.3 Envelope (sent with the payload, not hashed)
`{ payloadBytes, payloadHash, writerEpochClaim, sessionGenerationClaim, acceptedWriterEpoch, deviceInstallId, clientBuild }` - DECISION. `deviceInstallId` is always the CURRENT install's id (transport identity, R5). `acceptedWriterEpoch` is the writer epoch the client knew when it accepted the record (0 if it had never synced the session); it is immutable, is never restamped by a takeover, and is what the ordering guard of 4.2 step 6g compares across epochs. `writerEpochClaim` and `sessionGenerationClaim` may change between retries (after a takeover, 8.1, or a `GENERATION_STALE` answer, 4.2) without changing identity. The server recomputes the hash from `payloadBytes`; it never trusts a client-supplied hash, role, UID or time.

### 2.4 What the server mints (answer to B-01)
- DECISION: the server mints no identity before the effect. It mints only: `serverTime`, `revisionBefore`/`revisionAfter`, and the receipt, whose id equals `operationId`. Nothing in this list gates local acceptance, so the package conflict (an online `prepare` that mints id, token and 2-minute expiry before the effect) no longer exists for these commands.
- DECISION: what the package token bound (UID, device session, account epoch, session writer epoch, session generation, payload digest) is instead checked inside the apply transaction at apply time (4.2). The authority is the authenticated caller plus current server state, not a pre-issued token. This is not weaker than today: FACT, the owner can already write `workout_sessions` directly (`firestore.rules` lines 61 to 83); the new path adds validation.
- DECISION: there is no server-side maximum command age. A command accepted 30 days ago (LOCAL_QUEUE_DECISION criterion 3) is applied if the session state allows it. Age never makes a command inadmissible; only a fence hit (5.2) or a session rule (7) can refuse it.

### 2.5 Version compatibility of queued commands (F9)
A queue entry can outlive the app build that wrote it (criterion 3: no eviction by age). DECISION rules:
1. The queue record stores, besides `canonicalBytes`, the structured fields of the command (`payloadFields`, the typed values before canonicalization) and `protocolVersion`, `hashVersion`, `limitsVersion`.
2. The server accepts every shipped `(protocolVersion, hashVersion, limitsVersion)` triple. A triple may be retired only after the minimum-version gate (8.5, P1) forces all clients to a build that can rebuild records; until then it is supported.
3. After retirement, the server resolves the fence first (the hash is computed over the received bytes, no parsing of the old schema is needed). A fence hit returns I2/I3 as usual. A fence miss proves the command was never applied (F1), so the server returns non-terminal `VERSION_RETIRED`.
4. On `VERSION_RETIRED`, and on app start after an upgrade, the client rebuilds every record with `maybeSent = false` or `VERSION_RETIRED` from `payloadFields` under the current version, keeping the same `operationId` (safe because a miss in the fence proves no effect exists). A record with `maybeSent = true` keeps its original bytes and is sent unchanged; the server must answer it from the fence even if the version is retired.
5. All limits (1000 reps, 1,000,000 grams, setIndex 1..1000, 500 queue cap, batch 25, `dependsOn` 3, session limit 2,000 resolved operations) are frozen in a `limitsVersion` table before release; changing one needs a new `limitsVersion`, and the old one stays accepted.
6. CI obligation: a golden queued payload produced by the oldest shipped client build is replayed against the current server on every release; the build fails if the answer is not the one in the golden file (FU-AC-095 (f)).

### 2.6 Privacy note on the uidTag
DECISION: the 48-bit `uidTag` inside every `operationId` is a pseudonym of the UID (a truncated hash that can be recomputed by anyone who knows a candidate UID). Therefore `operationId` is pseudonymous personal data: it is allowed in the UID-scoped Firestore documents and in the device queue; it must not be used as a metric label (4.6), must not be written to shared logs above debug level, and must be included in the data export and deleted with the account like the fence and receipts. The random 128-bit part carries no user information.

---

## 3. Local queue

### 3.1 Record
One record per command, keyed by `(uid, operationId)`. DECISION fields:

| Field | Meaning |
|---|---|
| `uid`, `operationId`, `sessionId`, `exerciseId`, `operation` | identity, immutable |
| `canonicalBytes`, `payloadHash`, `payloadFields`, `protocolVersion`, `hashVersion`, `limitsVersion` | immutable except the rebuild of 2.5 |
| `seq`, `dependsOn`, `logicalSetId` | immutable |
| `state` | one of the five states in 3.2 |
| `maybeSent` | boolean; set to true in the same commit that moves the record to `sending`, never reset |
| `attempts`, `lastAttemptLocalMs`, `lastResultCode` | diagnostics |
| `writerEpochClaim`, `sessionGenerationClaim` | envelope; mutable (restamped by takeover or `GENERATION_STALE`) |
| `acceptedWriterEpoch`, `originDeviceInstallId` | envelope; immutable. `originDeviceInstallId` is the install that accepted the record; it is informational after a restore (R5) and is never sent as identity |
| `intentKey` | opaque id of the user event that produced the record: the UI event id of a tap, or the id of a final recognition result. Required on every CompleteSet record (R1c) |
| `conflictKind`, `conflictTerminal`, `blocksSession` | set when `state = conflicted` (section 7) |
| `ackSummary` | revisionAfter, serverTime, detailExpired flag, `superseded` flag; set when `synced` |
| `supersedes` | operationId of a terminal-conflicted record this one replaces, or null |
| `acceptedAtLocalWallMs`, `acceptedAtMonotonic` | informational only |

Local unique indexes (DECISION), enforced by the store: `(uid, operationId)`; `(uid, sessionId, originDeviceInstallId, seq)`; `(uid, intentKey)` for CompleteSet records; and `(uid, logicalSetId)` for `operation = CompleteSet` and `mode = APPEND` and `state` not `discarded`. The `logicalSetId` and `intentKey` indexes are the last line of defence; the primary protection against a second APPEND is the set-context rule of 3.3, because "next free index" would never collide with the index.

Separate local tables (DECISION), none of them pruned with records:
- `session_seq(uid, sessionId, originDeviceInstallId, nextSeq)`;
- `set_context(uid, sessionId, exerciseId, currentSetIndex)`;
- `effective_set(uid, sessionId, exerciseId, setIndex, appendExists, syncedValues, effectiveValues, anchorOperationId)`: one row per set the device has ever logged. `syncedValues` are the values of the last acknowledged APPEND/CORRECT; `effectiveValues` are the values of the newest non-discarded, non-terminal-conflicted pending CORRECT or APPEND, else `syncedValues`. The row is updated in the same local transaction as every acceptance, acknowledgement, discard and terminal conflict, so it survives pruning of the records (R1b);
- `intent_keys(uid, intentKey, operationId, acceptedAt)`: kept for at least 30 days, independent of record pruning (R1c);
- `session_sender_state(uid, sessionId, hold, nextProbeAt)` (3.4).

### 3.2 States
| State | Meaning | Counts toward the 500 cap |
|---|---|---|
| `accepted` | committed locally, not yet in flight | yes |
| `sending` | a send attempt is in flight or may have been in flight at process death | yes |
| `synced` | server answered COMMITTED, ALREADY_COMMITTED (also detail-expired) or SUPERSEDED | no |
| `conflicted` | server refused it (terminal) or a non-terminal hold needs user action (section 7) | yes |
| `discarded` | user explicitly discarded after export, or confirmed discard naming the count | no |

Transitions (DECISION; any other transition is a bug):
- (none) -> `accepted`: only by the acceptance commit (3.3).
- `accepted` -> `sending`: one local commit that sets `maybeSent = true` and increments `attempts`, then the network call.
- `sending` -> `synced` | `conflicted` (terminal or hold) | `accepted` (retryable network or server error, same bytes).
- on process start, every `sending` record is treated as `accepted` with `maybeSent = true` and is re-sent with the same bytes (never a new id).
- `conflicted` (non-terminal hold) -> `accepted` after the user action named in 7.2 (same `operationId`).
- `conflicted` (terminal) -> `discarded` only by the export-then-discard or confirmed-discard flow; a "retry" creates a new record (2.1).
- `synced` records are kept for 7 days after the acknowledgement (DECISION, display and support only) and then pruned. This is not eviction of an unacknowledged command, so criterion 3 is not touched. Pruning never touches `session_seq`, `set_context`, `effective_set` or `intent_keys`.
- `accepted`, `sending` and `conflicted` are never removed by age or size (criterion 3).

### 3.3 Atomic durable acceptance and the set-context rule (criterion 2, criterion 5)
DECISION: acceptance is one transaction of the local store that does all of the following or nothing:
1. read the count of records in `accepted`, `sending`, `conflicted` for the UID; refuse with a visible message if it is 500 (criterion 3); raise the warnings of 3.7;
2. for a CompleteSet intent, apply the set-context rule (R1):
   - (c) intent dedupe first: if `intent_keys` already holds the intent's `intentKey`, create nothing and return the existing record. This holds across context changes: a late duplicate of the same recognition result or the same tap event, delivered after the user pressed "next set", cannot create a phantom APPEND at the next index;
   - otherwise let `i = set_context.currentSetIndex` for (session, exercise) (default 1) and read `effective_set` for index `i`:
     - no row: create an APPEND at `i` and insert the row;
     - row exists with `appendExists` and the APPEND is not terminal-conflicted: compare the new values (all body fields except `performedAtClientMs` and `source`) with `effectiveValues`, the LATEST effective values (newest non-discarded CORRECT, else the APPEND, else `syncedValues`, never the first APPEND):
       - equal: create nothing and return the record that holds those values; the UI shows its state; the rest timer is not restarted;
       - different: create a CORRECT for `set_000i` (dependsOn the APPEND only while that is not `synced`; if the APPEND was pruned or synced there is none) and set `effectiveValues` to the new values. So X, then Y, then X again produces APPEND(X), CORRECT(Y), CORRECT(X): last intent wins and the set ends as X, never a silent no-op against the first APPEND (R1a);
     - the anchoring APPEND is terminal-conflicted: create nothing; the UI offers the resolution of 7.2.
   - `intent_keys` gets the new key in the same transaction (also when the result was a no-op).
   A synced APPEND that was pruned after 7 days leaves its `effective_set` row, so a later tap with new values produces a CORRECT, never `DUPLICATE_LOGICAL_SET` (R1b).
   The index advances only through the explicit "next set" action, which updates `set_context` in its own local transaction. DECISION (R1d): when the "next set" UI is absent, which is v1 behaviour today because the player has one set per exercise (FACT 1.3), the context stays at the current set: a repeat tap with identical values is a no-op and with different values a CORRECT; a genuine second identical set needs the explicit action. UNKNOWN: the UI for "next set". Every multi-set test below is gated on that UI existing;
3. allocate `seq` from `session_seq`; compute `dependsOn`; generate `operationId` (with `uidTag`); build and store the canonical bytes, `payloadFields` and the hash;
4. insert the record in state `accepted`.
Only after the transaction reports commit may the UI show "pending sync" or start the rest timer. A failed or interrupted transaction leaves nothing and the UI reports "not saved". No network call happens before the commit. Because the whole rule runs inside one store transaction, two taps 100 ms apart, or the same voice recognition result delivered twice, are serialized and the second sees the first. UNKNOWN: the storage engine and its durability setting must be chosen and shown by FU-AC-093.

### 3.4 Sender
- DECISION: one sender per UID. Per session, at most one request in flight (concurrency limit, not a blocking rule). Different sessions may run in parallel. A batch call carries up to 25 consecutive eligible records of one session in `seq` order (4.5).
- DECISION: what blocks what. A terminal conflict, a C4 client-defect result (including `INVALID_PAYLOAD`) or any record-level hold blocks ONLY the records that list it in `dependsOn`; independent later records are still sent. Only a session-level hold (`NOT_WRITER`, `MIGRATION_HOLD`, `AUTH_REVOKED`, `ACCOUNT_DELETING`, `RATE_LIMITED`, `SESSION_COMMAND_LIMIT`) stops the session's send loop, recorded in `session_sender_state`, because every further record would get the same answer.
- DECISION (R2, the ONE dependency rule): a record is held locally, not sent, while any record in its `dependsOn` is UNRESOLVED: `accepted`, `sending`, or `conflicted` non-terminal (a retryable conflict such as `NOT_WRITER`). Once every dependency is terminal (`synced`, or terminal-conflicted) the client sends the dependent, and the SERVER decides by the dependent's own preconditions (4.2 step 6e): an `R` predecessor alone does not reject it. If the predecessor failed to establish what the dependent needs (for example the exercise is absent), the server answers terminal `DEPENDENCY_REJECTED`, the dependent is not applied and ends `conflicted` "could not sync". If the thing exists anyway (for example the predecessor add was refused as `EXERCISE_ALREADY_IN_SESSION` because the exercise is already present), the dependent applies. There is no "force send": the user can only export, discard or resubmit (7.2).
- DECISION: backoff on retryable errors is exponential from 2 seconds with jitter, capped at 5 minutes, reset on connectivity change and on app foreground; it never changes the bytes and never gives up (no attempt limit; the record stays `accepted`).
- DECISION (R3, hold exit): a session-level hold is never permanent. While a hold is active the sender probes by sending the first eligible record of the session (no separate probe message), with backoff starting at 30 seconds, doubling to a cap of 15 minutes, with full jitter, and honouring a server `retryAfter` when it is larger. The backoff resets on app foreground, connectivity change and sign-in. The first answer that is not a hold clears the hold and every record of the session returns to normal sending automatically, with no user action. Per code: `MIGRATION_HOLD`, `RATE_LIMITED`, `ACCOUNT_DELETING` probe as above; `AUTH_REVOKED` does not probe until sign-in; `NOT_WRITER` probes only on foreground to read `sessionState` (if this device is now the writer the hold clears), otherwise the exit is the user takeover of 7.2; `SESSION_COMMAND_LIMIT` exits only by the user action of 7.2.
- DECISION (R3, unknown codes): any result code the client does not know (a newer server or protocol) is treated as a retryable session hold: the record stays `accepted`, is never marked `synced` and never terminal, a local counter is raised and the alert of 4.6 fires.

### 3.5 Honest status (criterion 8)
DECISION: UI states map as: `accepted`/`sending` = "saved on this device, waiting to sync"; `synced` = "synced"; `conflicted` = "could not sync". "Synced" is shown only from a server answer of classes C1 or C2 (4.4). Local pending data is excluded from history, progress, coach replies and exports as canonical fact until `synced` (FU-AC-099), but is included in the device-only part of the export snapshot (criterion 14). Any record held (conflicted non-terminal, or `accepted` with a session-level hold) for more than 24 hours shows a persistent banner.

### 3.6 Hooks for lifecycle criteria (11 to 14), protocol part only
- DECISION: the queue store is keyed by UID; the sender takes a per-UID send lease before each attempt and releases it after the answer or cancellation. Sign-out and account deletion must acquire the lease exclusively (waiting for or cancelling the in-flight call) before releasing the UID binding or deleting data. A send never starts without the lease.
- DECISION: the queue file is excluded from OS backup and device-to-device restore (see 9, device restore).
- DECISION: on the server, an apply for a UID in deletion is refused (8.6), so a send racing with deletion cannot recreate data.

### 3.7 Age and size warnings (F11)
DECISION: the 400-record warning is computed in the acceptance transaction. The 25-day aging warning uses an age computed as `max(wallNow - acceptedAtLocalWallMs, monotonicAge)`, where `wallNow` is replaced by a persisted non-decreasing wall-clock high-water mark `wallHigh = max(wallHigh, wallNow)` written at every app start and every acceptance. Once the warning is raised it is latched in persistent storage (`ageWarningRaisedAt`) and cleared only when no non-synced record older than 25 days remains. A clock moved backwards, a reboot (monotonic reset) or a process restart cannot hide or reset it.

---

## 4. Server apply

### 4.1 Interface
DECISION (names are proposals): callable `submitWorkoutCommands({ sessionId, items: Envelope[<=25] })` returning one result per item in order; read-only callable `getWorkoutCommandOutcomes({ operationIds[<=50] })` for status after restart (reads the fence and receipts of the caller, applies nothing); `takeOverWorkoutWriter({ sessionId, deviceInstallId })`; `deleteWorkoutSession({ sessionId })`; `ackLegacyDrain({ deviceInstallId, migrationEpoch })`. Authentication is required on all; the UID is the authenticated UID only.

Every per-item answer, including non-terminal ones, carries `sessionState = { exists, writerEpoch, writerDeviceInstallId, sessionGeneration }` so a client can restamp its claims (F2, F8). DECISION: the same three fields are mirrored on the session document by the server (clients can read the document), so a synced view also shows them.

### 4.2 One Firestore transaction per item
All reads first, then all writes, in one `runTransaction` (the package already requires one atomic effect, `04_CORE_TDD.md` section 4). Steps:

1. Parse and validate: schema for the received `(protocolVersion, hashVersion, limitsVersion)`, ASCII ids, integer ranges (limits of 2.5, whose reps and grams values are the package proposals, FACT in `API_CONTRACTS.json` `x-boundaries.existing_domain`, labelled there as new schema limits needing domain review). Recompute `payloadHash`. Reject `payload.uid != auth.uid` with `UID_MISMATCH` and `operationId` whose `uidTag` differs from the tag of `auth.uid` with `ID_UID_MISMATCH`, in both cases before reading any receipt or fence (nothing is exposed). Invalid shape -> `INVALID_PAYLOAD` (client defect, nothing recorded). Retired version -> see 2.5 (after step 3).
2. Read `AccountCommandPolicy` (`users/{uid}/workout_command_policy/current`, package name, FACT in `05_DATA_MODEL.md` section 2). Absent, or account deleting, or `sendingPaused`, or the device not drain-acknowledged in state `DRAIN`: non-terminal `MIGRATION_HOLD` / `ACCOUNT_DELETING` (nothing recorded). Per-user rate limit (DECISION): more than 2,000 applied commands in the current UTC day, or more than 50 session creations in the current UTC day, returns non-terminal `RATE_LIMITED` with a retry-after time. It bounds fence growth under abuse; the 500-record backlog drain is below it. Counter location: one document per user per day, `users/{uid}/workout_command_counters/{utcDay}` with `applied` and `sessionsCreated`, read once at the start of each `submitWorkoutCommands` call and incremented once at its end by the number of items that committed, in its own small transaction (at most one write per call, so no hot document at the per-item rate). The limit is a soft abuse bound and may overshoot by one batch; it is not a correctness mechanism. The collection is carved out of the wildcard like the other command collections (5.3).
3. Read the fence shard (and its spill documents, 5.2) for the item. If an entry exists for the operation digest, go to the idempotency table 4.3 and return; no effect.
4. Read device/account revocation state (UNKNOWN: the existing server representation of device sessions; the package assumes one, `04_CORE_TDD.md` section 6). Revoked: non-terminal `AUTH_REVOKED`.
5. Read `workout_mutation_controls/{sessionId}` (`writerEpoch`, `writerDeviceInstallId`, `sessionGeneration`, `lastSeqByTarget`), the session tombstone `workout_session_tombstones/{sessionId}` (5.5), the session document, and the fence entries of each `dependsOn` id.
6. Decide, in this order:
   a. Document absent and this item has no `sessionInit`: if a `dependsOn` init operation is not in the fence -> non-terminal `DEPENDENCY_PENDING`; otherwise -> terminal `SESSION_DELETED`. This covers the case "init operation applied, session since deleted" and the case of a legacy-era client delete that left no tombstone (F7).
   b. Tombstone exists with `deletedGeneration >= sessionGenerationClaim`: if the claim is 0 and the item has `sessionInit` (the client never saw the old session) -> non-terminal `GENERATION_STALE` carrying `requiredGeneration = deletedGeneration + 1`; the client restamps the claim of every non-terminal record of that session and resends the same operations (F8). Otherwise -> terminal `SESSION_DELETED`.
   c. Writer check (F2): if `controls` is absent (a new session, or a legacy document not yet converted) the claim must be 0, and this device becomes writer at epoch 1 (the controls are created in step 8). If `controls` exists, `controls.writerDeviceInstallId` must equal the envelope `deviceInstallId` AND `writerEpochClaim` must equal `controls.writerEpoch` or be 0. Failure -> non-terminal `NOT_WRITER` with `sessionState`. A `sessionInit` against an existing typed document never overwrites its fields; the writer check still decides.
   d. Session status `abandoned` -> terminal `SESSION_CLOSED`.
   e. Dependencies (the rule of 3.4): a `dependsOn` entry absent from the fence -> non-terminal `DEPENDENCY_PENDING`. A `dependsOn` entry with code `R` or `S` does not by itself reject the item: the item is evaluated against its own preconditions in step 6g; if they fail and at least one dependency has code `R`, it is refused as terminal `DEPENDENCY_REJECTED`; if they hold it proceeds (F10: an identical re-add of an exercise already present, or a predecessor refused as `EXERCISE_ALREADY_IN_SESSION`, does not strand its dependents). If the preconditions fail with no refused dependency, the ordinary reason code of 7.1 is returned.
   f. Session size: if `controls.resolvedOps >= 2000` -> non-terminal `SESSION_COMMAND_LIMIT` (R3). `resolvedOps` is a field of the controls document, incremented in step 8 by every committed fence entry for the session (including `R` and `S`). Order: this check runs only after the fence read of step 3 missed, so a replay of an already-resolved operation is still answered by I2 to I4 even when the session is at the limit; it runs after the deletion and writer checks (6a to 6c), so a deleted session or a non-writer device gets the more specific answer.
   g. Operation preconditions of 7.1 -> terminal reasons, including the monotonic guard (F3): for SetDifficulty the target is `d:{exerciseId}`, for CORRECT it is `c:{setId}`; `lastSeqByTarget[target]` stores `(e, deviceInstallId, seq)` of the last applied command, where `e` is that command's effective accepted epoch. The item's effective epoch `e'` is its `acceptedWriterEpoch`, or `controls.writerEpoch` at apply time when that field is 0. The item is terminal `SUPERSEDED` (not applied) when `e' < e` (R4: after a takeover, commands accepted under an older epoch can never overwrite a value written under a newer epoch, even if the old device later retakes the role and its claim is restamped), or when `e' == e` and the stored device equals the item's `deviceInstallId` and the stored `seq` is greater than or equal to the item's `seq`. Otherwise it applies. `seq` is never compared between different installs (R5); with equal epochs and different installs the later applied command wins. Example A/B/A: A accepts `d:E` seq 5 under epoch 1 offline; B takes over (epoch 2) and applies a newer `d:E`; A retakes the role (epoch 3) and its seq-5 command is restamped to claim 3: it carries `acceptedWriterEpoch` 1, so `1 < 2` and the answer is `SUPERSEDED`; B's value remains.
7. Apply the one targeted mutation to the session document (create it if `sessionInit` is present and the document is absent and no blocking tombstone; convert a legacy-shaped document first, 8.3), increment `revision`, set `protocolVersion = 2`, mirror `writerEpoch`, `writerDeviceInstallId`, `sessionGeneration`, update `lastSeqByTarget` and `maxSeqSeen`.
8. Write the fence entry (code `C` for an applied command, `R` for terminal refusals, `S` for `SUPERSEDED`), increment `controls.resolvedOps`, write the detail receipt, the controls document when created, and the outbox record if the package requires one for this operation (`04_CORE_TDD.md` section 4). Steps 7 and 8 commit together or not at all.

DECISION: non-terminal results write nothing (no receipt, no fence entry). Terminal refusals write a fence entry with code `R` and a detail receipt with the reason, so a replay returns the same refusal even if preconditions later change (this keeps FU-AC-059 semantics). A transaction that loses a contention race is retried by the Firestore transaction loop and re-reads steps 3 to 6, so a paused or delayed request observes any newer fence entry or `lastSeqByTarget`.

### 4.3 Idempotency table
Key: the operation digest (5.2) within the caller's UID scope.

| # | Situation | Result | Effect | Recorded |
|---|---|---|---|---|
| I1 | no fence entry, valid, all rules pass | `COMMITTED` with receipt | one set / exercise / difficulty change | fence `C` + receipt |
| I2 | fence `C`, hash matches, receipt detail present | `ALREADY_COMMITTED` with the original receipt | none | none |
| I3 | fence `C`, hash prefix matches, detail expired | `ALREADY_COMMITTED_DETAIL_EXPIRED` (revision, time, reason unavailable) | none | none |
| I4 | fence `R`, hash matches | `ALREADY_REJECTED` (reason code if detail present, else `reason: UNAVAILABLE`) | none | none |
| I4b | fence `S`, hash matches | `SUPERSEDED`, with or without the receipt detail (the fence code alone carries it) | none | none |
| I5 | same `operationId`, different payload (hash differs from receipt, or prefix differs from fence) | `ID_PAYLOAD_MISMATCH`, no receipt contents exposed | none | none |
| I6 | an `operationId` presented under a UID other than the one it was minted for: either the envelope with `payload.uid != auth.uid` (`UID_MISMATCH`), or any payload whose `operationId` tag is not the tag of `auth.uid` (`ID_UID_MISMATCH`) | rejected before any read; nothing exposed | none | none |
| I7 | same `operationId`, session digest in the fence differs from `payload.sessionId` | `ID_SESSION_MISMATCH`, no receipt contents exposed | none | none |
| I8 | different `operationId`, same `logicalSetId`, mode APPEND, slot already holds a set (any origin) | terminal `DUPLICATE_LOGICAL_SET`; the existing set is untouched | none | fence `R` + receipt |
| I9 | different `operationId`, CORRECT of an existing `setId` | applies as its own operation (a correction is not a second completion) unless superseded (4.2 step 6g) | replaces values of that one set | fence `C` + receipt |
| I10 | different `operationId`, same payload otherwise (two devices, same logical set) | same as I8 | none | fence `R` |
| I11 | different `operationId`, AddEligibleExercise for an exercise already present with identical content | `COMMITTED` with `effect: NOOP_IDENTICAL`; dependents are satisfied | none | fence `C` + receipt |

I6 note (DECISION, FU-AC-095): ids are minted per UID by construction (the `uidTag`). A client that rewrites the payload to B's UID but keeps A's `operationId` is rejected as `ID_UID_MISMATCH`; a client that mints an id with B's tag has made a new, B-scoped identity and cannot reach A's data. No global id registry is needed.

### 4.4 Result classes returned to the client
| Class | Codes | Client state | Blocks |
|---|---|---|---|
| C1 applied | `COMMITTED` | `synced` | no |
| C2 already applied or obsolete | `ALREADY_COMMITTED`, `ALREADY_COMMITTED_DETAIL_EXPIRED`, `SUPERSEDED` | `synced`; for `SUPERSEDED` the ack summary sets `superseded = true` and the UI shows "replaced by a newer change", never the plain "synced" label (R4) | no |
| C3 refused (terminal, data state) | `ALREADY_REJECTED`, `SESSION_DELETED`, `SESSION_CLOSED`, `EXERCISE_NOT_IN_SESSION`, `EXERCISE_ALREADY_IN_SESSION`, `DUPLICATE_LOGICAL_SET`, `SET_NOT_FOUND`, `DEPENDENCY_REJECTED` | `conflicted`, terminal | only its dependents |
| C4 client defect (terminal-local, nothing recorded server-side) | `ID_PAYLOAD_MISMATCH`, `UID_MISMATCH`, `ID_UID_MISMATCH`, `ID_SESSION_MISMATCH`, `INVALID_PAYLOAD` | `conflicted`, terminal-local; kept for export; the build is flagged | only its dependents |
| C5a record-level non-terminal | `DEPENDENCY_PENDING`, `GENERATION_STALE`, `VERSION_RETIRED` | stays `accepted`; the client restamps or rebuilds (7.2, 2.5) and resends the same operation | only its dependents |
| C5b session-level non-terminal | `NOT_WRITER`, `MIGRATION_HOLD`, `AUTH_REVOKED`, `ACCOUNT_DELETING`, `RATE_LIMITED`, `SESSION_COMMAND_LIMIT` | `conflicted` non-terminal or `accepted` with a session hold per 7.2 | the whole session send loop |
| C6 retryable | transport error, `UNAVAILABLE`, `FENCE_SHARD_FULL` (only after the spill capacity of 5.2 is exhausted) | `accepted` with backoff | the whole session send loop |
| C7 not attempted | `NOT_ATTEMPTED` (an item after a C5b/C6 stop in the same batch, 4.5) | no state change: the record stays `accepted`; it says nothing about the record and is never an outcome | the whole session send loop (the stop that caused it) |
| C3b outcome unknown, replay closed | `OUTCOME_UNKNOWN_REPLAY_CLOSED` (5.4) | `conflicted`, terminal (never `synced`); current history shown separately | only its dependents |
| C8 unknown or future code | any code not listed in this table | treated as a retryable session hold (3.4): the record stays `accepted`, never `synced`, never terminal; alert (4.6) | the whole session send loop |

### 4.5 Batch semantics
DECISION: items of one call are processed in order, each in its own transaction. Processing continues after any C1 to C4 and C5a result; it stops at the first C5b or C6 result and the remaining items are returned as `NOT_ATTEMPTED`. Therefore a batch `[invalid, good1, good2]` returns `INVALID_PAYLOAD, COMMITTED, COMMITTED`.

### 4.6 Observability (F4)
DECISION: the server emits counters by result code per UTC hour (no payload fields, no UID in the metric labels) and an alert when `NOT_WRITER`, `MIGRATION_HOLD`, `GENERATION_STALE`, `VERSION_RETIRED` or `RATE_LIMITED` exceed 1% of answers in an hour, when any C4 code occurs (client defect), when a client reports an unknown result code (C8, a newer server or protocol than the client), and when any fence shard passes 50% fill (5.2). The client keeps local counters (oldest non-synced age in days, count by `lastResultCode`) and shows the banner of 3.5. UNKNOWN: whether any client telemetry may leave the device is a privacy decision of the privacy review; this document requires only the local counters.

---

## 5. Receipt retention and the replay fence

### 5.1 Why the package model cannot hold with a queue (B-02)
- FACT: the package makes admission last 2 minutes and requires, before the 90-day detail TTL, that every birth epoch is durably closed and replay "permanently inadmissible" (`04_CORE_TDD.md` sections 3 and 4; `05_DATA_MODEL.md` retention row). A command first sent after more than 2 minutes, or after the epoch close, is inadmissible there.
- FACT: the queue forbids eviction by age (LOCAL_QUEUE_DECISION criterion 3: the 30-day mark is a warning, not a deadline). A command accepted offline and unsent for 100 days must still be applied once.
- DECISION: so the fence must distinguish "never seen by the server" (apply) from "seen, applied or refused" (never apply again). A time-based or epoch-based inadmissibility cannot make this distinction and is dropped. Instead the fence records every operation the server has ever resolved, permanently, written in the same transaction as the effect.
- DECISION (invariant F1): a fence entry exists for an `operationId` if and only if the apply transaction for it committed (as `C` or `R`). Because the entry and the effect are one transaction, a fence miss proves "this operation was never applied", for any command age.

### 5.2 The compact fence (kept for the life of the account)
- DECISION: `users/{uid}/workout_command_fence/{shard}` with 256 primary documents at most, `shard` = two lowercase hex characters = first byte of `D = SHA-256("op1|" + operationId)`. Each document has one map field `e`: key = base64url of the first 16 bytes of `D` (22 characters), value = one string of 23 characters: 1 code character (`C` applied, `R` refused, `S` superseded), 11 characters base64url of the first 8 bytes of `SHA-256("s1|" + sessionId)`, 11 characters base64url of the first 8 bytes of the payload hash. A primary document also holds `spill` (integer 0..3).
- DECISION: size bound. One entry is about 45 bytes of payload (about 55 with field overhead). A user who logs 15 sets a day for 10 years makes about 55,000 entries, about 3 MB over 256 documents (about 12 KB each). The per-document guard is 12,000 entries (about 700 KB, below the 1 MiB document limit).
- DECISION (spill, F13): when a shard document reaches 12,000 entries the server creates `{shard}-1` (up to `{shard}-3`) and increments `spill` in the primary document; writes go to the newest spill document; a lookup reads the primary document and its `spill` documents (at most 4 reads). Only when all four are full does the server return non-terminal retryable `FENCE_SHARD_FULL` (fails closed, never evicts). Capacity per user is about 12 million operations. The server raises an alert when any primary shard passes 6,000 entries (50%, 4.6).
- DECISION: relation to the queue cap. The queue holds at most 500 unacknowledged commands (criterion 3); the fence has no count-based eviction at all, so it holds at least the 500 plus every earlier operation. This satisfies criterion 7 ("at least as many receipts per user as the queue can hold plus the retention window"). The 256-receipt proposal of the AI-Coach design is not adopted anywhere in this protocol. The per-user daily limits of 4.2 step 2 bound abusive growth.
- DECISION: the map field `e` is exempt from Firestore single-field indexing, to avoid the write cost of maintaining index entries. The earlier claim that indexing would cap a shard long before 1 MiB was wrong: UNKNOWN, reviewer-stated and to be confirmed against the Firestore limits of the pinned platform, each map leaf creates 2 index entries (ascending and descending), so 12,000 entries make 24,000 index entries, which is under the 40,000 per-document limit. UNKNOWN: confirm in the emulator and in a staging project that a write to the map key is atomic with the session write in one transaction.
- DECISION: the fence is deleted only with the account (the deletion framework, 8.6). It has no TTL.
- DECISION (collision, stated honestly): a fence hit for an operation that was never applied would silently lose that command. This needs the 128-bit key to collide with an existing key in the same shard (probability about n times 2 to the power -128 for n entries) and, for the answer to be I2/I3 instead of I5, also the 64-bit session digest and 64-bit hash prefix to agree. The probability is negligible; the design relies on that and does not claim the failure direction is harmless.

### 5.3 Detail receipt (cleanup only, not the correctness boundary)
- DECISION: `users/{uid}/workout_command_receipts/{operationId}` holds: `payloadHash` (full), `status` (`COMMITTED`, `REJECTED` or `SUPERSEDED`), `reasonCode`, `effect`, `sessionId`, `exerciseId`, `operation`, `logicalSetId`, `seq`, `deviceInstallId`, `revisionBefore`, `revisionAfter`, `serverTime`, `performedAtClientMs`, `clockSuspect`, and `expireAt = serverTime + 90 days`. It is deleted by a Firestore TTL policy (UNKNOWN: TTL policy availability; a scheduled sweep is the fallback). Package retention of 90 days is kept as the proposal (FACT: `05_DATA_MODEL.md` retention row); the closure precondition for deleting it is replaced by invariant F1, because the fence already outlives it.
- DECISION: collections `workout_command_fence`, `workout_command_receipts`, `workout_mutation_controls`, `workout_session_tombstones`, `workout_command_policy` are carved out of the wildcard rule (FACT that carve-outs are by name in `firestore.rules` lines 61 to 83) with `allow read, write: if false` for clients; clients obtain outcomes through the callables. The data a client needs to restamp claims (writer epoch, writer device, generation) is exposed through the session document mirror and the per-answer `sessionState` of 4.1.

### 5.4 What is answered for an expired detail
- DECISION: with the fence the historical outcome is known in coarse form. Fence `C` with no receipt -> `ALREADY_COMMITTED_DETAIL_EXPIRED` (I3). Fence `R` with no receipt -> `ALREADY_REJECTED` with `reason: UNAVAILABLE` (I4). Fence `S` with no receipt -> `SUPERSEDED` (I4b), not `ALREADY_REJECTED`. None of these re-applies. The client treats I3 as `synced`.
- DECISION: the package status `OUTCOME_EXPIRED` (FACT: `04_CORE_TDD.md` section 10 FC-01 and `API_CONTRACTS.json` `ExpiredHistoricalOutcome`) is kept only for the case where the server has no fence entry and cannot prove a miss means "never applied": operations accepted before this protocol existed, or after a restore of fence data that is older than the session data (not expected inside one Firestore database, since both are in the same database). In that case the server returns `OUTCOME_UNKNOWN_REPLAY_CLOSED`, never applies, and the client shows current canonical history and keeps the record `conflicted` terminal for export. UNKNOWN: whether a point-in-time restore of only some collections is ever performed; the runbook must forbid partial restores of these collections.
- This closes B-02 for the stated case: an acked-but-lost command replayed after 90 days hits the fence (I3), so no set is duplicated; a command unsent for 100 days misses the fence and is applied exactly once; a replay fence never claims an outcome it does not hold.

### 5.5 Session tombstones (same retention class)
DECISION: `users/{uid}/workout_session_tombstones/{sessionId}` = `{deletedGeneration, deletedAtServer}`, written by `deleteWorkoutSession` (8.4), kept for the life of the account, no workout payload. Size: one tiny document per deleted session. It is what prevents a late command from recreating a deleted session (criterion 9). The generation is client-observable through `GENERATION_STALE` and `SESSION_DELETED` answers (4.2 step 6) so that a legitimate new session on a reused deterministic id (`day_{dayId}`) is created at `deletedGeneration + 1` and is not refused forever.

---

## 6. Ordering and dependencies per session

- DECISION: `seq` is per device and per session. It orders delivery from one device and feeds the server guard of 4.2 step 6g. It is not a display order and is not comparable across devices. Display order inside an exercise is by `setIndex`; between exercises it is by the order of their addition on the server (document order), never by `seq` or arrival (F12). The server does not require `seq` to be contiguous (a locally discarded record leaves a gap and must not stall the session) and does not require `seq` order across independent commands; it records `seq` in the receipt and stores `maxSeqSeen` in `workout_mutation_controls/{sessionId}`.
- DECISION: correctness comes from explicit `dependsOn`, identity rules and the per-target guard, not from contiguity:
  - the first operation for a session carries `sessionInit`; every later operation of that session carries it in `dependsOn` until the creating operation is `synced`;
  - CompleteSet or SetDifficulty on an exercise added by a not-yet-synced AddEligibleExercise carries that operation in `dependsOn`;
  - a CORRECT carries the APPEND of the same `logicalSetId` in `dependsOn` while that APPEND is not `synced`. The longest chain (init, add, APPEND) is why the cap is 3 (F10). The server checks every listed dependency directly; transitive sufficiency is not assumed.
- DECISION: canonical order of sets inside an exercise is by `setIndex`, so reordered delivery of independent CompleteSet commands yields the same document (FU-AC-097).
- DECISION (R2): the single dependency rule. A missing dependency fence entry gives non-terminal `DEPENDENCY_PENDING`. A dependency with fence `R` or `S` does not reject the dependent by itself: the dependent is judged by its own preconditions (4.2 step 6e); it ends `DEPENDENCY_REJECTED` only if it needs something the predecessor failed to establish. Reconciliation with LOCAL_QUEUE_DECISION criterion 6 ("a dependent is not applied before its predecessor; if the earlier command is in conflict, dependents are held as could not sync, not applied"): the client holds dependents while the predecessor is unresolved or in a retryable conflict (3.4), so nothing is applied before the predecessor; when the predecessor is terminally refused, the criterion's tested case (the first command fails, the exercise is absent) ends with the dependents not applied and shown as "could not sync". The one refinement is the case where the dependency is satisfied anyway (the exercise already exists); there the dependent applies because its own preconditions hold. This is an interpretation of the criterion's intent (never apply on state the predecessor failed to establish); it is recorded in 11.3 item 9 with the literal alternative.
- DECISION (F3): last-writer semantics for SetDifficulty and CORRECT is enforced by the server guard, not by delivery order. A request that was abandoned by the client after a timeout may still be alive on the network; if a newer command from the same device and epoch has already been applied to the same target, the late older command is answered `SUPERSEDED` and changes nothing. Final difficulty therefore equals the newest command of the newest writer epoch, and within one epoch and one install the one with the highest `seq`; `seq` is not compared across installs and a command accepted under an older epoch never overwrites a newer-epoch value (4.2 step 6g).
- DECISION: to recover a chain after a terminal predecessor conflict the user resubmits the predecessor and its held dependents as new operations in one action; the client creates new ids, new `seq` and new `dependsOn` links and keeps `supersedes` links to the old records.

---

## 7. Conflict taxonomy and client behaviour

### 7.1 Server conditions
| Code | Condition | Terminal on server | Applies when |
|---|---|---|---|
| `SESSION_DELETED` | 4.2 step 6a/6b: document absent, no `sessionInit`, no pending init dependency; or tombstone generation >= claim with claim >= 1 or no `sessionInit` | yes (fence `R`) | any operation |
| `SESSION_CLOSED` | session `status = abandoned` | yes | any operation. FACT: statuses are `pending`, `completed`, `abandoned` (`workout_session.dart` line 11). DECISION: `completed` is not terminal because the player keeps appending to a completed session (`workout_player_page.dart` lines 664 to 686 and 948 to 959) |
| `EXERCISE_NOT_IN_SESSION` | CompleteSet/SetDifficulty on an exercise not in the document | yes | CompleteSet, SetDifficulty |
| `EXERCISE_ALREADY_IN_SESSION` | AddEligibleExercise for an exercise already present with different content | yes | AddEligibleExercise. Identical content is success (I11) |
| `DUPLICATE_LOGICAL_SET` | I8 / I10 | yes | CompleteSet APPEND |
| `SET_NOT_FOUND` | CORRECT of a `setId` not present | yes | CompleteSet CORRECT |
| `DEPENDENCY_REJECTED` | a dependency has fence `R` and the item's own preconditions fail | yes | any |
| `SUPERSEDED` | 4.2 step 6g | yes (fence `S`, reported as obsolete) | SetDifficulty, CORRECT |
| `NOT_WRITER` | `writerDeviceInstallId` differs or epoch claim differs | no | any |
| `GENERATION_STALE` | tombstone exists, claim 0, item has `sessionInit` | no | session-creating item |
| `DEPENDENCY_PENDING` | a dependency not yet in the fence | no | any |
| `MIGRATION_HOLD` | policy absent, paused, device not drained | no | any |
| `VERSION_RETIRED` | triple retired and fence miss (2.5) | no | any |
| `AUTH_REVOKED`, `ACCOUNT_DELETING` | revocation / deletion in progress | no | any |
| `RATE_LIMITED` | daily limits of 4.2 step 2 | no | any |
| `SESSION_COMMAND_LIMIT` | `controls.resolvedOps >= 2000` (DECISION; 4.2 step 6f) | no | any |
| `FENCE_SHARD_FULL` | all 4 documents of a shard are full | no | any |
| C4 codes of 4.4 | client defects | no (nothing recorded) | any |

### 7.2 Client behaviour
| Condition | Client state and message | User actions |
|---|---|---|
| any terminal code (C3) | `conflicted`, terminal, "could not sync", data kept visible | export, discard (confirmation), resubmit as a new operation (2.1) where the cause can change; never auto-retry |
| `SESSION_DELETED` | same; the client never recreates the deleted session under the old identity | "log into a new session" (a new-intent resubmission under a new session id with `supersedes` links, criterion 9 and F14), export, or discard |
| `GENERATION_STALE` | the client restamps `sessionGenerationClaim = requiredGeneration` on every non-terminal record of that session and resends with the same ids; no user action | none |
| `NOT_WRITER` | `conflicted`, non-terminal, session send loop paused, "another device is the writer"; the answer's `sessionState` is stored | "take over and sync" (calls `takeOverWorkoutWriter`, stores the new epoch and writer device, restamps `writerEpochClaim` on all records of the session, state back to `accepted`, same ids), or export, or discard |
| `DEPENDENCY_PENDING` | stays `accepted`, not shown as an error until it persists for 10 minutes while the dependency is `synced` locally | none |
| `DEPENDENCY_REJECTED` (dependent of a terminally refused predecessor, the predecessor did not establish what it needs) | `conflicted`, terminal, "could not sync", kept visible; it was sent only after the predecessor became terminal (3.4) and was judged by its own preconditions | export, discard, or the chain resubmission of section 6 |
| unknown or future code, `NOT_ATTEMPTED` | record stays `accepted`; unknown codes hold the session and raise the alert (3.4, 4.4 C7/C8) | none |
| `VERSION_RETIRED` | rebuild per 2.5 and resend | none |
| `MIGRATION_HOLD`, `AUTH_REVOKED`, `ACCOUNT_DELETING`, `RATE_LIMITED` | records stay `accepted`, session send loop paused with an explanation; the probe and automatic exit of 3.4 apply (no user action needed except sign-in for `AUTH_REVOKED`); the banner of 3.5 after 24 hours | wait, sign in again, export |
| `SESSION_COMMAND_LIMIT` | session send loop paused, "this workout has too many entries" | "start a new session and move the held entries" (new-intent resubmission into a new free session id, `supersedes` links), export, discard |
| `FENCE_SHARD_FULL` | treated as retryable with backoff; the alert of 4.6 requires an engineering response | wait |
| C4 client defect | `conflicted`, terminal-local, "internal error, data kept"; other records keep syncing | export; report |
| `ALREADY_COMMITTED_DETAIL_EXPIRED` | `synced` | none |
| `SUPERSEDED` | `synced` with `superseded = true`; label "replaced by a newer change", not "synced" | none |
| `OUTCOME_UNKNOWN_REPLAY_CLOSED` | `conflicted` terminal with a notice that the old confirmation is no longer available and current history is shown separately | export, discard |

### 7.3 Terminal rule
DECISION: every refusal caused by data state is terminal and recorded (fence `R`), and a replay returns the same refusal even if the state later changes. Refusals caused by who is asking or when (writer, generation, migration, auth, rate, version, dependency pending) are non-terminal and record nothing. This keeps every outcome of a given `operationId` unique over time.

---

## 8. Writer epoch and legacy-writer migration

### 8.1 Writer epoch bound to a device (F2)
- FACT: ADR-CMD-04 keeps one active writer per workout; an explicit takeover increments a session writer epoch that the commit transaction reads (`04_CORE_TDD.md` section 5; `15_DECISIONS_AND_RISKS.md` ADR-CMD-04).
- DECISION: `workout_mutation_controls/{sessionId}` holds `writerEpoch`, `writerDeviceInstallId`, `sessionGeneration`, `lastSeqByTarget`, `maxSeqSeen`. The writer check of 4.2 step 6c requires BOTH the writer device and the epoch. The values are mirrored on the session document and returned in every answer, so a client can read them (4.1).
- DECISION: first claim. A device that has never synced the session sends claim 0. If `controls` is absent (new session, or a legacy document before conversion), the first claim-0 item that reaches the server becomes the writer at epoch 1 (new session: it is also the creating item; legacy document: conversion per 8.3 in the same transaction). Any other device sending claim 0 afterwards, against existing controls, fails the writer check (`NOT_WRITER`), including a second device that created the same deterministic `day_{dayId}` offline: its `sessionInit` never overwrites the first device's document. Its user may take over.
- DECISION: `takeOverWorkoutWriter` increments `writerEpoch`, sets `writerDeviceInstallId`, and returns the new `sessionState`. The previous writer's queued commands are not lost and not applied; they end as `NOT_WRITER` and the user chooses takeover (then the same ids go out with the new claim) or export (UID binding is separate from writer role).
- Test requirement: two devices both at epoch 1, only A is writer: B's item gets `NOT_WRITER` even though its epoch claim equals 1.

### 8.2 Migration states
AccountCommandPolicy (`users/{uid}/workout_command_policy/current`, server-only) holds `migrationState`, `migrationEpoch`, `drainedDevices` (map `deviceInstallId` to `lastAckMs`, at most 20), `sendingPaused` (boolean), `drainStartedAtMs`, `pausedSinceMs`, `pausedTotalMs`. DECISION: exact states:

| State | Who may write `workout_sessions` | Typed commands | Entered by |
|---|---|---|---|
| `LEGACY_OPEN` (also: policy document absent) | client whole-document `.set` and client delete as today | refused `MIGRATION_HOLD`; the app queue feature flag is off for the account, so the old code path runs | default |
| `DRAIN` | client create and update only on documents with no `protocolVersion` (or lower than 2), never on a document that has `protocolVersion >= 2`; client DELETE is denied by rules for every id (deletes go through `deleteWorkoutSession`, which writes the tombstone, F7) | accepted only from a device present in `drainedDevices` | server cohort enrollment (operator action), only if precondition P1 of 8.5 holds |
| `SERVER_ONLY` | nobody from the client (create, update and delete denied for every `workout_sessions` id, including absent and newly invented ids) | accepted from any device of the new protocol | server, when the rule in 8.5 is met |
| `DELETING` | nobody from the client | refused `ACCOUNT_DELETING` | account deletion (8.6), reachable from any state, never left |

- DECISION: transitions are forward-only: `LEGACY_OPEN` -> `DRAIN` -> `SERVER_ONLY`; an attempted regression is refused. Any state may move to `DELETING` (8.6), which is terminal. `sendingPaused` is the rollback lever: it makes the server return `MIGRATION_HOLD`, queues keep accumulating on devices (nothing lost, bounded by the 500 cap), and voice and touch keep working locally. Reopening whole-document writers after any typed command has committed is forbidden (package rule, `04_CORE_TDD.md` section 7 and `14_INTEGRATION_MIGRATION_RUNBOOK.md` section 5).
- DECISION (F6): while `sendingPaused` is true the DRAIN clock is frozen: elapsed drain time is `now - drainStartedAtMs - pausedTotalMs - (pausedSinceMs if paused)`, and the cutover of 8.5 is forbidden. The 30-day period therefore counts only unpaused time.
- FACT: the package FC-02 puts the policy at the same path and requires rules to read trusted policy, not client protocol fields (`04_CORE_TDD.md` section 10). The DRAIN and SERVER_ONLY checks need `get()` of the policy document and of the session document inside rules. UNKNOWN: rule evaluation cost and the 10-`get()` limit must be checked in the emulator (FU-AC-063 wildcard OR bypass test applies).

### 8.3 Coexistence without overwrite or duplication
Risks and the DECISIONs that remove them:
1. Overwrite: a pending legacy whole-document `.set` flushes after a typed command was applied and erases the typed sets. Fix: in `DRAIN` and `SERVER_ONLY` the rule denies any client write to a document whose `protocolVersion >= 2`. The first typed apply sets `protocolVersion = 2` in the same transaction that applies the command. A late legacy write is therefore denied, never merged.
2. Lost legacy work (residual risk R-L1, accepted): that denial discards the legacy write on the old build. FACT: the old repository gives no signal: a write future that completes by timeout is treated as success and "a genuine server rejection after the timeout is not reported to this caller" (`firestore_workout_session_repository.dart` lines 61 to 71), so no error is shown on that device. Mitigations: the new client's drain barrier (8.4); the mandatory minimum-version gate (P1 of 8.5) which stops old builds from creating new pending writes once they are online; and the cutover condition of 8.5. The loss is limited to a write pending on an old build, for a session that was converted by a typed command before that write flushed, or still pending at cutover. It is documented in the release notes as accepted data loss (O-1, 11.1).
3. Conversion: when a typed command meets a legacy-shaped document (no `protocolVersion`), the apply transaction converts it first: assign set ids `legacy_{exerciseIndex}_{n}`, mark each existing set `source = LEGACY_UNVERIFIED` (package label, `05_DATA_MODEL.md` section 8), set `revision = 1`, `protocolVersion = 2`, create controls with `writerEpoch = 1`, `writerDeviceInstallId` of the first claimant and `sessionGeneration = 1`.
4. Duplication: a typed CompleteSet APPEND whose `logicalSetId` slot is already occupied by a `LEGACY_UNVERIFIED` set (FACT: the legacy player holds one set per exercise, so index 1 is the same physical set) is refused as `DUPLICATE_LOGICAL_SET` (I8); the user may fix it with a CORRECT command (new id). No value is guessed and no set is added twice.
5. New session ids: a legacy write for an id that the typed path created is denied by the same `protocolVersion` rule. A typed `sessionInit` for an id that already exists as a legacy document is treated as the conversion case (3), not as a create.
6. Deletions: in `LEGACY_OPEN` an old client may delete a session with no tombstone. A later typed item for that id sees an absent document and resolves to `SESSION_DELETED` by 4.2 step 6a, never creating the document. From `DRAIN` on, client deletes are denied and the callable writes the tombstone.

### 8.4 Drain barrier on the device and ack
- DECISION: a new-protocol client in a `DRAIN` account (a) stops issuing `.set` for the three operations (no direct fallback), (b) obtains a verified flush of its legacy write queue, (c) then calls `ackLegacyDrain({deviceInstallId, migrationEpoch})`, which records the device in `drainedDevices`. Until the ack, typed sends return `MIGRATION_HOLD`; local acceptance continues unaffected.
- DECISION (flush mechanism and fallback): the primary mechanism is the SDK `waitForPendingWrites`. UNKNOWN: its availability in the pinned `cloud_firestore` version and its behaviour offline are not verified, and the package warns that the SDK queue cannot be enumerated (`04_CORE_TDD.md` section 7). Fallback: write a marker document (`users/{uid}/sync_markers/{deviceInstallId}`, ordinary client collection) through the normal SDK path and wait for its server acknowledgement; UNKNOWN: this relies on the SDK acknowledging writes in submission order, to be verified in a test with an old-build stub. If neither can be verified, the new client does NOT enter `DRAIN`: it never sends `ackLegacyDrain`, typed sends stay `MIGRATION_HOLD`, the queue accumulates (bounded by 500) and the account cannot be cut over by the device condition of 8.5. A fresh install with an empty persistence cache acks immediately (nothing can be pending).
- DECISION (cap of 20): `drainedDevices` keeps at most 20 entries; on the 21st ack the entry with the oldest `lastAckMs` is evicted (an ack is evidence, not data; the evicted device, if it returns, re-runs the barrier and acks again). Reinstalls get a new `deviceInstallId` and ack immediately, so they cannot get stuck in `MIGRATION_HOLD` by the cap. A device that is not in the set shows "finishing update" and retries the barrier on each app start.
- DECISION: session deletion is the server operation `deleteWorkoutSession(sessionId)`, available from `DRAIN` on: in one transaction it deletes the document, writes the tombstone with `deletedGeneration = generation of the deleted session`, and deletes the controls. FACT: today delete is a plain client delete (`firestore_workout_session_repository.dart` lines 73 to 76); new builds switch to the callable when the account is in `DRAIN` or `SERVER_ONLY`.

### 8.5 Preconditions and cutover rule
Preconditions to enter `DRAIN` (fail closed: if any is not true the account stays `LEGACY_OPEN`):
- P1 (mandatory, F5): a minimum-version gate is live and has been live for at least 30 days. UNKNOWN: the app has no verified gate; if none exists, building one (a remotely set minimum build number checked at app start and on resume, which blocks the logging UI of older builds with an update prompt) is a deliverable of the rollout that precedes the first `DRAIN`.
- P2: the verified flush of 8.4 exists in the new client (either mechanism).
- P3: server rules and the carve-outs of 5.3 are deployed and covered by FU-AC-063 and FU-AC-119.

Cutover `DRAIN` -> `SERVER_ONLY` happens only when ALL hold: (a) unpaused DRAIN time is at least 30 days (operator decision O-1 of 2026-10-22); (b) `sendingPaused` is false (F6); (c) if a device-session registry exists (UNKNOWN), no device whose last seen build is older than the gate has been seen in the last 14 days, and every device seen in the last 90 days is in `drainedDevices`; if no registry exists, condition (c) is replaced by the 30-day gate of P1. Before the move, no automated data rewrite is done beyond the lazy conversion of 8.3.

### 8.6 Account deletion and fence
DECISION: account deletion sets `migrationState = DELETING` first (all applies return `ACCOUNT_DELETING`, 4.2 step 2), then the client sends are cancelled and the queue cleared, then server data including fence, receipts, controls, tombstones and sessions is deleted, the policy document last. An apply for a missing policy document is refused (`MIGRATION_HOLD`), so nothing is recreated after deletion completes (criterion 13). UNKNOWN: how the existing deletion framework (referenced as an extension point in `05_DATA_MODEL.md` section 2, row DeletionTombstone) would host this state; its code was not read.

### 8.7 New acceptance id
DECISION: the proof that legacy pending set writes and typed local commands cannot overwrite or duplicate each other's accepted effects is owed (`package-amendments/SUPERSESSION.csv`, row for FU-RQ-014: "OWED: not covered by FU-AC-095"). Propose FU-AC-119; scenarios in section 10.

---

## 9. Failure-mode table

| Event | Required behaviour | Mechanism |
|---|---|---|
| Lost ack (server applied, client never heard) | Retry with the same id and bytes; the server answers `ALREADY_COMMITTED` (or the detail-expired form after 90 days); exactly one set exists; local state ends `synced` | F1, I2/I3, 5 |
| Delayed duplicate request overtakes a newer one | The older SetDifficulty/CORRECT arrives after the newer one was applied: answered `SUPERSEDED`, final value is the newer | 4.2 step 6g |
| App kill mid-send | On restart `sending` records become `accepted` with `maybeSent = true` and resend with the same bytes; the outcome is the same as lost ack or never-arrived | 3.2 |
| App kill during acceptance | Either the whole record exists (shown pending) or nothing (reported "not saved"); no seq or set-context change is kept without a record | 3.3 |
| Double tap, duplicate voice callback | One APPEND; the second intent is a no-op (identical values) or a CORRECT (different values) | 3.3 |
| Network drop inside a batch | Items already answered keep their state; the rest stay `accepted` | 4.5 |
| Clock skew on the device | No server decision uses client time. Order uses `setIndex` and, per device, `seq`. `performedAtClientMs` is stored as informational; if it is more than 5 minutes after `serverTime` or more than 400 days before it, `clockSuspect = true` is stored and the value is still kept (DECISION). Aging warning per 3.7: persisted high-water mark and latch, not hidden by a backwards clock | 2.4, 3.7, 6 |
| Server clock | Receipt `expireAt` uses server time only | 5.3 |
| Device restore or new phone | The queue is excluded from OS backup. If a restored copy appears anyway (UNKNOWN platform guarantee), replays are harmless because of the fence; the risk is that commands the user had discarded come back. The client binds the queue to a `deviceInstallId` stored outside backup. DECISION (R5): on a mismatch every record keeps its `operationId`, bytes, `seq` and `acceptedWriterEpoch`; its `originDeviceInstallId` stays as informational history; it is marked `conflicted` non-terminal "restored from backup, review before sending" and nothing is sent automatically. After the user reviews, records are sent with the CURRENT install's `deviceInstallId` as the transport identity, and each session first requires an explicit `takeOverWorkoutWriter` (the new install is not the writer). The old install's identity is never replayed. The server seq guard never compares `seq` across different installs (4.2 step 6g), so a restored `seq` cannot collide with the old install's; duplicates of already-applied commands are removed by the fence, not by `seq`. Residual risk: with equal epochs and different installs the later applied command wins for `d:`/`c:` targets, which is why the review step is mandatory | 3.6, 5, 4.2 step 6g |
| Second device, same account | Second device is read-only unless takeover; offline it may still accept, then gets `NOT_WRITER` (even at the same epoch number). Both devices logging the same set give `DUPLICATE_LOGICAL_SET` on the later one | 7, 8.1 |
| Long offline (over 90 days) | Command never seen: fence miss, applied once. Seen and acked-but-lost: fence hit, no duplicate | 5.1 to 5.4 |
| Session deleted elsewhere meanwhile | `SESSION_DELETED`, kept, offered "log into a new session", never recreated under the old identity; a fresh device logging a reused `day_{dayId}` gets `GENERATION_STALE` and then a new generation | 5.5, 7 |
| Sign-out or deletion during a send | Lease is held exclusively before releasing the UID; the in-flight call finishes or is cancelled; a call that was already on the wire is resolved by the fence on next sign-in | 3.6, 8.6 |
| Fence shard full | Spill documents first; only after 4 full documents a retryable hold with an alert, nothing evicted | 5.2 |
| Legacy write races a typed command | Legacy write denied by rule, typed effect intact; the old build is not told (R-L1) | 8.3 |
| App upgrade with a queue | Unsent records are rebuilt under the current version with the same ids; sent records keep their bytes | 2.5 |
| Migration paused | Records stay `accepted`, the DRAIN clock is frozen, cutover is forbidden | 8.2 |
| Server rejects as `INVALID_PAYLOAD` | Client defect; record kept `conflicted`, independent records keep syncing; release blocked in test (FU-AC-095 vectors) | 4.4 |

---

## 10. Test obligations

All cases are NOT_RUN. Each case must name the exact implementation SHA, as every row of `ACCEPTANCE_AMENDMENTS.csv` requires. For each row the scenario below must FAIL on a build that breaks the stated guard.

| ID | Concrete failing scenario (what must fail if the design is broken) |
|---|---|
| FU-AC-092 | Airplane mode 20 minutes, 15 CompleteSet taps (touch and voice mixed) on 15 distinct (exercise, set context) pairs. While the "next set" UI is absent the 15 sets are 15 different exercises; the multi-set variant (same exercise, "next set" between taps) is gated on that UI. Each tap shows "pending sync" and the rest timer starts with zero network calls recorded. Reconnect: server holds exactly 15 sets, queue has 0 non-synced records. Fails if any set is missing, doubled, or if a tap waited on the network. |
| FU-AC-093 | Kill the process (a) between the store transaction start and commit, (b) right after commit, (c) MANDATORY: forced device reboot or an equivalent hard power loss on a physical test device during a burst of acceptances. After restart every set shown "pending" before the kill is present with identical bytes and hash; a command killed in (a) is absent and the user was told "not saved". Fails if a half record exists, if `seq` or the set context changed without a record, or "pending" was shown before the commit returned. A run without (c) is not a pass. |
| FU-AC-094 | Fill 500 records, try the 501st: refused with a message before any record is created, all 500 intact. Warnings at 400 and when the oldest is 25 days old: clock moved forward 31 days, process restarted, clock moved backward, process restarted again, device rebooted: the warning is still shown (latched). A session at 2,000 resolved operations answers `SESSION_COMMAND_LIMIT` and the user can start a new session and move the held entries; none lost. Fails if any record disappears, the 501st is accepted, the warning clears, or the session-limit path loses entries. |
| FU-AC-095 | (a) Send the same record 3 times with the same bytes: one effect, identical receipt. (b) Same `operationId` with `loadGrams` changed: `ID_PAYLOAD_MISMATCH`, no receipt contents in the answer, the stored set unchanged. (c) A's envelope under B's authentication: `UID_MISMATCH`; and A's `operationId` placed in a payload rewritten to B's UID: `ID_UID_MISMATCH`, both with B's data unchanged and no A receipt exposed (strong reading: an identity minted for A is rejected under every other UID). (d) Same `operationId` with another `sessionId`: `ID_SESSION_MISMATCH`. (e) Hash version 2 golden vectors agree between Dart and the server byte for byte; `expectedRevision`, `writerEpoch` and `sessionGeneration` are absent from the hash input. (f) CI replay: a golden queued payload produced by the oldest shipped build is replayed against the current server and returns the recorded answer; with a retired version and a fence miss the answer is `VERSION_RETIRED` and the rebuilt record (same id) applies once. Fails if any of (a) to (f) differs. |
| FU-AC-096 | (a) Server applies, ack dropped, client retries: one set. (b) Two CompleteSet taps within 100 ms on the same set context, and separately two identical voice-callback deliveries of the same recognition result: each ends with exactly one APPEND and at most one CORRECT (identical values: no second record); the test must FAIL on a build that allocates "next free index", which would produce `:1` and `:2` and two applied sets. (c) Two devices, different `operationId`, same `logicalSetId`: the second ends `conflicted` `DUPLICATE_LOGICAL_SET`, the first set value unchanged; plus the two-device deterministic `day_{dayId}` case: both devices create the session offline, the first to reach the server becomes writer at epoch 1, the second gets `NOT_WRITER` and its `sessionInit` does not overwrite the document. (d) Process killed between `sending` and the answer, then restart: one set. (e) R1a: tap with values X, then Y, then X on the same set context: the records are APPEND(X), CORRECT(Y), CORRECT(X) and the server set ends as X. (f) R1b: sync an APPEND, simulate 8 days so the record is pruned, then tap new values on the same context: a CORRECT is created and applied, not `DUPLICATE_LOGICAL_SET`, and the queue contains no second APPEND. (g) R1c: deliver the same recognition result id twice, once before and once after the "next set" action: exactly one set exists and no phantom APPEND at the next index (gated on the "next set" UI for the after-`next set` half). (h) R5: restore a queue onto a new install while the old install is still online: every restored record is held `conflicted` until the user reviews; after takeover they are sent with the new install's id only; no guard collision, no double apply, and the old install's id is never sent. Fails if the session has two sets at the slot in any case, if X, Y, X ends as Y, or if any restored record is sent without an explicit takeover. |
| FU-AC-097 | Queue: init+AddEligibleExercise(op1), CompleteSet(op2, dependsOn op1), SetDifficulty(op3, dependsOn op1). Deliver 2 before 1: `DEPENDENCY_PENDING`, nothing applied. Make op1 terminal-fail with the exercise absent: op2 and op3 end `conflicted` `DEPENDENCY_REJECTED`, not applied; with the exercise already present (identical re-add, I11) they apply. Chain init, add, APPEND, CORRECT carries 3 dependencies and all are verified. Deliver two independent CompleteSet commands (setIndex 1 and 2) in reverse order: document has sets in setIndex order. Batch `[invalid, good1, good2]` returns `INVALID_PAYLOAD, COMMITTED, COMMITTED`: both good records reach `synced` and only the invalid one is `conflicted`. Ordering race (F3): SetDifficulty `d1` seq 5 and `d2` seq 6 in a batch; the batch is delayed, the client times out and resends; pause the first request inside the transaction after its reads, let the resend commit `d1` and `d2`, then release the paused request; repeat with the late request carrying `d1`: final difficulty is always `d2` and the late `d1` is answered `SUPERSEDED`. Persistent counter (F12): log, sync, prune the synced records, log another set: `seq` continues, display order is by `setIndex`. R2: a predecessor AddEligibleExercise refused as `EXERCISE_ALREADY_IN_SESSION` (the exercise already exists with different content) with a CompleteSet and a SetDifficulty depending on it: the dependents are held while the predecessor is unresolved, sent once it is terminal, and both apply; final state on the client is predecessor `conflicted` terminal, dependents `synced`, and on the server the exercise holds the existing content, one new set and the new difficulty; with the exercise absent the same dependents end `DEPENDENCY_REJECTED` and nothing is applied. R4: A/B/A takeover with A's old seq-5 `d:E` command (accepted under epoch 1) after B's newer `d:E` under epoch 2 and A's retake at epoch 3: the answer is `SUPERSEDED` and B's value stays; replay the same command after the simulated receipt TTL: still `SUPERSEDED`, not `ALREADY_REJECTED` and not `UNAVAILABLE`; the UI shows "replaced by a newer change". Fails if a dependent applies first, order follows arrival or `seq`, an invalid record blocks independent records, the final difficulty is `d1`, or the old-epoch command overwrites B. |
| FU-AC-098 | Accept 500 commands; resolve 300 successfully, then apply 300 more (more than 256 newer); then replay the original 500 in random order: every replay returns an already-applied class, zero new sets. Then delete every detail receipt older than 90 days (simulated TTL), replay the 500 again: `ALREADY_COMMITTED_DETAIL_EXPIRED`, zero new sets. Then a command held 100 days that the server never saw: applied exactly once. Fence entry written in the same transaction as the effect (fault injection: abort after the effect write; both or neither). Shard-full scenario (F13): fill one primary shard to 12,000 entries in a test fixture, apply a new command that hashes to that shard: it lands in `{shard}-1`, a replay of an old command in the primary shard still returns already-applied, a replay of the new one is found through the `spill` lookup; fill all four documents: `FENCE_SHARD_FULL`, retryable, nothing evicted; alert at 6,000. Per-user limits: the 2,001st applied command of a UTC day returns `RATE_LIMITED` with a retry-after; the records stay `accepted`, the sender probes with capped backoff, and after the retry-after (day rollover in the test) they drain automatically with no user action, each applied once. Session limit (R3): in the emulator, a session with `resolvedOps = 2000` answers `SESSION_COMMAND_LIMIT` for a new command while a replay of an already-resolved command is still answered by the fence; the user moves the held entries to a new session. Unknown code (R3): a stub server answering a code from a newer protocol keeps the record `accepted`, never `synced`, raises the local counter and the alert. Superseded fence (R4): a SUPERSEDED command replayed after the simulated receipt TTL returns `SUPERSEDED`. Fails if any replay applies, if a never-seen old command is rejected for age, if any entry is evicted, if a hold needs user action to clear, or if an unknown code marks a record synced. |
| FU-AC-099 | While pending, history, progress, coach context and server-side exports contain no pending set; the device-side export snapshot lists it as pending. "Synced" appears only after a C1/C2 answer; with the server answering `MIGRATION_HOLD` the UI never says synced. Fails otherwise. |
| FU-AC-100 | Offline log a set and start rest; delete the session from another device; reconnect: `SESSION_DELETED`, the set remains visible and exportable, the user is offered "log into a new session" and that resubmission applies under a new session id, server history and volume metrics contain only committed effects, no document at the old `workout_sessions/{id}` exists. Also: session `abandoned` elsewhere: `SESSION_CLOSED`. Also (F8): delete `day_X` on device A, then a fresh device B that never saw it logs offline on `day_X` (claim 0 with `sessionInit`): the answer is `GENERATION_STALE` with `requiredGeneration` 2, B restamps and the same operations apply to a new generation-2 session; a stale queue from A with claim 1 on `day_X` stays `SESSION_DELETED`. Also (F7): a legacy-era client delete (no tombstone) followed by a typed item for that id returns `SESSION_DELETED` and creates no document; in `DRAIN` a direct client delete is denied and `deleteWorkoutSession` writes the tombstone. Fails if any document is created for the deleted generation. |
| FU-AC-101 | One shared entry point: a voice-originated CompleteSet and a touch-originated one produce records differing only in `body.source`, written by the same code path (coverage assertion on the accept function). Two taps within 100 ms and two identical voice-callback deliveries each end with exactly one APPEND and at most one CORRECT; the test must fail on a build that allocates the next free index. StartSet by voice or touch: queue size unchanged, no receipt, no completed set. Fails if a voice path writes without the queue, a duplicate callback creates a second set, or a StartSet creates a record. |
| FU-AC-119 (NEW, proposed) | Migration proof for legacy writers and typed commands, under `DRAIN` and `SERVER_ONLY`. Scenarios: (1) a legacy device holds a pending whole-document `.set` for session S while a typed command for S is applied and converts S; the legacy write then flushes: it is denied by rules and S keeps the typed sets (no overwrite). (2) Reverse order: legacy write lands first, typed command converts it: legacy sets are `LEGACY_UNVERIFIED`, a typed APPEND at the same slot returns `DUPLICATE_LOGICAL_SET`, no set doubled. (3) In `SERVER_ONLY` a client create/update/delete of any `workout_sessions` id, including a never-seen id, is denied under every matching rule (wildcard OR bypass); in `DRAIN` a client delete is denied. (4) A typed command from a device not in `drainedDevices` returns `MIGRATION_HOLD`, stays queued, applies after the ack; a 21st device evicts the oldest entry, and a reinstall acks immediately. (5) `sendingPaused = true`: 15 commands accepted and kept, none applied; the DRAIN clock does not advance while paused and a cutover attempt at day 30 of calendar time with 5 paused days is refused; after unpausing 15 sets exist once each. (6) Attempted state regression `SERVER_ONLY` -> `DRAIN` is refused. (7) Old-build stub: a pending `.set` is flushed after a typed convert of the same session; it is denied, typed data is intact, and the loss is recorded in the test result as residual risk R-L1 (the old build shows nothing, FACT 1.3). (8) A device offline across the cutover with a pending legacy `.set`: either the cutover is blocked by condition (c) of 8.5 when a registry shows that device within 14 days, or the loss occurs and is listed in the release notes; the test asserts whichever mechanism the build implements and fails if neither happens. (9) Enter `DRAIN` with the verified flush unavailable: the account stays out of `DRAIN`, no ack is sent, typed sends stay held. (10) Enter `DRAIN` without the minimum-version gate: refused (P1). Fails if any set is lost, doubled, or a legacy write is accepted after typed data exists. Requires `package-amendments/ACCEPTANCE_AMENDMENTS.csv` row FU-AC-119 and a `SUPERSESSION.csv` update, at priority P0, parent FU-RQ-014 / FU-014. |

Cross-reference with existing package rows (FACT, `registers/ACCEPTANCE.csv`): FU-AC-012 (terminal close vs late commit), 058 (closed epoch after TTL), 060 (closure races effect), 057 (lost prepare response) are about the withdrawn admission model and need rewriting for this protocol (FU-AC-058 -> "fence after detail TTL", FU-AC-057 -> "lost ack with same operationId"); FU-AC-014, 063, 081 to 083 stay and are extended by FU-AC-119.

---

## 11. Open questions and unknowns

### 11.1 Questions that needed an operator decision
- O-1 (DECIDED by the operator on 2026-10-22): the `DRAIN` period is 30 days of unpaused time (8.2); after it, when the other cutover conditions of 8.5 hold, the account moves to `SERVER_ONLY`. Correction to version 1.0: the earlier text "with an error shown there" was wrong. FACT (1.3): the old repository swallows the 4 second timeout and reports no later rejection, so an old build whose pending legacy write is denied after a typed convert or at cutover shows nothing. The consequence of O-1 is therefore stated as accepted data loss R-L1 (8.3 item 2): a legacy write pending on a never-updated old build can be lost silently. It is reduced by the mandatory minimum-version gate (P1), the verified flush on new builds, and the registry condition (c); it is not eliminated, and it must be named in the release notes. No further operator decision is needed.

Everything else above is a DECISION of this document and can be changed only by editing it.

### 11.2 Explicit unknowns (engineering must verify, none blocks writing the code)
1. Local store engine and its durability guarantee (3.3).
2. Firestore index exemption for the fence map, the per-document index entry limit (reviewer states 40,000; 12,000 entries times 2 = 24,000) and the 1 MiB behaviour (5.2); TTL policy availability (5.3).
3. `waitForPendingWrites` availability and offline behaviour in the pinned SDK; ordered acknowledgement for the marker-write fallback; no verified way to enumerate the SDK write queue (8.4).
4. Existence of a device-session registry, a minimum-version gate (mandatory for `DRAIN`, 8.5 P1), and the shape of the existing deletion framework (8.5, 8.6, 4.2 step 4).
5. Rule evaluation cost of `get()` calls for the DRAIN/SERVER_ONLY checks (8.2).
6. Whether any existing function in `functions/src` writes `workout_sessions` (1.3).
7. Deployed Cloud Functions runtime and billing for the extra writes per command (fence, receipt, session, controls: four document writes per command); no measurement exists.
8. Whether v1 introduces an explicit "workout finished" terminal state; today `completed` is appendable (7.1). If it does, `SESSION_CLOSED` extends to it and the player flow changes.
9. Any future set-deletion feature must write a set tombstone in the same transaction, otherwise I8 can re-apply a deleted slot.
10. The UI for the explicit "next set" action and for the CORRECT flow (3.3); the 24-hour banner text; whether client telemetry beyond local counters is permitted (4.6).
11. Whether a client can distinguish at runtime a clean re-install from a restore (3.6, 9); the platform backup exclusion mechanism for the queue file.

### 11.3 Contradictions found in the inputs
1. Package v1 canonical payload includes `expectedRevision`, `writerEpoch` and `sessionGeneration` (`COMMAND_GOLDEN_VECTORS.json`, `API_CONTRACTS.json`), which an offline-accepted command cannot know or keep stable across retries. Resolved by hashVersion 2 (2.2).
2. The package 2-minute admission plus closed birth epoch before the 90-day TTL (`04_CORE_TDD.md` sections 3, 4; `05_DATA_MODEL.md` retention row) makes any command unsent past the window permanently inadmissible, which contradicts "no silent eviction" and the 30-day warning (LOCAL_QUEUE_DECISION criterion 3). Resolved by the fence invariant F1 (5.1).
3. `04_CORE_TDD.md` FC-01 says the epoch fence alone gives `OUTCOME_EXPIRED` without historical outcome. This design stores a coarse outcome in the fence and so can answer more precisely; `OUTCOME_EXPIRED` survives only for the no-entry-but-unprovable case (5.4). Needs the package author to update FC-01 and `API_CONTRACTS.json` `ExpiredHistoricalOutcome`.
4. LOCAL_QUEUE_DECISION criterion 4 (id never changes across retries) versus criterion 9 ("kept in the queue for retry"): reconciled by separating transport retry (same id) from user resubmission after a terminal conflict (new id, `supersedes` link) (2.1).
5. The package data model assumes stable set ids and an increasing revision (`05_DATA_MODEL.md` section 8); FACT: the current document has neither (1.3). The design therefore adds a lazy conversion with `LEGACY_UNVERIFIED` sets (8.3), and requires the readers listed in the package migration contract to ship before the flag is on.
6. Current player behaviour (one set per exercise, re-tap overwrites, FACT 1.3) versus "one logical set, one completion, tap twice = one set": resolved by the set-context rule (3.3): a repeat tap on the same context with identical values is a no-op, with different values a CORRECT; only an explicit "next set" action creates a new index. UNKNOWN: the exact UI for these.
7. `SUPERSESSION.csv` marks the migration proof as owed without an id; this document proposes FU-AC-119 (section 10).
8. Version 1.0 of this document claimed that a false fence hit is "safe" and that head-of-line delivery gives apply order; both were wrong and are corrected in 5.2 and 6.
9. LOCAL_QUEUE_DECISION criterion 6 says that when an earlier command is in conflict its dependents are held as "could not sync" and not applied. This document applies the dependents only when their own preconditions hold on the server (for example the exercise exists anyway). It is an interpretation of the criterion's intent, applied in 3.4, 4.2 step 6e and 6. The literal alternative is a one-line client change: hold every dependent of a terminally refused predecessor as `conflicted` "could not sync" and let the user resubmit it (section 6). If the operator wants the literal reading, switch to it; no server change is needed.
10. Version 1.1 left `migrationState = DELETING` out of the state list of 8.2, the rate-limit counter location unspecified and the `uidTag` privacy status unstated; 1.2 adds the state (8.2), the counter document (4.2 step 2) and 2.6.
