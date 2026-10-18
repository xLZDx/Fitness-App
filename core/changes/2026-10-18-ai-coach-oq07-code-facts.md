# AI Coach: record existing OQ-07 code facts

Date: 2026-10-18. Documentation-only update after reading the existing safety and progression sources identified by OQ-07.

## What changed and why

OQ-07 previously said the existing eligibility and progression files had not been read. Read the current local sources and documented their actual scope without treating existing product heuristics as approved AI Coach safety limits:

- `mobile/lib/features/safety/data/eligibility.dart` gates screening, clinician advice, post-surgical restrictions and per-exercise eligibility. It composes intensity heuristics, including 0.8, 0.9 and 0.95 ceilings.
- `mobile/lib/features/safety/data/age_policy.dart` uses 0.8/0.85 intensity ceilings and 4/3 maximum weekly days for minor/senior bands.
- `mobile/lib/features/workouts/data/progression.dart` suggests a next-session weight: default target of 8 reps; -5% after `tooHard`; +5% after three `tooEasy` sessions meeting target; 2.5 kg compound or 1.25 kg isolation increment after two `justRight` sessions meeting target; otherwise repeat. This is progression logic, not a hard safety cap.

The inspected files do not establish a signed AI Coach maximum-load/repetition rule or the new mid-session symptom list. Numeric values remain product heuristics and require OP/TR review; the symptom list requires a named signer. No numeric limit or clinical conclusion was invented or approved.

## Paths and contracts

- `docs/ai-coach/01_REQUIREMENTS.md`: OQ-07 evidence and remaining decision.
- `docs/ai-coach/02_BACKLOG.md`: OQ-07 summary.
- `docs/ai-coach/acceptance.md`: OQ-07 evidence and ownership.
- `docs/ai-coach/00_README.md`: operator-decision summary.
- `docs/ai-coach/01b_CODE_MAP.md`: verified source map fact.
- `docs/DOCUMENT_REGISTRY.md`: regenerated after document edits.

No application code, runtime behavior or authorization boundary changed.

## Verification state

- Read-only source inspection: performed for the three named Dart files.
- Registry generation: `python scripts/dev/gen_document_registry.py` completed and wrote `docs/DOCUMENT_REGISTRY.md` with 362 documents.
- Product tests, checks, builds, migrations and runtime/device runs: NOT_RUN; documentation-only change.
- Push and merge: not performed.

## Remaining acceptance

OQ-07 remains open. OP/TR decisions, a named symptom-list signer and any future validation are outstanding. This update does not claim clinical validity or authorize shipping.
