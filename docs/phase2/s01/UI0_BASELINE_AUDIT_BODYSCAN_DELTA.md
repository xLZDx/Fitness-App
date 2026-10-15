# UI-0 delta after PR #5: body_scan, nutrition_plan and food_diary

Status: S01 document, read-only audit by the `code-explorer` agent (Sonnet 5.5). It extends `UI0_BASELINE_AUDIT.md` and `UI0_BASELINE_AUDIT_ADDENDUM.md`, which describe the mobile tree before PR #5. Worktree HEAD at audit time: `f3db1574`. About 20 file reads and 15 greps. Paths are under `mobile/lib` (written `lib/` below). The agent did not read the original audit in full, only its grep-matched lines. Labels: FACT (read in code), INFERENCE (drawn from facts), NOT VERIFIED / UNKNOWN (not read).

## 1. New routes and screens

All 15 new routes are in `lib/core/router/app_router.dart`. All are top-level `GoRoute`s with `_fadeThrough` transitions and sit **outside** the `ShellRoute`, which holds only `/home`, `/scan`, `/workouts`, `/progress` and `/profile` (lines 674-699).

- FACT: `/body-scan/history` (552), `/body-scan/privacy` (556), `/body-scan` (628) and `/body-scan/result/:scanId` (632).
- FACT: `/nutrition/profile` (564), `/nutrition` (569), `/nutrition/weight` (573), `/nutrition/sources` (619) and `/nutrition/how-it-adapts` (623).
- FACT: `/nutrition/diary` (578) and `/nutrition/add` (582, with `?day=&slot=`).
- FACT: `/nutrition/add/search` (589, with `saved=1`).
- FACT: `/nutrition/add/photo` (598), `/nutrition/add/barcode` (605) and `/nutrition/add/label` (612).
- FACT: Not present: `/body-scan/*` or `/nutrition/*` under `_publicPaths` (70), `_accountActionPaths` (77) or `isDemoGatedPath` (83).
  - They go through the normal sign-in and onboarding redirect only.
  - Note `/nutrition/profile` is for users who have already onboarded (comment at 560).
- FACT: The three flags live in `lib/core/config/body_scan_flags.dart:43-47`, compile-time `bool.fromEnvironment`, all default false.
  - Flags never gate routing. The routes always exist.
  - They gate only widgets: `BODY_SCAN_CLOUD` (`cloudPhotos`) gates the consent sheet and the cloud sections of privacy (`body_scan_flow_page.dart:91`, `retention_settings_view.dart:123`).
  - `FOOD_AI` (`foodAi`) and `FOOD_LOOKUP` (`foodLookup`) hide the photo, text, label and barcode tiles on `add_food_page.dart:50-65`, and set `serverEnabled` at `diary_providers.dart:425`.
  - With `FOOD_AI` off the diary shows an AI-off note (`food_diary_page.dart:223`).
  - INFERENCE: with all flags off, a deep link to `/nutrition/add/photo` still opens the page. `meal_scan_page` was not read for a page-level guard. NOT VERIFIED.
- FACT: Entry points are `BodyScanEntryCard` and `NutritionEntryCard`. Both are placed in `home_page.dart:133,135` (compact) and `progress_page.dart:54,56`.
  - `/body-scan` is also pushed from `scan_entry_card.dart:34,42` (progress photos) and `scan_compare_screen.dart:221`.
  - `/photos/scan` is pushed from the body-scan flow (`body_scan_flow_page.dart:124`).
  - INFERENCE: no Settings or Profile entry to the body-scan privacy page. Only `body_scan_entry_card.dart:122` links to `/body-scan/privacy`.

## 2. Token layer

- FACT: The new screens use no `FrostedScaffold` and no `HudScreenBody`. Every page is a plain Material `Scaffold` with `AppBar`.
  - body_scan: history 19, flow 185, result 65, privacy 16.
  - food_diary: add_food 41, barcode 179, diary 29, search 115, label 225, meal_scan 193.
  - nutrition_plan: sources 37, weight 89, profile_flow 149, plan 129, explainer 36.
  - They also have no `HudSkyBackground`.
  - INFERENCE: these pages sit on the default theme background, not the photo sky used by the tabs.
