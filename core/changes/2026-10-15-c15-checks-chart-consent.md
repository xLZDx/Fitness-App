# C15 change record: check items card, trend chart, cloud consent sheet

Story: C15, part 4 of 5.

## What changed
- `mobile/lib/features/body_scan/widgets/check_items_card.dart`: closed-set `CheckCode` texts (`checkCodeText`), chips with icon + text + explicit "needs checking / resolved" label, one announcement of the item count on appearance, focus moves to the next unresolved chip or to the card heading after a resolve (D-85).
- `.../widgets/trend_chart.dart`: painted chart excluded from semantics, one summary node with an expand custom action, expandable data table (date, reading with range, smoothed, outlier; per-row semantic labels), shape-coded dots/line/outlier diamonds, legend, "new estimator" marker, last 12 points, locale-aware numbers and dates (D-85).
- `.../widgets/cloud_consent_sheet.dart`: separate upload consent, modal route, heading focus; the caller shows it only when the provider needs photos (D-5).

## Verification state
Not run (operator rule). Test agents own widget tests.
