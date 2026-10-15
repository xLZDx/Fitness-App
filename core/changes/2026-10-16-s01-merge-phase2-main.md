# S01: merge `origin/phase2/main` into the S01 branch

Date: 2026-10-16. Branch: `phase2/s01-contracts`. Merged: `origin/phase2/main` at `89927444` (S00 PR #7 and S00b PR #8).

## What changed
- The S01 branch was cut from the S00 branch before PR #5, S00 and S00b landed on `phase2/main`; this merge brings it up to date so the S01 pull request is a clean documentation-only diff.
- One conflict, `core/DECISION_LOG.md` (append-only on both sides): both sets of entries kept.
- `core/DECISION_LOG.md`: one entry.

## Why
Prerequisite for the S01 review gate and pull request.

## Affected contracts and paths
Documentation merge only; the S01 documents are unchanged by it. Note for readers: the UI-0 audit was run on the `mobile/` tree before PR #5 (Body Scan and Nutrition Coach); the screens and routes PR #5 added are not covered by it.

## Verification state
No tests or checks run.
