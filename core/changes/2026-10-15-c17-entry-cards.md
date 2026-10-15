# C17 part 3: Body check-in entry card, Progress and Home mounting

## What changed
- `mobile/lib/features/body_scan/widgets/body_scan_entry_card.dart` (new): user-facing title "Body check-in" (D-76), provisional label (D-73), last check-in line (localised plural), measurement-only note (D-74), access-aware start action into `/body-scan`, links to `/body-scan/history` and `/body-scan/privacy`; the full form also mounts the C15 `ResumeScanCard` (pending or terminal-failure) for the newest unfinished local scan. `compact: true` is the Home form (title, label, last check-in, one action).
- `mobile/lib/features/progress/progress_page.dart`: card mounted under the headline stats (3 lines).
- `mobile/lib/features/home/home_page.dart`: compact card after the quick-scan row (3 lines).

## Left for follow-up
- Result page hooks (a History link, `editScanWeightFlow` / `deleteScanPhotosFlow` from `scan_row_actions.dart`) are not done: they need a `ScanHistoryRow` for the open scan.
- Resume of a pending scan only opens `/body-scan`; the Cancel/Delete actions delete the local record through `ScanRepository.delete` (no remote-delete handling, which the flow's cancel path owns).
- Notification tap routing: documented limit, see the part 2 record.

## Verification state
Not run (no checks before the testing phase).
