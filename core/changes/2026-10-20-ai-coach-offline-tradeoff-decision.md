# AI Coach GPT-PM offline tradeoff decision and resend record

Date: 2026-10-20  
Project: Fitness_App AI Coach  
Repository: `D:\Repo\Fitness_App_aicoach`  
Change type: correlated product decision and documentation preparation. No implementation or code GO is asserted.

## Request delivery

The earlier decision request `8fd23d10-6840-4db1-9ee3-52ef849bf7dc` failed before send because its attachments did not land; the historical failed state is preserved in [the prior transport record](2026-10-19-ai-coach-gptpm-offline-contract-request.md). A new request, `4b6238a0-1c80-4d69-87ba-45a214fc7e31`, was sent with eight UTF-8 Markdown attachments to project `fitness_app_aicoach`, conversation `6ad656cf-7c4c-83ed-89f0-fd349f19ba1a`.

Durable PM Bridge status for job `4176bb29-d3f1-42a8-920c-e7f562f42ee0` was re-read on 2026-10-20: `status=succeeded`, `sendPhase=sent`, one attempt, `correlated=true`, user turn `313be192-99de-436e-bc12-0ddd545f0a16`, reply `5e446c22-bca5-464f-9fac-c167648855d4`. The exact attachments and SHA-256 values were preserved in the durable send snapshot:

| Attachment | SHA-256 |
|---|---|
| `03_DESIGN.md` | `b183458c25a1f26023f0615f3a332092f0e2085baef769c7e3ea72bbced2b162` |
| `acceptance.md` | `be69d5caf816610f7502b75c4d7a31caa58a5003a189d9186a5aae63355e911f` |
| `01_REQUIREMENTS.md` | `37fd32c344b1118256551c139dcaa8ce3db9032fd1970b698b1e4d2f59d8177e` |
| `02_BACKLOG.md` | `5b7b475e88f6baf43450be8f19f8da446690bd22598d151e6340d15105b81cb7` |
| `21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md` | `a53ba1ff798fc04473a4854490840967f75299ae6697dd050dabd0ad1a13b24e` |
| `22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md` | `db0119a0abeb806bb156606a600ad775c7f9b38eb71d43723aa5f8c873960fa0` |
| `23_PHASE9_ACCEPTANCE_RECONCILIATION_2026-10-20.md` | `620e6e66044c1a0419f57010d804ec3582ccf3dbfa91c3ec5ee1ed02879445be` |
| `2026-10-19-ai-coach-gptpm-offline-contract-request.md` | `c868b215c91f75697d9e6ae47387c1668dc710fa60707c7af714a6ff088b9fb5` |

The logical request text asked for product/authorization disposition only and explicitly disclaimed clinical sign-off, tests, deployment, production changes, push and merge. PM Bridge's durable `sendSnapshot.text` additionally contained a generic `EXECUTION AUTHORITY: GO AUTHORIZED / PUSH AUTHORIZED` footer that was not present in `logicalText`. This footer is a transport-level conflict with the request's stated scope; it is not operator authorization and is not treated as a project decision. GPT-PM's correlated response explicitly returned code `NOT AUTHORIZED` and production/push/merge `NOT AUTHORIZED BY THIS REVIEW`. The unexpected footer requires correction by the PM Bridge owner before relying on generated authority text in future requests; that owner is not identified in this repository. No cross-project PM Bridge source was inspected or changed.

## Correlated decision

Overall disposition: **PARTIAL ACCEPT — OPTION A APPROVED, IMPLEMENTATION NOT AUTHORIZED.**

1. **Offline tradeoff:** Option A accepted for the new shared set/add/difficulty action: use a fresh-document transaction over the current `WorkoutSession`; no durable offline write; retain an unsaved capture only in the current screen; no rest or saved claim for a non-acknowledged action. `NOT_SENT_OFFLINE` is valid only when non-submission is established; an ambiguous send/commit is `UNKNOWN` and requires server-backed reconciliation of the same operation identity. `SERVER_ACKNOWLEDGED` requires confirmed transaction success. Option B (separate durable offline operation records) is rejected for this scope.
2. **OQ-07:** fail-closed product boundary accepted. No clinical authorization, numeric limits, symptom thresholds, credentials or qualified signer were granted. Prescription/symptom-dependent behavior remains unavailable pending the required versioned policy and qualified-human signature.
3. **OQ-14/OQ-18:** existing bounded fail-closed directions remain accepted. Deferred source allowlists, mappings, freshness/clock values, templates, recovery/calendar inputs and persistence conformance remain open; no defaults were supplied.
4. **AI-COACH-01 code sprint:** `NOT AUTHORIZED`. GPT-PM listed AICR-074/legacy touch impact, transaction identity/replay, old-client metadata stripping, writer/reader/export compatibility, UI lifecycle outcomes and frozen scope as prerequisites.

The exact correlated reply is in PM Bridge job `4176bb29-d3f1-42a8-920c-e7f562f42ee0`. It does not authenticate Git ancestry or runtime behavior and is not a qualified clinical signature.

## Documentation actions requested by the response

The decision's ordered follow-up was: make Option A controlling in design/OQ records; reconcile AICR-074 and current touch behavior; define operation identity, replay/conflict, acknowledgement, unknown recovery and UI disposal; complete writer/reader/export/client compatibility mapping; and prepare a bounded AI-COACH-01 scope for later authorization. The resulting scope preparation is [24_PHASE9_AI_COACH_01_TRANSACTION_SCOPE.md](../../docs/ai-coach/24_PHASE9_AI_COACH_01_TRANSACTION_SCOPE.md). Its explicit open gates mean it does not claim code GO.

The documentation update covers `docs/ai-coach/00_README.md`, `01_REQUIREMENTS.md` (AICR-074), `01b_CODE_MAP.md`, `02_BACKLOG.md` (AI-COACH-01/OQ-01/OQ-02), `03_DESIGN.md` (§0.4 and historical-status correction), `23_PHASE9_ACCEPTANCE_RECONCILIATION_2026-10-20.md`, `24_PHASE9_AI_COACH_01_TRANSACTION_SCOPE.md`, and `acceptance.md`; `docs/DOCUMENT_REGISTRY.md` was regenerated with the repository generator. A read-only `code-reviewer` pass found one stale §0.3 sentence that presented the transaction choice as still undecided. It was corrected to identify the 2026-10-19 checkpoint and point to §0.4 for current status. The reviewer reported no other material inconsistencies in the decision provenance, withheld code authorization, AICR-074 boundary, or scope exclusions.

## Responsibility for transport choice

Codex selected `gpt_send_and_await` because the PM Bridge tool instructions recommend one continuous browser session through send and wait, avoiding a close/reopen gap that had interrupted GPT generation. Codex owns that execution choice and verification. The successful request was actually delivered and correlated; no claim of background activity is made. The generic authority-footer mismatch above was discovered by reading the durable send snapshot and was not authored by the operator as part of this logical request.

## Verification limits

This record documents PM Bridge transport evidence and the correlated GPT-PM reply. It does not prove implementation, tests, service health, alert delivery, clinical approval, or story disposition. No tests, checks, builds, CI, migrations, runtime writes, production changes, push or merge were performed as part of the documentation follow-up.
