# S02 sprint acceptance record: unified activity

Status: FIRST FULL DRAFT, written by the product owner role. Date: 2026-10-16. Claims are tagged FACT (source cited), INFERENCE or UNKNOWN. Nothing here states that a check ran unless a findings file or `core/DECISION_LOG.md` says so. No test, scanner or code was run to write this record.

## 1. Sprint goal and scope

FACT (`docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md`, S02 row): "Unified activity (E1)": `ActivitySession` persistence (summary in Firestore, streams as compressed private objects), rules with shape validation, retention per contract, deletion, export, provenance fields, tolerant schema migration, merger performance, FIT/GPX export, consent matrix per source and datatype, native-session dedup. Roadmap gate: round trip of 100 real-shaped sessions; deletion removes streams; lifecycle rows; no external-source dedup promise.

FACT (`docs/sdlc/STATE.md`): GPS-specific requirements stay with later sprints; S02 covers the activity model, persistence, retention, deletion, export and the debug telemetry server guarantee that must exist before any GPS code. All new modes are behind flags that are OFF by default (`mobile/lib/core/config/activity_flags.dart`).

FACT (`core/DECISION_LOG.md`, entry "docs: record operator answers after the S02 merge"): PR #10 merged into `phase2/main` as merge commit `2c121242` on 2026-10-16; GPT-PM APPROVE on exact head `72cc3803` (round 14).

Binding operator decisions (same entry): one app (Phase 2 is an update of the same app); local journal opens in the default build regardless of the cloud flag (OD-9); retention: "never" is NOT offered, default 2 years (730 days), allowed 90 / 365 / 730. Phase 2 deploys only to the Firebase alias `phase2`, never to production project `fitness-app-korostelev` (brief; `docs/phase2/split/BACKEND_SEPARATION.md`).

## 2. Story verdicts

Verdict scale: ACCEPTED / ACCEPTED WITH LIMIT / NOT ACCEPTED. Test counts are copied from the cited files; a later epic may supersede an earlier count.

