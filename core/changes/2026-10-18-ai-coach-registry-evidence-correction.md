# Correct document registry evidence in PM Bridge recovery record

Date: 2026-10-18

## Change and reason

Corrected `core/changes/2026-10-18-ai-coach-pm-bridge-recovery-eligibility.md`: registry generation reported 371 documents, but `docs/DOCUMENT_REGISTRY.md` remained unchanged and does not list the new change record. The earlier phrase “expected to include this record” was unsupported.

## Affected paths

- `core/changes/2026-10-18-ai-coach-pm-bridge-recovery-eligibility.md`
- `core/changes/2026-10-18-ai-coach-registry-evidence-correction.md`

## Verification state

Read-only inspection confirmed the record is absent from the generated registry. No tests, checks, builds, CI, migrations, runtime actions, push, or merge were performed.
