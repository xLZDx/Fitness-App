# AI Coach: record ordered Phase 9 closure dependencies

Date: 2026-10-18. Documentation-only routing record.

## Why

The acceptance record contains the individual OQ routes and owner-source evidence, but the remaining external dependencies were spread across multiple review records. A single ordered queue makes the required deliverables and unresolved ownership visible without treating the operator's explicit PENDING story disposition as a blocker or inventing a person from `TR`/`OP` labels.

## Changes

- Added an ordered six-item external-dependency queue to `docs/ai-coach/acceptance.md` for OQ-07 technical review, OQ-07 product/safety sign-off, OQ-14 technical review, OQ-18 technical follow-up, ACS-100 alert/on-call ownership, and unavailable `product-owner`/`technical-writer` profiles.
- Recorded the project-assignment or host-profile action needed for each, and distinguished each technical owner from the operator's accountability for the delegated task.
- Explicitly stated that the 13 PENDING story dispositions follow the operator's instruction and are not counted as blockers.
- No OQ decision, product policy, owner assignment, story acceptance, implementation behavior, or test plan was changed.

## Evidence and verification

The queue is based on the current acceptance/OQ records, the scoped owner-source audit, the OQ-07 and OQ-14 architect reviews, the OQ-18 follow-up, and the host's recorded `unknown agent_type` errors for the named `product-owner` and `technical-writer` profiles. The owner-source result is bounded to the inspected records and does not claim global absence. `python scripts/dev/gen_document_registry.py` regenerated the registry. No tests, checks, builds, CI, migrations, or runtime actions were run for this change.
