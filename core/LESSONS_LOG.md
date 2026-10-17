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

## 2026-10-16 - S02 test epic 12b (4): wipe and rebind e2e
Kind: SHORTCOMING (mine). My throwing-close wipe test assumed `bindUid` creates the key; the journal creates it lazily, so the test failed at its own precondition. I classified it from the code and the notes as a test defect and fixed the precondition, not the assertion. Layer: author of the test (me) missed it; the run caught it. The end-to-end journey (delete A, re-emit A, B signs in) passed on the first run after the earlier production fix. Rule: when a precondition check fails, read what the production code really guarantees before choosing test or production.

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

## 2026-10-16 - S02 remediation G1: journal uid tied to auth uid
Kind: FAILURE.
Facts: a pass starting between `FirebaseAuth.currentUser` flipping to B and the journal rebinding had journal uid A and auth uid B; `_beginPass` and `_mayCall` checked each against its own start value only, so A's summaries and tombstones could be written to B's cloud (core/changes/2026-10-16-s02-remediation-g-journal-auth-tie.md).
Root cause: the author of F1 and F2 tied the pass to the epoch and the journal uid, and separately to the auth uid, but never to each other.
Layers: the author missed it; the 12a tests never started a pass with journal and auth disagreeing; the first round of four independent reviewers and the F implementers missed it; the second independent review round (reliability and security reviewers, independently) caught it.
Rule next time: when two sources of identity exist, tie them to each other at pass start and re-check the tie before each side effect, and test the disagreement case.

## 2026-10-16 - S02 remediation G2/G5: republish on account or binding change
Kind: FAILURE.
Facts: `onAccountChanged()` cleared caches but never published and nothing published after a bind or unbind, so the live conflict presenter kept the previous account's conflicts and never got `loadFailed` after a failed bind (core/changes/2026-10-16-s02-remediation-g-republish-and-skip-log.md).
Root cause: F1 treated "state changed" as something the next sync pass would announce; a failed bind never starts a pass.
Layers: the author and the F implementers missed it; the first review round missed it; the Flutter reviewer of the second round caught it.
Rule next time: every transition that invalidates displayed state must publish itself, not rely on a later pass; test with a live subscriber and no user action.

## 2026-10-16 - S02 remediation G3/G4: raw-uid change and wipe marker
Kind: SHORTCOMING.
Facts: the cloud sync listener keyed the account-change reset on the filtered sync uid (null for anonymous users), so anonymous X to real user B kept stale caches; `wipeForUid` set its marker only for a bound scope; the sync wiring did not skip the account being deleted (core/changes/2026-10-16-s02-remediation-g-raw-uid-and-wipe-marker.md).
Root cause: the same rule (which uid may be bound or reset) was written twice with different filters instead of once.
Layers: the author missed it; the F tests and first review round missed it; the second review round caught it.
Rule next time: one helper per identity rule, used by every wiring; a reset keyed on identity uses the raw identity, not a filtered one.

## 2026-10-16 - S02 remediation G docs: accepted backlog and test notes
Kind: SUCCESS.
Facts: the two accepted limits (late bind retry does not re-run the sync start; presenter retry cannot force a bind) were written into design 17 item 23 with their reason instead of being silently dropped (core/changes/2026-10-16-s02-remediation-g-docs.md).
Why it worked: a secondary mechanism that already had its one fix round is accepted and documented, per the no-secondary-blockers rule.

## 2026-10-16 - S02 test epic 13a: stale oracles and fakes after remediation G
Kind: FAILURE.
Facts: first compiled whole-directory run +1260 -4, all stale oracles (see docs/phase2/s02/S02_TEST_FINDINGS_EPIC13.md). Root cause: the G stale-test search listed fakes, not assertions about wipe then bind. Layers: G authors and reviewers missed it; the first compiled run caught it. Rule next time: grep for the changed call sequence (wipeForUid then bindUid) in all tests, not only the named files.

## 2026-10-16 - S02 test epic 13a: G1 auth tie and G5 skip logs
Kind: SUCCESS.
Facts: G1 and G5 production code met every oracle on the first compiled run (+17). Why it worked: oracles came from the notes and the promise; the only error was a missing import in the test. Layer: none missed a production defect.

## 2026-10-16 - S02 test epic 13a: G2 G3 G4 republish, raw-uid reset, wipe marker
Kind: SHORTCOMING.
Facts: G2 to G4 production code met all oracles; three first-run failures were my own test oracle (wipeForUid opens the scope once to delete it). Root cause: the notes said 'no directory created' without distinguishing the wipe's own open. Layer: notes author missed it; the first compiled run caught it. Rule next time: assert what the guarded call adds relative to the state after the wipe.

## 2026-10-16 - S02 test epic 13a: auth-flip end-to-end
Kind: SUCCESS.
Facts: the real-journal auth flip e2e passed on the first run (+2). Why it worked: the G1 tie is checked at pass start and before each call, so the promise holds at the real boundary. Layer: no defect.

## 2026-10-16 - S02 test epic 13a: complete runs, flaky ciphertext assertion, findings
Kind: FAILURE.
Facts: the second whole-directory run failed once in file_activity_journal_encryption_test I07 (searching random ciphertext for 1F 8B), passed on reruns; fixed to a start-of-stream check (docs/phase2/s02/S02_TEST_FINDINGS_EPIC13.md). Root cause: an oracle on random data with a nonzero false-positive rate. Layers: the epic 4 test author and reviewers missed it; the repeated complete run caught it. Rule next time: never assert absence of a short byte sequence inside random data.

## 2026-10-16 - S02 second independent review round on remediation E, F and G

Kind: SUCCESS, with FAILURES it exposed.
Facts: seven specialist reviews (four on the remediation E code, then three verification reviews on the F code) found real defects that 40 plus tests written by the test agents had not looked for: a sync pass that kept running for account A after a switch to B (found by all four first-round reviewers), an unbound journal reported as "in sync", a live conflict screen showing the previous account's data, a retry counter that never reset, and a pass that never tied the journal uid to the auth uid (found independently by two of three second-round reviewers). Evidence: commits aa8f24ec, 4a58317b, 39feb2a1 and the epic 12 and 13 findings.
Why it worked: reviewers worked independently from the code and the stated contract, were NOT told that anything was already fixed, and every cited line was re-read before changing code.
Layers: the author of E1 and E2 (pinned only the tombstone phase), the author of F1 and F2 (tied the pass to the epic and to the journal uid but not to the auth uid) and the epic 11 and 12 tests (they switched accounts between operations, never in the middle of one, and never with the journal and the auth user disagreeing) missed these; independent review caught them.
Rule next time: (1) remediation code gets its own independent review round, always; (2) every async operation that touches per-account state carries a pass identity and re-checks it before each side effect; (3) when two sources of identity exist, tie them to each other at the start of the operation and test the disagreement case; (4) for each long-running operation add a "switch account mid-flight" test.

## 2026-10-16 - S02 remediation E and F were written without compiling

Kind: SHORTCOMING.
Facts: the E1 code shipped with a compile error (a type check across unrelated interfaces does not promote the type in Dart, so bindUid and wipeForUid were undefined); the first test epic that compiled the tree (11a) found it. The operator rule forbids implementers from running builds, so no layer could see it earlier. Evidence: docs/phase2/s02/S02_TEST_FINDINGS_EPIC11.md.
Root cause: compile safety was left entirely to the test stage; the briefs asked for care but gave no checklist of Dart traps.
Layers: implementer and reviewers (reading only) missed it; the first compiled test run caught it, within minutes.
Rule next time: the first test agent of a remediation epic compiles the tree before writing any test; implementer briefs carry a short list of known Dart traps (type promotion, definite assignment, Fake classes needing every new member).

## 2026-10-16 - S02 test notes listed fakes but not the assertions the new contract breaks

Kind: SHORTCOMING (mine, as the author of the briefs).
Facts: the F2 and G test notes listed the stale fakes but not the older assertions that the new contract changes (a wiped uid is no longer re-bindable; the error code is cleared after a clean pass; the retry timer count). Four older tests failed only in directory runs (epic 12b, 12a, 13a). Parallel agents sharing one git index also swept each other's log entries into their commits, and one agent killed every dart.exe process, which may have disturbed a parallel run.
Root cause: the notes were derived from the changed interfaces, not from a search of the tests for the behaviours that changed; I started parallel test agents in one worktree.
Layers: coordinator (briefs), implementers (notes); the complete directory runs caught the failures.
Rule next time: when a contract changes, grep the tests for the old behaviour and list those assertions in the notes; run complete runs by one agent at a time; tell agents never to kill shared processes.

## 2026-10-16 - Hook false positives on commit-subject quotes

Kind: SHORTCOMING (tooling).
Facts: the decision-references hook treated a parenthesised word such as "(s02)" in a quoted commit subject as an unexplained decision reference and blocked several replies; the quote line was changed to commit hashes only. Rule next time: quote hashes, not commit subjects, in evidence lines.

## 2026-10-16 - S02 consent path assumed a single account (round-12 MAJOR)

Kind: FAILURE.
Facts: the external gate (round 12) found that AccountScopedConsentStore kept one mutable store for all accounts and the startup closure had no uid re-check after syncAll, so a delayed sign-in of account A could overwrite B and B could upload under A consent. Evidence: core/changes/2026-10-16-s02-remediation-h-a-consent-store-and-settings-client.md.
Root cause: the original consent wiring was designed for a single account; the earlier internal reviews were scoped to the remediation diff, so the consent path was never in scope; the epic tests never interleaved two accounts through the consent path.
Layers: author (design), reviewers (scope), tests (no interleaving) missed it; the external gate caught it.
Rule next time: after a defect class is found, sweep the whole surface by class (every async chain that reads or writes per-account state) and add a mid-flight account switch test to every async chain.

## 2026-10-16 - S02 uploader trusted a uid-less consent flag

Kind: FAILURE (same root cause as the consent store entry of the same day).
Facts: the uploader read isGranted without asking whose consent it was, did not stop for an account deletion in progress, and marked journal entries without re-checking the epoch or the scoped journal binding. Evidence: core/changes/2026-10-16-s02-remediation-h-a-uploader.md.
Root cause: per-account state was consumed as if global; the consent sweep was scoped to the remediation diff.
Layers: author and diff-scoped reviewers missed it; class sweeps after the round-12 REJECT caught it.
Rule next time: every read of per-account state names the account it was read for, and an async chain re-checks that account after each await before a side effect.

## 2026-10-16 - S02 conflict surface assumed a single account (class sweep after round 12)

Kind: FAILURE.
Facts: the sync repository filled its conflict cache and assembled its state across awaits without re-checking the account, and a pass could run while the account deletion completed; the conflict presenter and the local export were not scoped to the account, and my own batch G republished the state but left the sheet drawing the old cards. Evidence: core/changes/2026-10-16-s02-remediation-h-b-deletion-and-cache-fills.md and the following H-B change records.
Root cause: the author of the presenter and export did not scope them to the account; earlier reviews were scoped to the remediation diff; the third-round class sweep found it.
Layers: author, tests (no first frame of the new account asserted), reviewers (diff scope) missed it; the class sweep caught it.
Rule next time: sweep a defect class across the whole surface and test the first frame of the new account.

## 2026-10-16 - Sheet kept drawing the old cards after batch G republished the state

