# S02 remediation I, item I1: state reads tied to the auth uid

Date: 2026-10-16. Area: mobile production code (`ActivitySyncRepository`). Nothing was compiled or run by the author
(operator rule: a test agent runs everything afterwards).

## Why

Remediation G1 tied a sync pass to the signed-in uid (`_beginPass` requires `journalUid == authUid` for a scoped
journal with an auth supplier). The state read path (`refreshState`, `_viewStamp`, `_viewCurrent`, added in H7) checked
only that the epoch, the bound uid and the auth uid did not move during the read, never that the two uids agree. In
the gap where FirebaseAuth already points to B and the scoped journal is still bound to A, `refreshState` could emit
A's conflicts and candidates as a loaded state under B. Taps were blocked by `expectedUid`, but the display was not.

## What changed

- `mobile/lib/features/activity/repository/activity_sync_repository.dart`:
  - New private `bool _viewTied(_Pass stamp)`: true for a plain journal or a null supplier (old behaviour); otherwise
    requires `stamp.journalUid != null && stamp.journalUid == stamp.authUid`.
  - `_viewCurrent` also requires `_viewTied(stamp)`.
  - `refreshState`: right after the first `_viewStamp()` of each attempt, a stamp that is not tied is logged through
    the existing `_logSkip('refreshState', stamp)` (reason word only, never a uid) and the attempt is retried through
    the existing loop (3 attempts, then `JournalUnbound`). `journal.list()` is not called for a mismatching stamp.

## Affected contracts

No public signature changed. Behaviour: `refreshState()` / `watch()` of a scoped journal with an auth supplier throw /
emit `JournalUnbound` while the journal uid and the signed-in uid differ. Plain journals and a null supplier are
unchanged.

## Verification state

Not compiled, not run. Tests are specified in `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md`, heading I (written in
the remediation I documentation commit).
