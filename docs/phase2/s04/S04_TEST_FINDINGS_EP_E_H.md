# S04 test findings, group EP_E_H (EP-E permission/consent, EP-H privacy guarantees)

Head under test: 1d76b05e plus one production edit (below). Not committed.

## Result
Command (from `mobile/`):
`flutter test test/features/recording/permissions test/features/recording/consent test/features/recording/safety test/features/recording/l10n`
Final run: 227 passed, 0 failed, 0 skipped (permissions 56, consent 58, safety+l10n 113).

## Files (all new, `mobile/test/features/recording/`)
- permissions/fake_permission_service_test.dart (DT-17-1, 17-4/5/15/16 seam: status helpers, fake contract, no re-prompt when permanently denied/restricted)
- permissions/permission_handler_service_test.dart (production service over a mocked platform channel: status mapping, never re-prompt, precise probe, no caching, openSettings; DT-17-5, 17-6, 17-13)
- permissions/revocation_watcher_test.dart (DT-19-1 detection within 2 s, 19-2 timer channel, 19-4 once per start/no auto-resume, unknown never revoked, no overlapping reads, stop/dispose)
- consent/location_consent_model_test.dart (DT-21-1 fields, 21-5 key shape/no collision/wipe prefix, 21-8 fail closed on corrupt/unknown values)
- consent/location_consent_notifier_test.dart (DT-21-1, 21-2 withdraw keeps data and stops a collecting recording with the consent reason, 21-3 grant fails closed, 21-4 ordered writes and uid guards incl. account switch in flight, 21-7 consent axis, 21-8 no overwrite)
- safety/recorder_safe_error_test.dart (DT-27-1 sanitiser half, 27-2 mapper over real typed exceptions, 27-7 isolate re-throw text dropped from stacks, global-handler hook)
- safety/to_string_content_free_test.dart (DT-27-2 /to-string-content-free for Fix and PipelineSample)
- l10n/recording_error_codes_test.dart, l10n/recording_log_test.dart (DT-27-2 code table, type-name sanitiser, log line shape, failing sink)
- l10n/privacy_defaults_and_scans_test.dart (DT-27-3/27-4/27-5, DT-28-1/2/4/5/6/7/8, DT-21-6: scans of lib/features/recording/**, defaults, ARB version equality and DRAFT markers, ru parity)

Stories covered: S04-17 (service/fake/mapper level), S04-19 (detection level), S04-21, S04-27, S04-28.

## Production bug found and fixed
1. `mobile/lib/features/recording/pipeline/pipeline_types.dart` `PipelineSample.toString()` printed `lat=` and `lon=` (S04-R-044, DT-27-2). Changed to `'PipelineSample(t=$offsetMs)'`. Guarded by safety/to_string_content_free_test.dart (failed before the edit via the DT-27-3 scan; the explicit toString test would also fail on the old text). This is the only production change.

## Observations (not changed)
- `JournalStorageFullException`, `JournalIoException`, `JournalWriteFailure`, `JournalUnbound` etc. map to `RecorderErrorCode.unknown` (only `JournalKeyUnavailable` and `JournalDecryptFailure` have dedicated codes). Content-free, but storage-full diagnostics are coarse. The test asserts only that a bare code is returned.
- `logRecorderEvent` / `sanitizeScope` keep digits and dots, so a coordinate passed as an event word would survive; the guard is the call-site scan (all call sites are fixed literals today).
- `kDefaultPrivacyZoneRadiusM` / `kDefaultGpsExpiryMonths` are referenced nowhere outside recording_defaults.dart (the settings row is not built yet); DT-28-7 asserts that.
- `kRecordingExpiryMs` (30-day sweep of quarantined local recordings) is excluded from the no-expiry scan; it is local housekeeping, not an upload expiry.

## Remaining gaps (NOT_RUN here, belong to widget/integration lanes or a phone)
- NOT_RUN: widget flows DT-17-2, 17-4, 17-6, 17-8, 17-9, 17-10, 17-12, 17-13 (panels), 17-16, 17-17, 17-19, 17-22 and panel focus/announcements (other folders).
- NOT_RUN: controller-level DT-17-3 call-order spy, 17-7, 17-11, 17-14, 17-18; DT-19-1 phase/session-save outcome, 19-3, 19-5..19-25 (journal Keep/Delete/decision-marker lanes, other folders); DT-21-2 "withdraw then Start refused" at controller level, 21-9, 21-10 call-order spy.
- NOT_RUN: DT-17-21, DT-19-8, DT-20-x (CONDITIONAL / device lab); DT-18-x (conditional).
- NOT_RUN: DT-26-x (performance, owned by performance-optimizer), DT-27-1 full flows with LogCapture and TelemetrySpy, DT-27-5 rendering of generated localizations with sentinels (only ARB-level check done), DT-27-6, DT-27-7 worker path, DT-28-3, DT-28-9.
- Mutation runs not performed by operator rule; each test's "fails when" is argued from its assertions.
