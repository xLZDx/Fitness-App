# Mobile food fixes (FL-F1, FL-F2, FL-F3, FL-F6)

- What: FoodSearchController keeps its state when the generic table loads and shows an error state on a table load failure; _fetch and the barcode lookup catch every error with a mounted check and the camera resumes on rescan; the torch toggle future is handled; a DiaryDayFollower moves the selected diary day to the new today after midnight on app resume when the user was on the old today. scan_history_actions.dart gets a one-line follow-up.
- Why: findings FL-F1, FL-F2, FL-F3, FL-F6 of the flutter review; barcode errors stranded the page, and entries could be saved to yesterday.
- Paths: mobile/lib/features/food_diary/{barcode_scan_page,food_diary_page,state/diary_providers}.dart, mobile/lib/features/body_scan/state/scan_history_actions.dart, tests under mobile/test/features/food_diary and accessibility.
- Contracts: no wire or storage change. FL-F7 skipped (changes the table loading contract).
- Verification: not run; regression cases added in the existing test files, to be run by test agents.
