# C17 part 2: weekly scan reminder rule, editor, legacy entry card routing

## What changed
- `mobile/lib/features/progress_photos/scan/scan_reminder.dart`: the 14-day gap is replaced by the pure rule `nextScanReminderFire` (default Sunday 08:00, next slot strictly after `max(now, newestScan + 5 days)`, calendar arithmetic). Same notifier, same `kScanReminderId`. Enabled state reads `body_scan_settings.reminder`, falls back to the v1 SharedPreferences bool, and defaults to OFF in `measurementOnly` mode (D-74). `paused` cancels the pending reminder (D-77). New notification text keys `scanReminderTitle/Body` ("Time for a body check-in", no body-fat promise). New `setSchedule` and the `scanReminderScheduleProvider`.
- `mobile/lib/features/progress_photos/scan/ui/scan_reminder_editor.dart` (new): switch, weekday chips, time picker, pause switch; weekday/time formatted with `intl` (`formatReminderWhen`).
- `mobile/lib/features/progress_photos/scan/ui/scan_entry_card.dart`: starts the new `/body-scan` flow and embeds the editor instead of the old 2-week switch.
- `mobile/test/features/progress_photos/scan/scan_reminder_test.dart`: expectations updated from the 14-day rule to the weekly rule; plan context overridden to `full`.

## Notification tap routing (VERIFIED limit)
`LocalNotificationService` calls `_plugin.initialize(init)` without a tap callback and the service interface has no tap hook, so tapping the reminder only opens the app. Documented limit (design s19); no new mechanism added.

## Verification state
Not run (no checks before the sprint testing phase). Existing tests that tap `scan.entry.start` and expect `/photos/scan` need the testing agents to update them to `/body-scan`.
