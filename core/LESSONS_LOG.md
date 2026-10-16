# Lessons log

Append-only history of mistakes, shortcomings and successful decisions, kept in the same commit as the related work (global rule "LESSONS LOG", operator 2026-10-16). Newest entries last. Sprint retrospectives are built from this file.

Entry format: `## <date> - <commit or topic>`, then `Kind` (FAILURE / SHORTCOMING / SUCCESS), `Facts` (with evidence pointer), `Root cause` (or why it worked), `Layers` (who missed it: author, tests, reviewers, gate; or who caught it), `Rule next time`.

## 2026-10-16 - S02 documentation phase: ten GPT-PM rounds

Kind: FAILURE (process) with a SUCCESS outcome.
Facts: rounds 3 to 9 kept finding new holes in the "input-class matrix" merge design (core/DECISION_LOG.md, S02 documentation entries); the design was replaced by value-based overrides and round 10 returned APPROVE on 9c68cab8.
Root cause: the design tried to enumerate every input class instead of stating one invariant (effective value = derived value, then explicit values, then overrides).
Layers: author missed it for seven rounds; the external reviewer kept finding it.
Rule next time: when a reviewer finds a third variant of the same hole, stop patching and restate the invariant the design must satisfy; replace the mechanism instead of extending it.

## 2026-10-16 - S02 test epic 7b: summary-synced entries were never uploaded

Kind: FAILURE.
Facts: the first stream uploader selected only `pending` or `upload_failed` entries, while summary sync writes `synced`; in the real order (summary sync, then upload) no stream was ever uploaded. Found by the test that drives the real sequence (commit bf8b6d39).
Root cause: the uploader reused the summary sync state as its own state flag (design 5.2 item 4 said "reuse" and nobody checked the other writer of that flag).
Layers: author and the design review missed it; the epic 7b test caught it before any review.
Rule next time: when reusing a state flag, list every writer and reader of it; test the real end-to-end order of the writers, not each in isolation.

## 2026-10-16 - S02 final complete run: stale fakes outside the epic directories

Kind: SHORTCOMING.
Facts: `delete_account.test.ts` and `account_deletion_reconcile.test.ts` (74 failures) and `firestore_indexes_body_scan.test.ts` (2 failures) lay outside `functions/src/__tests__/activity`, so no epic ran them; the final complete run found them (commit 479b7342).
Root cause: epics ran their own directories; nobody mapped changed shared code (`deleteAccount` Step 1c, indexes) to the tests that exercise it.
Layers: epics missed it; the final complete run caught it.
Rule next time: when production code of a shared function changes, grep for every test that exercises it and put those files into the epic's run list.

## 2026-10-16 - S02 journal wipe on account switch (remediation B2), rejected by GPT-PM round 11

Kind: FAILURE (mine).
Facts: remediation B2 added an owner-uid marker and made `claimActivityJournal()` wipe the whole device journal (sessions, sources, quarantine, key) when another account signs in. Account A's device-only GPS and heart-rate data would be destroyed for good on A signs out, B signs in. GPT-PM round 11 on f1646961 returned REJECT (MAJOR-01); MAJOR-02: a missing marker made the next account adopt another account's journal. Fixed by account-scoped journals (remediation E1).
Root cause: I specified the fix for one threat (cross-account leak) and did not run the opposite check (what is lost, can it be rebuilt from the cloud). The approved design 6.2 required a warning and an export offer before any wipe; I implemented the wipe without the offer. A separate owner marker in preferences duplicated the ownership that the storage location can carry.
Layers: coordinator (author of the brief) and the implementer followed it; test epic 9b encoded the same behaviour as the oracle; the Flutter and architecture reviewers were told by me that the owner guard and wipe were "already fixed, do not re-report" and judged it sound; only the final GPT-PM gate caught it, before any push.
Rule next time: (1) every destructive guard gets a two-sided threat check: what leaks without it AND what is lost with it; (2) never tell reviewers to skip recently added mitigations, remediation code is reviewed with the same independence as the original; (3) ownership of data is expressed by where it lives (per-account directory and key), not by a separate marker; (4) an oracle written from the implementer's own brief proves conformance, not correctness, so add one adversarial test that states the user-visible promise ("signing in as someone else never destroys my data").