Kind: FAILURE.
Facts: the conflict sheet drew view.conflicts and view.candidates after its loading/error/empty chain, so an error or first frame of a new account still showed the previous cards; the presenter had no uid dependency. Evidence: core/changes/2026-10-16-s02-remediation-h-b-presenter-and-sheet.md.
Root cause: my own batch G republished the state but did not check what the sheet draws in the error state; no test looked at the first frame of the new account.
Layers: author and tests missed it; the class sweep caught it.
Rule next time: for every state-reset fix, assert what the widget draws in the first frame and in the error state.

## 2026-10-16 - S02 startup closure had no uid re-check between awaits

Kind: FAILURE (third part of the round-12 MAJOR).
Facts: the closure awaited syncAll, signIn, load and runPending in sequence with a uid check only after the journal bind; resume was called before consent was known. Evidence: core/changes/2026-10-16-s02-remediation-h-a-startup-wiring.md.
Root cause: the earlier account-switch fixes covered the bind step only; no test interleaved an account switch into each later await.
Layers: author, diff-scoped reviewers and epic tests missed it; the external gate caught it.
Rule next time: one current() predicate per async chain, re-checked after every await; one mid-flight switch test per await.

## 2026-10-16 - Wipe and export hooks acted on whatever account was bound at call time

Kind: FAILURE.
Facts: onSignOut asked the user and then wiped the journal bound at that moment; exportAll could mix entries of two accounts. No production caller yet. Evidence: core/changes/2026-10-16-s02-remediation-h-b-wipe-and-export.md.
Root cause: the author of these hooks did not scope them to the account; reviews were scoped to the remediation diff, so latent callers were never in scope.
Layers: author and reviewers missed it; the class sweep caught it.
Rule next time: an interface that will gain a caller later is reviewed for account binding now, not when the caller lands.

## 2026-10-16 - H-B documents written with the code

Kind: SUCCESS.
Facts: the test notes name the oracle for each guard and the stale fakes in the same batch as the code. Evidence: core/changes/2026-10-16-s02-remediation-h-b-docs.md.
Why it worked: oracles written from the findings, each tied to a guard whose removal must fail it.

## 2026-10-16 - S02 remediation H-A notes derive stale tests from a grep, not from interfaces

Kind: SUCCESS.
Facts: following the earlier lesson, the notes list older assertions by grepping the tests for the changed behaviour (write before sign-in, once-per-instance delete, resume order, uploader with an in-memory client). Evidence: core/changes/2026-10-16-s02-remediation-h-a-test-notes.md.
Why it worked: the earlier retrospective rule was applied before the brief, not after the runs.
Rule next time: keep grepping tests for the old behaviour whenever a contract changes.

## 2026-10-16 - Mid-flight skip after the tombstone listing was not logged

Kind: SHORTCOMING.
Facts: The H5 notes require the account-deleting skip to be logged, but syncAll returned silently when the identity went stale after listTombstoneIds; only the start-of-pass skip logged. Evidence: core/changes/2026-10-16-s02-test-epic14b-deletion-flag.md.
Root cause: the author added the log to the start check only. Layers: author and reviewers missed it; the epic 14b oracle (log line after a mid-flight flag) caught it. Rule next time: every early return of a pass either logs a reason word or is documented as silent.

## 2026-10-16 - H6 presenter and sheet compiled and met every oracle

Kind: SUCCESS.
Facts: The remediation H presenter, uid provider and sheet changes compiled unchanged and passed 7 new tests on the first run; the older presenter and sheet tests also passed (+28). Evidence: core/changes/2026-10-16-s02-test-epic14b-presenter-sheet.md.
Why it worked: the guards are small and the H-B notes named the stale tests exactly. Limit: the tests use the real container and a fake auth stream, so the real FirebaseAuth stream timing is not covered.

## 2026-10-16 - H6 and H7 guards met every oracle at the first compiled run

Kind: SUCCESS.
Facts: All 11 tests passed on the first run, with a positive control for each guard (matching expectedUid resolves; no switch serves the cloud values). Evidence: core/changes/2026-10-16-s02-test-epic14b-stale-state.md.
Why it worked: each test blocks the exact await with a Gate and switches the account there, so the guard is the only thing between the stale result and B. Limit: the window between a passing _alive check and the delegated journal write is not closed (accepted limit).

## 2026-10-16 - Remediation H-A compiled unchanged; stale fakes were the only breakage

Kind: SHORTCOMING.
Facts: The "never compiled" H-A production code compiled as is. Five _Settings fakes threw UnimplementedError for reset() and four older tests broke on the new contract (e.g. +13 -1 resume test, +0 -7 uploader tests where consent was uid-agnostic). The notes listed the fakes but not that tests flipping the uploader uid also need consent that follows it. Evidence: core/changes/2026-10-16-s02-test-epic14a-stale-fakes.md.
Root cause: the uploader test fixtures assumed uid-agnostic consent. Layer that missed it: H-A authors (notes incomplete). Caught by: first compiled runs of the test layer. Rule next time: when a view gains a uid, grep every fixture that varies the uid supplier.

## 2026-10-16 - H8 wipe and export guards met every oracle at the first compiled run

Kind: SUCCESS.
Facts: All 12 tests passed on the first run; positive controls cover the no-switch wipe, declined prompt, empty journal and plain journal. Evidence: core/changes/2026-10-16-s02-test-epic14b-wipe-export.md.
Why it worked: the guards compare a captured uid with the bound uid at each await, which a hook that switches the bound uid inside the awaited call exercises directly. Limit: no production caller exists yet, so the tests exercise the hooks, not a UI.

## 2026-10-16 - Stale-view promise holds end to end

Kind: SUCCESS.
Facts: The journey passed at the first run; logs show the queued pass skipped as pass-identity and the tap as uid-changed. Evidence: core/changes/2026-10-16-s02-test-epic14b-stale-view-e2e.md.
Why it worked: both accounts hold the same deterministic id, so any missing guard would have crossed accounts. Limit: auth stream timing is simulated by a mutable provider.

## 2026-10-16 - Epic 14b: remediation H-B verified by 41 new tests

Kind: SUCCESS.
Facts: Complete H-B run: 02:46 +167 passed; one observability shortcoming found (silent mid-flight skip) and fixed. Evidence: core/changes/2026-10-16-s02-test-epic14b-findings.md.
Why it worked: oracles written from the notes and the promise, one Gate per await, positive controls for every guard.

## 2026-10-16 - H-A guards met every interleaving oracle; one oracle slip of mine

Kind: SUCCESS.
Facts: All consent store, client, uploader and startup guards of remediation H-A passed 42 gated interleaving tests with no production change; my first run was +41 -1 because test 16d expected B to finish while A held the journal bind, but the scoped journal serializes binds, so B waits behind A (my oracle slip, caught by the first run; fixed by releasing A first). Evidence: core/changes/2026-10-16-s02-test-epic14a-consent-binding.md.
Why it worked: each test holds the exact await (platform store read, syncAll, signIn, load, commit) so the guard is the only protection. Limit: no mutation run by operator rule; the real uploader provider supplier for accountBeingDeleted is untested.

## 2026-10-16 - Sync repository is single-flight: B waits behind a stalled A pass

Kind: SHORTCOMING.
Facts: My first e2e run (+1 -1) expected B to reach its consent step while A was held in syncAll; it does not, because the repository joins the in-flight pass. Safe for the promise (nothing runs for B earlier than A) but it delays B until A releases. Evidence: core/changes/2026-10-16-s02-test-epic14a-consent-switch-e2e.md.
Root cause: my oracle assumed independent chains. Layer that missed it: me (test author); caught by the first run. Rule next time: check single-flight and serialization in the seam before writing a stall-then-switch test.

## 2026-10-16 - Epic 14a closed green

Kind: SUCCESS.
Facts: Complete run of my tests plus the repository, e2e and config directories ended +784 all passed. The only breakages were stale fakes and assertions (notes incomplete on uid-flipping uploader tests). Evidence: docs/phase2/s02/S02_TEST_FINDINGS_EPIC14.md.
Why it worked: Completer gates on exact awaits. Rule next time: when a view gains a uid, grep fixtures that vary the uid supplier.

## 2026-10-16 - docs(s02): test epic 14c final run findings

Kind: SUCCESS.
Facts: Four one-at-a-time complete runs on cf1a4eb5 (after the activityDelete quota change) were all green: +1389, +120, 791 and 315 tests; no stale oracle or production defect surfaced. Evidence: docs/phase2/s02/S02_TEST_FINDINGS_EPIC14.md.
Why it worked: earlier epics already fixed stale fakes; running serially avoided jest timeouts. Open item: jest reports a worker that failed to exit gracefully in the activity run (possible leaked handle), not investigated.

## 2026-10-16 - fix(s02): tie state reads to the auth uid (remediation I1)

Kind: FAILURE.
Facts: The state read path (`refreshState`) compared the journal uid and the auth uid only for movement during the read, never for agreement, so in the account-flip gap A's cards could be emitted under B, although remediation G1 had already tied sync passes to the auth uid. Evidence: core/changes/2026-10-16-s02-remediation-i-display-tie.md.
Root cause: the author of remediation H did not tie the display path to the auth uid although G1 had tied the pass; the guard was added to one path and its sibling path reading the same identity pair was not searched. Layers that missed it: author, epic 14 tests (no test exercised the display gap), first verification review; caught by the second verification review round (reliability).
Rule next time: when a guard is added to one path, grep for every sibling path that reads the same identity pair (here `_beginPass` vs `_viewStamp`) and give each the same guard or an explicit reason.

## 2026-10-16 - fix(s02): consent contract with an unbound store and early consent bind (remediation I2)

Kind: FAILURE.
Facts: With an unbound consent store the settings client sent the server call and only then failed on the store write, leaving the server and client disagreeing and a null key in `_unpersistedWithdrawals`; the store was bound only after the journal bind and the whole `syncAll`, so the unbound window was long. Evidence: core/changes/2026-10-16-s02-remediation-i-consent-contract.md.
Root cause: the author of H bound the consent store behind unrelated steps and checked the uid only by equality, so null equalled null. Layers that missed it: author, epic 14 tests (none exercised an unbound store), first verification review; caught by the second verification review round (security).
Rule next time: bind per-account state as early as it can be bound, and make every mutator refuse before any side effect when its owner is unknown.

## 2026-10-16 - docs(s02): remediation I accepted limits and test notes

Kind: NEUTRAL.
Facts: Documentation of four accepted limits and the I1/I2 test oracles; the old design sentence about the bind gap was narrowed because I1 changed it. Evidence: core/changes/2026-10-16-s02-remediation-i-docs.md.

## 2026-10-16 - test(s02): epic 15 stale assertions after remediation I

Kind: FAILURE.
Facts: Remediation I compiled unchanged but 27 existing tests failed on the first whole-directory run (12 in the withdrawal test and 2 in the stream upload test on an unbound in-memory store, 13 on the old start order or on "consent failure blocks bind and sync"). One production regression: the early `current()` check made the `account is being deleted; sync not started` log unreachable (republish test G4). Evidence: core/changes/2026-10-16-s02-test-epic15-stale-assertions.md.
Root cause: the implementer compiled and ran nothing, and the H test notes listed the stale files incompletely (the e2e consent test, the journal wipe wiring bind-failure case and the FL6 load-throws case were missing; the log regression was not foreseen). Layers that missed it: author, notes; caught by the epic 15 baseline run.
Rule next time: after a contract change run the whole affected directory once before writing the notes, and when a new early return is added in front of a branch, grep the logs and tests that observed that branch.