- FACT: Counts per feature directory:

| Directory | `GlassCard` | `FrostedScaffold` | `HudPanel`/Hud widgets |
|---|---|---|---|
| nutrition_plan | 11 | 0 | not counted |
| body_scan | 24 | 0 | 1 (`body_scan_entry_card.dart`) |
| food_diary | 0 | 0 | 0 |

  - The `GlassCard` counts are `GlassCard(` occurrences across the files in the agent's grep; the count output was per file and the agent summed it by eye (see "Not verified").
  - `HudTokens` and `context.hud`: 10 hits across 9 body_scan widget files (e.g. `cloud_consent_sheet.dart:11,32-34`, `retention_settings_view.dart:17,122`), 13 hits in nutrition_plan and 0 in food_diary.
  - `AppSemanticColors`: no hits in any of the three dirs.
- FACT: Text colours come from `context.hud.textPrimary` / `textSecondary` (`retention_settings_view.dart:137`).
  - Cards come from the legacy `GlassCard` (`shared/widgets/glass.dart`).
  - Spacing uses `HudTokens.screenGutter` in body_scan only.
- INFERENCE: PR #5 is a third pattern. Material scaffold, `GlassCard` (legacy), `context.hud` text tokens and no HUD scaffold. food_diary is essentially unthemed Material (`Theme.of(context)` only, e.g. `food_diary_page.dart:137`).

## 3. States per screen

- FACT (`food_diary_page.dart`, header comment 19):
  - Loading uses a `CircularProgressIndicator` inside a `Semantics(liveRegion)` (53-64).
  - Error is `l10n.foodDiaryError` plus `foodDiaryErrorBody` with a Retry that invalidates the provider (156-161).
  - An empty day has its own copy (208-222).
  - There is a `ReferProfessional` notice (37), a needs-profile notice with a CTA (41-46) and an AI-off note (223).
  - Delete shows an Undo snackbar (125-131) and a write-failure snackbar (122).
- FACT: body_scan flow (`body_scan_flow_page.dart:134-184`) covers these states:
  - access gate with plain text: `scanAccessMessage` (138);
  - intro;
  - weight-prompt sheet;
  - capture;
  - analysing with cancel and retry (175);
  - failed with retry, keep or delete (160).
  - The access gate is one centred `Text` with no CTA. Consent, age and Supporter gating all collapse to that text (`ScanAccess` enum, `scan_access.dart:12,36-41`).
- FACT: Error copy is not raw. `scrubbed_error.dart:17-40` reduces errors to closed slugs. `food_api.dart:65-96` maps callable errors to the `FoodApiFailure` enum.
  - The privacy page shows `bodyScanPrivacyFailed` for every failure (`retention_settings_view.dart:103,113`).
  - No `$e` or `e.toString()` surfaced to the UI in the three dirs (the grep found only locale `toString()` calls and `debugPrint`).
  - UNKNOWN: whether every FoodApiFailure maps to distinct user copy. `meal_scan_page`, `barcode_scan_page` and `label_scan_page` were not read.
- FACT: Offline: no dedicated offline state found.
  - `FoodApiFailure.upstreamUnavailable` and `network-error` slugs exist.
  - The ARB has 45 lines matching offline, permission, denied or consent (`app_en.arb`).
  - NOT VERIFIED whether any is an offline banner.
- FACT: Camera permission denial: `capture_image_port.dart:15` and `barcode_port.dart:26` document "never throws" and return null or a result for denied or no camera.
  - There is no `permission_handler` or `PermissionStatus` use in food_diary.
  - The permission-denied UI is NOT VERIFIED.

## 4. Accessibility

