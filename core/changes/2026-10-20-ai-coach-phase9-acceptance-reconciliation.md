# Phase 9 AI Coach acceptance reconciliation

Date: 2026-10-20. Documentation and bounded read-only source reconciliation for Phase 9 work items 1–5. No implementation, production operation, alert change, or clinical decision was made.

## Baseline and provenance

The baseline captured at the start of the documented reconciliation was checkout `D:\Repo\Fitness_App_aicoach` on `docs/ai-coach-tdd-001`, `HEAD=a2610e6194f7b2676dc1d9a4843b6359e86b50da`, tracking `origin/docs/ai-coach-tdd-001` and ahead by 100 commits. Tracked files were clean. The pre-existing untracked file `core/changes/2026-10-18-ai-coach-phase9-gptpm-transport-followup.md` was preserved and not edited.

At the start of this continuation, the Phase 9 tracked-document diff and the two new Phase 9 records below were already present from earlier work in the active task. This continuation refreshed the ACS-100 metric observation in the acceptance/reconciliation/change record, labeled the 2026-10-19 backlog addendum historical and linked the current 2026-10-20 reconciliation, then regenerated the document registry. The earlier files' origin is attributed to their recorded history, not to actions newly performed in this continuation.

PM Bridge health returned `OK`, mode ON, no active job or queue backlog. GPT review request `c57e1b19-8a35-49a6-9e21-8045cd0b77d4` was sent with three real UTF-8 Markdown attachments from this checkout:

- `docs/ai-coach/acceptance.md`
- `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md`
- `docs/ai-coach/22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md`

`gpt_send_and_await` returned a reply containing the same request ID and disposition `MODIFY`, 0 BLOCKER, 5 MAJOR and 3 MINOR. It did not authenticate the supplied repository HEAD or current production telemetry. The retained response did not include separate job/user-turn/reply UUIDs; no such UUIDs are claimed here.

The reply's F-01 reports that the active ChatGPT conversation contains a direct `ACCEPT` for request `a1d8e730-5c4b-4a92-9b67-3e28f06c1a55`. This is distinct from the durable transport evidence in [the prior contract follow-up](2026-10-19-ai-coach-phase9-gptpm-contract-followup.md): job `403e0882-9227-4d7a-967b-eca657fce9d0` failed before send (`sendPhase=not-started`, `ATTACHMENT_NOT_LANDED`, no Bridge user turn/reply). The current ledger records `DIRECT_CHAT_RESPONSE_REPORTED / PM_BRIDGE_CORRELATION_FAILED / EXACT_TREE_NOT_AUTHENTICATED`; it does not claim successful Bridge delivery, exact-tree approval, implementation authorization, clinical sign-off, runtime proof, or story acceptance.

## Changes made in this turn

- Added `docs/ai-coach/23_PHASE9_ACCEPTANCE_RECONCILIATION_2026-10-20.md` as the controlling current status snapshot, including all eight latest review findings, status axes, bounded OQ-07/OQ-14/OQ-18 path maps, ACS-100 status and ordered closure queue.
- Updated `docs/ai-coach/acceptance.md` to point to the controlling record, separate document/product/implementation/clinical/live/story status, preserve all 13 PENDING story dispositions, separate reported direct-chat evidence from failed Bridge transport, and record the latest natural metric observation.
- Updated `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md` and `docs/ai-coach/22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md` with explicit supersession notices, corrected current task roles, reconciled the OQ-18 target as a selected design (not implementation), corrected ACS-100 target status, and preserved the factual record that `a1d8e730` failed before send.
- Updated `docs/ai-coach/00_README.md` reading order/status so the new reconciliation is discoverable. Regenerated `docs/DOCUMENT_REGISTRY.md` using `python scripts/dev/gen_document_registry.py` (372 Markdown documents).
- Current delegated task roles: Codex leads and executes routine technical decisions; GPT reviews. The separate ACS-100 assignment record names Fitness_App AI Coach as the project component, Codex as task-local technical on-call/triage executor while this work is active, the project operator as interim human escalation recipient, and GPT-PM as product escalation owner. This does not create continuous 24/7 coverage, an alert endpoint, clinical qualification, or production delivery evidence. Historical correlated GPT-PM decisions remain limited to their documented scope.

## Source evidence recorded

- OQ-14 source → callable → UI: `mobile/lib/features/ai_coach/ai_coach_service.dart`, `functions/src/ai_coach_advice.ts`, `mobile/lib/features/ai_coach/ai_coach_sheet.dart`; callers in equipment detail, exercise and scanner screens. The current route returns/renders free-form advice and has no typed factual-evidence boundary. The response/provider cache is transient Riverpod state; no durable persisted advice store was found in the bounded search.
- OQ-07 assignment paths: `generatedPlanProvider` → `buildPlan` → `ai_planner_page.dart`; `onboardingPlanPreviewProvider`; `suggestNextWeight` in the workout player; existing programme/scheduled-session generation; and the pure voice parser in `mobile/lib/features/voice/data/voice_command.dart`. The search found no signed-policy resolver at these actionable paths and no production speech-to-text command dispatcher; this is absence in the inspected source, not a claim about external behavior.
- OQ-18 storage/readers: `FirestoreProgrammeRepository` and `FirestoreScheduledSessionRepository` write separate user-scoped documents with `.set`; `programme_providers.dart` saves programme and schedule rows separately. Existing programme/schedule providers, workout/session-screening and recovery readers, mobile export, server account export, and the user-scoped recursive rule in `firestore.rules` are listed in the reconciliation. A transaction coordinator is the selected design target only; current atomic conformance remains NOT_IMPLEMENTED/NOT_VERIFIED.
- ACS-100 metric observation refreshed in this turn by a read-only Cloud Monitoring GET queried at `2026-10-20T10:08:17Z` UTC, with a three-minute ingestion buffer, for `2026-10-19T10:05:17Z`–`2026-10-20T10:05:17Z` UTC. Exact filter: `metric.type = "run.googleapis.com/container/instance_count_with_readiness" AND resource.type = "cloud_run_revision" AND resource.labels.service_name = "aicoachadvice" AND resource.labels.location = "europe-west1"`. HTTP 200 returned only `unit`, no `timeSeries`: zero returned matching series and points. Observability remains UNKNOWN; this does not establish zero traffic or service health. No callable or synthetic AI request was generated, and no alert or production configuration was changed. This supersedes the earlier 09:27Z observation.

