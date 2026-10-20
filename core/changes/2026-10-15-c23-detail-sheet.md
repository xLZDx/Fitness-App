# C23 part 6: meal slot section and food detail sheet

## What changed
- `widgets/meal_slot_section.dart`: slot heading with total, entries (source badge, confidence text, delete with 48 dp target), "Add to <slot>" button, calm empty line.
- `food_detail_sheet.dart`: framework modal bottom sheet (initial focus on the heading, semantics outside blocked, focus returns to the trigger), slot picker, per-item source badge, per-100 g line, portion editors, Check these chips with a resolution sheet (oil choice via the generic table, otherwise "Mark as checked"), live-region totals, Save (data-notice gate D-79 before the first diary write) and "Save this food" for single-item entries. Estimates carry an explicit note.

## Verification
Not run (sprint rule).
