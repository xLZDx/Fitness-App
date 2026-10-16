# S02 test epic 11a: "signing in as someone else never destroys my data"

## What changed

Added `mobile/test/features/activity/e2e/s02_account_switch_promise_e2e_test.dart`: A records a session with GPS and heart-rate streams, A signs out, B signs in and records, B signs out, A signs in. Asserts A's session and streams are byte-identical and not lost, B's session is invisible to A (and the reverse), no key was deleted. Run once over `bindUid` and once through the auth-driven binding listener, on the real `FileActivityJournal` and a temp directory.

## Why

The lessons-log incident (GPT-PM MAJOR-01, MAJOR-02: an account switch destroyed or adopted another account's local data) needs a user-level test, not only unit tests.

## Verification

`flutter test test/features/activity/e2e/s02_account_switch_promise_e2e_test.dart`: 2 passed. Final complete run in `docs/phase2/s02/S02_TEST_FINDINGS_EPIC11.md`.
