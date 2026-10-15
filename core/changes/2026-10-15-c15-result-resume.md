# C15 change record: result view and resume/failure card

Story: C15, part 5 of 6.

## What changed
- `mobile/lib/features/body_scan/widgets/result_view.dart`: result built from `ScanResultViewModel`. Likely range (never a bare number), confidence as icon + text, the fixed plain-language limit, change label with the noise threshold note, points to goal, fat/lean mass tiles ("this reading" vs "from your trend", never mixed), weight trend, strength sessions card, chart and check items. Provisional (D-73): banner, weight-first headline, rough-estimate label, ring/points/change/ETA/plan decision hidden, "See your plan" action. Measurement only (D-74): estimate behind a neutral ask, no goal figures.
- `.../widgets/resume_scan_card.dart`: pending variant (Resume / Cancel) and terminal-failure variant (Retry / Keep on this device / Delete), D-78.

## Notes
- The ETA range text key exists but the ETA is not rendered yet: it needs height, sex and pace that the result source does not carry; it stays hidden (safe) until C18 supplies them.
- Editing the recorded weight from the result is not part of this story.

## Verification state
Not run (operator rule).