## Follow-up GPT review and corrections

PM Bridge request `b84a3e72-6f1c-4da9-9f35-a019df8752c6` was sent with eight real Markdown attachments: `00_README.md`, `acceptance.md`, the OQ-14/OQ-18 and OQ-07 proposals, this reconciliation, `DOCUMENT_REGISTRY.md`, and the 2026-10-19 and 2026-10-20 transport/change records. Durable job `aa05b400-9957-43e4-a40a-7505737b0c68` records `sendPhase=sent`, user turn `3b4dbec1-dfe5-4d68-9e93-4b648697add9`, reply `58d95c14-c70f-49fd-b2c4-682b90257a70`, and `correlated=true`. GPT returned `MODIFY`, 0 BLOCKER, 1 MAJOR, 1 MINOR. Its MAJOR finding said OQ-07 journal wording and OQ-21's `Journal only` default could imply a second authoritative store; its MINOR finding said OQ-28 journal-size terminology was ambiguous.

After receiving that response, Codex:

- changed OQ-21 to keep storage unresolved while requiring compatibility with the existing authoritative workout path;
- changed OQ-28 capacity wording to cover existing workout records and only separately approved compatible auxiliary audit metadata;
- retained OQ-07 fact immutability, provenance, unavailable classification and auditable reclassification, while making the physical storage mechanism implementation-open and prohibiting a standalone or parallel authoritative workout journal/state machine;
- found direct journal-only references in the older requirements, backlog and design sources during a repository-local documentation search and added explicit supersession/storage-neutrality language; historical decision records remain unchanged;
- updated the README, acceptance, OQ proposals and reconciliation to identify the latest review and post-review corrections without claiming the corrected bundle has been re-reviewed.

This follow-up remains documentation-only. The post-correction bundle has not been reviewed again by GPT.

## Focused post-remediation review and final wording correction

Request `c4f2178a-91e4-4d63-a2c8-73c8cc221e50` sent eleven attachments through PM Bridge, including the prior acceptance/reconciliation set plus `01_REQUIREMENTS.md`, `02_BACKLOG.md`, and `03_DESIGN.md`. Durable job `a15f286f-9b0f-4f46-9728-ee5c482963b2` records `sendPhase=sent`, user turn `7410f468-bd86-4076-9e1e-5897acf74fae`, reply `78564210-114c-4565-aedd-0b5a8fc9a247`, and `correlated=true`. GPT returned `MODIFY`, 0 BLOCKER, 0 MAJOR, 1 MINOR. It accepted the M-01/m-01 storage corrections and the requirements/design supersession, but found that the original Sprint-00 ACS-001/ACS-002 criteria in `02_BACKLOG.md` §5 still read as normative.

Codex inserted a historical/supersession notice immediately before Epic E00-A in `02_BACKLOG.md`, linked §5 to the current §2.1 scope, and reiterated that ACS-001/002 remain CARRIED while all 13 final story dispositions stay PENDING. A focused final review then supplied ten attachments for commit `66eb9bcf8d67dca38c97f36eea6451e85c9a48a7`. Durable job `6c2ba4b6-665a-45b6-ab68-064ae32152a9` records request `d7f2369e-cf3a-4d88-a523-6f3f5ca0ed11`, user turn `572eb05f-68b7-43ed-98ff-06c64506af84`, reply `c216528b-4871-4356-bad1-1fea5366efde`, and `correlated=true`. GPT returned `ACCEPT`, 0 BLOCKER, 0 MAJOR, 0 MINOR; it closed m-02, accepted the updated ACS-100 metric interpretation, and found no direct regression in scope. GPT treated the metric query/response as supplied evidence and did not independently reproduce live telemetry.

## Verification limits

This work consists of documentation editing, documentation-registry generation, a bounded manual cross-document consistency pass, and read-only source/transport inspection. No tests, checks, builds, CI, migrations, runtime writes, alert configuration, notification test, synthetic AI request, deployment, push or merge was run or performed. This record does not claim a push or merge; local commit state is determined by the repository history.

## Remaining acceptance gates

1. The final m-02 wording is a local documentation clarification after the latest GPT review; do not describe that exact sentence as GPT-reviewed or the full acceptance package as approved.
2. Keep all 13 story dispositions PENDING until their requested review and OQ routing are complete.
3. OQ-07 clinical values and symptom scope remain unavailable until a qualified signer provides an actual versioned policy and signature.
4. OQ-14 source mappings/freshness and OQ-18 product/persistence inputs and implementation conformance remain open; no code or runtime behavior is proven here.
5. For ACS-100, Codex is the task-local technical triage executor and the project operator is the interim human escalation recipient. Alert binding, reachable delivery, acknowledgement, continuous coverage and current natural metric evidence remain unverified; do not generate synthetic traffic or use an artificial notification as health evidence.
