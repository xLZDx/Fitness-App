# S02 remediation G1: tie the journal uid to the auth uid at pass start

Date: 2026-10-16. Branch phase2/s02-unified-activity. Area: `ActivitySyncRepository`.

## What changed

- `mobile/lib/features/activity/repository/activity_sync_repository.dart`:
  - `_beginPass` now returns a dead pass (epoch -1, never equal to the account epoch) when the
    journal is account-scoped, an `authUid` supplier exists and the bound journal uid is null, the
    auth uid is null, or the two differ (exact, case-sensitive). Every later `_alive` / `_mayCall`
    check refuses such a pass, so `syncEntry`, `syncAll`, `syncBatch`, `saveSession` and the
    resolution operations make no backend or pusher call and return pending / empty.
  - `_mayCall` additionally requires, for a scoped journal, that the auth uid read right before
    each backend or pusher call still equals the journal uid of the pass.
  - New private getter `_tiesJournalToAuth`.
- `docs/phase2/s02/S02_DESIGN.md` section 17 item 23: clause (e).
- `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md`: new section G, tests for G1.

## Why

`FirebaseAuth.currentUser` flips to account B before the auth stream emits and before the journal
rebinds. A pass starting in that gap had journal uid A and auth uid B; both old checks stayed true,
so A's summaries and tombstones were written to B's cloud (ids are deterministic across accounts and
the Firestore backend resolves the current user per call).

## Affected contracts / paths

No public signature changed. Plain (non-scoped) journals and a null `authUid` supplier keep the
previous behaviour. A null auth uid at the start stays fail-closed.

## Verification state

Nothing compiled or run by the author. Tests are specified in
`docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md` section G1.
