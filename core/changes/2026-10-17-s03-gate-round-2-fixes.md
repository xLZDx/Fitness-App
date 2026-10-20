# S03 documentation gate round 2 and the independent retry review

Date: 2026-10-17. Kind: documentation only.

## What changed
- docs/phase2/s03/S03_DESIGN.md: section 2.1 item 3 defines failedToOpen as a defensive state without retry, adds the retryNow() contract (started, busy, notApplicable; busy as a separate boolean), per-generation single flight with stale completions touching nothing, the RecoveryReportSource seam, the rule 2 exception and the gave-up index rule, sign-out and account-deletion status; risk R14 (long LOADING window accepted for S03); the GPT-PM disposition section covers rounds 1 and 2 and the independent review.
- docs/phase2/s03/S03_TEST_PLAN.md: DT-0-3, DT-0-4, DT-0-5, DT-0-9, DT-0-13, DT-0-14 and DT-13-15 rewritten or extended, new DT-0-15 and DT-0-16; counts now 458 without and 470 with the two conditional stories.
- core/DECISION_LOG.md, core/LESSONS_LOG.md, docs/DOCUMENT_REGISTRY.md: entries for this commit.

## Why
GPT-PM round 2 found that DT-0-5 required impossible open and bind counts; the independent review showed that a separate open attempt does not exist in the code and listed four more gaps in the retry contract, all found before any code exists.

## Affected contracts and paths
None in code. The build (lane L1, story S03-0) adds RecoveryReportSource to uid_scoped_activity_journal.dart, logs the exception type in the bindUid catch, and turns the closure of activityJournalBindingProvider into a controller; activity_journal_binding_retry_test.dart must stay valid unchanged.

## Verification state
Documentation only; nothing was run. Round 3 of the documentation gate follows.
