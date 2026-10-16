# Rename a fake uid sentinel flagged by the secret scanner

Date: 2026-10-16. Kind: test and scanner configuration only.

## What changed
- mobile/test/features/activity/repository/activity_journal_binding_retry_test.dart: in the test "no raw uid in any log line, even when the error message holds it" the constant is renamed from a name with the word "secret" to `sentinel` and its marker value gets a neutral prefix (4 lines; behaviour and assertions are identical).
- .gitleaksignore: one new fingerprint for the already-merged commit 2791285a, with a comment explaining the manual review.
- core/DECISION_LOG.md, core/LESSONS_LOG.md, docs/DOCUMENT_REGISTRY.md: entries for this commit.

## Why
The full-history secret scan went red on the merged S02 pull request with one finding. The only matching text is this fake user-id marker. The operator chose to fix the false positive (rename and add an ignore entry).

## Affected contracts and paths
None in product code. The test keeps the same guarantee: a raw user id never appears in a log line.

## Verification state
Not run. The coordinator does not run tests or scanners. The test agent that owns the activity tests runs this file with the next focused set. The ignore fingerprint is inferred (rule id generic-api-key, line 264 at the introducing commit) and is confirmed only by the next CI secrets job.
