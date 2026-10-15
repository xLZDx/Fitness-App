# Change record: server review fixes part 4 (SF-F9)

## What changed
- `functions/src/analyze_meal_photo.ts`: model output that is not a JSON object with an `items` list now refunds the quota and answers `unavailable`; a well-formed `{"items": []}` remains a successful "no food found".
- `functions/src/parse_nutrition_label.ts`: model output that is not a JSON object refunds the quota and answers `unavailable` instead of returning an "unusable" label.
- Tests: `analyze_meal_photo.test.ts`, `parse_nutrition_label.test.ts` updated (unusable output -> unavailable, usage 0).

## Why
Truncated or non-JSON output was reported as a successful empty result while the user stayed charged (review SF-F9).

## Contract change
Clients now receive `unavailable` for unusable model output; they must treat it like any transient AI failure.

## Verification state
Not run.
