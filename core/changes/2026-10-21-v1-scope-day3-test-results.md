# v1 scope: Day-3 modal off, test update and results (2026-10-21)

Code under test: commit 2e67e48b (`day3WelcomeModalEnabledProvider`, default false, read in `home_page.dart`). No file under `mobile/lib` was changed.

## Files changed
- `mobile/test/features/modes/mode_chooser_test.dart`:
  - DT-08-9 now overrides `day3WelcomeModalEnabledProvider` with true.
  - New test: with the default (false) and a repository that makes `shouldShowDay3Welcome` true (precondition asserted in the test), Home shows no `Day3WelcomeModal`, the launch count is bumped exactly once, `markShown` is never called, and the mode chooser is offered after the Day-3 step settles.
  - New control test: provider true with the same repository shows the modal, then `markShown(day3Welcome)` is recorded and the chooser follows (proves the recorder can observe a mark).
- `mobile/test/features/home/home_mode_lens_test.dart`: the `day3: true` scenario helper also overrides the provider with true. Without it AC-HM-4/day3Modal and DT-12-1 failed (no BottomSheet).

## Commands (cwd `D:\Repo\Fitness_App_v1scope\mobile`, `/d/flutter/bin/flutter`)
- First run, all 12 HomePage-mounting files plus moment_test (`flutter test --timeout 90s <files>`): 2 real failures (home_mode_lens AC-HM-4/day3Modal and DT-12-1), fixed as above; 14 golden pixel failures (see below).
- Final run of the 10 non-golden files: `flutter test --timeout 90s test/features/modes/mode_chooser_test.dart test/features/moments/moment_test.dart test/features/home/home_body_check_in_card_test.dart test/features/home/home_mode_lens_test.dart test/features/home_page_test.dart test/features/modes/mode_switcher_test.dart test/features/modes/mode_ui_seams_test.dart test/features/s03_conformance/s03_conformance_extra_test.dart test/features/s03_conformance/s03_conformance_pages_test.dart test/features/training_context/training_context_generation_journey_test.dart` -> +287 ~12 (12 skipped), all passed.
- Per file: mode_chooser +52, home_mode_lens +26, moment_test +7.
- Goldens: `flutter test --timeout 90s test/golden/composed_screen_golden_test.dart test/golden/hud_golden_test.dart` -> +3 -14. All 14 failures are pixel diffs (for example HudPanel 8.99%, composed home 61%); none is a Day-3 assertion.

## Not verified
- The 14 golden failures were not compared against the pre-change baseline. They look like the known platform-rendering golden limit: hud_golden_test does not mount Home, and the composed Home uses the default mock repository (1 launch), where the Day-3 rule is false and the modal never showed. This is an inference, not a measurement.
- The pure `shouldShowDay3Welcome` rule is unchanged and covered only by the existing moment_test.