- FACT: PR #5 code is more deliberate than the original audit's "37 files carry Semantics" picture.
  - Semantics, tooltip, `minimumSize`, `FocusNode` and reduce-motion hits: body_scan 88 across 14 widget files, food_diary 96 across 13 files, nutrition_plan 41 across 12 files.
  - Headers use `Semantics(header: true)` (`food_diary_page.dart:31,87,213`).
  - Tap targets are 48x48 minimum via `minimumSize` or `BoxConstraints` (`cloud_consent_sheet.dart:57,64`; `food_diary_page.dart:171,179`).
  - Radio-like choices use `Semantics(inMutuallyExclusiveGroup, selected, button)` (`retention_settings_view.dart:157-160`).
  - Busy state is `Semantics(liveRegion: true)` (`retention_settings_view.dart:265`).
  - Day-nav icons have tooltips (`food_diary_page.dart:173,196`).
- FACT: Reduce motion uses `context.reduceMotion`, defined in `lib/core/theme/hud_tokens.dart` (3 hits there).
  - New-screen users: `retention_settings_view.dart:270` and `analysis_progress_view.dart` (1 hit each).
  - It swaps the progress bar for static text.
  - Only 7 files total in `mobile/lib` use `reduceMotion`, so food_diary has none.
- FACT: Modal focus handling is explicit: the consent sheet autofocuses a `Focus` wrapping a header `Semantics` (`cloud_consent_sheet.dart:39-49`), and its header comment 1-5 cites D-85 for focus return.
  - Dialog titles use `Semantics(header, focusable)` (`retention_settings_view.dart:47`).
- FACT: Text scaling: no `textScaler` or `textScaleFactor` hits in the three dirs.
  - INFERENCE: no clamps or exceptions, so large-text behaviour relies on layout.
  - Fixed 48x54 button sizes exist (`food_diary_page.dart:99`).
  - Overflow at 200 percent is NOT VERIFIED.
- Does not carry over the original audit's 7.5-12.5 px HUD-type concern. The new screens use Material `textTheme`, not `hud_typography`. INFERENCE only, based on the greps.

## 5. Consent and disclosure patterns reusable for GPS

All in `lib/features/body_scan/`:
- **Consent sheet** (`widgets/cloud_consent_sheet.dart`): `showModalBottomSheet<bool>`, which resolves true only on an explicit agree, with dismissal counting as refusal (1-5, 18-26).
  - It has a header with focus, body, a 48dp primary "agree" and a 48dp "decline" button. Keys are `bodyScan.cloud.agree` and `.decline`.
  - The consent is versioned: `kBodyScanCloudConsentVersion` and `settings.hasCurrentConsent`. A stale version re-prompts (`body_scan_flow_page.dart:94,99`).
  - It is requested just in time on Start (151-155). A refusal or failed write degrades to local-only, not a block (97-102).
  - Storage is `bodyScanSettingsStoreProvider.acceptCloudConsent` and `withdrawCloudConsent` (`retention_settings_view.dart:215`).
- **Privacy page** (`body_scan_privacy_page.dart` plus `widgets/retention_settings_view.dart`):
  - Intro text switches on the build flag (135).
  - Retention choices carry an "honest timing" note (174).
  - An apply-to-existing action.
  - A consent state text plus a Withdraw button (201-217).
  - Delete-all-photos and delete-all-scans use a `_confirm` AlertDialog (41-66).
  - There is a pause-tracking switch (282-289).
  - Busy lock disables actions (`_busy`).
  - Results are reported by snackbar (`_say`).
- FACT: There is **no export flow** in PR #5.
  - `/backup` (`lib/features/data_export/backup_page.dart`) is separate and older.
  - `/delete-account` also pre-exists.
