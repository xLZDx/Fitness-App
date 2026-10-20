# S03 lane L9 run 1: Sources page

Date: 2026-10-17. Kind: production code (UI), story S03-15.

## What changed
- mobile/lib/features/modes/pages/sources_page.dart (new): the Sources page (app row states from the journal availability, fixed information rows, rows for sources found in the journal, dedup note, two-column layout from 880 dp).

## Why
Story S03-15 (design 2.5, contract S-8): show where activity data can come from without calling any adapter.

## Affected contracts and paths
No existing file changed. The route still points to the stub page until the page swap in run 2. The recovery-loss line and the 'May provide' lines wait for ARB keys (lane L13 follow-up).

## Verification state
Nothing was run; NOT_RUN until the test agents (epic 4).
