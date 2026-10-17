# S04 test findings, group EP_D (journal, kill and recovery)

Status: tests written and run. Branch `phase2/s04`, HEAD `1d76b05e`, working tree (nothing committed by this agent).
Author: test-writing agent for group EP_D. Oracle: `S04_TEST_PLAN.md` rows, `S04_DESIGN.md` 4.2 to 4.8, not the code.

## Stories covered

S04-11, S04-12, S04-13, S04-14, S04-15, S04-16 (EP-D), the DECISION arbitration / recovery table / KEEP cleanup rows DT-19-12 to DT-19-25 at the journal level, the 30-day fallback and expiry rows DT-30-3 and DT-30-13, the pre-unbind hook (journal side), and the journal parts of S04-26 (DT-26-1, 2, 5, 6) and S04-31 (DT-31-1 to 3).

## Files (all new, `mobile/test/features/recording/journal/`)

| File | Tests |
|---|---|
| `journal_kit.dart` | shared kit (memory file system, fault wrapper, ops seam, simulated kill), not a test file |
| `s04_11_append_flush_test.dart` | 33 (DT-11-1..9, 11..15, 17, 18) |
| `s04_12_13_recovery_test.dart` | 28 (DT-12-1..5, 11..13; DT-13-1, 2, 5, 7) |
| `s04_14_handoff_test.dart` | 21 (DT-14-1..8, 10..12) |
| `s04_15_16_lifecycle_test.dart` | 26 (DT-15-1..4, 7..10; DT-16-1..4; DT-30-3, DT-30-13; hook) |
| `s04_19_decision_test.dart` | 42 (DT-19-12..15, 17..25) |
| `s04_26_31_journal_test.dart` | 10 (DT-26-1, 2, 5, 6; DT-31-1..3) |

## Exact command

`cd D:\Repo\Fitness_App_Phase2_s01\mobile` then
`flutter test test/features/recording/journal --timeout 600s`
(final run: `+160: All tests passed!`, about 45 s; the 100k test is about 40 s of it).

## Counts

160 passed, 0 failed, 0 skipped (the folder, as a whole, on the final working tree). No analyze, no build, no full suite was run.

## Production bugs found and fixed (every production change, smallest possible)

All in `mobile/lib/features/recording/` (files re-read right before editing). Each bug was seen RED by a test before the fix, except item 6.

1. `journal/file_recording_journal.dart` `begin()`: a failed meta write left an empty `recording/<id>/` directory, which the next `listUnfinished()` reported as an unreadable recording (recoveryFailed offer for a recording that never started). Fix: remove the directory when this call created it. Tests: DT-11-4 `/begin-failure`, DT-16-4.
2. `journal/file_recording_journal.dart` `handOff()`: a second call after a completed hand-off (double tap) returned `failedKept` (UI would say "could not save" after a successful save). Fix: when the recording directory is gone and the activity with the deterministic id exists, return `done`. Test: DT-14-4 `/double-tap-finish`.
3. `journal/file_recording_journal.dart` `_handOffLocked()`: an already stored activity that had lost its streams (`streamLost`) counted as "exists" and as a verified hand-off, so the recording was deleted while the only stored copy had no track (data loss; Design 4.3 step 5 says "not streamLost"). Fix: "exists" now means the entry reads back loaded and not `streamLost`, the put is repeated otherwise, and the post-put verification rejects a `streamLost` entry. Test: DT-14-5 (streams lost).
4. `journal/file_recording_journal.dart` `_writePending()` / `_drain()`: the segment number advanced before the segment file was opened, so a failed open (storage full) left a hole in the numbering; after a storage-full episode the reader reported a missing middle segment (`recoveryFailed`) and `seal` threw `unreadable`. A failure before any segment existed also inserted a `segmentBreak` into segment 1 (invalid). Fix: advance the number only after a successful open; no suspect segment when none was opened. Tests: DT-16-1 `/space-returns`, `/stops-after-60s`.
5. `journal/file_recording_journal.dart` `_recoverOne()`: a hand-off exception during recovery (store down, key unavailable) was swallowed by the listing loop as `unreadable`, so a healthy sealed recording was shown as recoveryFailed (Keep or Delete only). Fix: `_tryHandOffLocked` turns the failure into `failedKept`, the recording stays offered. Tests: DT-15-9 `/subsequent-sign-in...`, DT-30-3.
6. `state/recording_journal_port.dart` + `journal/file_recording_journal.dart`: Design 4.3 / 5.4 say a revoked, sealed recording (pending Keep or Delete) "does not block Start", but `blocksStart` was true for every readable recording. Added the optional field `UnfinishedRecording.pendingDecision` (default false, set by `listUnfinished` for SEALED with reason `permissionRevoked`); `blocksStart` is false for it. Backward compatible (other groups construct `UnfinishedRecording` with named arguments). Tests: `s04_19_decision_test.dart` first group. (The test was written after the fix; not seen red.)
7. Documentation (not code): `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` lacked the "S04 proposed clarification, pending operator approval" note next to GPS-PRIV-014 that the requirements promise (DT-15-10). One PROPOSED note added next to the GPS-PRIV-014 line.

