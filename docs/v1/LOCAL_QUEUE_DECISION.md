# Decision: durable local queue for set logging (2026-10-21)

Decision (operator, 2026-10-21): accept a durable local queue for the three workout commands that the rebaseline package made online-only (CompleteSet, AddEligibleExercise, SetDifficulty), instead of measuring gym connectivity first. This replaces "Option A" (online-only, touch and voice) of the package.

## Why
A set finished in a basement gym with no signal must not be lost and must not block the rest timer. The existing app already tolerates offline writes (Firestore offline persistence, with a 4 second save timeout that hides the missing server acknowledgement). Option A would regress that behavior for the main logging path.

## Required behavior (acceptance criteria to carry into the package registers)
1. Local first: tapping or speaking "complete set" stores the command in a durable local queue before any network call and shows the state "pending sync". The rest timer may start on local acceptance. Acceptance test: airplane mode for 20 minutes, 15 sets logged, 0 lost and 0 duplicated after reconnect.
2. Idempotent delivery: every command carries a client-generated operation ID (and a set ID for CompleteSet) scoped to the signed-in UID and session. The server treats the same ID with the same payload as success, and the same ID with a different payload as a conflict that changes nothing.
3. Honest status: the UI distinguishes "saved on this device" from "synced" and never shows "synced" without a server acknowledgement.
4. Conflicts: a command for a session that was deleted or changed elsewhere is reported to the user as "could not sync" with the data kept in the queue for retry or export; it never recreates a deleted session.
5. Account switch and sign-out: queued commands belong to their UID; a different account never sends them; sign-out with pending commands shows the existing cannot-check sheet with the explicit choice.
6. Deletion and export: account deletion clears the queue; data export includes pending commands.
7. Bounded: queue size and age limits are defined (proposal: 500 commands, 30 days) with a visible warning before the limit.
8. Voice and touch use the same queue (one source of truth), so a voice command cannot bypass the local-first path.

## What this changes in the package
Option A (these three commands require the network) is withdrawn. Server-minted receipts (ADR-CMD-02) stay useful for idempotency, but their admission step must not block local acceptance. The 4 second silent timeout must not be restored as the mechanism; the queue is.

## Not yet verified
No gym connectivity measurements exist. They are still useful to size the queue limits but no longer gate this decision.
