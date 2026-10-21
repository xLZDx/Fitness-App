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
Documentation only. No source, test, build or rules file changes. Open items not closed here: the offline-first command protocol design itself (B-01, B-02), the queue lifecycle in the data model and privacy documents (B-03), the route and action coverage matrix for the module dispositions (M-05), the legacy-versus-local migration proof, and the current source and runtime manifest (M-07).

## Verification state
Documentation; nothing was executed. Row mappings were checked for ID uniqueness (27 unique ids, no collision with FU-AC-001 to FU-AC-091). Findings other than the six rows re-read in the package files are the reviewer's claims.

## Gate round 1 remediation (GPT-PM: 0 BLOCKER, 4 MAJOR, 2 MINOR)
- FU-AC-095 now requires a client-generated operation ID, UID and session binding, logical set id and rejection of a mismatched identity.
- FU-AC-101 is scoped to the three queued commands; StartSet is explicitly not queued.
- FU-AC-114 restores the unrelated-sentence-with-affirmative-word class.
- FU-AC-112 requires each journey to be run once per permission state.
- SUPERSESSION.csv: ADR-CMD-03 is superseded, FU-RQ-015/FU-015 and FU-AC-015/064 are rewritten in place (ids stay active), and the legacy-versus-local migration proof is marked owed instead of linked to FU-AC-095.
- The reconciliation table heading and status wording no longer imply gate closure (COVERED / PARTIAL / OPEN).
