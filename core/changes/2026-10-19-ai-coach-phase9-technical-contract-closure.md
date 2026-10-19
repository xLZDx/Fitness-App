# Phase 9 technical contract closure boundary

Date: 2026-10-19  
Scope: documentation and contract records for OQ-07, OQ-14, OQ-18, plus the cross-cutting Phase 9 status.  
Executor and task-local technical owner: Codex, by the operator's direct delegation.  
Accountable task owner: operator. GPT-PM remains the product decision owner and product escalation. Codex is the task-local technical on-call/triage executor while this work is active. This does not imply continuous or 24/7 monitoring.  
Disposition: the limit-free fail-closed technical boundary is manually self-reviewed and documented; product inputs, clinical approval and implementation conformance remain open.

## Why

The Phase 9 status documents described OQ-07/OQ-14/OQ-18 as having no technical review/contract while their bounded product direction had already been accepted. Codex's current assigned role is to perform that technical contract work and self-review. This record distinguishes the completed limit-free interface decisions from inputs or approvals that cannot be invented, and from code/runtime evidence that has not been produced.

## Decisions recorded

- **OQ-07:** define one authoritative `PrescriptionPolicyResolver` and immutable verified-policy envelope. Only a verifiable, active, correctly scoped policy with resolved approval and signer-qualification references can authorize an actionable prescription. Every other resolver outcome fails closed. No clinical values, symptom list, credential standard, or clinical conclusion is supplied here. A structurally valid performed-set fact is preserved independently of assignment policy and is never clamped to an unsigned ceiling.
- **OQ-14:** initial factual source/claim allowlist is empty. The currently unverified path emits no factual claim envelope. Future claims require exact product-approved, versioned mappings and source evidence with stable identity/version, authoritative capture time, and required consistency/freshness inputs. Rendering is deterministic and template-based; free-form model factual prose, locale-only authorization, inferred rounding/conversion, and unsupported fallback are excluded.
- **OQ-18:** the pure composer accepts only complete immutable versioned inputs and explicit ordered slots. With recovery classes, horizon, freshness, or calendar/day-slot policy absent, it returns unavailable and refuses the complete draft. Drafts remain inactive until explicit user acceptance. The selected persistence target reuses existing `ProgrammeRepository` and `ScheduledSessionRepository` user-scoped records through a future single transactional create-if-absent coordinator. Current `.set` writers do not conform; no parallel store is proposed.
- **Review status:** Codex manually self-reviewed the bounded technical decisions for internal consistency against the cited proposal and current code-map evidence. This is not an independent review, implementation conformance, test result, GPT-PM approval of this new wording, or clinical sign-off.

## Evidence and limits

- Contract detail: `docs/ai-coach/22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md` and `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md`.
- Acceptance and remaining work: `docs/ai-coach/acceptance.md`.
- OQ-18 storage evidence: existing repository implementations write the programme and scheduled-session paths using document `.set`; this establishes a current conformance gap, not transaction behavior.
- Current PM Bridge request `8fd23d10-6840-4db1-9ee3-52ef849bf7dc`, job `d0949314-8a06-4148-96b9-7f9a21d21e6b`, failed before send because attachments did not land. `sendPhase=not-started`; no user turn/reply or GPT-PM decision exists. No replacement request ID or duplicate was created. The separate, previously correlated GPT-PM decisions remain limited to their recorded payloads and dates.
- ACS-100 natural-metric recheck is documented in `core/changes/2026-10-19-ai-coach-acs100-metric-recheck.md`; it returned no matching time series in the queried window. This does not prove zero requests, healthy service state, or alert delivery.

## Remaining acceptance

1. OQ-07 product policy source, actual values and symptom scope require a qualified clinical signer's signed decision before application. No such signer or signature is evidenced.
2. OQ-14 exact source mappings, freshness/clock/skew values, and approved deterministic templates remain product inputs; until present, the claim allowlist remains empty.
3. OQ-18 required source, freshness, recovery and calendar values remain product inputs; transaction implementation and schema/rules/export conformance have not been performed or proven.
4. ACS-100 remains blocked on fresh natural metrics and the existing product gate. No policy binding, controlled delivery, acknowledgement, or production on-call rotation was changed or claimed.
5. All 13 Phase 9 story dispositions remain PENDING by operator direction. No implementation GO or test/review phase was started.

## Actions not performed

No source-code/runtime change, test, check, build, CI, migration, production alert mutation, synthetic AI request, push, or merge was performed for this record. No story disposition was changed.