## 2026-10-16 - S02 specialist reviews before the gate

Kind: SUCCESS.
Facts: six independent specialist reviews (security, reliability, database, silent-failure, Flutter, architecture) found real defects before the gate: an abandoned account deletion fenced a live account for good, journal recovery deleted committed generations on a transient I/O error, an unfinished upload could continue under another account, one client flag gated journal, sync and streams together. All were fixed in batches A to D with regression tests.
Why it worked: reviewers worked independently from one stated contract, findings were deduplicated and every cited line was re-checked against the source before any change.
Layers: reviews caught what authors and epic tests missed.
Rule next time: keep the independent review round before the gate, and keep the rule "verify the cited line before changing code".

## 2026-10-16 - Agent briefs and turn limits

Kind: SHORTCOMING.
Facts: many agents stopped at 12 to 25 turns with uncommitted work (test epics 7a, 7b, 8a, 8b, 9a, 9b, 10b, several remediation agents), costing resumptions; some left probe files.
Root cause: briefs asked for research plus implementation plus final run in one agent and did not demand "commit after every file".
Layers: coordinator.
Rule next time: split work so one agent has at most about five deliverables, require a commit after each, and put the exact run command in the brief.

## 2026-10-16 - S02 tombstone push capped at 8 per pass (GPT-PM round 11, MAJOR-03)

Kind: FAILURE.
Facts: `_pushLocalTombstones` stopped after `kMaxSummaryBatch` (8) per sync pass and nothing continued; 30 offline deletions needed four app starts, and the daily `activityDelete` quota of 100 could block erasure of a larger backlog. Fixed in remediation E2 (continuation rounds up to 128, pending count in the sync state, backoff retry, quota 1000).
Root cause: the cap was designed as a per-pass work bound and nobody asked what happens to the remainder; privacy erasure shared the abuse limit of ordinary calls.
Layers: author and design review missed it; none of the six specialist reviews or the epic tests asked for a completion path; the external gate caught it.
Rule next time: every bounded loop or per-call cap states its continuation or completion path in the design, and erasure paths get their own capacity separate from abuse limits.

## 2026-10-16 - Account journal ownership (remediation E1)
Problem: a device-wide journal plus a separate owner marker meant a different sign-in wiped device-only data, and a missing or corrupt marker let another account adopt the journal.
Root cause: ownership was stored apart from the data it protected, and a destructive default (wipe on switch) stood in for an export flow that did not exist yet.
Layers: design review accepted the wipe-on-switch as an interim rule; the external gate caught it.
Rule next time: make ownership the location of the data (per-account scope) and never let an interim flow default to deleting user data.

## 2026-10-16 - Scoped journal tests (test epic 11a, part a)
SUCCESS: the never-run scoped journal compiled and passed 22 behaviour tests on real files; the only defects were in the tests themselves (record equality on lists, a consumed gate). Layer: epic tests now cover what the review rounds only argued about.

