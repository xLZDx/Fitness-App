# S02 sprint report and retrospective: unified activity (E1)

Phase 10 of the SDLC for sprint S02. This is the final record; it supersedes the living draft `docs/phase2/s02/S02_SPRINT_REPORT_AND_RETRO.md` (kept as history). No test, build or scanner was run to write this report: every number below is MEASURED (read from a git command, a file or a findings file, source named) or INFERRED (stated as such). Review verdicts are quoted from the repository records and are the reviewers' claims, not own measurements.

## 1. Goal

Source: S02 row of `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md`, restated in `docs/phase2/s02/S02_ACCEPTANCE.md` section 1.

Goal: persist a unified `ActivitySession` (summary in Firestore, streams as compressed private objects), with rules and shape validation, retention, deletion, export (FIT/GPX), provenance, tolerant schema migration, merger performance, consent per source and datatype, and native-session dedup. GPS-specific requirements stay with S04 onwards. The debug telemetry server guarantee had to exist before any GPS code. All new modes ship behind flags that are OFF by default.

Roadmap gate: round trip of 100 real-shaped sessions, deletion removes streams, lifecycle rows exist, no external-source dedup promise.

## 2. Outcome in one paragraph

All planned stories S02-00 to S02-12 were built, tested by the test agents and merged. PR #10 (branch `phase2/s02-unified-activity`) was merged into `phase2/main` as merge commit `2c121242` on 2026-10-16 (MEASURED: `git log`, decision log entry "docs: record operator answers after the S02 merge"). The merge followed GPT-PM APPROVE on exact head `72cc3803` in code-gate round 14. The code gate needed four rejected rounds (11, 12, 13 and the documentation gate before them), all caused by one defect family: per-account state and ambient-credential calls in a multi-account app. One story-level promise (OD-9, local journal open in the default build) was NOT delivered by S02 and moved to S03. Operator acceptance of the sprint is not stated in any file.

## 3. Heads and gate evidence

| Item | Value | Source |
|---|---|---|
| Branch base | `5bb61f15` | git, STATE.md |
| Gated head, round 14 | `72cc3803` (2026-10-16 22:52 +0300) | git log, decision log |
| Merge commit | `2c121242` (2026-10-16 23:05 +0300) | git log |
| Commits `5bb61f15..72cc3803` | 242 (MEASURED: `git rev-list --count`); 243 to the merge commit | git |
| Diff `5bb61f15..2c121242` | 554 files changed, 69781 insertions, 170 deletions (MEASURED: `git diff --shortstat`; includes everything merged from the base, not only S02 files) | git |
| Change records | one `core/changes/` file per commit, 239 files named `2026-10-16-s02*` (MEASURED: directory count; other S02 records have different names) | core/changes |
| Follow-up after merge | `849abd5e` "S02 follow-up: apply the retention and privacy answers, close phase 9" on the next sprint branch | git |

Documentation gate (design and test plan revision 12, 239 planned tests per STATE.md and acceptance record):

| Round | Verdict | Note |
|---|---|---|
| 1 | REJECT, 1 BLOCKER and 5 MAJOR | includes the deletion fence |
| 2 | REJECT | merge convergence, uncommitted-generation activation |
| 3 to 9 | REJECT each | new holes in the "input-class matrix" merge design; severities not recorded in the files read (UNKNOWN) |
| 10 | APPROVE on `9c68cab8` | design replaced by value-based overrides |

