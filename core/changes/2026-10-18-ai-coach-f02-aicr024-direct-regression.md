# Change record: AICR-024 direct F-02 regression

## Change

Corrected `docs/ai-coach/01_REQUIREMENTS.md` AICR-024 to enumerate exactly the nine persisted Workout Runtime states and state that `NEXT_EXERCISE` is a derived view, not a persisted state. The transition-table acceptance wording now covers those nine persisted states. Updated `docs/ai-coach/acceptance.md` D-7 to record this direct F-02 sibling-regression correction and its local reviewer recheck.

## Why

The accepted F-02 remediation already defined nine persisted states and treated `NEXT_EXERCISE` as derived in design §4.1 and backlog ACS-001 AC-1. AICR-024 still listed `NEXT_EXERCISE` among ten runtime states, contradicting those corrected contracts and leaving a direct stale requirement in scope. AICR-083 already stated the derived-view rule and remains consistent.

## Affected contracts and paths

- `docs/ai-coach/01_REQUIREMENTS.md` — AICR-024 persisted-state contract.
- `docs/ai-coach/acceptance.md` — D-7 remediation evidence.
- `docs/DOCUMENT_REGISTRY.md` — generated registry byte count for the changed acceptance record.

## Decision and ownership

This is a documentation consistency correction within the existing F-02 remediation scope. It does not accept proposed stories, decide open questions, authorize implementation, or change product behavior. The operator confirmed that the proposed story dispositions remain pending until named-role review and open-question routing. Operator is accountable for the delegated task; Codex executed the documentation change. No technical/service owner is inferred.

## Review and verification state

- The actual local `code-reviewer` (GPT-6 Luna, medium) rechecked AICR-024 against `docs/ai-coach/03_DESIGN.md` §4.1, `docs/ai-coach/02_BACKLOG.md` ACS-001 AC-1, and AICR-083. It confirmed the nine persisted states, the derived `NEXT_EXERCISE` rule, and no remaining direct stale sibling in the searched requirements, backlog, or design.
- Product tests, checks, builds, CI, and migrations were not run. No product-runtime claim is made.
- The document registry is generated from the working tree by `python scripts/dev/gen_document_registry.py`; regeneration and the resulting registry entry are recorded with this commit.
- The full GPT-PM package review on the later exact head remains without a verdict because its attachment composer failed before send (`ATTACHMENT_NOT_LANDED`, `sendPhase=not-started`). The separate inline response was explicitly evidence-limited and is not represented as full-package approval.
