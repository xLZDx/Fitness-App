# Pre-implementation conditions (2026-10-22)

Status: PROPOSED, NOT IMPLEMENTED. Source: the independent pre-implementation review of 2026-10-22 (verdict NO-GO for the full implementation as specified; 2 BLOCKER, 11 MAJOR; the review saw only the supplied documents, not the repository code). This document records how each finding is closed, what is still a precondition, the order of work and the first vertical slice. Owners are roles, not people.

## 1. Closure table

| Finding | Closed by | State |
|---|---|---|
| PI-B01 trigger failure can lose an overwritten legacy snapshot | Protocol 8.3 item 12: the guarantee is "no SILENT loss" with four layers (retries, 10-minute watchdog, gap records plus alert plus owner-visible disclosure, point-in-time recovery window) and residual risk O-R2; FU-AC-119 scenario S26 | design closed; facts to verify in item 4 |
| PI-B02 account deletion reopens the direct-write path | Protocol 8.7: `deleted_accounts/{uid}` fence created first, checked by rules and by every server writer, expires by TTL 24 h after completion; scenario S25 | design closed; rules and TTL to verify |
| PI-M01 rules for the new collections | Protocol 5.3: rules plus negative tests are a deploy prerequisite of the first callable; the carve-out change is the first item of the queue sprint (the operator's deferral is kept) | design closed |
| PI-M02 origin install and epoch not bound | Protocol 2.2, 2.3, 4.2 step 6g: `originDeviceInstallId` is hashed, the envelope copy is removed, a future `acceptedEpoch` is `INVALID_PAYLOAD` | design closed; golden vectors owed |
| PI-M03 rate limit overshoot | Protocol 4.2 step 2: counter read and incremented inside the per-item transaction, exact limit | design closed |
| PI-M04 T17 versus fixture | FU-AC-125 text (protocol section 10 and reissued CSV): failure only when neither an export nor the distinct confirmation exists | closed |
| PI-M05 scenario 21 oracle | One deterministic expectation per run (createTime available or not); deploy check fails closed | closed |
| PI-M06 free text in the queue | Protocol 2.2: `titleKey` from a closed set, no free text | closed |
| PI-M07 FU-AC-119 too coarse | Scenario manifest `queue_migration_scenarios.json` with ids S01 to S26 and an aggregator that fails on a missing id | design closed; the file is created in the queue sprint |
| PI-M08 release scope | Section 3 below: no release-reachability claim until FU-AC-130 to 140 are executed against real release defines; `DEMO_FEATURES` and the recorder port are checked | condition |
| PI-M09 ML baseline | Section 4 below | condition |
| PI-M10 runtime baseline | `SOURCE_RUNTIME_MANIFEST_2026-10-22.md` refreshed (section 6 there); canary and rollback drill listed in section 5 | refreshed; drill owed |
| PI-M11 prerequisites not sequenced | Section 2 below | sequenced |

## 2. Order of work (dependencies first)

1. Foundations that can start now and do not change user behaviour: choose and prove the local transactional store (unique indexes, commit durability, interruption recovery, OS backup exclusion on Android and iOS); define the secure-token-store interface; start the minimum-version gate (its 30-day clock in the migration is a calendar dependency, so it starts early; no account enters `DRAIN` in the first slice).
2. Freeze the executable contract: `queue_protocol_fixture.json` and golden canonical payloads (hashVersion 2 including the origin install), the T17 branches, the DELETE outcomes of scenario 21, and the scenario manifest. Dart and server tests iterate the same files.
3. Rules before callables: carve-outs for every new collection (5.3, including `deleted_accounts`, summary and head documents) with negative tests (FU-AC-063) deployed to the dev project BEFORE any callable that writes those collections.
4. Verify the platform facts the design leans on, each with a recorded result: trigger SDK exposes `before.createTime`; trigger retry window; TTL policy availability; point-in-time recovery and data-write audit logs; secret store and rotation for the HMAC seal key; `waitForPendingWrites` in the pinned `cloud_firestore`; existence of a minimum-version gate and a device registry; whether `deleteAccount` can host a begin step (O-02 below).
5. Only then the server apply path, then the mobile sender, then the migration states. Voice, attendance and the module-matrix work follow their own rows.

## 3. Release scope (PI-M08)

The module matrix is a partial trace. Until FU-AC-130 to 140 have run against real release build defines, direct routes, resume paths, keyboard actions and the recorder port, no document may state that every KEEP module is reachable and every HIDE module is closed. Build-time bypasses (`DEMO_FEATURES`, recorder-enabled builds exposing hiking and cycling) are a release gate, not a note.

## 4. ML and AI baseline (PI-M09)

Before any change to recognition behaviour: hash the packaged TFLite asset, resolve its training lineage, create its entry in the model registry (`core/ml/MODEL_REGISTRY.json`), and record which model was evaluated versus which one ships (the architecture document reports a 10-class shipped model and a 29-class measured one). A recognition result is never promoted to an automatic decision without a registered model, an independent evaluation tied to that exact version and a stated abstention and fallback behaviour. New continuous retraining telemetry is out of v1 (decision O-03).

## 5. Runtime and operations (PI-M10)

The dev project was brought to the master code on 2026-10-22 (see the manifest). Owed before enabling any new feature: a diff of every deployed function and its configuration against its expected source; the two equipment-identity functions rebuilt from master (blocked by the stale `P1_SNAPSHOT_STALE` snapshot copy and the Windows predeploy quirk); the scheduler 403 for the canary and enforcement-state jobs resolved or consciously accepted with a written reason; one executed rollback drill. `ACTIVE` and `nodejs22` are runtime facts, not proof of functional parity.

## 6. First vertical slice V0

One `CompleteSet` for one user, one session, one exercise, one logical set: local durable commit, canonical payload, stable operation id, minimal server fence and receipt, pending and synced display behind an interface, lost acknowledgement, identical replay. Negative evidence required: crash before and after the local commit; lost response; second identical submission; altered payload under the same id; uid mismatch; second APPEND to the same logical set; server mutation and receipt in one transaction. Excluded: any feature activation, `DRAIN`, backfill, voice and ML work, account-deletion changes, route refactors. Exit: the slice passes deterministic Dart and server tests and emulator tests on the same revision, and no new collection is writable through the owner wildcard.

## 7. Operator decisions still open

| Id | Decision | Options and consequence | Recommendation |
|---|---|---|---|
| O-01 | Typed canonical session with a client-writable projection | accept the departure from the original package, or redesign preservation; refusing without an alternative conflicts with the no-silent-loss decision | accept, subject to the items above |
| O-02 | Dedicated begin-deletion step | a dedicated irreversible begin step protects pending commands and payment pre-checks; the fallback may leave a live account with an empty queue after a failed final delete | dedicated begin step |
| O-03 | New ML telemetry | defer, or authorise narrowly with consent changes | defer in v1 |
| O-04 | Wear OS in the v1 release | include with signing, pairing and mutation-path acceptance, or defer | decide before Wear release work, not before V0 |
| O-05 | Queue encryption at rest | OS sandbox only (proposal), or an app-level key with a tested key-loss recovery | privacy sign-off on the proposal |
| O-06 | Equipment recognition automation | manual review of confirmed or text-anchored results, or validated automatic recognition at a stated threshold | no automatic promotion of unverified model output |
| O-R2 | Residual risk of section 8.3 item 12 (a snapshot overwritten between two watchdog runs whose event failed permanently, found after the recovery window) | accept as disclosed risk, or require a stronger mechanism (not available for old clients) | accept as disclosed |
