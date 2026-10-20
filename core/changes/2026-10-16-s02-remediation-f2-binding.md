# S02 remediation F2 (3/4): journal binding retry, deleting-account skip, authUid

## What changed

`mobile/lib/core/wiring/activity_wiring.dart`:

- `activityJournalBindingProvider`: a `bindUid(uid)` that returns false or throws for a non-null uid is retried with bounded backoff (`kActivityBindRetryDelays` = 5 s, 15 s, 60 s, 5 min, 5 min; at most 5 retries). At most one retry is pending; a new auth value, a successful bind or provider disposal cancels it, and a retry runs only while the same account is still the one to bind. Only `runtimeType` is logged, never the uid.
- The uid equal to `accountBeingDeletedUidProvider` is not bound (the journal is unbound instead), also on retry. The import `features/account_deletion/state/account_deletion_providers.dart` follows the pattern already used by other wiring and feature code (`show accountBeingDeletedUidProvider`).
- New seam: `ActivityBindRetryTimerFactory` and `activityBindRetryTimerFactoryProvider` so tests inject a fake timer.
- `activityRootOverrides` passes `authUid: () => FirebaseAuth.instance.currentUser?.uid` to `ActivitySyncRepository` (the parameter is added by remediation F1; null in tests means no check).

## Why

The discarded `bindUid` result was a silent permanent failure (a transient secure-storage error left the journal unbound for the session and readers saw empty lists), and a same-uid re-emission during account deletion could re-create the scope.

## Verification state

Not compiled and not run. Depends on the F1 `authUid` constructor parameter. Tests are listed in `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md`.
