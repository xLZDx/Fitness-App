# S02 test epic 6b: story-map completeness lint F96 with mutated-copy proofs (S02-11)

## What
New `story_map_lint.test.ts`: a parser that reads design section 11 (only; section 17 is excluded) and plan sections 1, 3 and 7 as text and reports placeholder tokens, unknown ids, orphan and duplicate definitions, stories without ids, unknown or mismatching prerequisites, cycles, order mismatch against plan section 3 and the DAG, design/plan cell drift and GPS-PRIV criteria unassigned. It passes on the real documents and fails with its own reason on in-memory mutated copies (TP-sync, unknown id, removed prerequisite, cycle, swapped order, emptied story, unassigned GPS-PRIV 015, orphan and duplicate definition). The real documents are not edited.

## Why
Plan F96 requires a lint that can fail. The check of MAJOR/BLOCKER names in design sections 6.1, 6.2 and 10 is narrowed to the GPS-PRIV ids the plan section 7 assigns to each story, because MAJOR/BLOCKER tokens have no machine-readable story mapping.

## Affected paths
- `functions/src/__tests__/activity/story_map_lint.test.ts`

## Verification state
Command (cwd functions): `npx jest src/__tests__/activity/story_map_lint.test.ts`: 1 suite, 14 tests passed. No production code changed.
