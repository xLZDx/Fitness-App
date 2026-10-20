# AI Coach GPT-PM decision request: offline writes and contract gate

Date: 2026-10-19  
Project: Fitness_App AI Coach  
Repository: `D:\Repo\Fitness_App_aicoach`  
Change type: product/authorization request and transport outcome; no decision or implementation is asserted.

## Why this request exists

The earlier request `e0b7b888-d2a4-4dfd-a3b9-f73e52a38fed` failed before its send boundary: PM Bridge recorded `ATTACHMENT_NOT_LANDED`, `sendPhase=not-started`, missing `03_DESIGN.md`, and no user turn or reply. The daemon is now healthy. A new request is prepared because no GPT-PM reply exists for that failed request.

## Supplied source basis

- `docs/ai-coach/03_DESIGN.md` §0.4 recommends a Firestore transaction over the latest existing workout session, stable operation/set IDs, identical-replay no-op, payload-mismatch conflict, `NOT_SENT_OFFLINE` when a transaction cannot start offline, and `UNKNOWN` after an ambiguous sent request until a server-backed read resolves it.
- The current repository boundary uses the existing `WorkoutSession` store; no second tracker/store, journal, or workout-wide lifecycle is accepted by the existing product/design decision.
- The transaction choice removes durable offline persistence for these workout mutations. An offline keyed-operation representation would expand the accepted storage/read/export and compatibility scope.
- Existing product/design acceptance for the voice contract explicitly did not grant implementation authorization. No clinical values, symptom thresholds, on-call identity, or runtime evidence is supplied by this request.

## Decision requested from GPT-PM

Please answer each item with `ACCEPT`, `MODIFY`, or `REJECT`, and state the consequence and any exact missing evidence.

1. **Offline-write product tradeoff:** Choose one:
   - **A — online transaction, recommended:** mutations use a fresh-document transaction; offline attempts return visible `NOT_SENT_OFFLINE`, preserve the unsaved capture only in the current UI, and do not start rest or claim durability. The user cannot durably record while offline, and leaving the screen may discard the unsaved capture.
   - **B — durable offline operation records:** approve expansion to a keyed offline-operation representation and explicitly accept the required reader/export, reconciliation, and old/new-client compatibility work. This is outside the currently accepted single-store boundary.

   Do not infer a third behavior from Firestore's offline queue: the current whole-document last-write-wins write does not satisfy the accepted concurrency and replay contract.

2. **OQ-07 product gate:** confirm that prescriptions and symptom-triggered behavior stay unavailable until a versioned policy and qualified-human signature exist. GPT-PM must not supply or imply clinical limits, symptom values, or a qualified signer. A product ACCEPT here is not clinical approval.

3. **OQ-14/OQ-18 closure boundary:** confirm whether the previously recorded fail-closed product directions remain binding while populated source allowlists, measured freshness/clock values, recovery classes/horizon/calendar policy, and persistence conformance remain deferred. No defaults are proposed for those values.

4. **Code-sprint authorization:** based on the attached current design and acceptance documents, state either `GO` or `NOT AUTHORIZED` for implementation of the existing-workout voice contract. If `GO`, enumerate the exact bounded in-scope contract and prerequisites; exclude runtime/production mutation, migration, alert configuration, and clinical policy unless separately authorized. If item 1 or an unresolved product value prevents a coherent scope, return `NOT AUTHORIZED` with the blocker.

This is a GPT-PM product/authorization request only. It does not ask for clinical sign-off or a production on-call appointment, and it does not authorize tests, deployment, production changes, push, or merge. No clinical limit may be applied before a qualified specialist signs the actual values and scope.

## Role boundary

The operator is accountable task owner. Codex is the delegated technical contract owner/executor. GPT-PM owns product decisions. A qualified human remains required for clinical sign-off; no person is named by this request. For ACS-100, Fitness_App AI Coach is the project-local owning component, while deployed service identity, configured recipient/rotation, delivery, and acknowledgement remain separate operational evidence.

## Current-turn transport outcome

PM Bridge health returned `OK`. At the operator's earlier instruction to use a new chat, PM Bridge opened conversation `6ad656cf-7c4c-83ed-89f0-fd349f19ba1a` and preserved the previous conversation. The attached `gpt_send_and_await` request used ID `8fd23d10-6840-4db1-9ee3-52ef849bf7dc` and job `d0949314-8a06-4148-96b9-7f9a21d21e6b`; it failed pre-send with `ATTACHMENT_NOT_LANDED` (missing `03_DESIGN.md` and `acceptance.md`). A same-ID retry returned the same terminal job and attempt count; `sendPhase=not-started`, `sendSnapshot=null`, `userTurnId=null`, and `replyId=null`. A text-only `gpt_send` using the same ID was refused because that request ID already owns the failed `send-and-await` lineage. No second browser send was issued and no replacement request ID was created.

The last-read GPT-PM response in the new conversation was the earlier correlated product/design acceptance `3c4bd141-27da-4e5e-a4f0-7a9c6a3e8b2d`, not a response to this request. The offline-write tradeoff, code-sprint GO, and any new OQ disposition therefore remain unanswered. The prepared decision content above remains the exact intended ask; no reply is attributed to it.

### Current-turn read-only conversation peek

Because the operator asked Codex to retrieve the response after the request attempt, a read-only `gpt_session_peek` used the same project conversation and request ID. PM Bridge job `871fec36-97ee-4538-813d-7f77b4688029` succeeded and returned the initial project greeting only (`turnsCount=1`), with no user turn or reply correlation. It did not retrieve an answer to the failed request. The peek sent no message and created no replacement request ID. GPT-PM's offline-write choice and code-sprint GO remain unanswered.
