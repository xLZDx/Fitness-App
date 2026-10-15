# Diary day follower baseline and result card overflow

- What: DiaryDayFollower now sets its last-today baseline in the constructor (it was a lazy late field first read after midnight, so the follow never fired); the confidence Row in the body scan result card wraps its Text in Flexible.
- Why: found by diary_providers_test (FL-F6) and new_pages_tap_targets_test (overflow of 17-297 px at 2x text scale and in Russian).
- Paths: mobile/lib/features/food_diary/state/diary_providers.dart, mobile/lib/features/body_scan/widgets/result_view.dart.
- Contracts: none.
- Verification: diary_providers_test 36 passed, new_pages_tap_targets_test 56 passed, run alone by the test agent.
