# Change record: C16 part 2, history list, privacy view, routes, l10n

## What changed
- `mobile/lib/features/body_scan/widgets/scan_history_list.dart`: history rows (date, weight, body fat, trend label, baseline marker, provisional label, "new estimator" marker, owed-delete note), compare entry points (`/photos/compare?mode=baseline|previous`), a second-scan prompt when only one scan exists, per-row menu (open, edit weight, delete photos). Numbers and dates use `NumberFormat`/`DateFormat` with the active locale.
- `mobile/lib/features/body_scan/widgets/scan_row_actions.dart`: `editScanWeightFlow` (dialog, data-notice acknowledgement before the weight-log write, D-72) and `deleteScanPhotosFlow` (confirmation, then cloud-first delete, offline queued as `pendingRemoteDelete`). Reusable from the result screen.
- `mobile/lib/features/body_scan/widgets/retention_settings_view.dart`: retention choices 0/30/90/365, "Apply to existing photos" (`applyRetention`), delete all cloud photos / scans (`manageBodyScanData`), consent status and withdrawal, pause tracking. Cloud sections only when `BODY_SCAN_CLOUD` is on. Copy says photos are deleted within 48 hours.
- `mobile/lib/features/body_scan/body_scan_history_page.dart`, `body_scan_privacy_page.dart`: route pages.
- `mobile/lib/core/router/app_router.dart`: `/body-scan/history`, `/body-scan/privacy`; `/photos/compare` reads `?mode=`.
- `mobile/lib/l10n/app_en.arb`, `app_ru.arb`: `bodyScanCompare*`, `bodyScanHistory*`, `bodyScanEditWeight*`, `bodyScanDeletePhotos*`, `bodyScanPrivacy*`, `bodyScanRetention*`. RU plurals use one/few/many/other; decimals use the non-inflecting unit "кг".

## Why
Sprint plan commit C16; design s9, s17, D-54, D-62, D-72, D-73, D-77, D-78, F12.

## Affected contracts and paths
Keys inserted before `bodyScanTitle` in both ARB files. gen-l10n was not run, per the rules; the generated getters appear on the next generation.

## Verification state
Not run, per DEVELOPMENT RULES v4.

## Review state
Pending the test phase and specialist reviewers. Not wired here: entry links to history/privacy from the result page and Progress (owned by the C15 flow work).
