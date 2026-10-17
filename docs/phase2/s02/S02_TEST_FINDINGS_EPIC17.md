# S02 test findings: epic 17 ("never expire" retention is not offered)

Contract (operator decision 2026-10-16): `STREAM_RETENTION_NEVER_OFFERED = false`; a settings request with `streamRetentionDays: null` is refused (`invalid-argument` / `invalid_retention`); a stored `null` is treated as the default 730 days; allowed set stays 90, 365, 730.

## Changed tests (in progress; results below are filled after each run)
- `functions/src/__tests__/activity/settings_consent.test.ts`: the branching "consistent with the flag" test is now unconditional (flag false, validator false, parser throws `invalid_retention`, callable refuses with exact code and message, nothing written); new tests: a refused null leaves an existing setting and generation untouched; `effectiveStreamRetentionDays` of a stored null / absent / invalid is 730 while 90/365/730 pass through; the planner plans a stored null as 730.
- `upload.test.ts`: stored null now yields an expiry of start + 730 days (was `expiresAt` null).
- `upload_fence.test.ts`: stored null is the 730 day default: a 1990 activity is `already_expired` (nothing issued), a 729-day-old one uploads (was "never already due").
- `retention_purge.test.ts` (found by Grep, not in the brief): the "never is not purged" user (null, 900 days old) would now be purged; the test asserts it is purged, adds a 729-day-old control that is kept with its hint rewritten to start + 730 days, and `purged` is 4.
- `remediation_a_expiry.test.ts`: classifyRow with `retentionDays: null` kept (pure classifier, `isExpiryDue`/`derivedExpiryMs` still handle null defensively in production code); only the title now says so.

## Runs (all from `functions/` unless noted; verbatim counts)
| # | Command | Result |
|---|---|---|
| 1 | `npx jest src/__tests__/activity/settings_consent.test.ts src/__tests__/activity/upload.test.ts src/__tests__/activity/upload_fence.test.ts src/__tests__/activity/retention_purge.test.ts src/__tests__/activity/remediation_a_expiry.test.ts` (all touched files) | `Test Suites: 5 passed, 5 total` / `Tests: 143 passed, 143 total` |
| 2 | `npx jest src/__tests__/activity` | `Test Suites: 1 failed, 28 passed, 29 total` / `Tests: 2 failed, 877 passed, 879 total` (only `remediation_a_validate_bound.test.ts`: the 32 MiB filler returned `timeout` instead of `too_many` under parallel load, and the neighbouring comma-filler test) |
| 3 | `npx jest src/__tests__/activity/remediation_a_validate_bound.test.ts` (alone) | `Test Suites: 1 passed, 1 total` / `Tests: 6 passed, 6 total` |
| 4 | `npx jest src/__tests__/activity/lifecycle_policy.test.ts src/__tests__/s02_remediation_a_policy.test.ts src/__tests__/scaling.test.ts` | `Test Suites: 1 failed, 2 passed, 3 total` / `Tests: 1 failed, 214 passed, 215 total` |
| 5 | from `mobile/`: `flutter test --timeout 60s test/features/legal test/core/privacy/data_notice_test.dart test/l10n` | `+151 -1: Some tests failed.` |
| 6 | `C:\Python314\python.exe -m pytest scripts/review/test_state_ledger.py -q -p no:cacheprovider` (imports `legal_text`) | `137 passed, 1 warning` |

Dart files found by Grep that mention the legal surfaces: `mobile/test/features/legal/legal_pages_test.dart`, `health_disclosure_test.dart`, `mobile/test/core/privacy/data_notice_test.dart`; l10n folder run because the `.arb` files were regenerated. No Dart test mentions `legalPrivacyBody`, `legalTermsBody` or `legalLastUpdated` by those names.

