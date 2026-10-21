# Decision: durable local queue for set logging (2026-10-21)

Decision (operator, 2026-10-21): accept a durable local queue for the three workout commands that the rebaseline package made online-only (CompleteSet, AddEligibleExercise, SetDifficulty), instead of measuring gym connectivity first. This replaces "Option A" (online-only, touch and voice) of the package.

## Why
A set finished in a basement gym with no signal must not be lost and must not block the rest timer. The existing app already tolerates offline writes (Firestore offline persistence, with a 4 second save timeout that hides the missing server acknowledgement). Option A would regress that behavior for the main logging path.

## Required behavior (acceptance criteria to carry into the package registers)

### Local acceptance and durability
1. Local first: tapping or speaking "complete set" stores the command in a durable local queue before any network call and shows the state "pending sync". The rest timer may start on local acceptance. Acceptance test: airplane mode for 20 minutes, 15 sets logged, 0 lost and 0 duplicated after reconnect.
2. Atomic durable acceptance: a command counts as accepted only after the local write is committed as one atomic unit (command, operation ID, payload). A write that is interrupted leaves either the whole command or nothing, never a half command, and the UI never shows "pending sync" for a command that is not committed. Tests: kill the process right after acceptance, restart the device with pending commands, and interrupt the local write; every command shown as pending before the kill is still pending and intact afterwards, and an uncommitted one is reported to the user as not saved.
3. No silent eviction: an unacknowledged command is never removed automatically, not by age, not by size. Proposed limits are 500 pending commands (a hard cap that fails closed) and a 30-day aging-warning threshold (not an eviction deadline); a visible warning appears at 400 commands and when the oldest pending command is 25 days old. At 500 the app fails closed: it refuses a new command with a visible message before accepting it, and keeps all accepted ones until they are acknowledged or the user explicitly exports or discards them. Tests: fill the queue to 500, try the 501st; age a pending command past 30 days; in both cases all earlier commands are still present and the user was told.

### Identity, idempotency and ordering
4. Stable identity: every command carries a client-generated operation ID scoped to the signed-in UID and session, and CompleteSet also carries a logical set ID (session, exercise, set index). The operation ID and the payload do not change across retries, app restarts and reconnects. The server stores the receipt and applies the mutation in one atomic step; the same ID with the same payload is success, the same ID with a different payload is a conflict that changes nothing.
5. One logical set, one completion: two commands with different operation IDs that complete the same logical set are not both applied; the second is reported as a conflict and kept for the user. A retry never generates a new operation ID. Tests: lost acknowledgement (server applied, client never heard, client retries), duplicate intent (user taps twice), and a restart between send and acknowledgement; each ends with exactly one completed set.
6. Order: commands of one session are delivered in the order accepted, and a command that depends on an earlier one (SetDifficulty or CompleteSet on an exercise added by AddEligibleExercise) is not applied before it. If the earlier command is in conflict, the dependent ones are held as "could not sync", not applied. Test: deliver reordered and with the first command failing.
7. Receipt capacity: the receipt-retention and capacity policy is frozen in the implementation contract so that an old unacknowledged command can never be replayed as a new mutation; the server receipt store must hold at least as many receipts per user as the queue can hold pending commands plus the retention window, or the receipt policy must be changed together with this limit. The unapproved 256-receipt proposal of the AI-Coach transaction design must not be adopted while the queue allows 500 pending commands. Test: replay 500 old commands after the 256th newer one; none is applied twice.

### Honesty, conflicts, voice
8. Honest status: the UI distinguishes "saved on this device" from "synced" and never shows "synced" without a server acknowledgement.
9. Conflicts: a command for a session that was deleted or changed elsewhere is reported to the user as "could not sync" with the data kept in the queue for retry or export; it never recreates a deleted session.
10. Voice and touch use the same queue (one source of truth), so a voice command cannot bypass the local-first path.

### Account lifecycle
11. UID isolation: queue storage is keyed by UID; code of another signed-in account cannot read or send it. After A, B, A account changes, A's pending commands are intact, were never sent under B, and are sent under A.
12. Sign-out with pending commands: the sign-out sheet for known pending workout commands (a new variant; the existing cannot-check sheet was designed for an unreadable journal) offers exactly three outcomes: wait and sync first, keep on this device for the next sign-in of the same account, or export then discard. Discarding without export needs a separate explicit confirmation naming the number of commands. In-flight sends are fenced: sign-out does not complete while a send is in flight, or the send finishes or is cancelled before the UID binding is released. Test: sign out during a sync; no command is lost, none is sent under another UID.
13. Account deletion: deletion first fences and cancels in-flight sends, then clears the queue, then deletes server data; a send racing with deletion must not recreate server data after deletion completes. Test: delete the account during a sync and check that no document reappears.
14. Export: data export includes commands that exist only on the device (pending and conflicted) as an explicit part of the snapshot, also when the device is offline. Test: export in airplane mode contains all pending commands.

## What this changes in the package
Option A (these three commands require the network) is withdrawn. Server-minted receipts (ADR-CMD-02) stay useful for idempotency, but their admission step must not block local acceptance. The 4 second silent timeout must not be restored as the mechanism; the queue is.

## Not yet verified
No gym connectivity measurements exist. They are still useful to size the queue limits but no longer gate this decision. No queue implementation exists; every criterion above is a proposal to be tested.
