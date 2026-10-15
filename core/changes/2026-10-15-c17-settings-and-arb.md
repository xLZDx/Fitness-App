# C17 part 1: reminder settings field and ARB keys

## What changed
- `mobile/lib/features/body_scan/state/body_scan_settings.dart`: new `ScanReminderPrefs` (enabled, weekday 1..7 default 7, minutes 0..1439 default 480); `BodyScanSettings.reminder` (null = never chosen); `BodyScanSettingsStore.setReminder` for the Firestore and in-memory stores.
- `mobile/lib/l10n/app_en.arb`, `app_ru.arb`: keys for the reminder notification text, "Body check-in" title (D-76), last check-in line (RU plural one/few/many/other), and the reminder editor.

## Why
Design section 19 and D-21, D-74, D-76, D-77: weekly weekday/time reminder, synced in `body_scan_settings/main.reminder`.

## Contracts and paths
Matches the rules shape `reminder: {enabled, weekday, minutes}` (design section 5.2). No rules change.

## Verification state
Not run (operator rule: no checks until the sprint testing phase). gen-l10n not run.
