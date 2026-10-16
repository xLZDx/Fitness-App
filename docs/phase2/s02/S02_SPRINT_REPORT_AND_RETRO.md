# S02 sprint report and retrospective (living draft)

Status: DRAFT, updated while the sprint runs and finished at SDLC phase 10 (report and retro). The source of every item is `core/LESSONS_LOG.md` (append-only, one entry per commit that carries a lesson); this file summarises and turns the lessons into actions. Measured vs inferred is stated per item.

## Where the sprint stands (MEASURED from git and the findings files)
- Documentation gate: GPT-PM APPROVE on 9c68cab8 in verification round 10 (ten rounds).
- Code gate, round 11 on f1646961: GPT-PM REJECT with three MAJOR findings, no BLOCKER (`docs/phase2/s02/` review record in the decision log). Remediation E (account-scoped journal, tombstone queue continuation, erasure quota) is in progress; a new exact head goes to round 12.
- Test evidence of f1646961: see `docs/phase2/s02/S02_TEST_FINDINGS_FINAL_RUN.md`.

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

## Actions (owner: coordinator unless stated)
1. Two-sided threat check in every brief that adds a destructive step: what leaks without it and what is lost with it (rule recorded in the lessons log).
2. Reviewers receive remediation code under the same independence as original code; no "already fixed, do not re-report" lists.
3. Ownership of per-account data is expressed by storage location and key, never by a side marker (implemented in remediation E1).
4. Every bounded loop states its continuation or completion path in the design (implemented for tombstones in remediation E2).
5. Epic run lists include every test that exercises a changed shared function, not only the epic directory.
6. Agent briefs: at most about five deliverables, commit after each, exact run command included.
7. The lessons log gets an entry in every commit (global rule added 2026-10-16).