| Story (plain words) | Criteria source | Evidence | Verdict |
|---|---|---|---|
| S02-00 test prerequisite (fake Firestore that can produce conflicting writes) | design section 11 | Server F94 self-test in `S02_TEST_FINDINGS_EPIC6A.md`; Dart twin is not a separate file, every convergence test asserts the fake refused the loser (`S02_TEST_FINDINGS_EPIC4.md`) | ACCEPTED WITH LIMIT: Dart self-test is indirect |
| S02-01 model v2 (activity model, schema 2, migration, cloud summary, stream payload) | design section 11, tests U01-U13, U30-U41 | `S02_TEST_FINDINGS_EPIC1.md`; three production defects found and fixed there; epic 1 gives no summary count line. Later complete Dart run: `+1117` in `S02_TEST_FINDINGS_FINAL_RUN.md` | ACCEPTED WITH LIMIT: the SportType-to-model table is pinned but no write path consults it (EPIC2 item 5); a loaded record is re-stamped with version strings without a design decision (EPIC1 item 5) |
| S02-02 local journal (file journal, crash safety, backup exclusion, wipe) | design 10, tests I01-I10, I18-I25 and others | `S02_TEST_FINDINGS_EPIC2.md` (four production defects fixed); EPIC9 and EPIC11/12 for later remediation (not opened in detail: UNKNOWN per-file counts) | ACCEPTED WITH LIMIT: journal is account-scoped after remediation E1; power-loss durability and real device backup NOT_RUN by design |
| S02-03 Firestore and Storage rules | design 4, tests R01-R37, S01-S03 | `S02_TEST_FINDINGS_EPIC5.md`; final rules set `Test Suites: 9 passed` / `Tests: 953 passed` on head `479b7342` (`S02_TEST_FINDINGS_FINAL_RUN.md`); rules files unchanged since `479b7342` per decision log entry for round 13 | ACCEPTED WITH LIMIT: emulator only, production access-call counting not verified (EPIC5 "Not verified") |
| S02-04a upload validator and schemas | design 5.1, F01-F06, F49-F53, F91 | `S02_TEST_FINDINGS_EPIC6A.md` (two production fixes) | ACCEPTED WITH LIMIT: heart-rate disguised as another number cannot be detected by the server (F91 pins the honest limit) |
| S02-04b create and commit state machine | design 5.2, F07-F11, F41, F44-F48, F60-F62, F83-F87, I15-I17, I27 | EPIC6A, EPIC7 (client upload), EPIC16 (`expectedUid` binding; final `Tests: 922 passed, 922 total`) | ACCEPTED |
| S02-05a settings and consent | design 5.3, F13, F68, F75, F82, I28 | EPIC6A, EPIC7 (consent withdrawal 12 tests), EPIC14 to EPIC16 (per-account consent) | ACCEPTED WITH LIMIT: withdrawal outbox and stream PUT timeout not built, recorded as accepted backlog (decision log, round 13 entry); no grant UI yet (EPIC7) |
| S02-05b retention and purge | design 5.3, F14-F19, F63-F67, F88, F89 | `S02_TEST_FINDINGS_EPIC6B.md` (`Tests: 423 passed` for its 12-file run) | ACCEPTED WITH LIMIT: allowed values were 90/365/730 plus "never" in the code at that time; operator decision removes "never" (see section 5, UNKNOWN whether code enforces it) |
| S02-06a tombstone and fence, `deleteActivity` | design 6.1-6.2, F20-F23, F59, F76, F79 | EPIC6A, EPIC4 (delete wins), EPIC8 | ACCEPTED |
| S02-06b account deletion sweeps, late sweep, reconciler, bulk delete | design 6.1, F24-F28, F54-F58, F72, F77-F81, F95 | EPIC6B; defect "late sweep erased a live account" fixed there; EPIC8 | ACCEPTED WITH LIMIT: a fence left by an aborted deletion keeps callables refused until the deletion completes (EPIC6B) |
| S02-07 export (account export, download URLs, GPX and FIT encoders) | design 7, U17-U20, F29-F33, E01 | EPIC3, EPIC6B, EPIC7 (E01 100-session round trip) | ACCEPTED WITH LIMIT: shipped FIT file not checked by a third-party validator (EPIC3); merged 100 sessions differ from the corpus in 14 records so the oracle is count, ids and quotas (EPIC7) |
| S02-08 lifecycle docs (policy rows, matrix, bucket runbook, privacy text request) | design 11 | `S02_TEST_FINDINGS_EPIC6B.md`; `S02_PRIVACY_TEXT_REQUEST.md` | ACCEPTED WITH LIMIT: privacy wording is a REQUEST, not approved; the privacy draft still says "or never" (decision log) |
| S02-09 telemetry guarantee (sanitising callable, rules `create: false`, sink migration) | design 8, F34-F37, F73, F74, F90, F93 | EPIC3, EPIC5, EPIC6B | ACCEPTED WITH LIMIT: `sendDebugTelemetry` is excluded from the expected-account check (section 4); real callable not run on a device or emulator (EPIC3 "Not verified") |
| S02-10 merger performance and native-id rule | design 10, U10, U11, U14-U16, U21-U24 | EPIC3 (calibrated ceilings 1 000 and 6 000 comparisons) | ACCEPTED WITH LIMIT: id key `<sourceId>|<externalId>` can collide for ids containing `|` (latent) |
| S02-11 story-map completeness lint (F96) | design 11 | EPIC6B (`story_map_lint.test.ts`, 14 tests) | ACCEPTED WITH LIMIT: named MAJOR/BLOCKER tokens are not machine-mapped (EPIC6B) |
| S02-12 sync-conflict UI and three-way merge | design 3.2, 6.2, I26, I38-I57, E04 | `S02_TEST_FINDINGS_EPIC4.md` (`+127`, no production defect) | ACCEPTED WITH LIMIT: a device never pulls; layout and pixels NOT_RUN |
| Cross-story gate: round trip, wipe, stream lifecycle (E01-E03) | design 11 | EPIC7 (E01, E02), EPIC6B (E03) | ACCEPTED |

INFERENCE: the roadmap gate is met as follows: round trip = E01 on the synthetic corpus; deletion removes streams = S02-06; lifecycle rows = S02-08; no dedup promise = copy lint U33 (EPIC3).

## 3. Gate record

