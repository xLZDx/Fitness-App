# S04 code review, round 1 (consolidated)

Date: 2026-10-17. Head reviewed: 03143df3. Reviewers (static reading, nothing run): reliability-reviewer, silent-failure-hunter, flutter-reviewer, security-reviewer (security findings are appended below when received). Findings that two reviewers made independently are marked x2.

## A. Journal and recorder controller (batch FIX-A)

| Id | Sev | Finding | Required change |
|---|---|---|---|
| C1 x2 | MAJOR | The journal's active recording is never released on several controller paths (begin timeout and late completion, failed start after begin, engine-detach halt, seal flushFailed, decideDelete failure, openForResume failure), so begin throws alreadyActive and Start stays blocked until the process restarts; listUnfinished skips the active id so the orphan is never offered. | Add `abandonActive(id)` to the journal port: cancel the flush timer, close the handle, clear `_active`, keep the data on disk as an unfinished recording (delete only an empty directory). Call it on every controller exit that neither seals nor deletes; cancel or compensate a late begin. |
| C2 x2 | MAJOR | A seal whose flush fails leaves the journal active with its timer running (same family as C1). | Detach the active recording on a flush failure during seal. |
| C3 x2 | MAJOR | Any exception while recovering a recording (I/O error, key unavailable, worker failure) is reported as `unreadable`; Keep then quarantines it and it is deleted after 30 days. | Separate confirmed damage (authentication, CRC, schema) from "could not read now". Report the second as a retryable `unavailable` status; never quarantine it, never expire it. |
| C4 x2 | MAJOR | The 30-day FALLBACK marker is written only inside the pre-unbind hook after the slow seal; a hook timeout (5 s) or the skip branches leave recordings with no expiry. The hook keeps running after its timeout and swallows a failed FALLBACK write. | Write FALLBACK for every remaining recording first as a cheap step, also for the skipped ones; make the hook cooperative with a cancel flag; await an in-flight stop; wire `onFallbackKept` so the sign-out notice appears; add a scope-agnostic expiry sweep at app start. |
| C5 | MAJOR | Quarantined recordings that came from an invalid or conflicting decision state are returned before the 30-day expiry check, so they never expire. | Evaluate the QUARANTINED marker age before returning in that branch; expiry uses a direct ordered delete, never publishing DELETE over an invalid DECISION. |
| C6 | MAJOR | The production DECISION publication always takes the exclusive-create fallback (hard link is a stub), which leaves an empty-file window; an empty DECISION after a crash becomes a quarantine and a lost user choice. | Under the process lock and the publication mutex publish by write temp, fsync, then rename only when the target is absent; or treat an empty DECISION left by the fallback as a half-written marker of this same process and re-run the intent. |
| C7 x2 | MAJOR | Recorder state is not tied to the account: after a sign-out or account change a stale `finished`, `permissionRevoked`, `restoring` or `recoveryFailed` phase survives and the foreign-owner logic blocks the next account. | Reset every non-collecting phase to idle on a confirmed uid change (after the pre-unbind hook); clear the owner on terminal phases. |
| C8 x2 | MAJOR | Keep/Delete/discard actions are silent no-ops or swallow failures (`alreadyDecided`, thrown errors) with no visible outcome. | Expose an explicit result in the state (failed, alreadyDecided) for each action; on alreadyDecided continue the winner (KEEP completes the hand-off, DELETE completes the delete). |
| C9 | MINOR | A hand-off whose activity is verified but whose cleanup throws returns failedKept and skips the UI refresh; a tombstoned activity returns done although nothing was saved. | Return done after verification and report cleanup failure separately; distinct result for the tombstone case. |
| C10 | MINOR | Delete and cleanup are not idempotent against a vanished directory; the .cleanup sweep races KEEP cleanup. | Tolerate ENOENT; run the sweep under the per-recording mutex. |
| C11 | MINOR | A late drain can write after seal or delete (`closed` is not set there). | Set closed under the lock before the final close in seal and decideDelete. |
| C12 | MINOR | Expiry uses the wall clock; a clock jump deletes recordings; a FALLBACK recording with unreadable meta never expires. | Check the file mtime as well; FALLBACK expiry before the meta check; content-free log on expiry delete. |
| C13 | MINOR | Lock acquisition races (two concurrent first callers throw journalLocked); the provider has no onDispose. | Memoise the acquisition future per scope; release in onDispose. |
| C14 | MINOR | `_rotateAfterError` can desynchronise counters after an in-loop rotation. | Advance the counter and prune pending per durable segment close. |
| C15 | MINOR | A crash between the stop event and SEALED is not re-sealed (design 4.3 step 2). | Seal with the stop reason at recovery or amend the design. |
| C16 | MINOR | Consent withdrawn during `preparing` does not stop the start; an automatic stop is dropped when the controller is locked; a failed recovery check is silent and not retried. | Re-check consent before acquiring; retry the dropped stop; visible recovery-check-failed state. |

## B. Location adapter, pages, shell and wiring (batch FIX-B)

| Id | Sev | Finding | Required change |
|---|---|---|---|
| U1 | BLOCKER (inference) | `StreamController(onCancel: stop)` with `await out.close()` inside `stop()` can wait on itself, so Stop, Discard or revoke hang inside releaseAll and the controller stays locked. | Do not await close inside onCancel; make stop idempotent and non-blocking when entered from onCancel. Test with the adapter and a mocked plugin. |
| U2 x2 | MAJOR | Overlapping `setInterval` calls leak a position stream that survives stop; pause/resume back to back triggers it. | Serialize setInterval and stop through one in-flight future; report failures as a fault; test that the live subscription count is 0 after stop. |
| U3 | MAJOR | System Back from the finished screen leaves the phase `finished`, so Start is silent no-op until Done is tapped; "Not now" on save-failed is sticky. | Acknowledge on pop or on dispose; "Not now" clears the flag; offer a real hand-off retry. |
| U4 | MAJOR | `permissionRevoked` gives a null strip; the contract requires a strip row and a Home card until Keep or Delete. The code comment cites design 7.2 which contradicts contract 14.1. | Follow the UI contract: add a revoked strip state; fix the design 7.2 sentence; requestStart must show the pending decision. |
| U5 | MAJOR | Duplicate announcements: the shell and the page both speak for one event; the shell copy has no 30 s gate (G-7). | One announcer: suppress the shell ones while the recording page is the top route. |
| U6 | MAJOR | Flag-on production leaves safety seams inert: fake battery monitor (no 10 %/3 % guards), `servicesOff` unreachable, location settings link opens app settings. | Wire real implementations where a plugin exists, otherwise make the gap explicit: with the flag on and a missing seam the Start panel says so; record the gap in the sprint report. |
| U7 | MAJOR | Consent withdrawal announces success although `withdraw()` returned false or persistence failed. | Surface the result; on failure show an error and keep the toggle in its true state. |
| U8 | MINOR | `resumeMode` ignored in idle/preparing; Review on blockedByJournal is a no-op; dead announcement `gpsAnnAcquiring`; duplicate background reporting; recovery shows "No data" and "0 m lost"; stale nothing-recorded flag; add-manually and open-workout use `go` and lead to /workouts; leftover scaffolding and TODOs; approximate-only location never detected in production wiring. | Fix each as stated in the reviewers' reports; carry distance and moving time on UnfinishedRecording (needs FIX-A). |

## C. Security reviewer

Appended below when the report arrives.
