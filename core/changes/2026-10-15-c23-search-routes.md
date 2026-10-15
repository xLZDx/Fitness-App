# C23 part 8: food search page, routes, weight link

## What changed
- `food_search_page.dart` (`/nutrition/add/search`): bundled foods answer while typing; packaged/USDA results only after an explicit submit (3-character minimum, 600 ms debounce, last-results cache in `FoodSearchController`); saved foods list (`saved=1`). States: too short, loading, empty, not-available-yet (server flag off), error, rate limited. Source badge and per-100 g line on every row; partial database records say so.
- `mobile/lib/core/router/app_router.dart`: routes `/nutrition/diary`, `/nutrition/add`, `/nutrition/add/search` (day, slot, saved query parameters; unknown slot means none).
- `food_diary_page.dart`: the weight-log entry now links to the existing `/nutrition/weight` page (the earlier in-page dialog was removed to avoid a second weigh-in surface).

## Verification
Not run (sprint rule).
