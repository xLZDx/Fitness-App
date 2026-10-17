# S03 lane L1 run 2: journal on by default, retry state machine, availability

Date: 2026-10-17. Kind: production code, story S03-0 part 2.

## What changed
- mobile/lib/core/config/activity_flags.dart: `ACTIVITY_LOCAL_JOURNAL` compile-time default true; the cloud flag is unchanged.
- mobile/lib/core/wiring/activity_wiring.dart: the retry closure becomes the controller `_ActivityBindController`; new public `RetryResult`, `BindPhase`, `ActivityBindStatus`, `ActivityBindStatusNotifier`, `activityBindStatusProvider`; `kActivityBindRetryDelays` and `activityBindRetryTimerFactoryProvider` unchanged.
- mobile/lib/features/activity/repository/uid_scoped_activity_journal.dart: optional `RecoveryReportSource` implemented by `UidScopedActivityJournal`; the `bindUid` catch logs the exception type.
- mobile/lib/features/activity/state/journal_availability.dart (new): sealed `JournalAvailability` (notEnabled, binding, open, gaveUp, failedToOpen) and the derived `journalAvailabilityProvider`.

## Why
Story S03-0 (design 2.1, RV-3, RV-10): the dashboards need to know whether the journal is loading, open or gave up, and Try again needs one defined behaviour.

## Affected contracts and paths
Release builds now open the local journal by default (nothing is written to it before S05; the backup exclusion is already in place). The automatic retry schedule (5 s, 15 s, 60 s, 5 min, 5 min) and six bind calls are unchanged.

## Verification state
Nothing was run. Known: mobile/test/features/activity/config/activity_flags_test.dart lines 75-79 still assert the old default and fail until the test agents update them. The tests DT-0-1 to DT-0-16 are written and run by the test agents after epic 0; until then NOT_RUN.
