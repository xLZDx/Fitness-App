# AI Coach docs: GPT-PM verification round remediation

Date: 2026-10-17. Base head reviewed by GPT-PM: `2a31a3f0`. Documentation only; no code, no production, no migration.

## What changed and why

GPT-PM verification returned MODIFY: four MAJOR contradictions between new contracts and old test rows (R2-01..R2-04) and five MINOR leftovers (MR-01..MR-05).

- R2-01: FT-1025 now expects the typed VOLATILE result (one volatile entry, zero durable records, retry writes once, process death loses only the volatile entry); `PERSIST_FAILED` stays for non-fact commands.
- R2-02: FT-1037 now matches MX-13 / AICR-117: `rest_elapsed` is applied in memory first when the append fails, the cue is emitted once and deduplicated by cue id; normal success gives one durable record and one cue.
- R2-03: `ui_confirmed` is a local UI confirmation capability (unforgeable in-process object passed to dispatch separately), not an envelope `source` value. Design 3 (two places) and 4.2, requirements, backlog, UI spec and E2E plan use one wording; FT-1002 rejects a `ui_confirmed` source or smuggled field.
- R2-04: FT-1175 and FT-1176 are asserted against the deletion-fence state machine (DETECTED, EXPORT_OFFERED, WIPE_PENDING, WIPED) with FT-1201 as the oracle.
- MR-01/MR-02/MR-03: the cooperative-only sentences in design (ownerEpoch bullet) and ADR-011 are marked superseded; the X-19 cooperative branches are a rejected mode, a PASS only with the recorded operator exception OQ-31.
- MR-04: AICR-089 "failed turn is not charged" is marked superseded by AICR-125 for provider-invoked turns.
- MR-05: the E2E-01 header finding that MX-09 lacks ACTIVE_EXERCISE is marked resolved.

## Affected paths

`docs/ai-coach/03_DESIGN.md`, `03a_ADR_PROPOSALS.md`, `01_REQUIREMENTS.md`, `02_BACKLOG.md`, `03b_UI_SPEC.md`, `04a_FUNCTIONAL_TEST_PLAN.md`, `04b_E2E_AND_DEVICE_PLAN.md`, `00_README.md`, `docs/sdlc/STATE.md`, `docs/DOCUMENT_REGISTRY.md`, `core/DECISION_LOG.md`, `core/LESSONS_LOG.md`.

## Verification state

No tests exist or were run (documentation). Wording was applied by targeted replacement and grepped for the old phrases. A focused GPT-PM verification of R2-01..R2-04 and MR-01..MR-05 follows; push is withheld until APPROVE on the exact head.