## 2026-10-16 - test(s02): epic 15 I1 display-tie tests

Kind: SHORTCOMING.
Facts: My first widget control (real repository, loaded conflict, pumped sheet) hung the fake-async binding for minutes with no timeout firing; I moved the control to the presenter. Cause not investigated. Evidence: core/changes/2026-10-16-s02-test-epic15-i1-display-tie.md.
Root cause: unknown; real file and crypto futures started inside the fake zone. Layer that missed it: my test design; caught by the first run.
Rule next time: run setup and reads of real journals under runAsync or in plain tests, and wrap a first widget run in an outer timeout.

## 2026-10-16 - test(s02): epic 15 I2 consent-contract tests

Kind: SUCCESS.
Facts: Remediation I2 production code met every I2 oracle on the first compiled run (9 of 9). The only slip was mine: a listener exception is reported to the zone of the container, so the test creates the container inside a guarded zone. Evidence: core/changes/2026-10-16-s02-test-epic15-i2-consent-contract.md.
Rule next time: create the container inside the zone that is meant to receive listener errors.

## 2026-10-16 - docs(s02): epic 15 final runs and findings

Kind: SUCCESS.
Facts: Whole activity directory +1410 and the second set +120 green after 27 stale tests and one log regression were fixed; production remediation I otherwise met every oracle. Evidence: docs/phase2/s02/S02_TEST_FINDINGS_EPIC15.md.
Why it worked: running the whole directory once first gave the complete stale list instead of guessing from the notes.

## 2026-10-16 - S02 external gate round 12: consent cache shared by all accounts

Kind: FAILURE (coordinator briefs and reviewer scoping), caught by the external gate.
Facts: GPT-PM round 12 on 10288e57 accepted the three round-11 findings as resolved and rejected for one MAJOR: AccountScopedConsentStore kept one mutable store for all accounts and the startup chain did not re-verify the account after its awaits, so B's GPS data could be uploaded on A's consent (activity_wiring.dart). I verified it against the source before acting. Evidence: reply stored in the scratchpad as s02_code_review_r12.json; remediation H and I.
Root cause: my briefs to the independent reviewers limited them to the diff of the remediation, and the consent path was not in that diff; the original consent wiring was designed for one account; the epic tests never interleaved two accounts through the consent path.
Layers: original author of the consent wiring, my reviewer briefs (scope), epic 7 to 13 tests; the external gate caught it.
Rule next time: when a defect class is found (state not bound to the account, stale async completion), sweep the WHOLE surface by class with independent reviewers, not the diff, before resubmitting; and bind per-account state as early as it can be bound.

## 2026-10-16 - S02 class sweep by three independent reviewers

Kind: SUCCESS.
Facts: after the round-12 rejection three reviewers (security, reliability, Flutter) enumerated every per-account state item and async chain in the activity surface and found the consent defect plus real siblings that no earlier review or test had found: sync and uploads continuing during account deletion, grant and withdraw applying to the wrong account, a once-per-instance deletion flag shared by accounts, the conflict sheet drawing the previous account's cards, a tap queued under A running under B, cache fills after a switch, an unbound sign-out wipe and export. All were fixed in remediation H with interleaving tests.
Why it worked: the brief asked for an inventory table (item, identity captured, re-checked after each await) before findings, so the reviewers could not skip an item.
Layers: caught what the diff-scoped reviews and the epic tests missed.
Rule next time: for any account-scope or concurrency defect class, require an inventory table from the reviewers before findings.

## 2026-10-16 - S02 verification reviews of remediation H and I found two more gaps in the fixes

Kind: SHORTCOMING.
Facts: the verification review of H found that the display path (refreshState and the sheet) did not tie the journal uid to the auth uid although G1 had tied the pass, and that the consent store was bound only inside the sync-start chain, so grant and withdraw on an unbound store sent the server call and then threw. Both were fixed in I. One reviewer also claimed that account deletion in flight was not covered; I checked firestore.rules (the fence at activity_account_state) and recorded it as closed by the server, not a defect.
Root cause: a guard was added to one path and the sibling path reading the same identity pair was not grepped; per-account state was bound behind unrelated steps.
Layers: the H implementer and the epic 14 tests missed it; the second verification round caught it.
Rule next time: when a guard is added, grep every sibling path that reads the same identity pair; verify a reviewer claim against the primary source before acting (it can be right or already covered).

## 2026-10-16 - Commit: fix(s02): bind server activity callables to the initiating account (remediation J1)

Kind: SHORTCOMING.
Facts: GPT-PM round 13 found that ActivityCloudSettingsClient grant and withdraw checked only the locally bound consent-store uid, while the Firebase callable runs as whoever is signed in when the token is read and the server resolves the account from request.auth. A flip from A to B between the check and the token read changes B consent. The same class covers setActivityCloudSettings, createActivityStreamUpload, commitActivityStream and deleteActivity. Evidence: core/changes/2026-10-16-s02-remediation-j1-server-expected-uid.md and S02_DESIGN.md section 17 item 25.
Root cause: the round 12 class sweep inventoried per-account state and async chains but never asked whether the identity travels WITH each outbound call that is authenticated only by ambient credentials.
Layers: missed by the H and I implementers, by the sweep brief, and by tests that moved the store bound uid instead of the live auth source; caught by the external gate.
Rule next time: any outbound call authenticated by ambient credentials carries the initiating identity in the request and the receiver verifies it before any side effect.

## 2026-10-16 - Commit: fix(s02): bind client activity calls to the initiating account (remediation J2)

Kind: SUCCESS (with an open verification debt).
Facts: the Dart half of the invocation-bound identity: settings client with a live-uid supplier and pre-call checks, expectedUid on the stream callables and the tombstone pusher, the server pair mapped to the existing account-changed outcome. Evidence: core/changes/2026-10-16-s02-remediation-j2-client-expected-uid.md. Nothing was run; tests of mobile/test do not compile until the fakes are updated (listed in the test notes).
Why it worked: the server contract (J1) was fixed first with an exact error pair, so the client mapping compares the message and does not depend on guesses; one shared helper maps the pair in all three real clients.
Layer: author only so far; test agents and reviewers pending.
Rule next time: change a shared seam signature together with a written list of every fake and call site, so the test agent starts from a known compile-break list.

## 2026-10-16 - Commit: refactor(s02): move the account-changed outcome to its own file (remediation J2)

