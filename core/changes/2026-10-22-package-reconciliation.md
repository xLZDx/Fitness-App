# Change record: package reconciliation with the four amendments (2026-10-22)

## What changed
New folder `docs/v1/package-amendments/`:
- `PACKAGE_RECONCILIATION_2026-10-22.md`: result of the independent package review (verdict MODIFY, 3 BLOCKER, 7 MAJOR), facts re-checked against the package files, closure map per finding, list of package documents the package author must still amend.
- `ACCEPTANCE_AMENDMENTS.csv`: 27 new acceptance rows FU-AC-092 to FU-AC-118 (14 queue, 7 attendance, 6 voice ready-prompt), all NOT_RUN.
- `SUPERSESSION.csv`: package rows superseded, rewritten, extended, split or preserved by each amendment.
Also corrects the criterion count in `core/changes/2026-10-22-voice-ready-prompt-decision.md` (six, not five), an editorial item from the voice gate.

## Why
The independent review found that the package registers still carry Option A (online-only), background-first attendance and the bare-go voice start, so they contradict the approved amendments. The package is an external deliverable, so this folder is the in-repository authority until it is reissued.

## Affected contracts and paths
Documentation only. No source, test, build or rules file changes. Open items not closed here: the offline-first command protocol design itself, the route and action coverage matrix for the module dispositions, and the current source and runtime manifest.

## Verification state
Documentation; nothing was executed. Row mappings were checked for ID uniqueness (27 unique ids, no collision with FU-AC-001 to FU-AC-091). Findings other than the six rows re-read in the package files are the reviewer's claims.
