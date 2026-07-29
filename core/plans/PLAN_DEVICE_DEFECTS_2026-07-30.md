# Plan — nine device-reported defects (2026-07-30)

Operator reported nine items after testing release **1.0.0 (4)** on a real phone.
Five of the nine are defects I shipped while reporting the features as working.
Root cause for every item was verified against source before this plan was written.

`GO ALL по порядку` given 2026-07-30. Gates run in the operator's order.

---

## Why the previous verification failed

487 widget/unit tests + `flutter analyze` were green. Neither touches:

* the **native ML Kit bridge** (a Dart-side `InputImage` is accepted by the fake, rejected by Android), or
* the **asset bundle** (`Image.asset` resolves from the built manifest, not from the filesystem).

So two shipped features could never have worked on a device, and the suite could not
see it. Gates 3 and 9 add the two missing kinds of proof: an asset-manifest assertion
and real emulator drive tests.

---

## Verified root causes

| # | Symptom | Root cause | Evidence |
|---|---|---|---|
| 1 | `ImageFormat is not supported.` in Live mode | Android impl is `camera_android_camerax 0.6.17`, which **ignores** `imageFormatGroup` and always emits YUV_420_888. Code concatenated 3 planes and declared the format from `image.format.raw` (=35). Native accepts only NV21(17)/YV12. | `android_camera_camerax.dart:450-453`; `InputImageConverter.java:111,119`; `mlkit_live_equipment_service.dart:162` |
| 1b | AI form coach silently dead | Same conversion defect, errors swallowed | `mlkit_pose_detector_service.dart:104-108`, `:83` |
| 2 | Settings tile inert | `onTap: () {}`; no settings page exists | `profile_page.dart:148` |
| 3 | "Demo unavailable" on every exercise | pubspec `- assets/exercises/` is non-recursive; frames live in per-exercise subdirs, so 0 of 132 reached the APK | built `AssetManifest.json`: `assets/data/*`=2, `assets/exercises/*`=0 |
| 4 | Health Connect never connects | `HEART_RATE_VARIABILITY_SDNN` is iOS-only; native builds permissions via `mapToType[key]!!` → NPE kills the whole request | `heath_data_types.dart:171` vs `:223`; `HealthPlugin.kt:2413`, `:615` |
| 5 | Suggestion tiles inert | Hardcoded `static const _suggestions`, `onTap: () {}` | `home_page.dart:29-39`, `:353` |
| 6 | Muscle map looks bad | 14 axis-aligned `Rect.fromLTWH` blobs on a rounded box | `muscle_map.dart:63-80` |
| 7 | Scrolling janks | Every `GlassCard` = `BackdropFilter(sigma 28)` (11 on the workout page); `ScrollDimList` adds `ImageFiltered`+`Opacity`+2×`Transform` per non-focused card and `setState`s the list on every scroll tick | `glass.dart:57`; `scroll_dim_list.dart:67-91`, `:157-171` |
| 8 | Interface still English | 18 keys in `app_ru.arb`, ~300 strings hardcoded | `lib/l10n/*.arb` |
| 9 | No workflow tests | No `integration_test/`, package absent | `pubspec.yaml` |

---

## Gates

| Gate | Scope | Proof required |
|---|---|---|
| **1 LIVE** | Pure-Dart YUV_420_888 -> NV21 converter (rowStride/pixelStride aware), shared by the labeler and the pose detector; declare the format explicitly; stop swallowing persistent native errors in the pose path | converter unit tests on synthetic planes + on-device run |
| **2 SETTINGS** | Real `/settings` page: theme, language, notifications, units, sign-out, about | widget tests + live walk |
| **3 VIDEO** | Flatten frames to `assets/exercises/<slug>_<n>.jpg`, rewrite the catalog generator, **plus a test asserting every JSON frame path is in the built manifest** | manifest assertion test |
| **4 HEALTH** | SDNN -> RMSSD, filter every requested type through `isDataTypeAvailable`, `configure()` before first use, actionable diagnostics instead of a bare "denied" | filter unit tests + operator's phone |
| **5 SUGGEST** | Generate suggestions from intake + progress; each opens a real workout | generator tests + tap tests |
| **6 MUSCLE** | Anatomical `Path` silhouette, 14 groups, front/back | screenshot to operator before commit |
| **7 PERF** | Remove scroll blur entirely; `BackdropFilter` only on app bar + nav bar; cards on a cheap fill | frame-timing before/after |
| **8 RU** | ~300 strings. Split into 5 sub-gates: 8a core+home, 8b exercises+scan, 8c profile+settings, 8d onboarding+health, 8e progress+rest | tests move from text to `Key` |
| **9 E2E** | `integration_test` + emulator drive: onboarding -> home -> scan -> workout -> progress -> profile -> settings, language switch | real run, log in the report |

Gate 8 exceeds the A3 scope trigger (15+ files) on its own, hence the five sub-gates.
Order is the operator's and is also correct technically: tests last, so gates 7 and 8
do not invalidate them.

---

## Standing constraints

* Local commit per gate, then STOP. **No push** without a separate literal `push`.
* 17 commits from 2026-07-29 are still local and unpushed; this plan adds more on top.
* Testnet/test-key only; no live payment paths touched.
