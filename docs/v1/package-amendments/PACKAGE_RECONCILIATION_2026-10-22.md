# FitnessUp v1 package: reconciliation with the four amendments (2026-10-22)

Status: the rebaseline package `FitnessUp_v1_Rebaseline_2026-10-20` is an external deliverable and is not stored in this repository. This folder is the in-repository bridge: it records the independent package review of 2026-10-22, the verified findings, which package rows the four approved amendments supersede, and the new acceptance rows. Until the package author reissues the registers, the amendments and this folder win over the package where they conflict.

Amendments in force (all under `docs/v1/`): `LOCAL_QUEUE_DECISION.md`, `ATTENDANCE_SPEC_AMENDMENT.md`, `MODULE_DISPOSITION_MATRIX.md`, `VOICE_READY_PROMPT_DECISION.md`.

## Review result
Independent review through GPT-PM (request 7b78ae18-5a6d-498a-8fa6-0dced7bdf1c9, input: the package registers and documents plus the four amendments): verdict MODIFY with 3 BLOCKER and 7 MAJOR findings, no confirmed arithmetic error. Preparatory work (source preservation and integration, runtime verification, standalone manual-fitness and nutrition work, private-gym inventory, read-only voice research) may proceed. The online command protocol (E1), the old background-first attendance design and the legacy voice start grammar must not be implemented as written.

Facts re-checked against the package files by the coordinator on 2026-10-22: `ACCEPTANCE.csv` FU-AC-015 and FU-AC-064 still require online-only behavior for the three commands; FU-AC-046 still contains background permission steps and registration after reboot; FU-AC-047 has no automatic/suggestion/unknown distinction; FU-AC-067 only rejects substring matching; `docs/04_CORE_TDD.md` still requires an online `prepareWorkoutCommand` with a server-minted command id before the effect; `docs/15_DECISIONS_AND_RISKS.md` ADR-CMD-03 still says online-only with no durable queue. The remaining findings are the reviewer's claims, not coordinator measurements.

## Findings and how they are closed

| ID | Severity | Finding | Closure in this folder |
|---|---|---|---|
| B-01 | BLOCKER | Local acceptance before network conflicts with the server-minted command admission step | FU-AC-092, 093, 095; the protocol itself is still to be written into the core design (see Document changes) |
| B-02 | BLOCKER | Replay protection, receipt retention and writer migration have no single consistent proof for commands that stay offline longer than the detailed-record TTL | FU-AC-094, 096, 097, 098; the protocol freeze is a precondition of E1 |
| B-03 | BLOCKER | Queue lifecycle (sign-out, deletion, export, backup) is not in the data and lifecycle contracts | FU-AC-102 to 105; data model and privacy documents to be amended |
| M-01 | MAJOR | Local, synced and conflicted workout projections are inconsistent | FU-AC-099, 100 |
| M-02 | MAJOR | Foreground attendance (delivery 1) is mixed with background geofences (delivery 2) in the visit design | FU-AC-110; SPLIT in `SUPERSESSION.csv` |
| M-03 | MAJOR | Attendance evaluation can still count suggestions as detections | FU-AC-106 to 109 |
| M-04 | MAJOR | The ready-prompt StartSet is missing from the voice runtime and acceptance contracts | FU-AC-113 to 118 |
| M-05 | MAJOR | The module matrix is not an executable release-scope gate | open: a route and action coverage matrix (build inclusion, navigation, direct routes, shortcuts, persisted preferences, action admission, release tests) is still to be written |
| M-06 | MAJOR | Register consistency is mechanical, not semantic | `SUPERSESSION.csv` plus `ACCEPTANCE_AMENDMENTS.csv`; the registers themselves are reissued by the package author |
| M-07 | MAJOR | The implementation baseline and runtime status are not verified for the current date | open: freeze a current source manifest (full commit and tree hashes) and the deployed runtime of both Cloud Functions codebases before E0 integration |

## Files in this folder
- `ACCEPTANCE_AMENDMENTS.csv`: 27 new acceptance rows FU-AC-092 to FU-AC-118 in the package column layout, all status NOT_RUN. They are contractual cases, not 27 separate test runs: existing fault-injection tests may be reused where they prove the same invariant, with cross-links instead of duplicate PASS evidence.
- `SUPERSESSION.csv`: which package rows are superseded, rewritten, extended, split or preserved by which amendment.

## Document changes still to be made by the package author
`01_PRODUCT_SCOPE` (local versus server save, readiness journey), `03_ARCHITECTURE` (replace the online-only exception, add the local queue boundary), `04_CORE_TDD` (offline-first protocol: identity, replay, writer fencing, lifecycle, migration), `05_DATA_MODEL` (local command store, UID lifecycle, receipt retention, delivery 1 and 2 attendance schema), `06_GLOBAL_COACH` (waiting-state interaction, microphone ownership), `09_GYM_VISITS_TDD` (foreground inference versus geofencing), `11_SECURITY_PRIVACY`, `12_ACCEPTANCE_AND_TEST_STRATEGY`, `13_DELIVERY_ROADMAP` (re-estimate E1, E2, E6 after the contracts are reconciled), `14_INTEGRATION_MIGRATION_RUNBOOK` (two generations of pending writes), `15_DECISIONS_AND_RISKS` (supersede ADR-CMD-03, update ADR-CMD-02, add the voice-ready decision and attendance delivery status), `16_DOCUMENT_REGISTRY`, `17_RELEASE_OPERATIONS`, `18_CURRENT_INTEGRATION_BASELINE` (dated snapshot, not current HEAD). `VOICE_WORKOUT_SOURCE_FINDINGS.md` stays historical; append a pointer that Option A is superseded rather than editing its provenance.

## Other observations from the review (not blockers)
- FU-AC-066, 067 and 072 are P0 while their parent requirements are P1: record the rationale (safety regressions inside P1 features) or align.
- FU-AC-084 to 091 point to `18_CURRENT_INTEGRATION_BASELINE.md` instead of the parent design document: mark primary versus supplementary reference.
- The AI cost model reconciles arithmetically (four scale cases); it is a voice-service cost only, not a total operating cost, and long-context replay, tools and retries could raise it. The editable workbook was not part of the review.
- Referenced companion registers (the 65-task historical crosswalk, the 15 source-compatibility checks, the nine integration groups, API canonical bytes, command golden vectors) were not in the review bundle and are unverified.
- The Google Cloud Functions runtime dates (Node.js 20 decommission 2026-10-30, Node.js 22 2027-10-31, Node.js 24 2028-10-31) were confirmed by the reviewer against the official table; the deployed state of this product is unknown.
