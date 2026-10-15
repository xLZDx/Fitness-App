# C15 change record: flow page, result page, routes

Story: C15, part 6 of 6.

## What changed
- `mobile/lib/features/body_scan/body_scan_flow_page.dart`: renders the pure flow state; gated by the existing `scanAccessProvider`; intro, weight prompt sheet, capture (delegates to the existing `/photos/scan` capture), analysis progress, terminal failure card; opens the result when the flow is `done` and `bodyScanActiveScanIdProvider` (set by the job runner) holds the id.
- `.../body_scan_result_page.dart`: loads one scan via `ScanResultSource` and renders `ResultView` with the plan context; calm not-found and error states.
- `mobile/lib/core/router/app_router.dart`: routes `/body-scan` and `/body-scan/result/:scanId`.

## Known follow-ups (not done here)
- The job runner (C14/C16) must set `bodyScanActiveScanIdProvider`, listen to `scanFlowControllerProvider` effects and bind a real `ScanResultSource`; until then the result route shows "not found".
- "See your plan" pushes `/nutrition`, a route added by a later story.
- Cloud consent sheet is built but is triggered by the runner/flow wiring when the provider needs photos (not wired here).

## Verification state
Not run (operator rule).
