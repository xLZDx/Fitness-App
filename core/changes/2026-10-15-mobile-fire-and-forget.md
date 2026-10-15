# Mobile review fixes 3: fire-and-forget runner calls observed (SF-F6, SF-F2 resume trigger)

## What
- Flow driver, app-root wiring and the unfinished-scan card observe every un-awaited runner call (`resume`, `retry`, `cancel`) with a logged, type-only error; the card's delete and open handlers catch failures and show the failure state.
- The runner provider resumes the runner once the profile / weight log have loaded, so a scan that waited for them (not-ready) continues.
- Test harness `FakeRunner.failWith` and a driver regression case.

## Why
SF-F6, SF-F2.

## Paths
mobile/lib/core/wiring/body_scan_wiring.dart, mobile/lib/features/body_scan/state/body_scan_flow_driver.dart, mobile/lib/features/body_scan/state/body_scan_providers.dart, mobile/lib/features/body_scan/widgets/body_scan_entry_card.dart, mobile/test/features/body_scan/support/driver_harness.dart, mobile/test/features/body_scan/state/body_scan_flow_driver_test.dart

## Verification
Not run (operator rules).