Code gate (GPT-PM through PM Bridge; claims are the reviewer's, each verified against source by the coordinator per the lessons log):

| Round | Head | Verdict |
|---|---|---|
| 11 | `f1646961` | REJECT, 3 MAJOR, 0 BLOCKER: account switch wiped another account's local journal; lost owner marker let the next account adopt a journal; tombstone push capped at 8 per pass |
| 12 | `10288e57` | earlier three resolved; REJECT, 1 MAJOR: cloud-upload consent cache shared by all accounts |
| 13 | `0096dd88` | earlier four resolved; REJECT, 1 MAJOR: consent calls checked the locally bound account while the server call ran as whoever was signed in |
| 14 | `72cc3803` | APPROVE |

Internal reviews before and between gate rounds (STATE.md and lessons log): six independent specialist reviews with remediation batches A to D; a second independent round (four specialists, three verification reviews) on remediation E, F, G; verification reviews of remediation H and I; three sweep reviewers with an inventory table (remediation J3). Per-reviewer finding counts for S02 were not found in a single file (UNKNOWN).

Agents and models: STATE.md for S02 names code-explorer, technical-writer, functional-test-reviewer, the test agents and the review specialists; the lessons log and decision log do not list a per-run model table for S02 (UNKNOWN per run). Sprint policy at the time: Sonnet 5.5 for agents.

## 4. Scope delivered versus planned

Planned: 16 stories (S02-00, 01, 02, 03, 04a, 04b, 05a, 05b, 06a, 06b, 07, 08, 09, 10, 11, 12; the design lists them in `S02_DESIGN.md` around lines 475 to 520). Verdicts below are the product-owner draft in `S02_ACCEPTANCE.md` section 2 (a draft, not an operator acceptance).

| Story | Verdict (acceptance draft) | Main limit |
|---|---|---|
| S02-00 conflicting-write fake | ACCEPTED WITH LIMIT | Dart self-test is indirect |
| S02-01 model v2 | ACCEPTED WITH LIMIT | SportType table pinned but no write path consults it |
| S02-02 local journal | ACCEPTED WITH LIMIT | power-loss durability and real device backup NOT_RUN |
| S02-03 rules | ACCEPTED WITH LIMIT | emulator only; production access-call counting unverified |
| S02-04a validator | ACCEPTED WITH LIMIT | heart rate disguised as another number cannot be detected server-side |
| S02-04b create and commit | ACCEPTED | none |
| S02-05a settings and consent | ACCEPTED WITH LIMIT | withdrawal outbox and stream PUT timeout not built; no grant UI |
| S02-05b retention and purge | ACCEPTED WITH LIMIT | "never" removed after merge, see section 7 |
| S02-06a tombstone, fence, delete | ACCEPTED | none |
| S02-06b account deletion sweeps | ACCEPTED WITH LIMIT | fence left by an aborted deletion keeps callables refused |
| S02-07 export, FIT and GPX | ACCEPTED WITH LIMIT | FIT not checked by a third-party validator |
| S02-08 lifecycle docs | ACCEPTED WITH LIMIT | privacy wording is a DRAFT, unapproved |
| S02-09 telemetry guarantee | ACCEPTED WITH LIMIT | `sendDebugTelemetry` excluded from the expected-account check |
| S02-10 merger performance | ACCEPTED WITH LIMIT | id key can collide for ids containing `|` (latent) |
| S02-11 story-map lint | ACCEPTED WITH LIMIT | MAJOR/BLOCKER tokens not machine-mapped |
| S02-12 conflict UI, three-way merge | ACCEPTED WITH LIMIT | device never pulls; layout and pixels NOT_RUN |

Count (MEASURED from the table above): 2 ACCEPTED, 14 ACCEPTED WITH LIMIT, 0 NOT ACCEPTED, 0 rejected. The acceptance file adds the cross-story gate E01 to E03 as a further row (ACCEPTED). "All planned stories were built" rests on this file and STATE.md, not on a story-by-story code check.

Unplanned work added by the gate: remediation A to D (specialist reviews), E (account-scoped journal, tombstone continuation, erasure quota 1000), F and G (second review round), H and I (consent and conflict surface), J (`expectedUid` carried in six activity callables and verified server-side).

## 5. Test evidence recorded in the findings files

All runs were made by the test agents; the coordinator ran none. Counts are copied from the files, not re-measured. Each line is a summary of the cited file.

| Evidence | Command / scope (from file) | Result (verbatim from file) | Source |
|---|---|---|---|
| Dart activity directory, head `45c747b0` | `flutter test test/features/activity` | `+1117: All tests passed!` | `S02_TEST_FINDINGS_FINAL_RUN.md` |
| Dart account deletion, health parity, team activation | three paths | `+97: All tests passed!` | same |
| Dart backup rules and architecture guards | three files | `+23: All tests passed!` | same |
| Server activity, head `4af1cb43` start | `npx jest src/__tests__/activity` | 26 suites, 744 tests passed | same |
| Server policy and scaling | two files | 191 tests passed | same |
| Rules emulator (six `s02_*` files) | alternate-port emulator run | 6 suites, 289 tests passed | same |
| Rules emulator complete set, head `479b7342` | nine rules files | `Test Suites: 9 passed` / `Tests: 953 passed` | same |
| Delete-account and index pins after fixes | three files | 124 tests passed (74 + 2 failures before: stale fakes, test-only fix) | same |
| Later epics 11 to 16 | recorded in `S02_TEST_FINDINGS_EPIC11.md` to `EPIC16.md` | Dart activity directory `+1485`, a second Dart run `120`, server `922` and `315` (the numbers as quoted by `S02_ACCEPTANCE.md` and the lessons log; not re-read in the epic files for this report) | acceptance, lessons log |
| Epic 17 (post-merge, retention) | five jest files after the change | `Tests: 143 passed, 143 total`; legal Dart run first `+151 -1`, final `+152: All tests passed!`; policy test final `43 passed`; new sync guard `6 passed` | `S02_TEST_FINDINGS_EPIC17.md` |

Findings-file inventory: 17 epic findings files (EPIC1 to EPIC17, with 6A/6B), plus `FINAL_RUN` and remediation test-notes files A to J (MEASURED: directory listing).

Gaps stated by the files themselves:
- No single complete run exists on head `72cc3803` (the final-run file is at `45c747b0`, before remediation E to J; later epics cover their own areas). UNKNOWN whether one exists elsewhere.
- Rules emulator not re-run after remediation J because rules and indexes were unchanged since `479b7342` (decision log, round 13).
- `remediation_a_validate_bound.test.ts` is a known load-sensitive flake: passes alone, fails under the parallel activity run (epics 16 and 17).
- Not run, by instruction: mutation runs (operator rule), full-repo suites, lint, typecheck, build, CI. Not exercised: the success path of real callables, a settings client with a live-uid supplier (needs Firebase), power-loss durability.
- `scripts/ci/check_data_access_policy.js` standalone exits 1 with 5 violations in non-S02 files (`body_scan/manage.ts`, `nutrition_cache.ts`), recorded, not changed.
- Epic 17 left unrun: the full activity folder was not repeated after the two test edits.

## 6. Defects found and how (from `core/LESSONS_LOG.md`)

| Defect | Found by | Layer that missed it |
|---|---|---|
| Account switch wiped another account's local journal; owner marker loss let the next account adopt it; tombstone push capped at 8 per pass (round 11, MAJOR x3) | external gate | author, tests, specialist reviews (briefed not to re-report new code) |
| Summary-synced entries were never uploaded | test epic 7b (order-of-events test) | author, earlier tests |
| Stale test fakes outside the epic directories | final complete run | epic run lists |
| E1 code did not compile (Dart type promotion across unrelated interfaces) | first compiled test epic (11a) | author; implementers may not build by operator rule |
| Sync pass not pinned to the account; journal uid not tied to auth uid; unbound journal read as "in sync"; retry budget never reset; key deletion failure swallowed; rebind of a wiped account | second independent review round and verification reviews | remediation author, epic tests (switched accounts between operations, never in the middle) |
| Consent cache shared by all accounts (round 12, MAJOR) and siblings: sync during account deletion, grant/withdraw on the wrong account, shared once-per-instance flag, stale conflict cards, queued tap under another account, unbound sign-out wipe and export | external gate, then a three-reviewer class sweep with an inventory table | coordinator briefs scoped to the diff |
| Display path and consent store not tied to the auth uid (gaps in the fixes for H) | verification reviews | H implementer, epic 14 tests |
| Ambient-credential callables not bound to the initiating account (round 13, MAJOR; four client gaps, two server callables unbound) | external gate, then sweep | author, inventory of round 12 never asked the question |
| Flaky oracle: absence of a 2-byte sequence searched in random ciphertext | repeated complete run (epic 13a) | epic 4 test author, reviewers |
| Test notes listed stale fakes but not assertions broken by the new contract (repeated in epics 12a, 13a, 14, 15) | first compiled runs | test-note authors |
| `public/privacy.html` hand-edited in three commits, generator source never updated (57-line drift); retention "never" still offered after the operator answer; test branched on the constant it checked; two further stale tests | acceptance agent and focused test run after merge | authors (coordinator and two agents), tests that pinned the output, reviewers |
| Fake uid sentinel named with "secret" flagged by the full-history secret scan after merge | CI secret scan | author; scan is not run locally by operator decision |
| Platform and form-factor scope never put to the operator as a decision | operator questions after the gate | roadmap, no reviewer asks |

Process incidents (lessons log): ten documentation rounds because the merge design enumerated input classes instead of stating one invariant; many agents stopped at turn limits with uncommitted work; parallel test agents shared one git index and one killed all `dart.exe` processes; a gate round resent after a project-folder binding error (nothing was sent the first time).

## 7. Carried items and accepted risks

Carried to S03 or later (FACT in acceptance and STATE.md):
- OD-9, local journal opens in the default build: not delivered by S02 (S02 shipped `ACTIVITY_LOCAL_JOURNAL` default false). It is S03 story S03-0; the S03 branch carries commit `f5b6acd4` "feat(activity): turn the local journal on by default and add the bind retry state machine and journal availability" (title MEASURED; its tests belong to S03, not verified here).
- Retention "never": merged code still offered it (`STREAM_RETENTION_NEVER_OFFERED` was `true`). Fixed after merge in `849abd5e` with epic 17 tests; the fix is on the S03 branch, not in the merged S02 PR. Dead `null` code paths and a wrong doc comment in `settings.ts` remain (EPIC17 finding 5).
- Grant UI after consent withdrawal (uploads restart at next app start).
- Withdrawal outbox, stream PUT timeout and other backlog items (design 17 items 23 and 25).

Operator-owned and still open (STATE.md): privacy wording approval (a DRAFT; Russian S02 paragraphs missing), first-release region, deletion-record retention (400 days proposed), bucket, IAM, alerts, soft-delete window, dedicated service account, release gate for off-UI-isolate work (design 17 item 20), Blaze billing and `phase2` deploy credentials, monetisation per mode (D-9), master branch name (D-3), legal status of the third-party dossier (D-10).

Accepted risks (documented limits): `sendDebugTelemetry` exempt from the expected-account check; heart-rate-as-number server limit; no third-party FIT validation; emulator-only rules evidence; production access-call counting unverified; `activity_reconcile_state` has no current code or rules reference; latent id collision for ids with `|`.

Open disagreements recorded in the acceptance file: final-run file head versus later epic results; STATE.md header "8 Gate" versus merged status; privacy draft versus operator decision.

## 8. Retrospective

What worked (kept): independent specialist reviews before the gate (found defects no epic test found); tests that drive the real order of events; an inventory table before findings in sweep reviews; fixing a whole defect class instead of the named members; OPEN-DEFAULT constants that made the retention answer a one-line change; a complete directory run before writing stale-test lists; merge commits to keep per-commit change records and the lessons log in history.

Actions (each derived from a lessons log entry; owner is the coordinator unless stated):

1. Class sweep over the whole surface. When a defect class is found (state not bound to an account, stale async completion, ambient credentials), brief independent reviewers on the whole surface with a mandatory inventory table (item, identity captured, re-checked after each await), never on the diff. Source: round 12 and class sweep entries.
2. Two-sided threat check. Any brief that adds a destructive step states what leaks without it and what is lost with it. Reviewers get remediation code with the same independence as original code, with no "already fixed, do not re-report" lists. Source: round 11 entry.
3. Bind identity at the call. Every outbound call authenticated by ambient credentials carries the initiating identity and the receiver verifies it; identity tests must move the live source (the auth uid), not only the local store. Enumerate all members of a class before fixing. Source: J1 to J3 entries.
4. Test notes by behaviour. Stale-test lists come from a grep for the old behaviour or call sequence plus one whole-directory run first, not from the list of fakes; one agent makes complete runs at a time. Source: epic 12a, 13a, 14, 15 entries.
5. Compile before tests. The first test agent of a remediation epic compiles the tree; implementer briefs carry a Dart trap list (type promotion, definite assignment, Fake classes needing every new member). Source: "remediation E and F written without compiling".
6. Generated files and decisions as code. Before editing anything under `public/` or legal ARB keys, find its generator, edit the source, and name it in every agent brief; keep `scripts/legal/test_build_legal_in_sync.py` as the guard. Pin decided values in tests; never branch a test on the constant it checks. Source: 2026-10-17 follow-up entry.
7. Agent sizing. At most about five deliverables per agent brief, commit after each, include the exact run command, split sweeps by area, require a partial written report when low on turns, expect to resume. Source: round 13 shortcomings and F-series entries.
8. Decide scope questions at sprint zero. Put apps, platforms, form factors and release lines on the first page of the roadmap and ask them as a decision; avoid fake values named "secret", "token" or "key"; resend gate rounds with the previous command line. Source: operator-answers and sentinel entries.

Open question for the next retro: whether the documentation gate can state its invariant first (value-based merge) to avoid repeating the ten-round pattern; no evidence yet beyond S02.