## 2026-10-16 - Tombstone continuation tests (test epic 11b)
SHORTCOMING: the E2 continuation compiled and met its notes (34 tests green), but account-scoped state was missed: the retry timer, the confirmed-id set (ids are deterministic, so account A's confirmed id would never be pushed for account B) and the backoff budget lived for the whole process and nothing reset them on sign-out or uid change. Root cause: E2 was designed per process while E1 made the journal per account; the two remediations were not read against each other. Layers: E2 author and design review missed it; the E2 test notes did not mention it; the E2 agent only noted that nothing calls `cancelTombstoneRetry()`; the epic test found it. Rule next time: any in-memory state next to an account-scoped store is reset on the account change, and a test switches accounts.

## 2026-10-16 - Erasure quota tests (test epic 11b, server)
SUCCESS: the four pinned 100s were found from the E2 notes and moved to 1000 without a surprise; the new test pins the 1000th/1001st call, per-user scope and the fence refund, so a regression to the abuse-limit value fails a test. Layer: tests, because the production change had left the pinned values stale.

## 2026-10-16 - Scoped journal did not compile (test epic 11a, part b)
Kind: FAILURE.
Facts: `journal is AccountScopedJournal` does not promote an `ActivityJournal` to the unrelated interface in Dart, so `bindUid` and `wipeForUid` were undefined in the wiring and the wipe decorator; the app did not compile after remediation E1 (see core/changes/2026-10-16-s02-test-epic11a-wiring-tests.md).
Root cause: E1 was committed without ever being compiled (no checks until all coding was done).
Layers: author and the review rounds missed it; the first test compile caught it.
Rule next time: a remediation touching a type contract gets one compile of its own test files before it is handed to review.

## 2026-10-16 - Flag matrix and account wipe e2e on scoped journals (test epic 11a, part c)
Kind: SUCCESS, with one test-side slip: a scripted edit lost the escaping of apostrophes in Dart string literals (compile error, caught by the first run); use Write/Edit for source with quotes.

## 2026-10-16 - Account-switch promise test (test epic 11a, part d)
SUCCESS: the user-level promise from the incident now has a test that fails if a switch deletes or adopts data; layer that was missing: user-level e2e, the earlier tests asserted the marker mechanics rather than the promise.

## 2026-10-16 - Stale journal fake after the E2 state change (test epic 11b)
FAILURE: `refreshState()` began to call `journal.listTombstones()` in E2 and the epic 10a fake `_FlakyJournal` (noSuchMethod throws) was not updated, so 4 existing state tests failed with `UnimplementedError`. Root cause: a production method gained a new journal dependency while hand-written fakes that throw on unknown calls were not searched. Layers: the E2 author did not grep fakes of the interface; reviewers did not either; the complete epic run caught it. Rule next time: when a method gains a call on an interface, grep every fake of that interface (especially noSuchMethod fakes) in the same commit.

## 2026-10-16 - Epic 11a closed
SUCCESS: complete run green (660 tests); the only production defect of E1 was the compile error caught by the first test compile.

## 2026-10-16 - S02 remediation F2 (1/4): no rebind of a wiped account
Kind: FAILURE.
Facts: after account deletion wiped the bound uid, a same-uid auth re-emission called `bindUid` again and re-created the deleted account scope and key (security and Flutter reviewers, core/changes/2026-10-16-s02-remediation-f2-no-rebind.md).
Root cause: E1 treated the wipe as a one-shot event and did not model "this uid is gone" as state; auth streams re-emit the same uid.
Layers: the author of E1 and the epic 11a tests missed it (no test re-emitted the same uid after a wipe); the independent reviewers caught it.
Rule next time: for any destructive account event, test the same-uid re-emission that follows it.

## 2026-10-16 - S02 remediation F2 (2/4): key deletion failure fails the wipe
Kind: FAILURE.
Facts: `SecureStorageJournalKeyProvider.forget()` swallowed a delete failure ("Best effort") and the wipe awaited it, so account deletion could report success with the key still in secure storage (core/changes/2026-10-16-s02-remediation-f2-key-delete.md).
Root cause: a best-effort comment written for a close path was reused on the one path where failure must be visible.
Layers: the author of E1 and the epic 11a tests missed it (no test made the keystore delete throw); the independent reliability and silent-failure reviewers caught it.
Rule next time: on a wipe path every step either succeeds or surfaces; best effort is only for close and dispose.

## 2026-10-16 - Sync pass identity and pinning (remediation F1, 1/4)
Kind: FAILURE.
Facts: a `syncAll` pass of account A in flight at an account switch kept acting on account B: `epoch` was captured but checked only inside the tombstone phase, so `_journal.list()` returned B's entries and A's server tombstone ids (deterministic ids) deleted B's local copies; `_syncLocked` could write under B's Firebase uid (see core/changes/2026-10-16-s02-remediation-f1-pass-identity.md).
Root cause: the E2 author pinned only the tombstone phase; the account-scoped journal facade of E1 made every later call in the pass resolve against whichever account is bound now.
Layers: the E2 author missed it; the epic 11a/11b tests never switched account mid-pass; four independent reviewers caught it.
Rule next time: every async pass that touches per-account state carries a pass identity and re-checks it before every side effect, and each long-running operation gets a switch-account-mid-flight test.

## 2026-10-16 - S02 remediation F2 (4/4): uploader single-flight state across an account switch
Kind: FAILURE.
Facts: `_runInFlight`, `_entryInFlight` and `_failedThisStart` of the stream uploader survived A to B, so `runPending()` returned A cancelled future and B got no upload run in that app start (core/changes/2026-10-16-s02-remediation-f2-uploader-switch.md).
Root cause: the same class as the E2 retry-timer defect: in-memory state next to an account-scoped store was not reset on the account change; the lesson from epic 11b was applied to the sync repository only, not searched across the other components.
Layers: the author of E1 and the epic 11a tests missed it (no test switched accounts through the uploader); the independent Flutter reviewer caught it.
Rule next time: after fixing one account-scoped state defect, grep every in-memory field of every component wired to the same auth stream.

## 2026-10-16 - S02 remediation F2 (3/4): journal binding retry and deleting-account skip
Kind: FAILURE.
Facts: the binding provider discarded the bool of `bindUid`, so one transient secure-storage error left the journal unbound for the whole session, and it did not consult `accountBeingDeletedUidProvider` (core/changes/2026-10-16-s02-remediation-f2-binding.md).
Root cause: a fail-closed API (returns false) was wired as fire-and-forget; nobody owned the retry.
Layers: the author of E1 and the epic 11a wiring tests missed it (the fake never failed a bind); the independent reliability and silent-failure reviewers caught it.
Rule next time: every fail-closed result must have a consumer that retries or surfaces it; test the failing first call.

## 2026-10-16 - S02 remediation F2 test notes
Kind: NEUTRAL.
Facts: the F2 test oracles and the stale-fake list are written down before any test exists (core/changes/2026-10-16-s02-remediation-f2-test-notes.md).
Rule applied: list every implementer of a changed interface in the same commit series (lesson of the stale journal fake).

## 2026-10-16 - Unbound visibility and cache reset (remediation F1, 2/4)
Kind: FAILURE.
Facts: an unbound or failed-bind scoped journal read as empty, so the conflict sheet showed loaded and in sync with zero pending deletions and `resolveConflict` returned `notFound`, shown as not failed; `onAccountChanged` left `_conflictCache` and `_conflictTried` of the previous account (see core/changes/2026-10-16-s02-remediation-f1-unbound-and-caches.md).
Root cause: E1 made "no account" a normal empty journal; the consumers treated empty as a valid answer.
Layers: the E1/E2 author missed it; tests had no unbound case; silent-failure, Flutter and reliability reviewers caught it.
Rule next time: when a store can be absent, the absence is a distinct error state in every reader, and each reader gets an "absent" test.

## 2026-10-16 - Tombstone retry budget and fallback (remediation F1, 3/4)
Kind: SHORTCOMING.
Facts: the six-attempt retry budget was never reset, so after about 44 minutes offline no timer existed for the rest of the session; exceptions of the tombstone phase escaped before scheduling; `lastTombstonePushError` stayed null when the listing failed (see core/changes/2026-10-16-s02-remediation-f1-tombstone-retry.md).
Root cause: E2 designed the budget per app start and covered only the push-failure path, not listing/journal failures or a long outage.
Layers: E2 author and tests missed it; reliability and silent-failure reviewers caught it.
Rule next time: a retry budget needs a reset condition and a last-resort slow path, and each error path of a phase gets a scheduling test.

## 2026-10-16 - Remediation F1 documentation (4/4)
Kind: SUCCESS. The test notes name an oracle per finding (switch account mid-pass with a blocked backend, authUid mismatch, unbound, retry budget) and the stale fakes up front, applying the lessons of the earlier stale-fake failure.

## 2026-10-16 - S02 test epic 12b (1): refusal of a wiped uid never ended
Kind: FAILURE.
Facts: after `wipeForUid(bound uid)` the journal is unbound, so `bindUid(null)` returned at the "already unbound" early exit before `_wipedUid` was cleared and only binding another uid ended the refusal; the F2 notes say `bindUid(null)` clears it (core/changes/2026-10-16-s02-test-epic12b-wipe-rebind.md). Also the epic 11a test and the wipe wiring fake still encoded the pre-F2 contract.
Root cause: the implementer compiled and ran nothing and tested the refusal state machine only on the paths it imagined; stale oracles were not searched when the contract changed.
Layers: F2 author and the independent reviewers missed it; found by the epic 12b test written from the notes.
Rule next time: test every state-clearing event from every reachable state, including the state where the clearing event looks like a no-op.

## 2026-10-16 - S02 test epic 12b (2): binding retry tests
Kind: SUCCESS. The binding provider, written without a compiler, met every F2 note on the first run (14 of 14), because the retry state is one generation counter plus one timer slot; a fake timer factory with forced stale callbacks made the cancel guarantees falsifiable. Architecture/import guard tests (data/-layer graph, backup rules) pass: they scan only feature `data/` directories, and `core/wiring` already imports account-deletion state like body_scan and food_diary do, so no import fix was needed (layer that missed it: none; the implementer simply did not check).

## 2026-10-16 - S02 test epic 12b (3): uploader account-switch tests
Kind: SUCCESS. The uploader reset (slot, per-id map, failed ids, epoch) held for all seven oracles. Test-side slip (mine): a fake whose fault hook runs before the blocking hook never blocked, so the first version of the old-epoch test proved nothing; rule: assert the precondition (the call is really blocked) before the action.

## 2026-10-16 - S02 test epic 12a (1): pass identity, caches, unbound, retry tests
Kind: SHORTCOMING (stale oracle) and SUCCESS.
Facts: the E2 test "60 s, 2, 4, 8, 15, 15 min then no seventh attempt" failed on the first compile-and-run of F1 (expected 6 timers, got 7) because the F1 fallback timer changed the contract and the implementers ran nothing (core/changes/2026-10-16-s02-test-epic12a-pass-identity.md). The F1 production code itself compiled and met all 33 new oracles on the first run.
Root cause: the contract changed in F1 and the old assertion was listed in the notes but nobody ran it. Layers: F1 author and reviewers missed the stale assertion; the epic 12a run caught it.
Own slip (mine): to stop a hung test run I killed every dart.exe process on the machine, which can also kill the parallel agent's runs; rule next time: stop only the process tree I started (use `timeout` and `--timeout` on the run itself).
Rule next time: when a contract changes, run the tests that encode the old contract in the same commit.

## 2026-10-16 - S02 test epic 12a (2): stale SF9 oracle found only by the directory run
Kind: SHORTCOMING.
Facts: `activity_sync_corrupt_summary_test.dart` SF9 still expected the tombstone error code to survive a clean pass; F1 clears it (expected 'permission-denied', actual null); only the full directory run found it, the notes did not list that file (core/changes/2026-10-16-s02-test-epic12a-e2e-and-run.md).
Root cause: the F1 notes listed stale fakes by search of constructors, not tests asserting `lastTombstonePushError` semantics. Layers: F1 authors and note writer missed it; the epic 12a directory run caught it.
Success: the account-switch e2e (3 tests) passed on the first run, so the pass-identity guards hold end to end.
Rule next time: when a getter's semantics change, grep all tests that read it and run them in the same commit.
