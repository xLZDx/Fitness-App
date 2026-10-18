# AI Coach Phase 9: operator-provided GPT-PM disposition copy

Date: 2026-10-18. Kind: decision-provenance reconciliation.

## What changed and why

The operator supplied the complete text artifact `C:\Users\koros\.codex\attachments\b1ca3691-e58e-475b-800e-07b82afa5e84\Pasted text.txt`, labeled `REQUEST_ID: 15dddc0d-4e77-41ce-8fa7-e07b7e0041e5`. The artifact records `APPROVE` for the bounded OQ-07, OQ-14 and OQ-18 product directions on the proposal content it says it examined, and `UNAVAILABLE` for canonical engineering/persistence/runtime/on-call/clinical appointments. Its supplied-head qualification is explicitly negative: connected GitHub returned `422 — No commit found` for `6915afb7cd78e96523ffa2737148c522ee07d393`, so the disposition is not an authenticated exact-tree approval.

The durable PM Bridge job for the same request ID is `430d3d00-200e-43a4-9094-a5b0af9ed19b`, idempotency key `15dddc0d-4e77-41ce-8fa7-e07b7e0041e5:send-and-await`, and payload hash `e6b3cc8dbe8d1fe32268079f1c0535785ccd19ed9ad88307afbc7eb535c3965f`. Its persisted state is `failed`, `sendPhase=not-started`, `ATTACHMENT_NOT_LANDED` (missing `acceptance.md`), `userTurnId=null`, `replyId=null`, and `sendSnapshot=null`. This durable state proves that PM Bridge did not send this request. The operator-provided answer text is therefore preserved as supplied content, not described as a correlated PM Bridge reply. No retry, payload change, or duplicate request was issued.

This corrects the previous acceptance/README/SDLC wording that treated the exact-tree product disposition as simply unavailable: the operator-provided text does supply bounded content-level dispositions, while exact-tree authentication and PM Bridge correlation remain unavailable. The acceptance record, ownership route and SDLC checkpoint now make both facts explicit.

## Decision boundary

- **OQ-07 bounded product direction — APPROVE per supplied text.** No actionable personalized prescription without an authoritative, versioned policy with qualified-human clinical/safety authorization; missing, invalid, expired or unsigned evidence fails closed; structurally valid performed facts are preserved rather than clamped to an unsigned assignment cap. Actual limits, symptom scope, signer qualification and signature remain open.
- **OQ-14 bounded product direction — APPROVE per supplied text.** Source-bound typed factual claims and deterministic localized templates; arbitrary model-generated factual prose is excluded. Populated source allowlist, claim/evidence schema, freshness/version rules and template/refusal coverage remain open.
- **OQ-18 bounded product direction — APPROVE per supplied text.** Deterministic application-owned composition, immutable/versioned inputs, idempotent persistence, explicit policy versions, and separation of observed/projected volume; recovery-dependent drafts refuse when required evidence is insufficient, and UNKNOWN never means RECOVERED. Detailed schema, source/freshness rules, recovery scope, persistence protocol/owner and acceptance mapping remain open.
- **Ownership — UNAVAILABLE per supplied text.** The operator's earlier assignment is retained: Codex owns task-local OQ technical authorship/execution/self-review; GPT-PM owns product decisions/signature. This is not a canonical production-service appointment. The artifact does not establish the ACS-100 runtime service, accountable operations owner or real on-call recipient.
- **Exact-tree disposition — NOT_VERIFIED.** The artifact says the supplied GitHub commit lookup returned HTTP 422. Nothing here upgrades the response into approval of local HEAD `b51b14c268a381fff00e9afab7df0f13f0ee66c7` or any later commit.
- **Story and implementation gates — OPEN.** All 13 Phase 9 story dispositions remain PENDING. No implementation, tests, checks, build, CI, migration, runtime/alert action, production activation, push or merge is authorized by this artifact.

## Changed paths

- `docs/ai-coach/acceptance.md` — preserve the job failure and separately record the supplied disposition content and its evidence boundary.
- `docs/ai-coach/20_PHASE9_EXECUTION_OWNERSHIP_AND_REVIEW_ROUTE.md` — reconcile the latest supplied disposition with the existing Codex/GPT-PM task roles and the separate service/clinical gaps.
- `docs/ai-coach/00_README.md` — update the current summary without claiming an authenticated exact-tree verdict.
- `docs/sdlc/STATE.md` — append the same provenance boundary and current gates.
- `docs/DOCUMENT_REGISTRY.md` — regenerated derived registry.

## Verification and limits

Manually compared the supplied artifact's decision tables and gate status with PM Bridge job status and the existing acceptance, route, README and SDLC records. The Bridge job and supplied answer conflict on whether a reply was sent; the persisted job controls the transport claim, while the answer is retained only as operator-provided content. The supplied file's author identity and GitHub HEAD qualification were not independently authenticated. Documentation consistency was manually reviewed. No tests, checks, builds, CI, migrations, implementation, runtime actions, alert delivery, push or merge were performed.