Kind: SHORTCOMING (caught by the coordinator's diff review before any test run).
Facts: the J2 implementer imported the settings client library into the stream uploader, the sync repository and the tombstone pusher only to reach the account-changed exception, while the settings client already imports the uploader. That made an import cycle between two repository libraries. The existing import-graph test guards only the data directories, so no test would have flagged it. Evidence: core/changes/2026-10-16-s02-remediation-j2b-account-changed-file.md.
Root cause: the brief named the exception but not where a shared type should live; the implementer took the shortest import.
Layers: the implementer and the brief; the coordinator's review of the diff caught it; no automated check covers repository libraries.
Rule next time: when a brief adds a type used by several libraries, name the file that owns it; review the import direction of every new import in a diff.

## 2026-10-16 - Commit: test(s02): send expectedUid from the activity test support (epic 16a)

Kind: SUCCESS.
Facts: the two support files were the only places where the existing activity tests reach the four handlers; adding the key there kept 744 of 745 activity tests green with no per-test edits. The one red test was a 5 s timeout of a 32 MiB validator test under parallel load; it passed alone. Evidence: core/changes/2026-10-16-s02-test16a-1-central-fixes.md.
Why it worked: the J1 test notes listed the central fix points from the call graph before any run. The red state before the fix was not observed (the fix was applied before the first run), so the claim that these tests would have failed rests on the notes, not on a measurement.
Layer: tests (author).
Rule next time: when a seam gains a required request key, fix the shared request builders first and keep an explicit-key escape hatch for negative tests.

## 2026-10-16 - Commit: test(s02): add expectedUid helper and handler tests (epic 16a)

Kind: SHORTCOMING (the test notes were inexact; a failing new test caught it).
Facts: the notes said the strict parser still refuses an unknown extra key for all four handlers. Running the new tests showed that createActivityStreamUpload, commitActivityStream and deleteActivity use lenient parsers that ignore unknown keys (existing F60 behavior pinned in callable_hardening.test.ts); only settings is strict. A first draft of my own helper test (an inherited prototype key) also asserted behavior the helper does not have; JSON request data cannot carry inherited keys, so that test was dropped. Evidence: core/changes/2026-10-16-s02-test16a-2-new-tests.md.
Root cause: the notes were derived from reading, not from a run; my first draft also seeded data inside a body builder after taking the snapshot.
Layer: the notes (author) missed it; the new tests caught it.
Rule next time: confirm each strict-parser claim against the specific parser before writing the assertion, and keep request builders free of side effects.

## 2026-10-16 - Commit: docs(s02): record the epic 16a server test findings

Kind: SUCCESS.
Facts: findings document for epic 16a server written from the actual run output, including the unrelated timeout flake and the inexact note. Evidence: core/changes/2026-10-16-s02-test16a-3-findings.md.
Why it worked: results were quoted verbatim and the unverified parts were listed.
Layer: tests.
Rule next time: quote result lines verbatim and say what was not run.

## 2026-10-16 - Commit: fix(s02): bind the remaining activity callables to the initiating account (remediation J3a)

Kind: SHORTCOMING.
Facts: the J1 fix bound four callables to the initiating account but left two callables of the same class (getActivityStreamDownloadUrls, deleteAllActivityStreams) unbound, because the J1 brief named four. Three independent class-sweep reviews found them. Evidence: core/changes/2026-10-16-s02-remediation-j3a-server-more-callables.md.
Root cause: the fix was scoped from a list of names instead of the whole class; design item 25 even recorded the two as "outside this item".
Layer: author and the J1 brief missed it; the class-sweep reviewers caught it.
Rule next time: when binding or hardening a class, enumerate ALL members of the class first (every onCall export) and add a structural test that fails when a new member lacks the guard.

## 2026-10-16 - Commit: fix(s02): class sweep findings in the client activity calls (remediation J3b)

Kind: SHORTCOMING and SUCCESS.
Facts: three independent reviewers found the same withdrawal-durability gap on their own, which confirms it is real; the sweep with an inventory table worked and found the two unbound callables and five client gaps. But the reviewers hit turn limits and two surface files were never read by anyone. Evidence: core/changes/2026-10-16-s02-remediation-j3b-client-class-sweep.md.
Root cause: a whole-surface sweep was given to too few reviewers, and partial reports were not required.
Layer: reviewers (coverage) and the brief author missed the unread files; the independent overlap caught the main defect.
Rule next time: split a whole-surface sweep over more reviewers or per area, and require a partial report with an explicit list of files not read.

## 2026-10-16 - Commit: test(s02): server tests for remediation J3a (epic 16a2, 1/2)

Kind: SUCCESS and SHORTCOMING.
Facts: the structural scan makes the J1 shortcoming (a guard added to a named list of handlers) mechanical; the first run failed only on my own test bugs (an unused variable, and a log assertion that ignored the log accumulating across tests). The J3 notes list of stale call sites was complete (Grep found one more stale assertion in callable_hardening.test.ts: "deleteAll ignores the body"). Evidence: core/changes/2026-10-16-s02-test16a2-1-server-tests-j3a.md.
Root cause: logger mock accumulates across tests, so a "not logged" assertion needs a mockClear first; the notes were derived from reading, so a Grep pass is still needed.
Layer: tests (author) caught both.
Rule next time: clear the logger mock before asserting the absence of a log line; always Grep for assertions that encode the old behavior, not only for call sites.

## 2026-10-16 - Commit: docs(s02): findings of test epic 16a2 server (J3a)

Kind: FAILURE (implementation, caught by tests).
Facts: J3a moved a line-pinned allowlist target in delete_all_streams.ts from line 201 to 203; three policy tests are red. Evidence: S02_TEST_FINDINGS_EPIC16.md, section 16a2 server, finding 1.
Root cause: the checker pins allowlist entries to line numbers and the J3a author did not run or search for the pin when inserting lines above it.
Layer: author missed it; the broader policy suites caught it.
Rule next time: after inserting lines in a file named in scripts/ci/check_data_access_policy.js, update the pinned line in the same commit (Grep the file name there).

## 2026-10-16 - Commit: fix(s02): repin the data-access allowlist line for delete_all_streams

Kind: SHORTCOMING (caught by the test agent of epic 16a2 on its first broader run).
Facts: remediation J3a added an import and a guard block to functions/src/activity_streams/delete_all_streams.ts, which moved a `.collection(...)` call from line 201 to line 203. scripts/ci/check_data_access_policy.js pins its allowlist entry for that call to a line number, so the checker reported a violation and three tests went red (two in s02_remediation_a_policy.test.ts and one in activity/lifecycle_policy.test.ts). Evidence: S02_TEST_FINDINGS_EPIC16.md section 16a2.
Root cause: the implementation brief did not say that implementers run no tests, so nobody grepped scripts/ci for the edited file name; an allowlist pinned to line numbers breaks on any unrelated edit above the pinned line.
Layers: the J3a implementer and my brief missed it; the test agent caught it.
Rule next time: before editing a server file, grep scripts/ci and the policy tests for its name; the briefs of implementers who run no tests must say so and list the pinned scripts to update. A line-pinned allowlist is fragile, but it is a secondary mechanism: update the line, do not redesign it.

## 2026-10-16 - Commit: test(s02): Dart compile fixes for remediation J2/J3b (epic 16b, 1/3)

Kind: SHORTCOMING (tests left stale by a signature change; found by the test agent).
Facts: J2 added required parameters to the settings client, the stream client fake and the tombstone pusher typedef; the implementer ran no tests, so about 17 test files did not compile. After the compile fix the only red assertion was the presenter test of activity_sync_pass_identity_test.dart (group C), which tapped with no uid and expected a repository failure; J3 B4 makes that tap a no-op.
Root cause: implementers run no tests by the sprint rules, so signature changes surface only in the test phase; the J test notes listed the files, which made the fix mechanical.
Layers: the implementer could not catch it; the test agent caught it on the first grouped run.
Rule next time: keep the stale-test list in the remediation notes (it worked); a test that depends on an ambient provider value (here the uid) should set it explicitly.

## 2026-10-16 - Commit: test(s02): settings client tests for remediation J2/J3b and findings 16b (epic 16b, 2/3)

Kind: SUCCESS (no defect found).
Facts: 33 new tests passed on the first run; the repository directory ran 749 tests green. Evidence: S02_TEST_FINDINGS_EPIC16.md section 16b.
Why it worked: the guard points of the client are synchronous read counts, so a supplier answering A for N reads flips the account at an exact point; the J notes gave the read order.
Layers: tests pinned the behavior; red-before-fix was not observed (no mutation runs by rule).
Rule next time: count the live-uid reads of a client path once in the test header and parametrize the flip point over them.

## 2026-10-16 - Commit: test(s02): uploader, tombstone, presenter and real client tests for remediation J2/J3b (epic 16c, 1/2)

Kind: SHORTCOMING (author, caught by the first run).
Facts: the first run had a compile error (FirebaseFunctionsException message is non-null) and one wrong expectation of mine: I expected the retry budget to persist after a clean pass, but a clean pass resets it; both were test bugs, no product defect. 42 tests passed after the fix.
Root cause: I did not read the reset rule in the sync pass before writing the budget assertion.
Layers: author missed it; the first run caught it.
Rule next time: read the reset and bookkeeping rules of a counter before asserting its value across passes.

## 2026-10-16 - Commit: test(s02): stale presenter test fix and findings 16c (epic 16c, 2/2)

Kind: FAILURE (test suite left stale by an implemented behavior change).
Facts: the full activity run failed 7 tests of sync_conflict_presenter_test.dart and one widget test hung past the 60 s timeout; the J3b notes listed the presenter change but my grep for affected tests missed this file. After the uid override the run passed (1485). Evidence: S02_TEST_FINDINGS_EPIC16.md section 16c.
Root cause: the stale-test list was derived from reading and I did not grep syncConflictPresenterProvider users in 16b.
Layers: author missed it; the complete directory run caught it.
Rule next time: grep every user of a changed provider or contract and run those files before the final complete run.

## 2026-10-16 - Commit: test(s02): final server run and large-filler timeouts (epic 16d)

Kind: SHORTCOMING and SUCCESS.
Facts: two tests building 32 MiB inputs hit the 5 s default timeout in the full parallel run (first 1, then 2 tests), pass alone; the repin 5ec1acc1 turned the three policy tests green. Evidence: S02_TEST_FINDINGS_EPIC16.md, section 16d.
Root cause: heavy-input tests were left on the default timeout; the earlier epic noted the flake but did not fix it.
Layer: tests (author) left it; the full run caught it.
Rule next time: give any test that allocates tens of MiB an explicit timeout when it is written.

## 2026-10-16 - Commit: docs: S02 report, state and retro after external gate round 13

Kind: SUCCESS (the remediation process), with two SHORTCOMINGS of mine recorded.
Facts: gate round 13 on 0096dd88 returned REJECT with one MAJOR; it was verified against the source, and the whole class (outbound calls authenticated by ambient credentials) was fixed on the server and the client, swept again by three independent reviewers with an inventory table, fixed in one batch (J3), reviewed once more read-only (no BLOCKER or MAJOR), and covered by test epic 16 (final complete runs: Dart 1485 and 120, server 922 and 315 tests, all green by the test agents). Evidence: docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md, core/changes/2026-10-16-s02-documents-after-round-13.md.
Why it worked: the inventory table forced the reviewers to list every operation, which surfaced two unbound server callables and four client gaps that a diff review would not have; the fix was applied to the whole class, not to the four members named by the finding.
SHORTCOMING 1 (mine): the first send of gate round 13 used the worktree folder as the project folder, but the project is registered on the main repository folder, so the send failed with a binding error and nothing was sent; I noticed it from the reply and resent. Rule: send every gate round with the same project folder as the previous rounds (the main repository folder).
SHORTCOMING 2 (mine): the review and test agents have small turn limits; four of them stopped without a final report on the first run and had to be resumed (the J1 implementer left its work staged but uncommitted, and I reviewed and committed it myself). Rule: give agents narrower tasks, tell them to batch tool calls and to commit early, and expect to resume.
Layers: caught by my own check of the reply, and by the resume handling.
Rule next time: see the two rules above; for a gate resend, copy the previous command line exactly.

## 2026-10-16 - Commit: docs: record operator answers after the S02 merge

Kind: SHORTCOMING (mine, plan and communication), with one near-miss.
Facts: after the S02 gate the operator asked two basic questions that the plan documents did not answer up front: whether Phase 1 is finished before Phase 2 and whether there will be two apps, and whether the design covers Android phone, iPhone, iPad, Android tablet and MacBook. The repository has only an `android` platform folder (no ios, macos or web), and the roadmap kept the tablet and large-screen layouts as an open question with a phone-only default, so the platform and form-factor scope had never been put to the operator as a decision. Near-miss: I edited `public/privacy.html` by hand and then saw from scripts/review/state_ledger.py that it is generated from the `legalPrivacyBody` key of app_en.arb and app_ru.arb; I reverted the edit before any commit. Evidence: core/changes/2026-10-16-s03d-record-operator-answers.md.
Root cause: the roadmap states sprints and defaults but has no one-page picture of what is released when, on which platforms and in how many apps; the privacy text is a generated file and I did not check for that before editing.
Layers: author (me); no reviewer or gate asks for a release and platform picture.
Rule next time: put the release picture (apps, platforms, form factors, release lines) on the first page of the roadmap and ask it as an operator decision at sprint zero; before hand-editing a file under public/ or core/, grep scripts/ for "generated" and for the file name.

## 2026-10-16 - Commit: test: rename a fake uid sentinel that the secret scanner flags

Kind: SHORTCOMING (mine, author).
Facts: after the S02 merge the full-history secret scan (gitleaks) went red with one finding. The only candidate is a unit test of the activity journal that declared a constant whose name contained the word "secret" and whose value was a made-up user-id marker ending in 7f3a91 (added in commit 2791285a, line 264 there). It is a made-up user-id marker, not a credential, but the variable name contains "secret" and the value has entropy 3.85, which matches the generic key rule. Evidence: core/changes/2026-10-16-gitleaks-false-positive-sentinel.md.
Root cause: I named a fake value after what it protects instead of what it is, and the scan is not run before a push (CI is not run locally by operator decision), so the first sign was a red job on the merged PR. Because the scan covers the whole history, a rename alone cannot clear it; the old commit needs an ignore entry.
Layers: author (me) introduced it; tests and reviewers could not see it (the test is correct); only the CI secret scan caught it.
Rule next time: never put secret, token, key, password or credential in the name of a test variable or value that is only a fake; call it sentinel or marker. The fingerprint added here is inferred (rule id and line are not from a scanner run), so the next secrets job is the only proof; check its output first.

## 2026-10-17 - Commit: S02 follow-up: apply the retention and privacy answers, close phase 9

Kind: FAILURE (mine and my agents', one defect class), plus one SUCCESS.
Facts: (1) `public/privacy.html` is generated from `scripts/legal/legal_text.py` by `scripts/legal/build_legal.py` (which also writes the legal keys of the two ARB files and `public/terms.html`), but it was hand-edited in three commits: 6dbe2392 (body scan wording), c7e30e9c (S02 routes and retention wording, by a test agent) and 7c4a404d (S02 remediation A, by an implementation agent). The source never received the wording, so one run of the generator, which its own docstring tells everyone to run, would have erased it and broken two jest policy tests that read the page; the rendered-versus-disk difference was 57 lines when measured. (2) The operator's post-merge retention answer ("never" is not offered) was not in the merged code: the constant `STREAM_RETENTION_NEVER_OFFERED` still said `true`, and the test for it branched on the constant so it passed either way. (3) Two more stale tests surfaced when the privacy surfaces were re-tested: one pinned the old "or never" sentence, one scanned a fixed 1200-character window of `functions/src/index.ts` for the booking sweep that had moved out of that window in commit ca40035e. (4) My own earlier statement that the page is generated "from the `legalPrivacyBody` key of the ARB files" was wrong: the ARB is also an output; the source is `legal_text.py`. Evidence: core/changes/2026-10-17-s02-followup-retention-privacy-phase9.md and docs/phase2/s02/S02_TEST_FINDINGS_EPIC17.md.
Root cause: no brief named the generator source, authors edited the file that is served, and the tests pinned the hand-edited output, so they guarded the wrong thing; nothing runs the generator check. The retention answer sat as an OPEN-DEFAULT in a constant and a conditional test that could not fail.
Layers: authors (me and two agents) introduced it; the tests pinned it; reviewers and GPT-PM never compared the page with its generator; I caught it only when applying the operator's answer and the acceptance agent flagged the constant.
Success: the OPEN-DEFAULT constants made the retention answer a one-line change, and a focused test agent run found a fifth test (`retention_purge.test.ts`) that depended on the old behaviour.
Rule next time: before editing any file under public/ or the legal ARB keys, find its generator (grep scripts/ for the file name and the word generated), edit the source and run the generator; name the source file in every agent brief. A conditional test that branches on the constant it checks is not a test: pin the decided value. The new `scripts/legal/test_build_legal_in_sync.py` is the mechanical guard.

## 2026-10-17 - Commit: docs: S03-D UI design contract revision 3 for all device families

Kind: SHORTCOMING (agent author, caught by reviewers) and SUCCESS (independent reviews).
Facts: revision 3 of the S03-D contract (window-size model, side rail, platform families, pointer and keyboard) went to product-ux-reviewer and a11y-architect separately; they found 4 and 3 MAJOR items (no BLOCKER) and converged on three defect classes: the rail column overflows a 360 dp high landscape window (6 items of 56 dp plus insets), two-pane layouts were sized from the window width instead of the content pane (the 840 dp rationale left out the rail, insets and gutters), and the Record surface form was specified in two sections that disagreed (by input device in one, by size class in the other). Further items: the rail Record slot appeared and disappeared per tab so the destinations moved under the cursor, the compact rail hid the running state, the scroll-position promise was untested, Esc was overloaded, and reduced motion covered tokens only. All items were remediated in one batch (section 19 of the contract). The designer agent stopped at its turn limit four times and was resumed each time. Evidence: docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md section 19 and core/changes/2026-10-17-s03d-ui-contract-revision-3.md.
Root cause: layout thresholds were stated in prose without the arithmetic, and one presentation rule was repeated in two places; a brief with twelve large changes does not fit into the 14 to 20 tool turns an agent gets.
Layers: the author missed it; the two reviewers caught it independently, which is why the findings could be merged with confidence; no gate would have caught it before build.
Rule next time: a contract states every size threshold with its arithmetic (pane width = window width minus rail minus insets) and keeps one table as the only authority for a surface's form, other sections only point to it. Brief design agents in chunks of three or four sections and expect two to four resumptions.

## 2026-10-17 - Commit: docs: S03-D fix the short-window chooser grid after the GPT-PM gate

Kind: SHORTCOMING (author and two internal reviewers), caught by the gate.
Facts: GPT-PM returned MODIFY on head 5302915e with 1 MAJOR and 2 MINOR. The MAJOR was a contradiction inside the contract that I verified in the text before fixing: the mode chooser rule said a short window uses a 4x1 grid, while cards had floors of 200 dp (Medium, content capped at 640 dp; four cards need 836 dp) and 140 dp (Compact, 360 dp window; four cards need 560 dp), so the acceptance criteria could not all pass. The old 140 dp floor was also 2 dp wrong at a 320 dp phone ((320 - 32 - 12) / 2 = 138). The MINOR items: an acceptance criterion that hard-coded the 96 dp rail before applying the measured-width rule, and a stale privacy status line. Evidence: docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md (grid rule in S-1, section 19 gate round 1 table) and core/changes/2026-10-17-s03d-gate-round-1-fixes.md.
Root cause: the contract gave a per-element minimum width and a per-situation column count in separate places and never wrote the check number of cards x minimum width + gaps against the available width for each size row; both internal reviewers re-checked the rail and pane arithmetic they had been told about but not this older rule, which came from revision 2.
Layers: author missed it; product-ux-reviewer and a11y-architect missed it; the GPT-PM gate caught it before any code existed.
Rule next time: for every layout rule of the form "N items in a row" or "minimum size X", the contract writes the fit check with numbers for each size row it applies to; reviewers get the instruction to re-derive every such check, including text inherited from an earlier revision, not only the ones that changed.

## 2026-10-17 - Commit: docs: record the S03-D documentation gate approval and its report

Kind: SUCCESS.
Facts: the S03-D documentation gate closed in two rounds: round 1 on 5302915e returned MODIFY (1 MAJOR, 2 MINOR); every item was verified against the contract text before it was fixed (the MAJOR was a real contradiction), all items were fixed in one batch, and round 2 on 45b9184b returned APPROVE with 0 BLOCKER and 0 MAJOR. Evidence: GPT-PM replies of request ids 9bdd45d1 and 6e9e542e, core/changes/2026-10-17-s03d-gate-round-1-fixes.md.
Why it worked: two independent internal reviews before the gate removed most defects (4 and 3 MAJOR findings, overlapping, fixed first), the scope note told the reviewer exactly what changed, and the fix was one batch that rechecked the arithmetic by hand.
Rule next time: keep the order internal reviews, one batch of fixes, external gate, one batch of fixes, verification round; and tell reviewers to recompute inherited rules (see the entry for the gate fixes).

## 2026-10-17 - Commit: docs: start sprint S03 on the operator GO

Kind: NEUTRAL.
Facts: sprint S03 starts only after the operator's explicit GO; the previous turn asked the question in plain words with the consequences of each answer, and the GO arrived as a short standalone message. The S03 state section lists the phases and artifacts so the sprint can be resumed from the repository alone. Evidence: docs/sdlc/STATE.md section S03 and core/changes/2026-10-17-s03-start.md.
Rule next time: record a GO in the decision log in the same commit that records the start state, and name the artifacts of each phase in the state file at once.

## 2026-10-17 - Commit: docs: S03 code map, technical design, test plan and internal review batch 1

Kind: FAILURE (inherited from S02, found by a reviewer of the S03 design).
Facts: the Android backup rules exclude `files/journal`, `files/sources` and `files/quarantine`, but the production journal root is `<support>/activity_journal/<scopeId>` with those three as children (uid_scoped_activity_journal.dart:47-55, journal_generation_writer.dart:35-37, backup_rules.xml:50-52, data_extraction_rules.xml:32-34 and 41-43). The real tree was never excluded. The S02 backup tests compared the XML with the same constants the code uses, so they stayed green. The S03 design had marked the question UNGROUNDED (R11) instead of reading three files; the security-reviewer and silent-failure-hunter established it independently and the coordinator verified it with Grep before it went into the design.
Root cause: an exclusion test derived its expected value from the constants under test, and a design left a one-Grep security fact open.
Layer that missed it: S02 author, S02 tests and S02 reviewers. Caught by: S03 internal review (security-reviewer, silent-failure-hunter). No user data was exposed: the journal flag is off in every shipped build and the journal has no writer before S05.
Rule next time: a path-exclusion or path-wipe test builds the real object (the factory, the real directory) and walks the files it created; a design must not leave a security fact UNGROUNDED when one Grep settles it.

## 2026-10-17 - Commit: docs: S03 code map, technical design, test plan and internal review batch 1

Kind: SHORTCOMING.
Facts: five independent reviewers (architect, flutter-reviewer, silent-failure-hunter, security-reviewer, tdd-guide) returned 0 BLOCKER and 21 root causes in the first S03 design and test plan; three of them (architect, flutter-reviewer, silent-failure-hunter) found the same race between the start-up migration and the onboarding hook, and four found that a journal that is still binding looks open and empty. Evidence: the disposition table at the end of docs/phase2/s03/S03_DESIGN.md (RV-1 to RV-19).
Root cause: the first draft gave several writers to one piece of per-account state, derived availability as "otherwise open", and reused a previous value without stamping the uid; the test plan used fakes where the real controller is the thing that can break and the default test font where the width rule needs a real measurement.
Layer that missed it: design author and test-plan author. Caught by: internal reviewers before any code existed.
Rule next time: for each per-account state name its single writer and stamp every async result with the uid and a generation; derive availability from positive facts, never from "otherwise"; a test that guards a running timer drives the real controller; a width rule needs a stub measurer that yields both outcomes.

## 2026-10-17 - Commit: docs: S03 code map, technical design, test plan and internal review batch 1

Kind: FAILURE (coordinator).
Facts: for remediation batch 1 the coordinator resumed the design author and the test-plan author in parallel and gave both the same decision list but no single registry of test ids; both invented new ids in the same id scheme, so the same id (for example DT-08-2, DT-07-7, DT-13-6, DT-01-9) named different tests in the two files. The coordinator found it only after both authors finished, by a mechanical set comparison of the ids (83 in the design, 144 in the plan, five design-only and 64 plan-only) and a sample of meanings. 94 lines of the design cited ids.
Root cause: shared decisions without a shared id owner; ownership of ids was not decided before parallel work started.
Layer that missed it: coordinator (brief). Caught by: coordinator, before any reviewer or the gate saw it.
Rule next time: when two authors write documents that cite each other's artifacts, name ONE owner of the id space in the brief (here the test plan) and tell the other author to cite, never to mint; run a set comparison of ids before a gate.

## 2026-10-17 - Commit: docs: S03 code map, technical design, test plan and internal review batch 1

Kind: SUCCESS.
Facts: reviewers with different scopes found different parts of the same defect classes, and merging them into numbered findings (RV-1 to RV-19 plus nine test-plan findings) allowed ONE remediation batch with the decisions fixed up front and the same file for each author; the documentation went through review before any code was written.
Why it worked: distinct role scopes, one finding contract, duplicates merged by root cause, decisions written down once and shared by both authors.
Rule next time: keep the numbered merged-findings file as the single input of the remediation batch.

## 2026-10-17 - Commit: docs: S03 one retry state machine for automatic and manual journal bind (GPT-PM MAJOR-01)

Kind: FAILURE.
Facts: GPT-PM documentation gate round 1 on 3bedcba4 returned MODIFY with one MAJOR: the test plan's DT-0-5 required that after a failed manual "Try again" no automatic retry follows (count stays 1 after 5 s of fake time), while the design kept the existing automatic bind retry (5 s, 15 s, 60 s, 5 min, 5 min) and added a manual retryNow() with the sentence "it does not touch the automatic back-off schedule". The coordinator verified it: activity_wiring.dart:101-164 and 189-204 keep one pending retry timer per generation and the plan row contradicted it.
Root cause: DT-0-5 was written from the pre-review semantics ("failedToOpen has no automatic loop"); the review batch then added a manual action next to an existing automatic mechanism (RV-3) without writing the combined state machine in one place, and the test was not re-derived from it.
Layer that missed it: design author (no combined state machine), test-plan author (kept an old expectation), coordinator (brief did not ask for a cross-check of new tests against retained mechanisms) and all five internal reviewers (none compared a test expectation with the retained retry code). Caught by: GPT-PM documentation gate.
Rule next time: when a design adds a manual action next to an existing automatic mechanism, write ONE state machine for both (states, who may start an attempt, what a failure does to the schedule) in the design and derive every test from it; tell reviewers to check each test expectation against the retained mechanisms in the code, not only against the design text.

## 2026-10-17 - Commit: docs: S03 one retry state machine for automatic and manual journal bind (GPT-PM MAJOR-01)

Kind: SUCCESS.
Facts: the gate returned a single MAJOR and no BLOCKER on a design of 21 stories and a plan of 452 tests; GPT-PM confirmed in its table that the single writer for the mode status, the three-way persisted-mode read, the uid and generation checks of the digests, the backup exclusion order, the element preservation of the shell, the owner uid of the timers and the lane ownership had no further proven BLOCKER or MAJOR, and accepted the sign-out guard refinement of contract J10.
Why it worked: five role-scoped internal reviews before the gate, one merged remediation batch with fixed decisions, mechanical set checks of test ids and counts before the commit.
Rule next time: keep the mechanical checks (id sets, sum of the count column, Cyrillic scan) as a standing pre-gate step.

## 2026-10-17 - Commit: docs: S03 failedToOpen is defensive, retryNow contract and per-generation rules (GPT-PM MAJOR-02, reliability review)

Kind: FAILURE.
Facts: GPT-PM documentation gate round 2 on 27d6dc44 closed MAJOR-01 and found MAJOR-02 inside the remediation: the rewritten DT-0-5 started from failedToOpen and expected both an open spy and a bind spy to have count 1 after a failed retry. An independent read-only reliability review run before round 3 (0 BLOCKER, 5 MAJOR, 4 MINOR) then showed that the whole idea of a separate "open attempt" does not exist in the code: the UidScopedActivityJournal constructor does no I/O and the factory is called only inside bindUid (uid_scoped_activity_journal.dart:58-127), so failedToOpen cannot be reached in production. The review also found an unspecified retryNow() and busy contract, single flight that must be per generation, an unspecified seam for the recovery counts that would have broken the existing retry test, and an 11 minute 20 second LOADING window before the error panel.
Root cause: the first remediation (round 1) and the coordinator's brief for DT-0-5 ("opener or bind spy count 1") were written from the design text, not from the control flow of activity_wiring.dart and uid_scoped_activity_journal.dart; the design invented an open step because an earlier review asked for a failedToOpen status.
Layer that missed it: coordinator (brief), design author, test-plan author, five internal reviewers (none traced the control flow). Caught by: GPT-PM round 2 (the count), then the independent reliability review (the root cause), both before any code existed.
Rule next time: before a gate round, trace every new state and every test expectation along the real call graph with numbers; run an independent read-only review of a state-machine remediation BEFORE sending it to the gate, not after; never invent a state that no code path can produce without saying that it is defensive.

## 2026-10-17 - Commit: docs: S03 failedToOpen is defensive, retryNow contract and per-generation rules (GPT-PM MAJOR-02, reliability review)

Kind: SUCCESS.
Facts: the independent review took about two minutes of reviewer time and removed a probable third GPT-PM round; its traces of nine scripts (manual failure, manual success, timer due during a manual attempt, gave-up, account switch during a manual attempt, sign-out while waiting, recovery failure) agreed with DT-0-11 to DT-0-14 and DT-13-11 (six bind calls) and with the existing retry test.
Why it worked: the reviewer was given the exact scripts to trace and the real code to compare with, and was told what previous reviewers had missed.
Rule next time: give reviewers a list of scripts to trace, not only a scope.

## 2026-10-17 - Commit: docs: record the S03 documentation gate approval and start the build

Kind: SUCCESS.
Facts: the S03 documentation gate ended in APPROVE on exact head 59828804 in round 3 (0 BLOCKER, 0 MAJOR), after MODIFY in round 1 (3bedcba4, one MAJOR) and round 2 (27d6dc44, one MAJOR). Each round found a real defect in the retry contract of the journal bind, and the independent reliability review run before round 3 found the root cause (a separate open attempt does not exist in the code). Evidence: docs/sdlc/STATE.md section S03, docs/phase2/s03/S03_DESIGN.md section 2.1 item 3.
Why it worked: every finding was verified against the code before it was accepted, remediation was written as numbered rules with tests derived from them, and mechanical checks (id sets, sum of the count column) ran before every commit.
Rule next time: send a state-machine remediation to an independent read-only review BEFORE the gate round.

## 2026-10-17 - Commit: docs: record the S03 documentation gate approval and start the build

Kind: NEUTRAL.
Facts: three attempts to send round 3 failed because the PM Bridge daemon was handing over to a new build (the error named two source builds changing, and the pm-bridge repository had uncommitted edits by another session); the request never reached the chat (recovery by request id found no inbound record), so resending created no duplicate. The fourth attempt went through after the other session's lifecycle operation finished and the mode came on by itself. The break-glass direct send was not used and the daemon was not restarted.
Rule next time: on 'source update did not complete', check recovery by request id first, then wait for the other session's lifecycle operation; never use the break-glass path while the normal path is merely busy.

## 2026-10-17 - Commit: fix(activity): exclude the per-account activity_journal tree from Android backup and device transfer

Kind: FAILURE (inherited from S02, found by the S03 design review, fixed here).
Facts: the S02 backup exclusion listed `journal`, `sources` and `quarantine` directly under the app support directory, but the production journal is created by `fileActivityJournalFactory` at `<support>/activity_journal/<scopeId>`, so the exclusion never matched the real tree. The journal is off in release builds and nothing is written to it before S05, so no user data was exposed. Evidence: mobile/lib/features/activity/repository/uid_scoped_activity_journal.dart (factory), mobile/android/app/src/main/res/xml/backup_rules.xml and data_extraction_rules.xml (before this commit), docs/phase2/s03/S03_DESIGN.md section 5 (finding found by the design review).
Root cause: the exclusion list and the factory path were written by two different stories and no test compared the directory the factory really creates with the directory the XML excludes. The tests asserted only the three names of the list.
Layer that missed it: author, tests and the S02 reviewers; the S03 design reviewers caught it before the journal was switched on.
Rule next time: a backup or privacy exclusion is tested against the path the production code really builds (one shared constant, now `kScopedJournalRootDirName`), never against a hand-copied list of names. The test agents extend the checker fixtures so that a list without `activity_journal` fails.

## 2026-10-17 - Commit: fix(activity): exclude the per-account activity_journal tree from Android backup and device transfer

Kind: SUCCESS.
Facts: the fix landed as its own commit BEFORE the default of the local journal flag is changed (build lane L1, run 1 of 3), which is the order the design review required (RV-13). The path is now one constant used by the factory, the exclusion list and both Android XML files.
Why it worked: the build brief fixed the order of the three runs of the lane and named the flag flip as a later run.
Rule next time: land the data-protection part of a change before the part that switches the data on.

## 2026-10-17 - Commit: feat(ui): add the window size class and optional focus, hover and semantics parameters to the HUD controls

Kind: SUCCESS.
Facts: build lane L3 wrote two stories (S03-03 HUD primitives, S03-02 window size class) in two runs without running anything; every new parameter of the HUD controls defaults to today's behaviour, and `HudPanel` and `HudSettingRow` pass `handlesKeys: false` so there is no second activation handler or extra tab stop. The exact hover colour is not specified by the UI contract (10.9); the implementation agent used the nearest existing token and said so in its report.
Why it worked: the brief required every default to reproduce current behaviour and named the files the lane may touch.
Rule next time: the test agents must prove the defaults (existing widget tests stay green unchanged) and the one cross-lane precondition: `WindowSizeScope` has to be mounted once above the router (main.dart, wave 4) for the rebuild-per-class guarantee of DT-02-3.

## 2026-10-17 - Commit: feat(modes): add the mode state models, the never-throwing codec and the per-account store

Kind: SUCCESS.
Facts: build lane L2 run 1 wrote the data layer of the mode state (models, codec, store) as pure Dart plus a thin SharedPreferences store. The store read is three-way (missing, value, unreadable with a reason), so a corrupt or newer-version value can never be mistaken for a missing key and overwritten (RV-2). The implementation agent reported its deviations from the design text itself (read returns a result type instead of a nullable state, write returns a result and never throws, the encoder accepts chooser status absent).
Why it worked: the brief named the risks from the review (RV-2, RV-14) and asked for a report of deviations and unknowns.
Rule next time: the wiped-uid guard needs a caller. The agent could not find one in its lane paths; the coordinator decided that the mode notifier listens to `accountBeingDeletedUidProvider` (set before the wipe) and marks the uid, so no security-sensitive wipe file is edited. A guard without a caller is a silent gap: the test agents prove DT-01-20 through the real deletion path.

## 2026-10-17 - Commit: feat(modes): add the mode notifier, the start-up migration and the warm-up provider

Kind: SUCCESS.
Facts: build lane L2 run 2 wrote the mode notifier (selectMode, resolveChooser, decideLater, markResolved, answerQuestion, skipQuestion, atomic initIfAbsent), the once-per-process migration and one warm-up provider. The wiped-uid guard reaches the store through `accountBeingDeletedUidProvider`, as decided after the run 1 report, so no security-sensitive wipe file was edited. The agent read the real profile provider (`currentProfileProvider`, onboarded = `UserProfile.hasCompletedOnboarding`) instead of guessing.
Why it worked: run 1 reported an open gap (nobody calls markUidWiped), the coordinator decided the seam before run 2 started.
Rule next time: a UNKNOWN in a lane report is answered with a concrete decision before the next run starts. Open risk to prove by the test agents: the first profile value can be null (Firestore cache miss while offline) before the real profile arrives; then an upgrader is not migrated in that process and is retried at the next start. Accepted as harmless (no chooser, no card); DT-01-14 covers the first-value rule.

## 2026-10-17 - Commit: feat(activity): turn the local journal on by default and add the bind retry state machine and journal availability

Kind: SHORTCOMING (one existing test is knowingly left red until the test agents update it).
Facts: the local journal flag default is now true. The existing test mobile/test/features/activity/config/activity_flags_test.dart (lines 75-79) asserts that `compileTime.localJournal` and `journalEnabled` are false, so it fails until updated. The design said the flag-matrix test encodes the old default; the implementation agent found that file does not, and the test that does is outside the lane ownership row.
Root cause: design section 4.4 states that activity_wiring_flag_matrix_test.dart holds a row "compile-time default => journal off" (cited from the code map) and lists every other reader of `ActivityFlags.compileTime` as UNGROUNDED; the design authors (coordinator and design writer) never opened the file to check the row, and the search the design deferred to the lane was not done before the brief was written. The implementation agent did search, found no such row in the flag-matrix test, found the real assertion in activity_flags_test.dart and reported it instead of editing a file outside its lane (correct behaviour).
Layer: author of the design and brief; caught by the implementation agent before any test run.
Rule next time: a design statement about the content of a test file is verified by opening the file; when a story changes a default, grep the tests for the old default while writing the design, not in the build. The epic 0 test agents update activity_flags_test.dart first and report it as a known precondition.

## 2026-10-17 - Commit: feat(activity): turn the local journal on by default and add the bind retry state machine and journal availability

Kind: SUCCESS.
Facts: lane L1 run 2 replaced the retry closure by a controller class with one state machine (single flight, busy result, preserved deadline after a failed manual attempt, generation-owned timer, stale completions touch nothing) and a bind-status notifier; the retry schedule and the existing log strings are unchanged. Recovery counts come from an optional read-only interface, so existing fakes keep working. The agent recorded nine decisions, including that status writes during provider build are deferred by a microtask.
Why it worked: the state machine was specified once as numbered rules before the build and the independent reliability review had already run on the text.
Rule next time: the controller is the highest-risk piece of the sprint; the reliability reviewer reads it against the seven rules before the code gate, and the test agents drive real controllers with the injected timer factory (DT-0-11 to DT-0-16).

## 2026-10-17 - Commit: feat(modes): record the onboarding choice and start the mode warm-up at the app root

Kind: SUCCESS.
Facts: lane L2 run 3 added exactly the two wiring edits the brief allowed: one awaited `initIfAbsent(onboarding)` call before `context.go('/home')` in the onboarding page, and one `ref.watch(modeWarmUpProvider)` line plus one import in `main.dart`. `_FitnessAppState` and its resume callback are untouched and no second `WidgetsBindingObserver` was added.
Why it worked: the wiring was kept for the last run, after the state layer existed, and each edit was specified to the line in the brief.
Rule next time: the test agents prove the three facts that matter here: a new user gets `pending` before `/home`, a failure never blocks the navigation, and `/onboarding/edit` for an onboarded user writes nothing (DT-01-12, DT-01-13, F-7). One small behaviour change to watch: if the page is unmounted during the awaited call, navigation is skipped (it was unguarded before).

## 2026-10-17 - Commit: docs: add the S03 documentation gate report pair for the operator

Kind: NEUTRAL.
Facts: the operator report of the S03 documentation gate (Russian for the operator, English as the durable record) was built from the draft written before the approval; the draft had to be corrected before publishing because two sentences ("code is not written yet", "nothing started") were already stale when the build had begun.
Rule next time: a report draft that is written before a gate verdict is re-read against the repository state (git log) at the moment it is built, not only filled in at the placeholders.

## 2026-10-17 - Commit: feat(activity): add the pure activity aggregates and the dashboard digest providers

Kind: SHORTCOMING (coordinator brief) and SUCCESS (agent behaviour).
Facts: the lane brief for run 3 gave the aggregates file the path `features/activity/state/`, while design 2.4 and the 9.2 ownership row say `features/activity/data/activity_aggregates.dart`; the agent followed the design and reported the conflict. The agent also found that the plan test DT-13-19 (an unmapped source kind is labelled 'Unknown source') cannot be written as planned: the label function switches exhaustively over `SourceKind`, so an unmapped kind does not compile, which protects better than a test but removes the test seam.
Root cause: the brief was typed from memory instead of copying the path column of the ownership table (coordinator); the plan row for DT-13-19 assumed a runtime fallback (plan author).
Layer: author (brief, plan); caught by the implementation agent.
Rule next time: lane briefs quote the paths of the ownership table verbatim. The test agent of epic 13 decides DT-13-19 (exhaustive switch kept; test the parsed-unknown case if `SourceKind` has one) and records it in the findings file.

## 2026-10-17 - Commit: feat(ui): add the adaptive surface route and the S03 routes with guarded mode questions

Kind: SUCCESS.
Facts: lane L5 wrote one route class that serves bottom sheet, popover and dialog, because a Flutter modal bottom sheet cannot turn into a popover while open and RV-9 requires live re-placement; the brief named three route types and the agent reported the deviation with its reason. The router is spliced once; the three stub pages live in `s03_routes.dart`, so later lanes replace their own page files and never edit the router. The first answer to the open availability question (a constant table) was replaced by the committed flags table read at router construction.
Why it worked: the agent reported UNKNOWNs instead of inventing a provider, and the coordinator answered each one with a concrete instruction.
Rule next time: the test agents prove the placement table (compact, medium, expanded), the depth counter reset on account change (late `closed` ignored) and the redirect of `/mode-questions/:mode` to Home with no write (DT-06-x, DT-09-6). Architect review checks the new import from `shared/widgets` to `features/auth`.

## 2026-10-17 - Commit: feat(workouts): add the active session status, the dock widgets and the session owner capture

Kind: SHORTCOMING (two gaps found while building) and SUCCESS (agent behaviour).
Facts: lane L4b stopped at the 20-turn limit once and was resumed; it finished the interface files first as briefed. Two gaps surfaced: (1) no lane owned the ARB files, so the dock code uses generated getters that did not exist (`recordPill`, `strip*`, `rail*`); lane L13 was created for both ARB files; (2) the screen-reader announcements for session started, paused, resumed and ended (contract section 12, AC-A11Y-4) are not written because an unmounted strip cannot announce its own end.
Root cause: the ownership table of design 9.2 covered code paths but not the two ARB files (coordinator design); the announcement host was not assigned to a lane.
Layer: design author; caught by the implementation agent's report.
Rule next time: when a design splits work into lanes, list shared resource files (ARB files, router, main.dart) as owned rows too. Carry-over: the persistent host (lane L4a shell) or the conformance fixes (lane L12) must write the announcements; the test agents keep AC-A11Y-4 as a failing-by-design finding until then.

## 2026-10-17 - Commit: docs: record the activity journal tree, the mode key and the Apple backup marking in the data documents

Kind: SUCCESS.
Facts: the doc-updater agent corrected three documents after story S03-0 landed and reported what it could not ground (the mode key surviving sign-out is marked INFERENCE in the matrix; the journal-on-sign-out behaviour is stated as 'as for the other local data' instead of a claim). It also found that core/DATA_INVENTORY_2026-08-11.md had no mention of the journal at all and added both rows.
Why it worked: the brief listed the code facts to verify and asked for UNKNOWN items instead of guesses.
Rule next time: the sign-out behaviour of the mode key and the journal is part of the S03-16 sign-out guard tests; when they are green, the two INFERENCE cells are turned into FACT in the documentation pass at the end of the sprint.

## 2026-10-17 - Commit: feat(shell): build the navigation bar and the side rail from one destinations list with the dock host

Kind: SHORTCOMING (design claim was wrong) and SUCCESS (agent behaviour).
Facts: design 2.6 says the bottom clearance of the bar presentation without a dock equals today's value. The implementation agent read the Flutter scaffold source and found it does not: with `extendBody` the body bottom padding is the bar height plus the inset, about 86 dp larger than the design's sum (14 + 72 + inset + 24). The agent kept the default build identical by building `ShellLayout` inside the body from the same body padding. The rewritten `main_shell.dart` also had to work without a `ProviderScope` because `back_navigation_test.dart` pumps `MainShell` bare; the agent detected the scope instead of changing that test.
Root cause: the design stated a number from the code map without deriving it from the framework source (design author).
Layer: design; caught by the implementation agent before any test run.
Rule next time: a design claim of the form 'equals today's value' is checked against the framework source or a measured value. The test agents measure the bar-presentation clearance against the pre-S03 value (AC-REG-x) instead of trusting the formula.

## 2026-10-17 - Commit: feat(l10n): add the S03 localization keys in English and Russian

Kind: SHORTCOMING (design gaps found while adding the keys) and SUCCESS.
Facts: lane L13 added 129 keys per language (groups 6.1 to 6.9: 20, 10, 15, 15, 10, 6, 29, 19, 5). The design left these open and the agent chose the nearest pattern: no `other` branch for the mode selects (fallback Train / Coming later / Record); English plural forms for five keys; Russian plural forms for `activityTimeFrom` and `activitySourcesMore` derived from the base phrase (marked as the agent's work that needs a translator check); `railMinutes` as a plain int placeholder because the table gave no plural forms; `activitySourceUnknown` named in the design but without a value (the existing `sourceLabelUnknown` covers it, key not added). The English text of `signOutConfirmDelete` was not a plural ('Delete 1 activities'); the coordinator made it a plural in this commit.
Root cause: design section 6 listed copy per key without a column for plural forms or select fallbacks (design author); no lane owned the ARB files until the build revealed it (see the L4b entry).
Layer: design; caught by the implementation agent and by the coordinator's read of the result.
Rule next time: the ARB parity test (S03-18) must check plural forms and select fallbacks, not only key sets; the pseudo-locale run and a Russian translator check cover the derived forms.

## 2026-10-17 - Commit: feat(shell): add keyboard shortcuts, the visible Back control and scroll helpers

Kind: SUCCESS.
Facts: lane L10 wrote the interface files first and reported its deviations: the Back shortcut does nothing on the home route (a key must not quit the app), and a matching key is consumed even when a guard stops the action. Two go_router APIs it uses (`routerDelegate.navigatorKey`, `currentConfiguration.uri`) were not checked against the pinned version.
Rule next time: the test agents prove the guards (no shortcut in a text field, none while a surface is open, tab shortcuts only on shell routes, Esc never navigates back) and compile-check the two router API uses first.

## 2026-10-17 - Commit: feat(app): mount the window scope and the shortcuts and refresh the digests on resume

Kind: NEUTRAL.
Facts: main.dart now wraps the router content in WindowSizeScope and AppShortcuts and refreshes the activity digests on app resume without a second lifecycle observer. Unverified: how AppShortcuts finds a navigator context above the router navigator (internal to app_shortcuts.dart).
Rule next time: the test agents pump FitnessApp once and prove that shortcuts reach the router and that the window class rebuilds only on a class change (DT-02-3, DT-17-x).

## 2026-10-17 - Commit: feat(sources): add the Sources page with the app row states and the source rows

Kind: SHORTCOMING (design gaps) and SUCCESS (survey).
Facts: lane L9 run 1 wrote the Sources page and surveyed the sign-out call sites without editing them. Gaps it found: the design names a `sourcesSummaryProvider` that does not exist in the code (the page derives its data from the digest snapshot); the keys `activityRecoveryNotice`, the 'May provide' texts and the sign-out guard sentences have no ARB entries; the contract asks for Try again on the failedToOpen state while the approved design says retryNow is not applicable there. The survey found exactly two sign-out callers (Profile tile, no confirmation today; account deletion, best effort after the wipe) and that `ActivityWipeCoordinator.onSignOut` does delete the departing uid's journal, and that `activity_local_export.dart` writes no file (bytes only), so the export file location is new code.
Root cause: design section 6 and 2.5 named strings and a provider without checking that they exist (design author); the contract and the design disagree on one button (documented AC-PR-2 deviation).
Layer: design; caught by the implementation agent.
Rule next time: every key and provider name in a design is grepped before the design is approved. Run 2 removes the Try again button for failedToOpen on Sources (consistent with the approved design).

## 2026-10-17 - Commit: feat(l10n): add the keys for the Sources capability lines, the recovery notice and the sign-out guard

Kind: SHORTCOMING (resolved).
Facts: 19 more keys per language were needed because design section 6 did not list the Sources capability texts, the recovery notice and the sign-out guard sentences although the approved design and contract name them; the lane agent drafted all English texts except one sentence and ALL Russian texts for them (listed in the lane report, not product-reviewed). A concurrent edit of signOutConfirmDelete by the coordinator was handled correctly by the agent (it did not revert it).
Root cause: design copy tables were not checked against the list of strings the contract and the design text refer to (design author).
Rule next time: before approving a design, grep every quoted UI sentence and key name against its copy table. Product review of the agent-drafted Russian texts is a carried item for the acceptance record.

## 2026-10-17 - Commit: feat(signout): add the sign-out guard for local activity and finish the Sources page

Kind: SUCCESS with open risks.
Facts: lane L9 run 2 wrote the sign-out guard (cannot-check sheet, warning sheet, delete confirmation, error sheet with Retry), the temporary export file bound to a hashed uid and deleted after the share, the Profile tile change and the Sources recovery and capability lines; account_deletion_providers.dart was not edited. The agent added a plain 'Sign out' button that keeps the data on the device (not in design 6.9) so that a user with local activity is not forced to delete. Risks it reported: tests that turn the journal flag on without a journal override get failedToOpen and the guard shows the cannot-check sheet; share_plus and generated getter signatures were not checked against the packages; `_SourcesStub` is now unused.
Rule next time: the test agents prove the guard rows (DT-16-x) with a journal override, check the export file is deleted after the share and that no wipe call happens unless availability is open; the first compile will confirm the package API.

## 2026-10-17 - Commit: fix(modes): persist again after a failed save when the same choice is repeated

Kind: FAILURE (caught by an implementation agent of another lane before any test).
Facts: the mode notifier set the state in memory first and returned `unchanged` when the identical value was already in memory, so 'Try again' after a failed save wrote nothing and the caller treated unchanged as success; the user would advance with an answer only in memory (test plan row DT-09-2). Fixed with a per-uid persist-failed flag: the identical call writes again while the flag is set. initIfAbsent is intentionally unchanged.
Root cause: 'set memory first, compare with memory' design in my lane brief (coordinator) plus no scenario 'repeat after failed write' in the state-layer review.
Layer: author (brief, notifier); caught by lane L6 while building the question page; the test agents prove it (DT-09-2, DT-01-x).
Rule next time: any optimistic-update state holder gets the scenario 'same value after a failed write' in its brief and its tests.

## 2026-10-17 - Commit: feat(modes): add the mode chooser, the per-mode questions, the switcher, the Coming-later sheet and the Record sheet

Kind: SUCCESS with open items.
Facts: lane L6 wrote stories S03-08 to S03-11 in two runs: the chooser (four cards, three layouts, grid rule by available width, no spinner, Back equals Decide later, unsaved selection dropped on account switch), the questions page, the mode switcher, the Coming-later sheet and the Record sheet (every row navigates, the only write is the explicit Open Train tap). While building it the agent found the repeat-after-failed-save defect in the state layer (fixed in 6521e152). Open items it reported: the rail Record slot has no GlobalKey so on expanded windows the Record sheet is a centred dialog unless an anchor is passed; SemanticsService.announce is used with an ignore for a deprecation; ModeState.answers holds one answer per mode (enough for one question per mode today).
Rule next time: the test agents prove: no write on opening or closing any sheet (AC-RC), Ride and Explore never write, a failed save keeps the selection and shows the error, Back on the chooser runs Decide later only while pending.

## 2026-10-17 - Commit: feat(app): route to the real chooser, questions and Sources pages and wire the switcher and Record openers

Kind: NEUTRAL.
Facts: the three stub pages of the S03 router splice were replaced by the real pages (three separate lanes edited the same router file one after another, each touching only its own line, and the unused stubs and the unused route list were then deleted). The mode switcher and Record sheet openers are wired as provider overrides in main.dart; tear-offs with an extra optional named parameter are assumed assignable to the one-argument typedefs (not compiled).
Rule next time: when several lanes must edit one file, serialise them and give each exact lines; the first compile of the test agents confirms the tear-off assignment.

## 2026-10-17 - Commit: feat(progress): add the all-activity block, the journal error panel and the Sources slot to Progress

Kind: SHORTCOMING (resolved in the same lane) and SUCCESS.
Facts: lane L8 stopped once at the turn limit and was resumed. Its first version needed six ARB keys and hard-coded the distance unit and reused the time wording for the distance hint; the keys were added (7 per language, lane L13 run 3) and the code switched to them. Its report listed deviations: tile keys use walk (not walkHike) to match the test plan; failedToOpen has no Try again (same documented deviation as AC-PR-2); the staleness refresh runs from a post-frame callback; the recovery notice also shows in the demoted slot when the lost count is above zero (design silent).
Root cause: design section 6.7 did not list the tile labels, the stale and incomplete notices or a distance unit (design author).
Rule next time: the existing progress_page_test.dart is at risk (headline text counts); the test agents run it first and report. Distance wording and the new Russian texts need product review.

## 2026-10-17 - Commit: feat(home): add the mode lens, the mode chip, the activity today card and the two-pane layout to Home

Kind: SHORTCOMING (agent work pattern) and SUCCESS.
Facts: lane L7 hit the 20-turn limit once with no file written (it read for the whole run), and finished after the coordinator told it to stop reading and write. Its report lists known gaps: no ARB key for the '+n more' line of the Activity today card (a bare '+n' is shown); the mode chip has no icon (HudChip has no icon parameter); the viewport is not compensated when the card arrives above the visible content (deviation from contract S-6 wording); the sport-group mapping is duplicated from the Progress lane; the lens only reorders and never removes sections.
Rule next time: briefs for big existing pages say 'write after at most five reads'. The test agents check the section keys, the TRAIN order equals the pre-S03 order, the Day-3 modal and the chooser never appear together, and report the viewport gap as a finding for the conformance pass.

## 2026-10-17 - Commit: fix(s03): fix the compile errors and the defects found by the first test run

Kind: FAILURE (expected consequence of the no-run build rule, recorded so the cost is visible).
Facts: the first run of the code by a test agent found six compile errors in production files written by four different lanes (type promotion between unrelated interfaces in two places, a go_router call with a type argument that does not exist, a nullable provider read, a missing import, a missing constructor key) and five behaviour defects: Sources kept saying In use after a failed refresh, Home chose two panes at a large text scale, the Home more line was a bare number without a key, and two viewport-jump findings (not fixed here). The existing Home and Progress tests also failed only because of the compile errors; with the six fixes applied in a scratch copy all nine existing files passed (115 tests).
Root cause: implementation agents are forbidden to run anything, so nothing compiled until the test phase; lane briefs did not ask for a careful compile read of type relations (is-checks across interfaces), only for a syntax read.
Layer: author (implementation agents) and reviewers (none had run yet); caught by the test agent on the first run.
Rule next time: the first test run is scheduled as soon as the first lane lands (a compile-only smoke by the test agent after wave 1), not after the last lane; lane briefs list the known Dart traps (is-check promotion needs a subtype, go_router extensions, nullable providers, imports of event classes).

## 2026-10-17 - Commit: fix(modes): show only the greeting while the mode is unknown and refuse a stale write without throwing

Kind: FAILURE (two defects found by the step 1 test agent).
Facts: Home rendered the TRAIN section order while the stored mode was still loading, so a BODY user saw a wrong-mode flash (contract forbids it, test DT-01-9); the mode notifier's refusal path read providers through a stale reference after an account switch, which throws an AssertionError in debug builds instead of returning saveFailed (DT-01-23).
Root cause: Home used `modeState?.selectedMode ?? AppMode.train`, a default that silently invents a mode (lane L7); the refusal read provider state without a guard (lane L2).
Layer: authors; caught by the step 1 test agent through real-notifier tests.
Rule next time: a null state never defaults to a concrete user choice; any async continuation that reads providers after an await is wrapped or uses a captured value. Open: the chooser offer path (`_maybeOfferChooser`) was not re-read for the loading case; the test agents check that no chooser is offered while the mode state is loading.

## 2026-10-17 - Commit: fix(modes): fix chooser focus order, anchor the rail Record sheet, put meal first for food answers and size the loading cards

Kind: FAILURE (defects found by the step 3 test agent in mode screens).
Facts: the chooser skipped two cards in Tab order once a card was selected (DT-08-1b); the rail Record slot had no anchor key so the Record sheet opened centred on expanded windows (DT-12); the Record sheet ignored the stored Body answer so a food answer did not put the meal row first (DT-11-3); the loading outline cards were 25 dp shorter than loaded cards, so the second row shifted on load.
Root cause: authors (lane L6) relied on default focus traversal and left the anchor and ordering inputs out of the first version; the lane L6 report listed the anchor gap itself as an open item, and the briefs did not turn open items into stories.
Layer: author; caught by the step 3 test agent through widget tests.
Rule next time: an open item in a lane report becomes a test-plan row or a fix item before the lane is closed; every screen with several focus targets gets an explicit traversal order in its first version.

## 2026-10-17 - Commit: test(modes): add the functional tests for the chooser, the questions, the switcher and the Record sheet

Kind: SUCCESS with open items.
Facts: the step 3 test agent wrote 96 widget tests (chooser 45, questions 20, switcher 16, Record sheet 15) and ran them in the real tree at 0969258b: 96 passed, 0 failed. Run history: 93 passed and 3 failed at 8a5c7474; the failures were production defects (chooser Tab order, missing rail anchor, meal-first), fixed in batch 3, after which the same tests pass.
Why it worked: the tests were written against the contract rows and run per epic by the author of the tests, so the defects were found before review.
Open: flag inputs for the Record rows (minor finding, tests DT-11-1 and the flags-off row of AC-RC-3 stay weak, DT-11-1b pins current behaviour and must be replaced when the inputs are added); DT-09-4, DT-09-5 and DT-10-2 are partial because no mode asks two questions yet; the loading height shift was not re-measured.
Rule next time: when a minor finding is skipped, the test that pins the current behaviour carries the marker in its name so the fix forces its replacement.

## 2026-10-17 - Commit: fix(shell): keep the viewport steady, show the rail focus ring, keep focus on resize, hide the Record pill for another account and announce session changes

Kind: FAILURE (defects found by test steps 2 and 4) and SHORTCOMING.
Facts: the Progress All-activity block and the Home Activity today card shifted the visible content by 376 dp and 155 dp when they arrived; the five rail destinations painted no focus ring; focus fell to the root navigator when the layout switched from rail to bottom bar; the Record pill stayed visible for another account; at text scale 2.0 on a 360x480 window the pill was 230x70 and the strip was not one line; session start, pause, resume and end were not announced to screen readers.
Root cause: authors (lanes L4a, L4b, L7, L8) did not apply the viewport, focus and text-scale rules of the contract to the parts they built; the lane briefs named the rules but the lanes could not run anything to see the effect.
Layer: author and reviewers (none had run yet); caught by the step 2 and step 4 test agents with widget tests.
Open and carried: the session owner is not cleared when another account signs in (clearing it while a timer runs would show account A's session to account B, so the provider-level test of that row must be re-worded); flag inputs for the Record rows are not done; announcement texts are agent-drafted and need product review.
Rule next time: contract rules about viewport, focus and text scale become acceptance rows in the lane brief itself, with the exact widget to measure.

## 2026-10-17 - Commit: docs(s04): add the S04 documentation readiness note

Kind: SUCCESS.
Facts: while S03 testing runs, the next sprint documents were reviewed once (as the delivery rules require, in parallel with the current sprint) and the result is a readiness note: 12 gaps and 8 entry decisions for the operator. Top gaps: there is no UI design contract for S04, the recorder requirements and numbers are undefined, the relationship between the recording journal and the S02 journal is undecided, Android location and foreground-service rules are unverified, and no sprint owns the consent centre.
Why it worked: the note is a list of facts with file pointers, produced without delaying the current sprint.
Rule next time: the S04 documentation pass starts from this note, one fix pass, no rewrite of settled documents.
