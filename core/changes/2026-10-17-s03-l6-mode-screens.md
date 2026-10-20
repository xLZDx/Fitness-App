# S03 lane L6: mode screens

Date: 2026-10-17. Kind: production code (UI), stories S03-08 to S03-11.

## What changed
New under mobile/lib/features/modes/:
- pages/mode_chooser_page.dart, pages/mode_question_page.dart.
- widgets/mode_grid_layout.dart, mode_card.dart, mode_text.dart, mode_chooser_offer.dart, mode_question_plan.dart (chooser and questions parts).
- widgets/mode_switcher_sheet.dart, coming_later_sheet.dart, record_sheet.dart (switcher, Coming-later sheet, Record sheet) with the two opener functions `openModeSwitcher` and `openRecordSheet`.

## Why
Stories S03-08 to S03-11 (design 2.3, contract S-1 to S-5): the user chooses a mode once, answers at most three skippable questions, can switch mode later and reach the main capture flows from one Record sheet without creating any capability.

## Affected contracts and paths
Nothing existing changes in this commit; the route swap and the opener wiring in main.dart follow in separate commits.

## Verification state
Nothing was run; NOT_RUN until the test agents (epics 2 and 3).
