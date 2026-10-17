# S03 lane L1 run 3: aggregates and digest providers

Date: 2026-10-17. Kind: production code, story S03-13.

## What changed
- mobile/lib/features/activity/data/activity_aggregates.dart (new, pure): session digests, sport groups, today, recent and week aggregates with 'k of n sessions have value' counts, source labels.
- mobile/lib/features/activity/state/activity_dashboard_providers.dart (new): `DigestSnapshot`, `activityDigestsProvider` with `refresh()` and `refreshIfStale()`, derived today, week-tile and recent providers, test seams for revision, clock and zone.
- mobile/lib/features/progress/data/progress_stats.dart: the day and Monday-week helpers become public (`localDayOf`, `mondayWeekStartOf`); `deriveProgress` is untouched.

## Why
Story S03-13 (design 3.1 to 3.7, RV-3, RV-10, RV-11): the dashboards need digests that never show another account's data, show loading while the journal binds, keep the last value after a failed refresh and count unreadable sessions apart from 'no data'.

## Affected contracts and paths
No screen reads these providers yet (Home and Progress lanes). The existing progress statistics behave as before.

## Verification state
Nothing was run. The tests (DT-13-x) are written and run by the test agents after epic 13; until then NOT_RUN.
