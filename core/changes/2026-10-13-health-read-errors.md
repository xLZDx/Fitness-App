# Change record: health read failures are shown as failures (NEW-HEALTH-ERR)

**Problem.** `PlatformHealthService.readSnapshots` caught every exception, recorded it and returned an empty list. `readTodaySnapshot` turned that into `null`, and the sync card rendered it as "No health data today", so a Health Connect failure looked like a quiet day. Separately, `healthAuthStatusProvider` is cached: a permission revoked while the app was running kept the "granted" card until the next restart.

**Change.**
- `mobile/lib/core/health/platform_health_service.dart`: `readSnapshots` records the error and rethrows. Its only callers are `todayHealthProvider` and `last7DaysHealthProvider`, whose error branch (`healthHealthReadFailed`) already renders a read failure.
- `mobile/lib/core/health/state/health_providers.dart`: when the today read comes back empty, `todayHealthProvider` re-reads the auth status and, if it differs from the cached one, invalidates `healthAuthStatusProvider` (in a microtask, to avoid invalidating during build).

**Contracts touched.** `HealthService.readSnapshots` may now throw on a platform failure; the mock service is unchanged and still returns data. An unsupported platform or a non-granted status still returns an empty list.

**Not changed.** `currentAuthStatus` still maps an exception to `notDetermined`; revocation detection runs only when a read returns empty, not on app resume.

**Verification state.** Not compiled and not run; the sprint-end test agents do that. No on-device check. Nothing pushed.
