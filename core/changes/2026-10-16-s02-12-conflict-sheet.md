# S02-12 change record: choice sheet and strings

Date: 2026-10-16. Story: S02-12 (test id I42).

## What changed

- New `mobile/lib/features/activity/widgets/sync_conflict_sheet.dart`: a `ConsumerWidget` bottom sheet over `syncConflictPresenterProvider`. Conflict cards show each conflicting field with the device and cloud value and the actions "Keep this device" / "Keep cloud". Candidate cards show the user's value, the cloud value (when an override exists) and the new computed value, with three actions (use the new computed value, keep my value, use the cloud value) or two, and the labels "Use recalculated value" / "Keep cloud value" for a recalculation candidate. No delete action. `show` opens at most one sheet; a second conflict updates the open one.
- `mobile/lib/l10n/app_en.arb` (source) and `app_ru.arb` (the project keeps both locales): `activitySync*` strings, 15 field labels, placeholders only in the English metadata like neighbouring keys.

## Verification state

No tests, builds, `flutter gen-l10n` or checks were run (operator rule v4); the generated localizations must be produced by the normal build.