## Observations that are not fixed (no production change made)

- `_atomicWrite` rethrows the raw `FileSystemException` (type kept for the sanitiser's code mapping, message never read); `runner`/decode/worker failures are already content-free. DT-31-1 proves the sanitiser strips a sentinel from it.
- The "in-memory buffer bounded" guard `pending.length > 1000` counts batches, not fixes, so it does not bound fixes by itself; the real bound is the 60 s retry window (about 60 fixes at 1 Hz). DT-16-3 asserts the window-based bound (gave up at about 65 s, nothing dropped).
- A replayed `decideKeep` returns `committed` (idempotent); `alreadyDecided` is returned only for the opposite decision. Tests accept both for a replay and assert that nothing changes.
- The `readDecision` wait on an empty `DECISION` (publication mutex) is unreachable from a single journal object because every caller is serialised by the per-recording mutex; DT-19-20 `/live-loser-finds-empty-file` therefore asserts the observable behaviour (the loser waits behind the winner and acts on nothing).
- `UnfinishedRecording` carries no age field; the age for DT-12-5 is derived from `startUtcMs + lastOffsetMs`.
- DT-26-5 timings (JIT test environment, NOT a frame-budget proof): 100 000 fixes, write 10.5 s, seal 8.7 s, open plus hand-off 22.5 s.

## Remaining gaps (NOT_RUN or not in this group)

- Device rows NOT_RUN until a phone: DT-11-16, DT-26-7, DT-16-6 (conditional on D-9).
- Controller rows (another group): DT-11-10 (live list at most 600 entries), DT-12-6, DT-12-7, DT-14-9 (190 000 sample cap), DT-16-2 stored-reason display, DT-19-22 `recoveryComplete` gating, DT-12-1 `requestStart` refusal itself (only `blocksStart` is tested here).
- Widget rows (another group): DT-12-8, 12-9, 12-10, 12-14, DT-13-3, 13-4, 13-6, 13-8, DT-15-5, DT-16-5, DT-19-16.
- DT-26-3 (S02 golden bytes), DT-26-4 (per-fix work counter seam), DT-31-4 (screens), DT-15-1 `/sign-out-and-delete` beyond the hook plus wipe on real files: covered at the journal level only.
- DT-11-9 `/rotation` uses the real constant (5000 frames), not a lowered test seam (none exists); cost about 7 s.
- DT-19-24 crash points (c) and (d) are built by deleting files inside a `.cleanup` directory (the memory file system deletes a directory in one operation, so a crash in the middle of the content deletion cannot be injected).
- The Dart in-memory file system has one view: the "durable versus volatile view" of DT-11-6 is modelled as "what was flushed before the kill", which is exactly the app-kill promise; a sudden power loss is excluded by Design 4.6.
- Real-file coverage: DT-15-1, DT-15-2, DT-15-4 use real temp files with the production defaults; everything else runs on the memory file system with fault injection.
- No mutation run was done (operator rule); "fails when" is argued from the assertions and, for items 1 to 5, from the red runs before the fixes.
