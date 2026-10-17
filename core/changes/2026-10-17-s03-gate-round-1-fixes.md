# S03 documentation gate round 1: one retry state machine

Date: 2026-10-17. Kind: documentation only.

## What changed
- docs/phase2/s03/S03_DESIGN.md: section 2.1 item 3 defines one state machine for automatic and manual journal bind attempts; failure rows F-16, F-37, F-38, the S03-0 story row, lane L1 file table and risk R13 aligned; GPT-PM round 1 disposition added; DD-1 numbers updated.
- docs/phase2/s03/S03_TEST_PLAN.md: DT-0-5 rewritten (single flight), new tests DT-0-11 to DT-0-14 (manual failure keeps the automatic deadline, manual success cancels the timer, gave-up behaviour, due timer during a manual attempt); counts now 456 without and 468 with the two conditional stories.
- core/DECISION_LOG.md, core/LESSONS_LOG.md, docs/DOCUMENT_REGISTRY.md: entries for this commit.

## Why
GPT-PM documentation gate round 1 on 3bedcba4 returned MODIFY with one MAJOR: the plan demanded that no automatic retry follows a failed manual retry, while the design retains the automatic back-off schedule. A test and a production behaviour that cannot both hold would make an implementation agent bend production code to satisfy the test.

## Affected contracts and paths
None in code. The build now has to turn the closure in activityJournalBindingProvider (mobile/lib/core/wiring/activity_wiring.dart, lane L1) into a controller class without changing the automatic retries; mobile/test/features/activity/repository/activity_journal_binding_retry_test.dart is the regression guard.

## Verification state
Documentation only; nothing was run. The fix has not been re-reviewed by GPT-PM yet (round 2 follows).
