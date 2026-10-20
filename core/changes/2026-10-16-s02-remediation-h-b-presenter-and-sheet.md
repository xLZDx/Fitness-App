# S02 remediation H-B, item H6: conflict presenter reset per account, sheet draws cards only for a loaded state

Date: 2026-10-16. Area: mobile production code (activity conflict UI). Nothing was compiled or run by the author.

## Why

`SyncConflictPresenter` is keepAlive and did not depend on the signed-in uid, so a uid change kept the previous
account's conflicts, busy keys and failure flag; a refresh error kept the old list; the sheet drew the conflict and
candidate cards after its loading/error/empty branch chain, so an error or first frame still showed them; a tap made
under account A and queued behind a long sync could resolve account B's entry (deterministic ids).

## What changed

- `sync_conflict_presenter.dart`: new `syncConflictUidProvider` (`Provider<String?>`, watches
  `authUserProvider.select(uid)`); `build()` watches it, so the state is rebuilt (first frame loading, no conflicts,
  no busy, no lastFailed) on every uid change; a stream error clears `sync`; actions capture the uid at tap time and
  pass it as `expectedUid`; a completion that arrives after a rebuild or dispose does not touch the state
  (generation counter). `retry()` only resubscribes and needs no uid.
- `sync_conflict_sheet.dart`: the two card loops moved under the branch chain (`else ...[ ]`), so cards are drawn only
  when `loaded && !loadFailed && hasItems`.
- The repository/resolution side (`expectedUid` parameter, `SyncOutcome.pending` on mismatch) was committed with
  item H5/H7 because the helper lives in the same library file.

## Affected contracts

`syncConflictUidProvider` (tests override it instead of `authUserProvider`); `resolveConflict`/`resolveCandidate`
receive `expectedUid`.

## Verification state

Not compiled, not run. Test notes: `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md`, heading H-B.
