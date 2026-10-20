# S02 sprint report and retrospective (living draft)

Status: DRAFT, updated while the sprint runs and finished at SDLC phase 10 (report and retro). The source of every item is `core/LESSONS_LOG.md` (append-only, one entry per commit that carries a lesson); this file summarises and turns the lessons into actions. Measured vs inferred is stated per item.

## Where the sprint stands (MEASURED from git and the findings files)
- Documentation gate: GPT-PM APPROVE on 9c68cab8 in verification round 10 (ten rounds).
- Code gate, round 11 on f1646961: GPT-PM REJECT with three MAJOR findings, no BLOCKER (`docs/phase2/s02/` review record in the decision log). Remediation E (account-scoped journal, tombstone queue continuation, erasure quota) was committed and tested (epic 11). A second independent review round (four specialists on the remediation, then three verification reviews) found further defects in the remediation; they were fixed in batches F and G and tested (epics 12 and 13). Round 12 (on 10288e57) accepted those three as resolved and returned REJECT for one new MAJOR: the cloud-upload consent cache was shared by all accounts, so the startup chain of a stale account could leave its consent visible to the next. It was verified, a class sweep of the whole surface by three independent reviewers found siblings, and remediation H and I (tests in epics 14 and 15) fixed them. Round 13 (on 0096dd88) accepted all four earlier findings as resolved and returned REJECT for one more MAJOR of the same family: the consent calls checked only the locally bound account while the server call ran as whoever was signed in at that instant. It was verified; the whole class (every call authenticated by ambient credentials) was fixed by sending the initiating account in the request and verifying it on the server (remediation J), and three independent reviewers swept the whole surface again with a mandatory inventory table (remediation J3). A new exact head goes to round 14.
- Test evidence of f1646961: see `docs/phase2/s02/S02_TEST_FINDINGS_FINAL_RUN.md`. Evidence after remediation: `S02_TEST_FINDINGS_EPIC11.md`, `EPIC12.md`, `EPIC13.md`. All test runs were made by the test agents; the coordinator ran none.

## What went well
- Independent specialist reviews before the gate found defects the epic tests had not (abandoned fence of a live account, journal recovery deleting committed generations on a transient I/O error, an upload continuing under another account, a flag that gated three layers at once). INFERRED value: each of these would otherwise have reached the external gate or production.
- Tests that drive the real order of events (summary sync, then stream upload) found the "streams never uploaded" defect in the first run.
- The final complete run (server and Dart) found stale test fakes that no epic directory covered.
- The external gate caught a data-loss path before any push.

## What went wrong
- MY mistake, caught only at the last gate: remediation B2 made an account switch wipe the previous account's whole local journal, which destroys device-only GPS and heart-rate data that was never uploaded, and a missing owner marker let the next account adopt another account's journal. Details, root cause and the layers that missed it are in `core/LESSONS_LOG.md` (entry "S02 journal wipe on account switch"). Contributing process errors: one-sided threat check (leak but not loss), implementation without the export offer the approved design required, and briefing the Flutter and architecture reviewers not to re-report the new code.
- Ten documentation rounds because the merge design enumerated input classes instead of stating one invariant.
- A bounded tombstone push (8 per pass) shipped without a continuation path (MAJOR-03).
- Many agents stopped at their turn limit with uncommitted work.
- The remediation itself was uncompiled and under-tested: a compile error in E1 (found by the first test epic that compiled the tree), a sync pass not pinned to the account (found by all four reviewers of the second round), no tie between the journal uid and the auth uid (found by the verification round), an unbound journal reported as "in sync", a retry counter that never reset. Contributing: the first tests switched accounts between operations, never in the middle of one.
- Test notes listed stale fakes but not the older assertions the new contract broke; parallel test agents shared one git index and one agent killed all dart.exe processes.

## Actions (owner: coordinator unless stated)
1. Two-sided threat check in every brief that adds a destructive step: what leaks without it and what is lost with it (rule recorded in the lessons log).
2. Reviewers receive remediation code under the same independence as original code; no "already fixed, do not re-report" lists.
3. Ownership of per-account data is expressed by storage location and key, never by a side marker (implemented in remediation E1).
4. Every bounded loop states its continuation or completion path in the design (implemented for tombstones in remediation E2).
5. Epic run lists include every test that exercises a changed shared function, not only the epic directory.
6. Agent briefs: at most about five deliverables, commit after each, exact run command included.
7. The lessons log gets an entry in every commit (global rule added 2026-10-16).
8. Remediation code always gets its own independent review round (the second round found a cross-account hole in the remediation of the cross-account hole).
9. Every async operation that touches per-account state carries a pass identity and re-checks it before each side effect; two sources of identity are tied to each other at the start; each long-running operation gets a "switch account mid-flight" test.
10. The first test agent of a remediation epic compiles the tree before writing tests; implementer briefs carry a list of Dart traps (type promotion, definite assignment, Fake classes needing every new member).
11. Test notes list the older assertions whose behaviour changes, found by grepping the tests for the old behaviour, not only stale fakes; complete runs are made by one agent at a time.
12. After a defect class is found, independent reviewers sweep the WHOLE surface for it (with an inventory table first), not the diff of the fix. The consent cache was missed in rounds 1 to 11 because my reviewer briefs were scoped to the remediation diff.
13. When a guard is added to one path, grep every sibling path that reads the same identity pair; bind per-account state as early as it can be bound; verify a reviewer claim against the primary source before acting.
14. Any outbound call authenticated by ambient credentials (the SDK reads the current user when it sends) carries the initiating identity in the request, and the receiver verifies it before any side effect. A local check before the call is not a binding. My round-12 inventory listed state and async chains but never asked this question, so the class survived one more round.
15. When a fix binds a class of operations, enumerate ALL members of the class first (the first fix bound four callables and missed two of the same class; the sweep found them). Tests for an identity binding must move the LIVE identity source (the auth uid), not only the locally bound store, or they prove nothing about the real race.
16. Whole-surface review agents have small turn limits: split the sweep by area over more reviewers, require a partial written report if they run low, and expect to resume them (two of three stopped without a report on the first run and had to be resumed).
17. A new shared type goes into its own file named in the brief; reviewing the import direction of new imports in a diff catches cycles that no existing test guards.