FACT sources: `docs/phase2/s02/S02_SPRINT_REPORT_AND_RETRO.md`, `core/LESSONS_LOG.md`, change records `core/changes/2026-10-16-s02-design*.md`, `docs/sdlc/STATE.md`.

Documentation gate (design and test plan, revision 12, 239 planned tests):
- Round 1: REJECT, 1 BLOCKER and 5 MAJOR (design revision 4; includes deletion fence).
- Round 2: REJECT, durable merge convergence and uncommitted-generation activation (revision 5).
- Rounds 3 to 9: each REJECT on new holes of the input-class merge design (override drop rule, per-field input mapping, explicit edit invisible, version-only transition, stale explicit value, unbounded edit history, candidate resolution); the design was replaced by value-based overrides (revisions 6 to 12). UNKNOWN: severity labels of rounds 3 to 9 (not opened).
- Round 10: APPROVE on `9c68cab8`.

Code gate:
- Round 11 on `f1646961`: REJECT, 3 MAJOR (account switch wiped another account's journal; missing owner marker let next account adopt a journal; tombstone push capped at 8 per pass). Fixed by remediation E.
- Round 12 on `10288e57`: three earlier findings resolved; REJECT, 1 MAJOR (cloud-upload consent cache shared by all accounts). Fixed by remediation H and I after a class sweep.
- Round 13 on `0096dd88`: four earlier findings resolved; REJECT, 1 MAJOR (consent calls checked the locally bound account while the server call ran as whoever was signed in). Fixed by remediation J (initiating account sent in the request, verified on the server).
- Round 14: APPROVE on `72cc3803`. PR #10 merged as `2c121242` by operator decision.

Before the external gate: six independent specialist reviews and remediation batches A to D (STATE.md); a second independent review round on the remediation (batches F and G).

## 4. Known limits accepted by decision

| Limit | Where recorded |
|---|---|
| `sendDebugTelemetry` is excluded from the expected-account check; it is the only exported handler without `verifyExpectedUid(`, named exempt in the structural scan | `S02_TEST_FINDINGS_EPIC16.md` section 16a2 |
| Six callables carry the expected-account check (`expectedUid`); mismatch gives `failed-precondition` / `account_changed` | `S02_TEST_FINDINGS_EPIC16.md`, design item 25 |
| Two large-filler tests (32 MiB comma filler, exactly at the bound) got a 60 000 ms timeout because they exceeded the 5 s default under parallel load; assertions unchanged | `S02_TEST_FINDINGS_EPIC16.md` section 16d |
| Withdrawal outbox, stream PUT timeout and other backlog items not built | `core/DECISION_LOG.md` round 13 entry; design item 25 |
| No mutation runs, no red-before-fix observation, by operator rule | EPIC16 "Not covered"; FINAL_RUN |
| Not exercised: wiring check that the settings client passes a live-uid supplier (needs Firebase); success path of real callables (SDK result type has a private constructor) | EPIC16 sections 16b, 16c |
| `scripts/ci/check_data_access_policy.js` standalone reports 5 violations in non-S02 files (`body_scan/manage.ts`, `nutrition_cache.ts`); pinned by a test | FINAL_RUN "Observations"; EPIC6B |
| `activity_reconcile_state` has no current code or rules reference (review only) | FINAL_RUN row 9 |
| Rules emulator not re-run after remediation J because rules and indexes are unchanged since `479b7342` | decision log, round 13 entry |
| Emulator counts access calls for a batch; 19 summaries accepted, 20 rejected; production counting unverified | EPIC5 |

## 5. Not done, and owner

Operator-owned (FACT: STATE.md, decision log, `S02_PRIVACY_TEXT_REQUEST.md`, `docs/phase2/split/BACKEND_SEPARATION.md`):
- Privacy wording approval; the generator source `legalPrivacyBody` in `app_en.arb` and `app_ru.arb` must drop "or never" and `public/privacy.html` be regenerated with it.
- First-release region.
- Deletion-record retention (400 days proposed, not decided).
- Bucket, IAM, alerts, soft-delete window, dedicated service account (runbook `runbooks/activity_stream_bucket.md`).
- Release gate for heavy work off the UI isolate (design 17 item 20).
- Blaze billing for the Phase 2 project; deploy credentials for the `phase2` alias.
- Other unanswered: monetisation per mode (D-9), master branch name (D-3), legal status of the third-party dossier (D-10).

Team-owned follow-ups:
- Local journal in the default build (OD-9). DISAGREEMENT: the operator decision says it opens always, but the S02 code ships `ACTIVITY_LOCAL_JOURNAL` default false and `journalEnabled = localJournal || cloudSync` (`mobile/lib/core/config/activity_flags.dart`), so in the default build the journal is not opened. The S03-D contract carries this as scope item S03-0. Verdict: OD-9 is NOT delivered by S02; it is carried to S03.
- Retention "never": FACT (`functions/src/activity_streams/commit_stream.ts` line 81, comment "Expiry hint in epoch millis, `null` = never") the server code still models "never" as a null expiry; UNKNOWN whether the settings callable and the client still accept or offer it after the operator decision (the grep was limited to `functions/src/activity_streams`); the S02 tests assert only 90 / 365 / 730 accepted for the settings callable (EPIC6A F13) and privacy text still mentions "never". Carry as a check story.
- Grant UI after consent withdrawal (uploads restart at next app start; EPIC7).
- Phase 9 acceptance (this file), release notes (`S02_RELEASE_NOTES.md`) and phase 10 report: retro is a living draft.

## 6. Definition of Done checklist

| Item | Status |
|---|---|
| Code committed with a change record per commit | DONE per decision log (each commit has a `core/changes/` record) |
| Per-epic functional tests written and run by test agents | DONE per findings files, epics 1 to 16 |
| Final complete runs | PARTIAL: `S02_TEST_FINDINGS_FINAL_RUN.md` is at head `45c747b0` (Dart `+1117`, `+97`, `+23`; server 744, 191, 289, 124; rules 953) and predates remediation E to J; later results are in EPIC11 to EPIC16 (Dart activity directory `+1485`, server `922` and `315`). DISAGREEMENT between files on which run is "last complete": the final-run file is older; EPIC16 is later. Neither is a single complete run on head `72cc3803` (UNKNOWN: none found) |
| EPIC16 server run | Not fully green at first (`3 failed`), later green (`922 passed`, `315 passed`) after the checker re-pin `5ec1acc1` and timeout change |
| Review consensus | DONE per STATE.md (six specialists, second round, three sweeps) |
| GPT-PM APPROVE for the head | DONE: round 14, `72cc3803` |
| Docs updated | PARTIAL: design revision 12 and STATE.md updated; the privacy text and the design flag description (OD-9) are stale against operator decisions |
| Release notes | NOT DONE in this file; Agent 2 writes `S02_RELEASE_NOTES.md` |
| No flag enabled by default | DONE per `activity_flags.dart` (both OFF) |
| Lessons log entry per commit | DONE for the lessons seen; not audited per commit (UNKNOWN) |
| Report and retro | NOT DONE: `S02_SPRINT_REPORT_AND_RETRO.md` is "living draft" |
| Secret scan after merge | Fix committed (rename sentinel and `.gitleaksignore` entry); not run locally; CI confirmation UNKNOWN (decision log) |

## 7. UNKNOWN list and disagreements

UNKNOWN: severities of documentation rounds 3 to 9; per-count results of epics 8 to 15 (not opened in this draft); whether code rejects "never" (as merged in `2c121242` it did not: `STREAM_RETENTION_NEVER_OFFERED` was `true`; the follow-up commit on the next sprint branch sets it to `false`, and its tests are recorded in `S02_TEST_FINDINGS_EPIC17.md` once that file exists); whether any complete run exists on head `72cc3803`; per-commit lessons log coverage.

Disagreements: (a) OD-9 versus flag default in code and design 12.1; (b) final-run file head `45c747b0` versus later epic results; (c) privacy draft and `S02_PRIVACY_TEXT_REQUEST.md` listed "never" and a 2-year proposed default versus the operator decision (the follow-up commit removes "never" at the wording's real source `scripts/legal/legal_text.py`; the wording stays a DRAFT pending approval); (d) STATE.md "Current phase: 8 Gate" header text versus merged status in the same paragraph.
