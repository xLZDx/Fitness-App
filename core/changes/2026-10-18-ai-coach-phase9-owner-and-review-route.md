# AI Coach Phase 9: assign task owners and adopt the bounded reviewer route

Date: 2026-10-18. Documentation-only ownership and workflow record.

## Why

The operator explicitly asked Codex to execute the OQ ownership and reviewer-profile work, then clarified that GPT-PM is the designated owner and signatory. The old acceptance queue only said to restore the unavailable `product-owner` / `technical-writer` agent profiles or establish an alternative route; it did not define that route's scope or authority. The OQ technical work also needed a concrete executor without misrepresenting a reviewer role as a production service owner.

## Changes

- Updated `docs/ai-coach/acceptance.md` with explicit decision/execution roles: GPT-PM is the product decision owner; Codex authors/executes OQ-07/OQ-14/OQ-18 technical documentation under the delegated task; the actual `architect` agent is the independent technical reviewer. This does not name an implementation/runtime service owner.
- Recorded GPT-PM as the operator-designated product owner/signatory and product-accountable owner for ensuring ACS-100 gets an operational assignment. The record distinguishes product accountability from an actual alert receiver.
- Approved a bounded alternative review route in place of restoring unavailable named agent profiles: `architect` for OQ contracts, `doc-updater` for factual accuracy/traceability, and `product-ux-reviewer` for journeys and acceptance clarity. The route cannot accept the 13 PENDING stories, assign a runtime service, or provide clinical authority.
- Added `docs/ai-coach/20_PHASE9_EXECUTION_OWNERSHIP_AND_REVIEW_ROUTE.md` with exact source identity, actual reviewer evidence, role boundaries, the GPT-PM request failure, and remaining clinical/on-call gates.
- Updated the README and SDLC state to distinguish the operator's role assignment from GPT-PM's not-yet-received sign-off.
- Logged PM Bridge decision `AICOACH-OQ07-SIGNATURE` as PENDING with the fail-closed recommendation.
- Clarified the technical state: the architect recommendation packages are recorded, but the adopted TR contract decisions for OQ-07, OQ-14 and OQ-18 are `NOT_RECORDED`.
- Recorded the operator's direct assignment of GPT-PM as product decision owner/signatory; Codex is the technical executor and architect is the independent reviewer. The distinction preserves the owner/executor boundary.

## Evidence and ownership

Source baseline reviewed by three actual agents was HEAD `42c2f0218422cda9c805d1bbf9702a61a54018ee`, tree `ec3769fdaf0e4cee56aba5b7b99ee4a65f386b7a`:

- `architect`, GPT-6 Luna / medium: recommended prescription-only ceilings, typed fail-closed OQ-07 outcomes, source-bound structured claims for OQ-14, and versioned/idempotent composer contracts for OQ-18.
- `product-ux-reviewer`, GPT-6 Luna / medium: found the prior route underspecified; confirmed reviewer roles cannot accept stories or sign clinical policy.
- `doc-updater`, GPT-6 Luna / medium: found no source inconsistency but required defined route authority, evidence format and closure criteria.

The operator is the accountable owner of the delegated work; Codex is the executor. GPT-PM's product-owner/signatory assignment comes directly from the operator. The PM Bridge request `8a1a6c41-4f21-4d0c-a44e-202610184201` failed before send with `ATTACHMENT_NOT_LANDED`; its durable status had `sendPhase=not-started`, no `userTurnId`, and no `replyId`. A retry with changed inline content and a second `gpt_send` were refused because the failed send-and-await lineage already owns that request ID. No message reached GPT-PM, no reply exists, and no GPT-PM signature is claimed.

The global delegation matrix reserves medical/clinical authority for a human. No human clinical/safety signer or approved numeric limits were identified. The repo also contains no deployed AI Coach alert service or named on-call rotation in the inspected sources. GPT-PM is not recorded as a live alert receiver. All 13 story dispositions remain PENDING per the operator's previous direction.

## Verification

Manual review of the changed text and its links only. No tests, checks, builds, CI, migrations, runtime actions, alert setup, push or merge were run or performed.

## Remaining acceptance

1. Recover a GPT-PM product decision/signature for the fail-closed OQ-07 product gate through an authorized new PM Bridge request after the failed request is closed. The failed request covered OQ-07/ACS-100 only; it did not route OQ-14/18. Until a reply arrives, the OQ-07 PM signature is `NOT_RUN`.
2. Route and record GPT-PM's product decisions for OQ-14 and OQ-18; those decisions have not yet been sent or recorded.
3. Obtain an authorized qualified human signature for actual OQ-07 numeric limits and symptom scope; keep those values/list unsigned and unavailable until then.
4. Identify the actual runtime service and its on-call rotation for ACS-100, configure alert delivery and prove delivery using a test alert.
5. Re-review the changed documents at their resulting exact HEAD/tree with the adopted alternative route.
6. Record the operator/product owner's final story dispositions on the then-current acceptance-file revision; they remain PENDING.