## Failures and findings
1. DEFECT, stale test for the new contract (needs a test-side edit by whoever owns it; I did not edit it, per the brief). `functions/src/__tests__/s02_remediation_a_policy.test.ts` line 212, test "the GPS paragraph from epic 6b is intact (GPS upload, expiry choice, heart rate stays on the device)": `expect(en).toMatch(/90 days, 1 year, 2 years or never/)` fails. It checks the privacy page's GPS retention sentence. The regenerated `public/privacy.html` now says "Stored routes expire automatically after the expiry period you choose (90 days, 1 year or 2 years; the default is 2 years), counted from the date of the activity." which is the correct text for the new contract (no "never"). Required change: the regex should pin the new wording and add a negative assertion that the page does not offer "never". Acceptance: the test passes against the current page and fails if "or never" returns.
2. `mobile/test/features/legal/legal_pages_test.dart` line 195, test "deletion disclosure tracks the deletion code no shared collection is pseudonymised without being disclosed": `Expected: contains all of Set:['coach_bookings', 'equipment_reports']` / `Actual: Set:['equipment_reports', 'debug_sessions']` / `Which: has no match for 'coach_bookings' at index 0`. This test scans a fixed 1200-character window of `../functions/src/index.ts` after `async function sweepSharedRecords`. It does not read the regenerated text; it is a source scan that fails because the window no longer contains the `coach_bookings` query. Not caused by this epic; not investigated further and not edited. A likely cause is that `sweepSharedRecords` moved or grew; the scan window needs to follow it.
3. Load-sensitive timeout, known flake (same as epic 16): `remediation_a_validate_bound.test.ts` passes alone (run 3), fails inside the parallel activity run (run 2). The earlier 60000 ms test timeout did not help because the product returns `timeout` from its own internal time budget under load. Not related to retention.
4. Found beyond the brief: `retention_purge.test.ts` depended on a stored null meaning "never" (the purge reads `effectiveStreamRetentionDays`); it would have failed and is fixed. Each of the four fixed files passes (run 1).
5. Production code: no change needed or made. Concern (not a defect): the type `StreamRetentionDays = number | null`, the `null` branch in `derivedExpiryMs` (`upload_common.ts` line 157), `isExpiryDue`, and the `null` comment in `set_settings.ts`/`parseSettingsRequest` doc (`streamRetentionDays?: 90 | 365 | 730 | null`) are now unreachable dead paths from real callers; `settings.ts` line 135 doc comment still lists `| null` as a valid request value. Harmless, but the doc comment is now wrong.

## Not covered
- Mutation or red-before-fix runs (not permitted). The settings_consent assertions are justified by what they observe: exact code and message, nothing written, effective value 730.
- Not run: whole-repo jest, lint, typecheck, build, CI, rules emulator, `build_legal.py --check`, Dart tests outside the three listed paths and `test/l10n`. Client UI offering "never" (mobile retention picker) was not examined.
- Whether `index.ts` or the legal test changed in this branch (no git history consulted) for finding 2.

## Follow-up: the two test defects fixed (test-only edits)
- `functions/src/__tests__/s02_remediation_a_policy.test.ts` (GPS paragraph test): now expects `90 days, 1 year or 2 years; the default is 2 years`, extracts the retention sentence (up to its first period after the parenthesis) and asserts it has no "never", and asserts the page has no `2 years or never`. My first regex ran into the next sentence ("heart rate values are never uploaded") and failed once; it was narrowed to the retention sentence only.
- `mobile/test/features/legal/legal_pages_test.dart` (deletion disclosure): the scanned text is now the body of `sweepSharedRecords` plus the body of `sweepBookings`, each cut at its own closing brace (`\n}`), not a fixed length; `containsAll` and the difference assertion are unchanged; the failure reasons name the function (`<name> was renamed or removed`, `closing brace of <name> not found`).

| Command | Result |
|---|---|
| `npx jest src/__tests__/s02_remediation_a_policy.test.ts` (from `functions/`) | first run with the loose regex: `Tests: 1 failed, 42 passed, 43 total`; final: `Test Suites: 1 passed, 1 total` / `Tests: 43 passed, 43 total` |
| `flutter test --timeout 60s test/features/legal test/core/privacy/data_notice_test.dart test/l10n` (from `mobile/`) | `+152: All tests passed!` |

Not rerun after these edits: the full activity folder and `lifecycle_policy.test.ts`/`scaling.test.ts` (neither file was touched). `remediation_a_validate_bound` stays recorded as the known load-sensitive flake (passes alone).

## Follow-up: generated-legal-surface sync guard
New file `scripts/legal/test_build_legal_in_sync.py` (read-only; imports `build_legal`, uses `render_html(doc)` and `arb_updates(lang)`, compares in memory; no files written, no shell-out). It checks `public/privacy.html`, `public/terms.html` and the keys `legalPrivacyBody`, `legalTermsBody`, `legalLastUpdated` in `app_en.arb` and `app_ru.arb`; the failure names the stale file, the first differing character and says to edit `scripts/legal/legal_text.py`, run `build_legal.py` and never edit the generated files. Positive controls: an altered, an extended and a truncated string are reported as different, and the message format is checked.

Command (from the repo root): `C:\Python314\python.exe -m pytest scripts/legal/test_build_legal_in_sync.py -q -p no:cacheprovider`
Result: `6 passed, 1 warning in 0.86s` (the warning is a pytest_asyncio deprecation notice).
Not done: the check was not seen failing against a really stale file (no mutation runs); its ability to fail rests on the in-memory control.
