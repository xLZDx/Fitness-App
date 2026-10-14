# Change record: mobile app hardening (release gating, silent failures, recommendations, body scan, privacy text)

Companion records: `2026-10-13-ws6-part1-recommendation-logic.md` (age policy and hints in detail), `2026-10-13-ws7-coach-registry-engine.md` (coach engine, separate commit).

## What changed
### Release gating of mock-only features (WS1, F1, F2, F9)
- `mobile/lib/core/config/demo_features.dart`: `kDemoFeaturesEnabled` is true outside release builds or with `--dart-define=DEMO_FEATURES=true`; `demoFeaturesEnabledFor` is the pure derivation the tests pin.
- `app_router.dart`: gated paths (`/community`, `/team/*`, `/celebrity-plans`, `/contribute`, `/moderate`) redirect home in release, so deep links and restored state are covered; profile, settings and the exercise reference hide their entries. The splash hold now waits for the profile snapshot (bounded to 5 s) so an onboarded user is not sent to onboarding on cold start (F6); a cancelled hold timer is reset so a second hold keeps its bound. New routes `/photos/scan` and `/photos/compare`.
- Marketplace: a guarded service refuses booking on a mock listing (`MarketplaceUnavailableException`); progress photos use a fallback repository that throws in release, so a store failure shows an error instead of a demo grid.

### Silent failures (WS3, F4, F5, F7, F8, F11, F13)
- Reminders return a `ReminderOutcome` (scheduled, past, denied, failed) with FNV-1a ids instead of `String.hashCode`; the offline prefetch awaits the schedule; batch clears on machine cards and recognition history are chunked (`chunked_delete.dart`); logs added where errors were swallowed.
- Manifest: removed exact-alarm, Bluetooth, foreground-service, activity-recognition and microphone permissions that no code requests; added the Health Connect write/read grants the workout write needs (total calories always; distance because the plugin asks for it in the same request). `flutter_blue_plus` removed. Wear debug build gets an application-id suffix.

### Honest recommendations (WS6)
- One age policy (`safety/data/age_policy.dart`) carried by `SafetyContext` to the plan, suggestion and programme builders: minors under 18 and seniors from 65 get a cautious path (intensity ceiling, fewer days, lower volume, no maximal-effort work, no high-impact work for seniors, balance and mobility for seniors) and a warning; an unknown age is treated as adult. The beginner difficulty ceiling applies to recommendations only, not to browsing.
- Onboarding fields now reach the generators through `recommendation_hints.dart`; the unused ones are documented with reasons.
- Training context (`features/training_context`): asked at recommendation time (gym with machines, outdoors with minimal kit, home, yoga as a separate mode), stored per account, never turned into "gym" when unanswered; wired into the planner, home suggestions and programmes; account switches no longer expose the previous account's answer.
- `recommendation_honesty_100_test.dart`: 100 synthetic profiles plus four hand-written canaries; every rule except one is at zero, and the equipment-link rule is asserted at its exact count.

### Body-comparison scan (WS8)
- `progress_photos/scan/**`: self-timer capture with readiness checks, auto shutter, voice and haptic prompts, three poses (front, side, back), encrypted per-account storage of photos and landmarks, side-by-side, slider and ghost-overlay comparison with similarity-transform alignment, a 2-weekly reminder, Supporter-only access, refused under 18 or with unknown age. Photos never leave the device and no body numbers are computed.
- Account deletion wipe covers scans, the scan reminder preference, the training-context answer and coach recordings; deletion also cancels pending notifications. The scan reminder and the training context reset on an account switch.

### Privacy text and store declarations
- `scripts/legal/legal_text.py` and the regenerated `public/privacy.html`, `app_en.arb`, `app_ru.arb`: exact Health Connect types, no activity-recognition or microphone use, the on-device scan, local reminders. `core/PLAY_DATA_SAFETY_2026-08-05.md` lists the Console actions the operator must take; `core/DATA_INVENTORY_2026-08-11.md` is rebuilt from `local_data_wipe.dart`; `core/ML_PLATFORM_ARCHITECTURE.md` classifies `training_context`.

## Why
Findings F1..F13 of the whole-project QA and the operator's decisions of 2026-10-13: mock features must not reach release users, failures must not be silent, recommendations must use the profile honestly (age, equipment, training context), and the body-comparison screen follows the reference video.

## Affected contracts and paths
- Release behaviour: gated routes redirect home; marketplace booking and photo-store fallbacks cannot run against mock data.
- Storage: new per-account keys `training_context.v1.<uid>`, `progress_photos.scan_reminder.v1.<uid>` and the encrypted `<docs>/progress_photos/<uid>/scans/` directory, all removed by the wipe.
- l10n: new `scan*`, `trainingContext*`, `planReasonContext*`, `eligAdvisoryAge*` keys in both languages; Russian copy is unreviewed by a native speaker.
- Not verified here: camera, ML Kit, speech output, haptics, Health Connect permission screens, Kotlin/Gradle (no device or emulator on this host).

## Verification state
Full `flutter test`: 4360 passed, 28 failed on the first run; the 25 golden failures are the host's font/rendering mismatch (same count as the baseline before this sprint), and the three real failures were fixed (hardcoded-white ledger now 69 with a written reason, the ML applicability matrix classifies `training_context`). `flutter analyze` reports no errors; remaining warnings are older code. The final head's focused results are in the PR description.
