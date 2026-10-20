# S02 remediation H-B, item H8: wipe coordinator and local export bound to the account

Date: 2026-10-16. Area: mobile production code (activity journal hooks, local export). Nothing was compiled or run by
the author. No production caller exists yet (S03 wires both); the contract is made account-bound first.

## What changed

- `activity_journal.dart`, `ActivityWipeCoordinator.onSignOut`: captures the bound uid of an account-scoped journal
  BEFORE the assessment and the prompts, aborts (returns false, no wipe) if the bound uid changed after the
  assessment or after the user's confirmation, and wipes exactly the captured uid with `wipeForUid`. A plain journal
  keeps `wipe()`; an unbound scoped journal keeps the old behaviour.
- `activity_local_export.dart`: `JournalActivityLocalExport.exportAll` captures the bound uid before listing and
  re-checks it after the listing and after every per-activity read; on a change the whole export is abandoned with a
  single new result `ActivityExportAccountChanged` (no partial or mixed export). Deviation from the brief, on
  purpose: the journal listing returns entries WITHOUT streams, so exporting the listed objects would lose the route
  in GPX/FIT; each entry is therefore still read by id, covered by the uid check after each read.

## Affected contracts

New `ActivityExportAccountChanged extends ActivityExportResult` (sealed class: exhaustive switches over the result
need the new case; none exist in lib or test per grep). `onSignOut` may now return false for an account change.

## Verification state

Not compiled, not run. Test notes: `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md`, heading H-B.
