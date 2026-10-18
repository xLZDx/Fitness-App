# AI Coach: align OQ-18 acceptance default with design guardrails

Date: 2026-10-18. Kind: documentation-only consistency correction.

## What changed

- Expanded the OQ-18 proposed default in `docs/ai-coach/acceptance.md` to state that existing mobile interfaces do not prove live-coach integration and the model cannot add exercises outside the deterministic composer's candidate output.
- Regenerated the derived document registry.

## Why

The supplementary product-ux-reviewer re-review at exact head `4d98765ad5f4c8114aa0f99fce82a9b42febb66a` found that the acceptance-table wording omitted two explicit constraints from the requirements and code map. This change makes the acceptance draft internally consistent with its sources.

## Affected contracts and decisions

- No product decision or application behavior changed. OQ-18 remains a technical design item; its source owner label is TR.
- The clarification does not claim the current app integrates those modules with live coach.

## Verification state

- Updated the acceptance wording against `01_REQUIREMENTS.md` OQ-18 and `01b_CODE_MAP.md` “Integration limit”.
- Regenerated `docs/DOCUMENT_REGISTRY.md` using `python scripts/dev/gen_document_registry.py`.
- Tests, builds, analyzers, runtime checks and device runs: NOT_RUN.
- No push performed; exact-head approval and per-commit push authorization remain required.
