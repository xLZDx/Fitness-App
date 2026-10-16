# S02 glue: app wiring, start-up sync and conflict entry point

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/core/wiring/activity_wiring.dart` (new): `openActivityJournal` (opens and recovers the file journal, only with the flag), `activityRootOverrides` (overrides `activitySyncRepositoryProvider` with the Firestore backend and exposes the journal), `activityCloudSyncWiringProvider` (one `syncAll(retryConflicts: true)` per signed-in non-guest account at app start, errors logged and swallowed).
- `mobile/lib/main.dart`: opens the journal before `runApp`, adds the overrides, watches the wiring provider in the root widget.
- `mobile/lib/features/activity/widgets/activity_sync_entry_card.dart` (new) and `mobile/lib/features/progress/progress_page.dart`: a card on the Progress page that opens `SyncConflictSheet.show` when the presenter reports entries; it reuses the existing sheet title string (no new l10n key).

## Why
Design 12.1: the cloud path ships behind `ACTIVITY_CLOUD_STREAMS`, default OFF. With the flag off no journal is opened, no provider is overridden, the card builds nothing and never reads the presenter (whose provider would otherwise throw), so behaviour is unchanged.

## Affected contracts and paths
`main.dart` startup (one extra awaited call that returns null immediately when off), Progress page layout (a shrink widget when off).

## Verification state
No tests, analyzer or build were run. Not verified: compilation, the flag-on path on a device, widget tests of the card.
