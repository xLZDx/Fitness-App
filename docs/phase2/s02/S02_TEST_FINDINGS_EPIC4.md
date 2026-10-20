# S02 test epic 4: findings (plan versus design versus code)

Scope: story S02-12 (sync, conflicts, candidate resolution): ids I13, I26, I31-I33, I37-I39, I42-I44, I50-I53, I56, I57, E04.

Final run (from `mobile/`, all eight epic-4 files in one command, git head before this commit 93f2d965):
`flutter test test/features/activity/repository/activity_rev_convergence_test.dart test/features/activity/repository/activity_tombstone_sync_test.dart test/features/activity/repository/activity_override_convergence_test.dart test/features/activity/repository/activity_override_value_rule_test.dart test/features/activity/repository/activity_override_explicit_edit_test.dart test/features/activity/repository/activity_override_recalc_candidate_test.dart test/features/activity/state/sync_conflict_presenter_test.dart test/features/activity/e2e/s02_delete_wins_e2e_test.dart`
Summary line: `00:17 +127: All tests passed!` (127 tests, 0 failed, 0 skipped).

## Test doubles

`mobile/test/support/two_device_world.dart`: a fake Firestore server that enforces the rev rule, immutable `startUtc`/`sport`, the closed key shape and bounds (incl. `userEditCount` 0..64), the `startUtc` clamp, the tombstone check and the account fence, and logs every accepted and refused write per device; devices with their own journal directory and repository, offline switch, dropped acknowledgement and a hook between a read and the next write. The existing `fake_summary_backend.dart` (epic 2, I05) is unchanged. The Dart twin of the F94 self-test is not a separate file: every convergence test first asserts that the loser WAS refused by the fake (`server.refused`), which fails if the fake never conflicts.

## Contradictions and how they were resolved (design/code followed)

1. G9/G32 say a version bump writes nothing. The summary carries `formulaVersion`, so the bump is a local change and one write containing the new version string is made. Tests assert: no write carries the stale distance, the override keeps its value, `atVersions` moves in the committed record, a second load creates no generation and no write.
2. G18/I44 "field B cannot recompute, held value 4 800": the code can only tell "no value" (null recompute) from "has a value"; a device that holds a stale value adopts the server value through an override. I44 is tested with a device that holds no value (null); a held-but-unreproducible value cannot be distinguished by the model. Recorded as a model limit.
3. I44 "keep this device" with no local value writes a summary WITHOUT that field (rev +1); the server document loses `distanceM`. Follows "write the local value"; questionable product behaviour, not changed.
4. A device never pulls: a synced device with no local change does not learn another device's edits. Plan sentences like "A converges" are tested by giving A a later local change (the next sync merges). Each device therefore holds all edits only after its own next write.
5. A device that holds no value for a field cannot adopt a server-only change of it (design rule 3 gives `sync_conflict`); fixtures give every edited field a value (`baseSession`).
6. Plan I43/E04 numbers `N` differ: the explicit edit of a candidate scenario writes an extra rev for `userEditCount`, so the adopted override's `atRev` is 3 in S34 (not N+1 of the plan).
7. Plan I26 case 3 expects `sync_conflict` for a clamp rejection of an existing entry; tested on a new far-future entry (create path), same reaction.
8. Plan I42 "a second conflict while the sheet is open updates the sheet and does not stack": tested by calling `show` twice; an update-in-place by a later stream event is covered by the presenter state tests.

## Production defects found

None. All 127 tests passed against the committed production code; no production file was changed in epic 4.

## Ids that are not in this epic or have no Dart subject

- I15, I16, I17 (`activity_stream_upload_test.dart`), I27 (`activity_stream_upload_retry_test.dart`), I28 (`activity_consent_withdrawal_test.dart`): the client has no stream upload, PUT, retry or consent-withdrawal code (`grep` over `mobile/lib/features/activity` and `core/`: nothing; only `ActivityStreamPayload` and `ActivityCloudSummary`, tested in epics 1 and 3, U08, U24). They belong with the stream-upload story (S02-04b/S02-05a) and cannot be written without that code. NOT RUN, no code exists.
- I30 and I34 (rules/repository constants), I13 is done (tombstone push). Epics 5-6 (emulator, functions): R-series, F-series; E04's real rules half is R26, R32-R34, R36-R37.
- Not verified: the Firestore adapter itself (no fake Firestore package; epic 3 note), real rules, layout and pixels of the sheet (NOT_RUN by design), real device restart.

## Test-side notes

- Widget tests of the sheet tap inside `tester.runAsync` because the journal futures cannot progress in FakeAsync; a first version hung.
- An earlier fixture error (A and B both editing `ascentM`) produced a genuine `sync_conflict` on A; fixtures now use disjoint fields.