- Disclosure banners: `lib/features/nutrition_plan/widgets/professional_notice.dart` and `lib/features/safety/widgets/eligibility_notice.dart` (read by name only, content not inspected). `plan_sources_page.dart` and `plan_explainer_page.dart` are disclosure-style pages.
- Gating enum: `ScanAccess` (`lib/features/progress_photos/scan/scan_access.dart:12-41`) shows an ordered precondition pattern (signedOut, ageUnknown, underage, needsSupporter, needsConsent, allowed) that a GPS gate could imitate.
  - The flow page renders it as bare text with no action (see section 3).
- INFERENCE (UX gaps for GPS to avoid): the consent sheet is a modal with no OS-permission step.
  - It has no "why we need it" detail beyond one body string.
  - Withdraw does not state its consequence in the code read.
  - Delete confirmations are single-step, with no typed confirmation.

## 6. Updated counts versus the original audit

| Item | Original | Now | Basis |
|---|---|---|---|
| Routes | 35 (30 top-level + 5 shell) | 50 (45 + 5) | enumeration of the router; the 15 new routes match PR #5 |
| `FrostedScaffold(` | 30 feature files | 31 feature files (32 hits, 1 in `glass.dart`, `form_check_page.dart` has 2) | `FrostedScaffold\(` count: 32 occurrences in 31 files |
| HUD primitives | 54 files, about 210 hits | not directly re-run | different pattern; the `HudPanel\(` pattern is not comparable. NOT VERIFIED |
| ARB keys | not stated in the lines seen | EN about 2008 top-level entries, RU about 2115 (`^  "@?[A-Za-z]`) | the RU pattern included `@`-metadata lines, EN did not; counts not comparable. EN raw colon-keyed lines 2904, RU 2364 |

- UNKNOWN: whether the delta of 1 `FrostedScaffold` file comes from PR #5 or from earlier commits. The new dirs contribute 0, so the difference is probably counting method. NOT VERIFIED.
- INFERENCE: EN and RU ARB key parity is unproven. The raw line counts differ by more than the metadata explains, so RU may be missing keys. Needs a key-set diff.
- New directory sizes (FACT, by file glob): body_scan has 14 widgets plus about 30 data and state files; nutrition_plan and food_diary add many more. The first glob cut off at 100 files, so the full list is NOT VERIFIED.

## 7. Differences that change the original baseline conclusions

1. FACT: The original "30 top-level + 5 shell = 35 routes" is stale. It is now 50, with 15 routes outside the shell.
2. INFERENCE: The original "HUD migration removes FrostedScaffold one screen at a time" story (`app_theme.dart:143`) is incomplete. PR #5 added about 15 screens that are neither HUD nor `FrostedScaffold`. A third baseline, "plain Material plus GlassCard", must be added.
3. FACT: The original baseline said "no GPS, `ActivitySession` or `geolocator`" (audit line 91). Not re-grepped, so NOT VERIFIED for the delta. PR #5 added no GPS code in the three dirs.
4. FACT: Compile-time `BodyScanFlags` is a new pattern for feature gating, separate from `kDemoFeaturesEnabled` / `isDemoGatedPath`. A GPS feature flag would have two precedents.
5. FACT: There is now a working consent plus retention plus delete UI. The original audit had none for new data classes.
6. INFERENCE: The original "many screens rely on default semantics" is weaker for the new dirs. They have explicit headers, 48dp targets and live regions. Not for the HUD typography concern.
7. INFERENCE: Original `/progress`, `/profile` and `/home` now host two more cards (`BodyScanEntryCard`, `NutritionEntryCard`). Re-check the original card inventory.

## Not verified (read budget used)

- `meal_scan_page`, `barcode_scan_page`, `label_scan_page`, `add_food_page` body, `body_scan_result_page` and `body_scan_history_page` internals.
- `nutrition_plan_page` state handling.
- `scanAccessMessage` copy.
- Offline and camera-denied UI.
- `GlassCard` count by directory (the agent summed `GlassCard(\|GlassAppBar\|FrostedScaffold` hits per file by eye, not an exact tool count).
- ARB key parity.
- Whether the HUD-primitive count in the original (54 files) changed.
